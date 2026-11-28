// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// What a drag over a guest surface reports to the window (and on to the guest).
enum DragEvent {
    case enter(CGPoint, hasText: Bool, hasFiles: Bool)
    case motion(CGPoint)
    case leave
    case drop(text: String?, files: [URL])
    /// A drag that began in the guest left the app's windows and became a native Mac drag.
    case takeOver
}

/// What a guest app is dragging, ready for the Mac pasteboard.
struct PendingDrag {
    var text: String?
    var files: [URL]
}

/// Drag and drop on a guest surface. Mac to Linux: the view is a dragging destination for text and files and tells the
/// guest, which answers with its accept state. Linux to Mac: a drag an app started becomes a native drag session once
/// the pointer leaves all of the app's windows (inside them the guest runs the drag itself).
extension SurfaceView {
    static let draggedTypes: [NSPasteboard.PasteboardType] = [.fileURL, .string]

    // MARK: Destination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        let files = Self.fileURLs(on: pasteboard)
        let text = files.isEmpty ? pasteboard.string(forType: .string) : nil
        guard text != nil || !files.isEmpty else { return [] }
        dragAccepted = true
        onDrag?(.enter(convert(sender.draggingLocation, from: nil), hasText: text != nil, hasFiles: !files.isEmpty))
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        onDrag?(.motion(convert(sender.draggingLocation, from: nil)))
        return dragAccepted ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDrag?(.leave)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard dragAccepted else { return false }
        let pasteboard = sender.draggingPasteboard
        let files = Self.fileURLs(on: pasteboard)
        let text = files.isEmpty ? pasteboard.string(forType: .string) : nil
        onDrag?(.drop(text: text, files: files))
        return true
    }

    private static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls ?? []
    }

    // MARK: Source

    /// Starts the native drag when a guest drag is pending and the pointer is outside every window of this app.
    func beginNativeDragIfOutside(_ event: NSEvent) {
        guard let pending = pendingDrag,
            !NSApp.windows.contains(where: { $0.isVisible && $0.frame.contains(NSEvent.mouseLocation) })
        else { return }
        pendingDrag = nil
        let items = Self.draggingItems(for: pending, at: convert(event.locationInWindow, from: nil))
        guard !items.isEmpty else { return }
        beginDraggingSession(with: items, event: event, source: self)
        // The guest ends its own drag, and the button it still believes is held is released.
        onDrag?(.takeOver)
        onInput?(.button(.with { $0.button = 0x110 }))
    }

    private static func draggingItems(for drag: PendingDrag, at point: CGPoint) -> [NSDraggingItem] {
        let frame = NSRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32)
        let items: [NSDraggingItem]
        if drag.files.isEmpty {
            guard let text = drag.text, !text.isEmpty else { return [] }
            let item = NSDraggingItem(pasteboardWriter: text as NSString)
            item.setDraggingFrame(
                frame, contents: NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil))
            items = [item]
        } else {
            items = drag.files.map { url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                item.setDraggingFrame(frame, contents: NSWorkspace.shared.icon(forFile: url.path))
                return item
            }
        }
        return items
    }
}

extension SurfaceView: NSDraggingSource {
    nonisolated func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }
}
