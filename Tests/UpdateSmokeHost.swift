// A disposable native app for exercising Sparkle installation. No SongWave
// capture, model, preferences, permissions, speakers or actuators are linked.
import AppKit
import Sparkle

@MainActor final class SmokeDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private var window: NSWindow?
    private var controller: SPUStandardUpdaterController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let info = Bundle.main.infoDictionary!
        let folder = URL(fileURLWithPath: info["TestResultFolder"] as! String)
        let build = info["CFBundleVersion"] as! String
        try? Data(build.utf8).write(to: folder.appendingPathComponent("launched-build.txt"))
        if build == "2" {
            try? Data("Update installed and relaunched.".utf8).write(to: folder.appendingPathComponent("installed.txt"))
            NSApp.terminate(nil)
            return
        }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        let window = NSWindow(contentRect: NSRect(x: 250, y: 250, width: 440, height: 180), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "SongWave Update Test"
        let label = NSTextField(wrappingLabelWithString: "Disposable updater test — build 1\nNo music, permissions, haptics, or keyboard lighting.")
        label.frame = NSRect(x: 24, y: 85, width: 390, height: 65)
        let button = NSButton(title: "Check Test Update…", target: controller, action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)))
        button.frame = NSRect(x: 24, y: 30, width: 210, height: 32)
        window.contentView?.addSubview(label); window.contentView?.addSubview(button)
        self.window = window; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        guard let path = Bundle.main.object(forInfoDictionaryKey: "TestResultFolder") as? String else { return }
        try? Data("\(appcast.signingValidationStatus.rawValue)".utf8).write(to: URL(fileURLWithPath: path).appendingPathComponent("feed-validation.txt"))
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        guard let path = Bundle.main.object(forInfoDictionaryKey: "TestResultFolder") as? String else { return }
        try? Data(error.localizedDescription.utf8).write(to: URL(fileURLWithPath: path).appendingPathComponent("last-error.txt"))
    }
}

@main struct UpdateSmokeHost {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = SmokeDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
