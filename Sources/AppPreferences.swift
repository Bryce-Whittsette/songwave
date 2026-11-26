import AppKit
import SwiftUI

/// Shared by the player and Settings, including when the player is closed.
@MainActor
final class AppPreferences: ObservableObject {
    @Published var appearance: Appearance {
        didSet {
            guard appearance != oldValue else { return }
            defaults.set(appearance.rawValue, forKey: "appearance")
            applyAppearance()
        }
    }
    @Published var showMenuControl: Bool {
        didSet {
            guard showMenuControl != oldValue else { return }
            defaults.set(showMenuControl, forKey: "showMenuControl")
            menuController?.setVisible(showMenuControl)
        }
    }

    private let defaults: UserDefaults
    private weak var menuController: MenuController?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        showMenuControl = defaults.object(forKey: "showMenuControl") == nil || defaults.bool(forKey: "showMenuControl")
        applyAppearance()
    }

    func bindMenuController(_ controller: MenuController) {
        menuController = controller
        controller.setVisible(showMenuControl)
        applyAppearance()
    }

    func applyAppearance() {
        guard let app = NSApp else { return }
        let theme: NSAppearance? = appearance == .system ? nil :
            NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
        app.appearance = theme
        for window in app.windows where window.canBecomeKey { window.appearance = theme }
    }
}
