import AppKit
import SwiftUI

// AppKit routes a local scroll event through the same monitor as a trackpad swipe.
// A hosted view's visibleRect can span the whole scroll area. Only the wheel whose
// bounds contain the cursor may consume that event.
private final class Swipe: NSEvent, @unchecked Sendable {
    var target: NSWindow?
    var point = CGPoint.zero
    var delta: CGFloat = 7
    var horizontal = false
    var inertial = false
    override var window: NSWindow? { target }
    override var windowNumber: Int { target?.windowNumber ?? 0 }
    override var locationInWindow: CGPoint { point }
    override var type: NSEvent.EventType { .scrollWheel }
    override var phase: NSEvent.Phase { .began }
    override var momentumPhase: NSEvent.Phase { inertial ? .changed : [] }
    override var scrollingDeltaX: CGFloat { horizontal ? delta : 0 }
    override var scrollingDeltaY: CGFloat { horizontal ? 0 : delta }
    override var hasPreciseScrollingDeltas: Bool { true }
    override var cgEvent: CGEvent? {
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 7, wheel2: 0, wheel3: 0)
    }
}

@main struct WheelRegression {
    @MainActor final class Levels: ObservableObject { @Published var values = [0.0, 0.0, 0.0] }
    struct Panel: View {
        @ObservedObject var levels: Levels
        var body: some View {
            ScrollView {
                VStack {
                    ForEach(0..<3, id: \.self) { index in
                        PrecisionWheel(title: Band.allCases[index].rawValue, value: $levels.values[index],
                                       range: -12...12, step: 0.5, label: String(levels.values[index]))
                    }
                }.padding()
            }
        }
    }
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let levels = Levels()
        let host = NSHostingView(rootView: Panel(levels: levels))
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 320, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderBack(nil)
        try await Task.sleep(for: .milliseconds(300))
        func receivers(_ view: NSView) -> [NSView] {
            var result = view.subviews.flatMap(receivers)
            if String(reflecting: type(of: view)).contains("WheelInput.InputView") { result.append(view) }
            return result
        }
        let wheels = receivers(host)
        precondition(wheels.count == 3)
        for wheel in wheels {
            let event = Swipe()
            event.target = window
            event.point = wheel.convert(CGPoint(x: wheel.bounds.midX, y: wheel.bounds.midY), to: nil)
            NSApp.sendEvent(event)
            try await Task.sleep(for: .milliseconds(30))
        }
        precondition(levels.values == [0.5, 0.5, 0.5], "Each swipe must change only its own EQ band.")
        let event = Swipe()
        event.target = window
        event.point = wheels[1].convert(CGPoint(x: wheels[1].bounds.midX, y: wheels[1].bounds.midY), to: nil)
        event.horizontal = true
        for _ in 0..<80 { NSApp.sendEvent(event) }
        precondition(levels.values.filter { $0 == 12 }.count == 1 && levels.values.filter { $0 == 0.5 }.count == 2)
        let afterSwipes = levels.values
        event.inertial = true
        event.delta = -70
        NSApp.sendEvent(event)
        precondition(levels.values == afterSwipes, "Momentum must not change a settled value.")
        event.inertial = false
        event.delta = -CGFloat.greatestFiniteMagnitude
        NSApp.sendEvent(event)
        precondition(levels.values.filter { $0 == -12 }.count == 1)
        print("EQ wheels handled targeted vertical and horizontal swipes, boundaries, and momentum.")
    }
}
