// SPDX-License-Identifier: AGPL-3.0-or-later
//! Renders window surface trees with pixman and streams the damaged pixels to the host.

use smithay::{
    backend::{
        allocator::Fourcc,
        renderer::{
            Bind, Color32F, Offscreen,
            damage::OutputDamageTracker,
            element::{
                Kind,
                surface::{WaylandSurfaceRenderElement, render_elements_from_surface_tree},
            },
            pixman::PixmanRenderer,
            utils::with_renderer_surface_state,
        },
    },
    desktop::utils::{bbox_from_surface_tree, send_frames_surface_tree},
    input::pointer::CursorImageStatus,
    reexports::wayland_server::{Resource, protocol::wl_surface::WlSurface},
    utils::{Logical, Physical, Point, Rectangle, Transform},
    wayland::{compositor::with_states, shell::xdg::SurfaceCachedState},
};

use crate::{
    handlers::toplevel_data,
    pb,
    state::{Role, State, Target},
};

/// Window geometry: the visible window, excluding client-side shadows.
pub fn geometry(surface: &WlSurface) -> Rectangle<i32, Logical> {
    with_states(surface, |s| s.cached_state.get::<SurfaceCachedState>().current().geometry)
        .unwrap_or_else(|| bbox_from_surface_tree(surface, (0, 0)))
}

// DEBUG-TEMP: per-second counters for the idle redraw investigation.
pub static DBG_COMMITS: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
pub static DBG_EMPTY: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
pub static DBG_SENT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
pub static DBG_ACKS: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
pub static DBG_CBS: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
pub static DBG_BYTES: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
static DBG_LAST: std::sync::Mutex<Option<std::time::Instant>> = std::sync::Mutex::new(None);
pub fn dbg_tick() {
    use std::sync::atomic::Ordering::Relaxed;
    let mut last = DBG_LAST.lock().unwrap();
    let now = std::time::Instant::now();
    match *last {
        Some(t) if now.duration_since(t).as_secs_f64() < 1.0 => {}
        _ => {
            tracing::info!(
                "DBG commits={} empty={} sent={} acks={} callbacks={} bytes={}",
                DBG_COMMITS.swap(0, Relaxed), DBG_EMPTY.swap(0, Relaxed), DBG_SENT.swap(0, Relaxed),
                DBG_ACKS.swap(0, Relaxed), DBG_CBS.swap(0, Relaxed), DBG_BYTES.swap(0, Relaxed)
            );
            *last = Some(now);
        }
    }
}

impl State {
    pub fn render_window(&mut self, id: u32) {
        let Some(idx) = self.windows.iter().position(|w| w.id == id) else { return };
        if self.windows[idx].in_flight {
            return; // rendered when the host acknowledges the previous frame
        }
        DBG_COMMITS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        dbg_tick();
        let surface = self.windows[idx].surface.clone();
        if !with_renderer_surface_state(&surface, |s| s.buffer().is_some()).unwrap_or(false) {
            return;
        }
        let geo = geometry(&surface);
        if geo.size.w <= 0 || geo.size.h <= 0 {
            return;
        }
        if !self.windows[idx].announced {
            self.announce(idx);
        }

        let scale_120 = self.scale_120;
        let scale = scale_120 as f64 / 120.0;
        let pw = (geo.size.w as f64 * scale).round() as i32;
        let ph = (geo.size.h as f64 * scale).round() as i32;

        // Frames the host would refuse are not rendered (the host limits are in docs/security.md).
        if !crate::limits::surface_ok(pw as u32, ph as u32, scale_120) {
            tracing::warn!(pw, ph, scale_120, "window too large to stream; not rendered");
            return;
        }

        let State { renderer, windows, .. } = self;
        let win = &mut windows[idx];
        let reallocated = !matches!(&win.target, Some(t) if t.size == (pw, ph) && t.scale_120 == scale_120);
        if reallocated {
            let Ok(image) = renderer.create_buffer(Fourcc::Argb8888, (pw, ph).into()) else {
                tracing::warn!(pw, ph, "pixman buffer allocation failed");
                return;
            };
            win.target = Some(Target {
                image,
                tracker: OutputDamageTracker::new((pw, ph), scale, Transform::Normal),
                size: (pw, ph),
                scale_120,
                first: true,
            });
        }
        let Some(target) = win.target.as_mut() else { return };

        let origin: Point<i32, Physical> = Point::<i32, Logical>::from((-geo.loc.x, -geo.loc.y)).to_physical_precise_round(scale);
        let elements: Vec<WaylandSurfaceRenderElement<PixmanRenderer>> =
            render_elements_from_surface_tree(renderer, &surface, origin, scale, 1.0, Kind::Unspecified);

        let age = if target.first { 0 } else { 1 };
        let damage: Vec<Rectangle<i32, Physical>> = {
            let mut fb = renderer.bind(&mut target.image).expect("bind pixman target");
            match target.tracker.render_output(renderer, &mut fb, age, &elements, Color32F::TRANSPARENT) {
                Ok(r) => r.damage.cloned().unwrap_or_default(),
                Err(e) => {
                    tracing::warn!("render failed: {e}");
                    return;
                }
            }
        };
        target.first = false;
        win.dirty = false;

        if damage.is_empty() {
            DBG_EMPTY.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            DBG_CBS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            self.send_frame_callbacks(&surface);
            return;
        }
        let rects = encode_damage(&target.image, &damage, (pw, ph), reallocated);
        DBG_SENT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        DBG_BYTES.fetch_add(rects.iter().map(|r| r.pixels.len() as u64).sum(), std::sync::atomic::Ordering::Relaxed);
        win.seq += 1;
        win.in_flight = true;
        let frame = pb::Frame { window: id, seq: win.seq, width: pw as u32, height: ph as u32, scale_120, damage: rects };
        self.send(pb::to_host::Msg::Frame(frame));
    }

    fn announce(&mut self, idx: usize) {
        let parent_surface = match &self.windows[idx].role {
            Role::Popup(p) => p.get_parent_surface(),
            Role::Toplevel(_) => None,
        };
        let parent = parent_surface.and_then(|s| self.windows.iter().find(|w| w.surface == s)).map_or(0, |w| w.id);
        let (flatpak_id, launch_id) = self.owner_of(&self.windows[idx].surface).unwrap_or_default();
        let win = &mut self.windows[idx];
        win.announced = true;
        let (kind, x, y, title, app_id) = match &win.role {
            Role::Toplevel(t) => {
                let data = toplevel_data(t.wl_surface());
                (pb::WindowKind::Toplevel, 0, 0, data.title, data.app_id)
            }
            Role::Popup(p) => {
                let g = p.with_pending_state(|s| s.geometry);
                (pb::WindowKind::Popup, g.loc.x, g.loc.y, String::new(), String::new())
            }
        };
        let (min, max) = with_states(&win.surface, |s| {
            let mut c = s.cached_state.get::<SurfaceCachedState>();
            (c.current().min_size, c.current().max_size)
        });
        let opened = pb::WindowOpened {
            id: win.id,
            kind: kind as i32,
            parent,
            x,
            y,
            title,
            app_id,
            min_width: min.w as u32,
            min_height: min.h as u32,
            max_width: max.w as u32,
            max_height: max.h as u32,
            flatpak_id,
            launch_id,
        };
        self.send(pb::to_host::Msg::Opened(opened));
    }

    /// The Flatpak app and launch behind a Wayland client, from its process.
    pub fn owner_of(&self, surface: &WlSurface) -> Option<(String, String)> {
        let client = self.display_handle.get_client(surface.id()).ok()?;
        let pid = client.get_credentials(&self.display_handle).ok()?.pid;
        self.control.owner_of(pid).map(|(app, launch)| (app.to_owned(), launch.to_owned()))
    }

    /// The host presented a frame: let the client draw the next one and flush anything queued.
    pub fn on_ack(&mut self, id: u32, seq: u64) {
        let Some(win) = self.win_by_id(id) else { return };
        if seq != win.seq {
            return;
        }
        win.in_flight = false;
        let surface = win.surface.clone();
        let dirty = win.dirty;
        DBG_ACKS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        DBG_CBS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        self.send_frame_callbacks(&surface);
        if dirty {
            self.render_window(id);
        }
    }

    pub fn send_frame_callbacks(&self, surface: &WlSurface) {
        let output = self.output.clone();
        send_frames_surface_tree(surface, &output, self.start_time.elapsed(), None, |_, _| Some(output.clone()));
    }

    pub fn send_cursor(&mut self, image: CursorImageStatus) {
        let Some(window) = self.pointer_window else { return };
        let name = match image {
            CursorImageStatus::Hidden => String::new(),
            CursorImageStatus::Named(icon) => icon.name().to_owned(),
            CursorImageStatus::Surface(_) => "default".to_owned(),
        };
        self.send(pb::to_host::Msg::Cursor(pb::Cursor { window, name, ..Default::default() }));
    }
}

/// Copies the damaged rectangles out of the render target, LZ4-compressed.
/// A reallocated target is sent whole, as is anything with many scattered rectangles.
fn encode_damage(
    image: &smithay::reexports::pixman::Image<'static, 'static>,
    damage: &[Rectangle<i32, Physical>],
    (w, h): (i32, i32),
    full: bool,
) -> Vec<pb::Rect> {
    const MAX_RECTS: usize = 8;
    let whole = Rectangle::<i32, Physical>::from_size((w, h).into());
    let rects: Vec<Rectangle<i32, Physical>> = if full || damage.len() > MAX_RECTS {
        vec![whole]
    } else {
        damage.iter().filter_map(|r| r.intersection(whole)).collect()
    };

    let stride = image.stride();
    // Safety: the image owns `stride * height` bytes and is not mutated while we read.
    let data = unsafe { std::slice::from_raw_parts(image.data() as *const u8, stride * image.height()) };
    rects
        .into_iter()
        .map(|r| {
            let (x, y, rw, rh) = (r.loc.x as usize, r.loc.y as usize, r.size.w as usize, r.size.h as usize);
            let mut packed = Vec::with_capacity(rw * rh * 4);
            for row in y..y + rh {
                packed.extend_from_slice(&data[row * stride + x * 4..row * stride + (x + rw) * 4]);
            }
            pb::Rect { x: x as u32, y: y as u32, width: rw as u32, height: rh as u32, pixels: lz4_flex::block::compress(&packed) }
        })
        .collect()
}
