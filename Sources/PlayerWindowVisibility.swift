import AppKit
import SwiftUI

// Window visibility is event-driven. This has no timer and never changes the
// playback engine; it only enables visual publishing and animation schedules.
struct PlayerWindowVisibility: NSViewRepresentable {
    let changed: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.changed = changed
        return view
    }

    func updateNSView(_ view: VisibilityView, context: Context) {
        view.changed = changed
        view.refresh()
    }

    static func dismantleNSView(_ view: VisibilityView, coordinator: ()) { view.detach() }

    final class VisibilityView: NSView {
        var changed: ((Bool) -> Void)?
        private var closing = false
        private var lastVisibility: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            closing = false
            guard let window else { publish(false); return }
            let center = NotificationCenter.default
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification, NSWindow.didBecomeKeyNotification,
                         NSWindow.willCloseNotification] {
                center.addObserver(self, selector: #selector(windowChanged(_:)), name: name, object: window)
            }
            for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                         NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
                center.addObserver(self, selector: #selector(applicationChanged(_:)), name: name, object: NSApp)
            }
            refresh()
        }

        override func viewDidHide() { super.viewDidHide(); refresh() }
        override func viewDidUnhide() { super.viewDidUnhide(); refresh() }

        @objc private func windowChanged(_ notification: Notification) {
            if notification.name == NSWindow.willCloseNotification { closing = true }
            else if notification.name == NSWindow.didBecomeKeyNotification || notification.name == NSWindow.didDeminiaturizeNotification { closing = false }
            refresh()
        }

        @objc private func applicationChanged(_ notification: Notification) { refresh() }

        func refresh() {
            let visible = window.map {
                !closing && !isHiddenOrHasHiddenAncestor && !NSApp.isHidden &&
                $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible)
            } ?? false
            publish(visible)
        }

        func detach() {
            NotificationCenter.default.removeObserver(self)
            closing = true
            let wasVisible = lastVisibility == true
            lastVisibility = false
            let handler = changed
            changed = nil
            if wasVisible { DispatchQueue.main.async { handler?(false) } }
        }

        private func publish(_ visible: Bool) {
            guard lastVisibility != visible else { return }
            lastVisibility = visible
            // NSView can move during a SwiftUI update. Deliver only the latest
            // state after that transaction, without mutating view state inside it.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lastVisibility == visible else { return }
                self.changed?(visible)
            }
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
