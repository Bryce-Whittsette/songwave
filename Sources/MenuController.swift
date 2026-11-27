import AppKit
import Combine

@MainActor
final class MenuController: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem?
    private weak var studio: Studio?
    private var observer: AnyCancellable?
    private var openWindow: (() -> Void)?

    private var quitting = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let studio else { return .terminateNow }
        if quitting { return .terminateLater }
        quitting = true
        let finish = { [weak self] in
            guard self?.quitting == true else { return }
            self?.quitting = false
            sender.reply(toApplicationShouldTerminate: true)
        }
        studio.terminate(finish)
        // Core Audio can wait on its system recording prompt. Keep AppKit responsive.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { finish() }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func attach(to studio: Studio, show: Bool, openWindow: @escaping () -> Void) {
        self.studio = studio
        self.openWindow = openWindow
        observer = Publishers.CombineLatest4(studio.$active, studio.$mode, studio.$localBypass, studio.$firstSuccess)
            .receive(on: RunLoop.main)
            .sink { [weak self] active, mode, bypass, check in
                self?.update(active && mode == .assist && !bypass && (check.phase == .idle || check.phase == .confirmed))
            }
        setVisible(show)
        let notifications = NSWorkspace.shared.notificationCenter
        notifications.removeObserver(self, name: NSWorkspace.willSleepNotification, object: nil)
        notifications.removeObserver(self, name: NSWorkspace.didWakeNotification, object: nil)
        notifications.addObserver(self, selector: #selector(sleeping), name: NSWorkspace.willSleepNotification, object: nil)
        notifications.addObserver(self, selector: #selector(waking), name: NSWorkspace.didWakeNotification, object: nil)
        studio.launchIfConfigured()
    }

    @objc private func sleeping() { studio?.suspendForSleep() }
    @objc private func waking() { studio?.resumeAfterWake() }

    func setVisible(_ show: Bool) {
        if show, item == nil {
            let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item = status
            status.button?.target = self
            status.button?.action = #selector(click)
            status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            update(studio?.assistEnabled ?? false)
        } else if !show, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    private func update(_ enabled: Bool) {
        guard let button = item?.button else { return }
        let title = enabled ? "SongWave haptics on" : "SongWave haptics off"
        let icon = NSImage(systemSymbolName: enabled ? "waveform.circle.fill" : "waveform.circle",
                           accessibilityDescription: title)
        icon?.isTemplate = true
        button.image = icon
        button.setAccessibilityLabel(title)
        button.toolTip = "\(title). Click to toggle. Right-click to open SongWave."
    }

    @objc private func click() {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            guard let button = item?.button else { return }
            let menu = NSMenu()
            let open = menu.addItem(withTitle: "Open SongWave", action: #selector(showWindow), keyEquivalent: "")
            open.target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit SongWave", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
        } else {
            studio?.toggleAssist()
            if studio?.showPlaybackAccess == true { showWindow() }
        }
    }

    @objc private func showWindow() {
        openWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }
}
