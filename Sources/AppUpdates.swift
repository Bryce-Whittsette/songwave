import AppKit
import Combine
import Sparkle

/// Sparkle owns scheduling, signed-feed validation, downloads and installation.
/// This model only binds its existing state to SongWave's native menus.
@MainActor
final class AppUpdates: ObservableObject {
    @Published private(set) var canCheck = false
    @Published private(set) var checksAutomatically = true
    private let controller = SPUStandardUpdaterController(startingUpdater: false,
                                                          updaterDelegate: nil, userDriverDelegate: nil)
    private var started = false

    init() {
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main).assign(to: &$canCheck)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main).assign(to: &$checksAutomatically)
        // Menu-bar launches may have no restored window. Start from the app's
        // lifetime after subscriptions are installed, rather than window.onAppear.
        Task { @MainActor [weak self] in self?.start() }
    }

    func start() {
        guard !started else { return }
        started = true
        controller.startUpdater()
    }

    func check() { controller.checkForUpdates(nil) }
    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }
}
