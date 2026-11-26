import AppKit
import SwiftUI

extension View {
    @ViewBuilder func glassSurface<S: InsettableShape>(_ shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .overlay { shape.strokeBorder(.primary.opacity(0.12), lineWidth: 0.6) }
        }
    }
}

struct ModeSwitch: View {
    @Binding var mode: OutputMode
    @GestureState private var dragX: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var slide: Animation? { reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.08) }

    var body: some View {
        GeometryReader { proxy in
            let half = proxy.size.width / 2
            let resting = mode == .trackpad ? 0 : half
            let position = dragX.map { min(half, max(0, $0 - half / 2)) } ?? resting
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.045))
                Capsule().fill(.primary.opacity(0.09)).glassSurface(Capsule())
                    .frame(width: half).offset(x: position)
                    .animation(dragX == nil ? slide : nil, value: position)
                HStack(spacing: 0) {
                    ForEach(OutputMode.allCases) { option in
                        Button { mode = option } label: {
                            Text(option.rawValue).font(.system(size: 11.5, weight: .medium))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(mode == option ? .isSelected : [])
                    }
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 6, coordinateSpace: .local)
                .updating($dragX) { value, state, _ in state = value.location.x }
                .onEnded { value in mode = value.location.x < half ? .trackpad : .assist })
        }
        .frame(height: 30)
        .padding(2)
        .background(.primary.opacity(0.04), in: Capsule())
    }
}

struct PrecisionWheel: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: String
    @State private var dragOrigin: Double?
    @State private var editing = false
    @State private var entry = ""
    @Environment(\.isEnabled) private var enabled
    @FocusState private var focused: Bool

    private var entryScale: Double {
        // The bipolar tone wheel displays a signed percentage even at its neutral position.
        range == -1...1 || (range == 0...1 && label.hasSuffix("%")) ? 100 : 1
    }

    private func openEditor() {
        entry = String(format: "%.4g", value * entryScale)
        editing = true
    }

    private func commitEntry() {
        let local = NumberFormatter()
        local.numberStyle = .decimal
        if let number = Double(entry) ?? local.number(from: entry)?.doubleValue, number.isFinite {
            change(number / entryScale)
        }
        editing = false
    }

    private func change(_ newValue: Double) {
        value = min(range.upperBound, max(range.lowerBound,
            range.lowerBound + ((newValue - range.lowerBound) / step).rounded() * step))
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.callout)
            Spacer(minLength: 4)
            Button(action: openEditor) {
                HStack(spacing: 7) {
                    Image(systemName: "dial.low").foregroundStyle(.secondary)
                    Text(label).monospacedDigit().font(.callout.weight(.medium))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10).frame(minWidth: 102, minHeight: 28)
                .glassSurface(Capsule())
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .highPriorityGesture(DragGesture(minimumDistance: 5)
                .onChanged { gesture in
                    if dragOrigin == nil { dragOrigin = value }
                    change((dragOrigin ?? value) + (gesture.translation.width / 4).rounded() * step)
                }
                .onEnded { _ in dragOrigin = nil })
            .background {
                WheelInput(enabled: enabled, increment: { change(value + $0 * step) })
                    .allowsHitTesting(false)
            }
            .onKeyPress(.upArrow) { change(value + step); return .handled }
            .onKeyPress(.downArrow) { change(value - step); return .handled }
            .fixedSize()
            .help("Swipe with two fingers or drag sideways. Click for a slider.")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(label)
            .accessibilityAdjustableAction { change(value + ($0 == .increment ? step : -step)) }
            .accessibilityAction { openEditor() }
            .popover(isPresented: $editing) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title).font(.headline)
                    Slider(value: Binding(get: { value }, set: change), in: range, step: step)
                        .accessibilityLabel(title)
                    HStack {
                        Button { change(value - step) } label: { Image(systemName: "minus") }
                            .accessibilityLabel("Decrease " + title)
                        TextField("Value", text: $entry).focused($focused)
                            .onSubmit { commitEntry() }
                        if entryScale == 100 { Text("%").foregroundStyle(.secondary) }
                        Button { change(value + step) } label: { Image(systemName: "plus") }
                            .accessibilityLabel("Increase " + title)
                        Button("Done") { commitEntry() }
                    }
                    if range == -1...1 {
                        Text("Negative values emphasize bass. Positive values emphasize detail.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onChange(of: value) { _, new in entry = String(format: "%.4g", new * entryScale) }
                .padding(14).frame(width: 240)
            }
        }
    }
}

private struct WheelInput: NSViewRepresentable {
    let enabled: Bool
    let increment: (Double) -> Void
    func makeNSView(context: Context) -> InputView { InputView() }
    func updateNSView(_ view: InputView, context: Context) {
        view.enabled = enabled
        view.increment = increment
    }
    static func dismantleNSView(_ view: InputView, coordinator: ()) { view.detach() }

    // SwiftUI's outer ScrollView receives trackpad scrolling before an embedded
    // NSView. Consume only scroll events inside this exact control in its window.
    final class InputView: NSView {
        var enabled = true
        var increment: ((Double) -> Void)?
        private var monitor: Any?
        private var remainder = 0.0
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.consume(event) == true ? nil : event
            }
        }
        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

        func consume(_ event: NSEvent) -> Bool {
            guard enabled, !isHiddenOrHasHiddenAncestor, let window else { return false }
            let location: CGPoint
            if let owner = event.window {
                guard owner === window else { return false }
                location = event.locationInWindow
            } else {
                let screen = event.locationInWindow
                guard NSWindow.windowNumber(at: screen, belowWindowWithWindowNumber: 0) == window.windowNumber else { return false }
                location = window.convertPoint(fromScreen: screen)
            }
            guard bounds.intersection(visibleRect).contains(convert(location, from: nil)) else { return false }
            if event.phase == .began { remainder = 0 }
            if !event.momentumPhase.isEmpty { return true }
            let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
            guard delta.isFinite else { return true }
            remainder += event.hasPreciseScrollingDeltas ? delta / 7 : delta
            let steps = remainder.rounded(.towardZero)
            if steps != 0 { remainder -= steps; increment?(steps) }
            return true
        }
    }
}
