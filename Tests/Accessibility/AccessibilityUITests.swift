import Foundation
import XCTest

final class AccessibilityUITests: XCTestCase {
    @MainActor private func launch(_ screen: String, motion: Bool = false, scheme: String = "dark") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["SONGWAVE_AX_SCREEN": screen, "SONGWAVE_AX_REDUCE_MOTION": motion ? "1" : "0", "SONGWAVE_AX_SCHEME": scheme]
        app.launch()
        app.activate()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "support.heading").firstMatch.waitForExistence(timeout: 8))
        return app
    }
    @MainActor private func spoken(_ element: XCUIElement) -> String { element.label.isEmpty ? element.title : element.label }
    @MainActor private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .action, .parentChild]) { issue in
            // The fixture has no Touch Bar UI. Xcode nevertheless audits its
            // empty system-provided TouchBar node on hosted Macs.
            if issue.element?.elementType == .touchBar { return true }
            if let element = issue.element, element.elementType == .group,
               element.identifier.isEmpty, element.label.isEmpty, !element.isEnabled {
                // Only the synthetic NSHostingView wrapping all fixture content.
                // It is outside the production support.content group.
                if issue.auditType == .sufficientElementDescription,
                   element.frame == app.windows.firstMatch.frame,
                   element.descendants(matching: .group).matching(identifier: "support.content").count == 1 { return true }
                // macOS's nested Full Screen glyph is not application content.
                let fullScreen = app.buttons["_XCUI:FullScreenWindow"]
                if issue.auditType == .parentChild, fullScreen.exists,
                   fullScreen.frame.contains(element.frame) { return true }
            }
            print("AX audit: \(issue.detailedDescription) | \(issue.element?.debugDescription ?? "no element")")
            return false
        }
    }
    @MainActor private func hierarchyNodes(_ app: XCUIApplication) throws -> [[String: String]] {
        var nodes: [[String: String]] = []
        func walk(_ element: XCUIElementSnapshot) {
            nodes.append(["id": element.identifier, "role": String(element.elementType.rawValue),
                          "label": element.label, "value": String(describing: element.value ?? "")])
            for child in element.children { walk(child) }
        }
        walk(try app.windows.firstMatch.snapshot())
        return nodes
    }
    private func assertOrder(_ nodes: [[String: String]], _ ids: [String], file: StaticString = #filePath, line: UInt = #line) {
        // A flattened XCUI button query returns shallower siblings before the
        // scroll area's descendants, which is not native navigation order.
        XCTAssertEqual(nodes.compactMap { $0["id"] }.filter { ids.contains($0) }, ids, file: file, line: line)
    }
    @MainActor func testConfirmationLabelsRolesAndReadingOrder() throws {
        let app = launch("confirmation")
        defer { app.terminate() }
        let ids = ["setup.test", "setup.confirm", "setup.recover", "setup.help", "support.done"]
        for id in ids { XCTAssertTrue(app.buttons[id].exists, "Missing button role: \(id)"); XCTAssertFalse(spoken(app.buttons[id]).isEmpty) }
        let nodes = try hierarchyNodes(app)
        assertOrder(nodes, ids)
        XCTAssertEqual(spoken(app.buttons["setup.confirm"]), "I felt it")
        XCTAssertTrue(app.progressIndicators["music.activity"].exists)
        XCTAssertFalse(app.buttons["music.activity"].exists, "Activity is information, not an action.")
        try audit(app)
        for id in ["support.heading", "setup.test.heading", "setup.confirm.heading"] {
            XCTAssertEqual(nodes.first { $0["id"] == id }?["role"], String(XCUIElement.ElementType.staticText.rawValue), "Missing heading text: \(id)")
        }
        app.buttons["setup.recover"].click()
        XCTAssertTrue(app.buttons["recovery.trackpad.retry"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["setup.confirm"].exists)
    }
    @MainActor func testRecoveryActionsHaveContextAndOrder() throws {
        let app = launch("recovery")
        defer { app.terminate() }
        let ids = ["recovery.trackpad.retry", "recovery.trackpad.settings", "recovery.capture.retry", "recovery.capture.settings",
                   "recovery.app.retry", "recovery.app.settings", "recovery.pause.retry", "recovery.pause.settings", "recovery.check", "recovery.copy", "support.done"]
        let nodes = try hierarchyNodes(app)
        assertOrder(nodes, ids)
        for title in ["Trackpad", "Audio capture", "Selected app", "Listening state"] {
            XCTAssertEqual(nodes.first { $0["id"] == "recovery.heading." + title }?["role"], String(XCUIElement.ElementType.staticText.rawValue))
        }
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
                    let activity = app.progressIndicators["music.activity"]
                    XCTAssertTrue(activity.exists)
                    XCTAssertEqual(spoken(activity), "Visual music activity")
                    XCTAssertNotNil(activity.value)
                }
                try audit(app)
                app.terminate()
            }
        }
    }
}
