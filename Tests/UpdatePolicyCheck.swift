import AppKit
import Sparkle

/// Uses an isolated host bundle without starting the updater, networking or UI.
@main
struct UpdatePolicyCheck {
    @MainActor static func main() {
        guard CommandLine.arguments.count == 2,
              let host = Bundle(path: CommandLine.arguments[1]),
              let identifier = host.bundleIdentifier,
              identifier.hasPrefix("studio.songwave.updater-test.") else {
            fatalError("Expected a disposable updater-test bundle")
        }
        defer { UserDefaults.standard.removePersistentDomain(forName: identifier) }
        let driver = SPUStandardUserDriver(hostBundle: host, delegate: nil)
        let updater = SPUUpdater(hostBundle: host, applicationBundle: host,
                                 userDriver: driver, delegate: nil)
        precondition(updater.updateCheckInterval == 3600, "Checks must default to hourly")
        precondition(updater.automaticallyChecksForUpdates, "Checks should be enabled by default")
        precondition(!updater.automaticallyDownloadsUpdates && !updater.allowsAutomaticUpdates,
                     "Installation must require listener approval")
        precondition(!updater.canCheckForUpdates, "The test must not start the updater")
        updater.automaticallyChecksForUpdates = false
        precondition(!updater.automaticallyChecksForUpdates, "Respect the listener's opt-out")
        updater.automaticallyDownloadsUpdates = true
        precondition(!updater.automaticallyDownloadsUpdates, "A saved preference cannot allow silent updates")
        updater.automaticallyChecksForUpdates = true
        precondition(updater.automaticallyChecksForUpdates && updater.updateCheckInterval == 3600)
        print("Real Sparkle hourly scheduling, opt-out and approval-only update policy passed without starting a check.")
    }
}
