import AppKit
import SwiftUI

/// Hands back the `NSScrollView` behind a SwiftUI `ScrollView`, so a drag can
/// auto-scroll it smoothly. Place it in the background of the scroll content.
struct ScrollViewProbe: NSViewRepresentable {
    let onResolve: (NSScrollView) -> Void

    func makeNSView(context: Context) -> ProbeView { ProbeView() }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.onResolve = onResolve
        view.resolveSoon()
    }

    final class ProbeView: NSView {
        var onResolve: ((NSScrollView) -> Void)?
        private weak var resolved: NSScrollView?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            resolveSoon()
        }

        func resolveSoon() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let scrollView = self.enclosingScrollView, scrollView !== self.resolved else { return }
                self.resolved = scrollView
                self.onResolve?(scrollView)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// A flipped (top-left origin) view filling the board viewport. Converting
/// an event's window location through it gives the same coordinates SwiftUI
/// uses for the `BoardSpace.viewport` coordinate space.
struct ViewportProbe: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> FlippedView {
        let view = FlippedView()
        onResolve(view)
        return view
    }

    func updateNSView(_ view: FlippedView, context: Context) {}

    final class FlippedView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

final class WeakScrollView {
    weak var view: NSScrollView?
    init(_ view: NSScrollView) { self.view = view }
}

extension NSScrollView {
    /// Scrolls by `delta` points along one axis, clamped to the content.
    /// Returns false when already at the end.
    @discardableResult
    func nudge(by delta: CGFloat, vertical: Bool) -> Bool {
        guard let document = documentView else { return false }
        let clip = contentView
        var origin = clip.bounds.origin
        let before = origin
        if vertical {
            let maxY = max(0, document.frame.height - clip.bounds.height)
            let step = document.isFlipped ? delta : -delta
            origin.y = min(max(origin.y + step, 0), maxY)
        } else {
            let maxX = max(0, document.frame.width - clip.bounds.width)
            origin.x = min(max(origin.x + delta, 0), maxX)
        }
        guard origin != before else { return false }
        clip.scroll(to: origin)
        reflectScrolledClipView(clip)
        return true
    }
}
