import Foundation
import XCTest

final class AccessibilityUITests: XCTestCase {
    private let reportURL = FileManager.default.temporaryDirectory.appendingPathComponent("songwave-native-ax-" + UUID().uuidString + ".json")
    @MainActor private func launch(_ screen: String, motion: Bool = false, scheme: String = "dark") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["SONGWAVE_AX_SCREEN": screen, "SONGWAVE_AX_REDUCE_MOTION": motion ? "1" : "0", "SONGWAVE_AX_SCHEME": scheme, "SONGWAVE_AX_REPORT": reportURL.path]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "support.heading").firstMatch.waitForExistence(timeout: 8))
        return app
    }
    @MainActor private func spoken(_ element: XCUIElement) -> String { element.label.isEmpty ? element.title : element.label }
    @MainActor private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .action, .parentChild])
    }
    @MainActor func testConfirmationLabelsRolesAndReadingOrder() throws {
        let app = launch("confirmation")
        defer { app.terminate() }
        let ids = ["setup.test", "setup.confirm", "setup.recover", "setup.help", "support.done"]
        for id in ids { XCTAssertTrue(app.buttons[id].exists, "Missing button role: \(id)"); XCTAssertFalse(spoken(app.buttons[id]).isEmpty) }
        let order = app.buttons.allElementsBoundByIndex.map(\.identifier).filter { ids.contains($0) }
        XCTAssertEqual(order, ids, "VoiceOver's button reading order must follow Test, confirm/recover, help, then exit.")
        XCTAssertEqual(spoken(app.buttons["setup.confirm"]), "I felt it")
        XCTAssertTrue(app.otherElements["music.activity"].exists)
        XCTAssertFalse(app.buttons["music.activity"].exists, "Activity is information, not an action.")
        try audit(app)
        app.typeKey("j", modifierFlags: [.command, .shift])
        let exists = NSPredicate { _, _ in FileManager.default.fileExists(atPath: self.reportURL.path) }
        expectation(for: exists, evaluatedWith: nil)
        waitForExpectations(timeout: 4)
        let nodes = try JSONSerialization.jsonObject(with: Data(contentsOf: reportURL)) as! [[String: String]]
        for id in ["support.heading", "setup.test.heading", "setup.confirm.heading"] {
            XCTAssertEqual(nodes.first { $0["id"] == id }?["role"], "AXHeading", "Missing native heading trait: \(id)")
        }
        try? FileManager.default.removeItem(at: reportURL)
        app.buttons["setup.recover"].click()
        XCTAssertTrue(app.buttons["recovery.trackpad.retry"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["setup.confirm"].exists)
    }
    @MainActor func testRecoveryActionsHaveContextAndOrder() throws {
        let app = launch("recovery")
        defer { app.terminate() }
        let ids = ["recovery.trackpad.retry", "recovery.trackpad.settings", "recovery.capture.retry", "recovery.capture.settings",
                   "recovery.app.retry", "recovery.app.settings", "recovery.pause.retry", "recovery.pause.settings", "recovery.check", "recovery.copy", "support.done"]
        let order = app.buttons.allElementsBoundByIndex.map(\.identifier).filter { ids.contains($0) }
        XCTAssertEqual(order, ids)
        XCTAssertEqual(spoken(app.buttons["recovery.trackpad.retry"]), "Retry trackpad")
        XCTAssertEqual(spoken(app.buttons["recovery.app.retry"]), "Rescan music apps")
        try audit(app)
    }
    @MainActor func testPermissionAndTestingStates() throws {
        for screen in ["permission", "testing"] {
            let app = launch(screen)
            if screen == "testing" {
                XCTAssertFalse(app.buttons["setup.test"].isEnabled)
                XCTAssertFalse(app.buttons["setup.confirm"].exists)
                XCTAssertFalse(app.buttons["support.done"].isEnabled)
            }
            try audit(app)
            app.terminate()
        }
    }
    @MainActor func testReducedMotionKeepsFeedbackAndSemantics() throws {
        for screen in ["confirmation", "recovery"] {
            for scheme in ["light", "dark"] {
                let app = launch(screen, motion: true, scheme: scheme)
                if screen == "confirmation" {
                    let activity = app.otherElements["music.activity"]
                    XCTAssertTrue(activity.exists)
                    XCTAssertTrue((activity.value as? String ?? "").contains("percent"))
                }
                try audit(app)
                app.terminate()
            }
        }
    }
}
