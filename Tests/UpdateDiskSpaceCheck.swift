import AppKit
import Darwin
import Sparkle

@MainActor final class DiskDriver: SPUStandardUserDriver {
    var failed: ((Error, @escaping () -> Void) -> Void)?
    var ready: (() -> Void)?
    var installed: (() -> Void)?
    override func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    override func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                                  reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    override func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { failed?(error, acknowledgement) }
    override func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    override func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    override func showDownloadDidReceiveData(ofLength length: UInt64) {}
    override func showDownloadDidStartExtractingUpdate() {}
    override func showExtractionReceivedProgress(_ progress: Double) {}
    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        ready?(); reply(.install)
    }
    override func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    override func dismissUpdateInstallation() {}
    override func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement(); installed?()
    }
}
@MainActor final class DiskCheck: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    var updater: SPUUpdater!
    var driver: DiskDriver!
    var sawFull = false
    var root: URL { URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "TestResultFolder") as! String) }
    func event(_ text: String) { try! Data(text.utf8).write(to: root.appendingPathComponent("disk-state"), options: .atomic) }
    func applicationDidFinishLaunching(_ notification: Notification) {
        precondition(Bundle.main.bundleIdentifier!.hasPrefix("studio.songwave.update-smoke."))
        let target = Bundle(path: Bundle.main.object(forInfoDictionaryKey: "TestTargetApp") as! String)!
        driver = DiskDriver(hostBundle: target, delegate: nil)
        driver.failed = { [self] error, acknowledge in
            var current: NSError? = error as NSError
            var full = false
            for _ in 0..<12 {
                guard let e = current else { break }
                print("Error domain/code:", e.domain, e.code)
                full = full || (e.domain == NSPOSIXErrorDomain && e.code == Int(ENOSPC)) ||
                    (e.domain == NSCocoaErrorDomain && e.code == NSFileWriteOutOfSpaceError)
                current = e.userInfo[NSUnderlyingErrorKey] as? NSError
            }
            guard full && !sawFull else { event("unexpected-error: " + error.localizedDescription); exit(1) }
            sawFull = true; acknowledge(); event("disk-full")
            Task { @MainActor in
                let deadline = ContinuousClock.now.advanced(by: .seconds(30))
                while (try? String(contentsOf: root.appendingPathComponent("space-restored"), encoding: .utf8)) != "ready" || updater.sessionInProgress {
                    guard ContinuousClock.now < deadline else { event("retry-timeout"); exit(1) }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                updater.checkForUpdates()
            }
        }
        driver.ready = { [self] in
            event(sawFull ? "retry-ready" : "attempting-full-install")
        }
        driver.installed = { [self] in
            guard sawFull else { event("unexpected-install-on-full-volume"); exit(1) }
            event("retry-installed"); exit(0)
        }
        updater = SPUUpdater(hostBundle: target, applicationBundle: target, userDriver: driver, delegate: self)
        do { try updater.start(); updater.checkForUpdates() }
        catch { event("start-error: " + error.localizedDescription); exit(1) }
    }
    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool { false }
}
@main struct DiskSpaceCheck {
    @MainActor static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared; let delegate = DiskCheck(); app.delegate = delegate
        app.setActivationPolicy(.prohibited)
        withExtendedLifetime(delegate) { app.run() }
    }
}
