# 0009: Window chrome: native title bar, no duplicate window buttons

Date: 2026-10-31. Status: accepted (revisit with a unified title bar experiment).

## Context
GNOME/libadwaita apps draw their own header bar (client-side decoration); a native title bar above it shows two bars with duplicate close/minimize/maximize buttons.

## Options
1. Hide the native title bar and float the traffic lights over the app's header bar. Rejected: they would cover the app's left-hand header controls.
2. Native title bar plus hide GTK's own window buttons (`gtk-decoration-layout=:` via image-provided GTK settings, exposed to Flatpak apps with a global read-only override of xdg-config/gtk-3.0 and gtk-4.0). **Chosen:** one set of window buttons, native behaviour (zoom, full screen Spaces, minimize), apps keep their header bars.
3. Always server-side decoration: only apps that honour xdg-decoration (Qt) respond; GTK ignores it.

## Consequences
GNOME apps show a slim Mac title bar above their header bar. xdg-decoration is answered with server-side so Qt apps have no frame of their own.
Revisit when: we can inset the traffic lights per app (needs app cooperation) or a reliable CSD-detection plus header-bar-in-titlebar approach exists.
