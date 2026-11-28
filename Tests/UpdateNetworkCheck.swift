import AppKit
import Combine
import Sparkle

// Only the presentation boundary is replaced. Sparkle performs real HTTP,
// signed-feed verification, retry/session cleanup and approval gating.
@MainActor final class NetworkDriver: SPUStandardUserDriver {
    var failure: NSError?
    var found: SUAppcastItem?
    var state: SPUUserUpdateState?
    var acknowledge: (() -> Void)?
    var approve: ((SPUUserUpdateChoice) -> Void)?
    var cancel: (() -> Void)?
    var downloads = 0

    override func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { cancel = cancellation }
    override func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        failure = error as NSError; acknowledge = acknowledgement
    }
    override func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                                  reply: @escaping (SPUUserUpdateChoice) -> Void) {
        found = appcastItem; self.state = state; approve = reply
    }
    override func dismissUpdateInstallation() {}
    override func showDownloadInitiated(cancellation: @escaping () -> Void) {
        downloads += 1; cancellation()
    }
    func reset() { failure = nil; found = nil; state = nil; acknowledge = nil; approve = nil; cancel = nil }
}

@MainActor final class NetworkCheck: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    var updater: SPUUpdater!
    var driver: NetworkDriver!
    var subscription: AnyCancellable?
    var availability: [Bool] = []
    var loadedSignatures: [SPUAppcastSigningValidationStatus] = []
    var aborted: [NSError] = []
    var downloadRequests = 0
    var installs = 0
    var root: URL { Bundle.main.bundleURL.deletingLastPathComponent() }

    func wait(_ description: String, timeout: Duration = .seconds(12), until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw NSError(domain: "NetworkRegression", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Timed out: " + description]) }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    func phase(_ name: String) async throws {
        try Data(name.utf8).write(to: root.appendingPathComponent("phase"), options: .atomic)
        try await wait("server " + name) {
            (try? String(contentsOf: self.root.appendingPathComponent("ready"), encoding: .utf8)) == name
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do { try await run(); print("Real Sparkle network failure, cancellation, signed retry and approval gating passed."); exit(0) }
            catch { fputs("Updater network regression: \(error)\n", stderr); exit(1) }
        }
    }
    func run() async throws {
        let host = Bundle.main
        guard let identifier = host.bundleIdentifier, identifier.hasPrefix("studio.songwave.updater-test.") else {
            fatalError("Requires a disposable Info.plist identity")
        }
        defer { UserDefaults.standard.removePersistentDomain(forName: identifier) }
        driver = NetworkDriver(hostBundle: host, delegate: nil)
        updater = SPUUpdater(hostBundle: host, applicationBundle: host, userDriver: driver, delegate: self)
        // The real production policy disallows unattended downloads/install.
        precondition(!updater.automaticallyDownloadsUpdates && !updater.allowsAutomaticUpdates)
        updater.automaticallyChecksForUpdates = false // Only this unique test domain.
        subscription = updater.publisher(for: \.canCheckForUpdates).sink { self.availability.append($0) }
        try updater.start()
        try await wait("initial availability") { updater.canCheckForUpdates }
        for name in ["refused", "valid-1", "http503", "valid-2", "disconnect", "valid-3", "truncated", "valid-4", "hang", "valid-5"] {
            try await phase(name)
            driver.reset(); availability.removeAll()
            updater.checkForUpdates()
            if name == "hang" {
                try await wait("request reached hanging server") {
                    (try? String(contentsOf: self.root.appendingPathComponent("requested"), encoding: .utf8)) == name
                }
                precondition(updater.sessionInProgress)
                guard let cancel = driver.cancel else { fatalError("Missing cancellation action") }
                cancel()
            } else if name.hasPrefix("valid") {
                try await wait("signed update found") { driver.found != nil || driver.failure != nil }
                precondition(driver.failure == nil, "Healthy retry failed: \(String(describing: driver.failure))")
                precondition(driver.found?.versionString == "2" && driver.state?.stage == .notDownloaded)
                precondition(driver.approve != nil && updater.sessionInProgress)
                try await Task.sleep(for: .milliseconds(150))
                precondition(driver.downloads == 0 && downloadRequests == 0 && installs == 0,
                             "An update started before listener approval")
                driver.approve?(.dismiss)
            } else {
                // macOS versions differ in waiting/retrying an unavailable
                // endpoint. Permit URLSession's normal timeout, independently
                // of the short cancellation test below; do not change Sparkle.
                try await wait("network error " + name, timeout: name == "refused" ? .seconds(75) : .seconds(12)) { driver.failure != nil }
                precondition(driver.found == nil && driver.acknowledge != nil)
                var causes: [NSError] = []
                var cause = driver.failure
                while let error = cause, causes.count < 8 {
                    causes.append(error); cause = error.userInfo[NSUnderlyingErrorKey] as? NSError
                }
                print("Expected \(name) error: " + causes.map { "\($0.domain)/\($0.code)" }.joined(separator: " → "))
                // Sparkle reports non-2xx HTTP directly; transport failures
                // retain URLSession's underlying network error.
                precondition(name == "http503" || causes.contains { $0.domain == NSURLErrorDomain },
                             "Expected a network failure rather than fixture/policy rejection")
                driver.acknowledge?()
            }
            try await wait("retry available after " + name) { updater.canCheckForUpdates && !updater.sessionInProgress }
            precondition(availability.contains(false) && availability.last == true,
                         "Menu availability must recover after " + name)
            precondition(driver.downloads == 0 && downloadRequests == 0 && installs == 0)
        }
        // Automatic checks must recover quietly too, without presenting an
        // error or silently turning automatic installation on.
        try await phase("background503")
        driver.reset(); aborted.removeAll()
        updater.checkForUpdatesInBackground()
        try await wait("background network failure") { !aborted.isEmpty && !updater.sessionInProgress }
        precondition(driver.failure == nil && driver.found == nil && updater.canCheckForUpdates)
        try await phase("valid-background-retry")
        updater.checkForUpdates()
        try await wait("retry after background error") { driver.found != nil || driver.failure != nil }
        precondition(driver.failure == nil && driver.found?.versionString == "2" && driver.state?.stage == .notDownloaded)
        precondition(driver.approve != nil && driver.downloads == 0 && downloadRequests == 0 && installs == 0)
        driver.approve?(.dismiss)
        try await wait("finished") { !updater.sessionInProgress && updater.canCheckForUpdates }
        precondition(loadedSignatures.count == 6 && loadedSignatures.allSatisfy { $0 == .succeeded },
                     "Every healthy retry must verify the signed feed")
        precondition(host.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "1")
    }
    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        loadedSignatures.append(appcast.signingValidationStatus)
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { aborted.append(error as NSError) }
    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) { downloadRequests += 1 }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) { installs += 1 }
}

@main struct UpdateNetworkCheck {
    @MainActor static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        let delegate = NetworkCheck(); app.delegate = delegate
        app.setActivationPolicy(.prohibited)
        withExtendedLifetime(delegate) { app.run() }
    }
}
