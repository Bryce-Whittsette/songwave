import AppKit
import ApplicationServices
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
            print("AX audit: \(issue.detailedDescription) | \(issue.element?.debugDescription ?? "no element")")
            return false
        }
    }
    @MainActor private func nativeNodes(_ app: XCUIApplication) throws -> [[String: String]] {
        let running = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "studio.songwave.accessibility.fixture").first)
        let root = AXUIElementCreateApplication(running.processIdentifier)
        var nodes: [[String: String]] = []
        func attribute(_ element: AXUIElement, _ key: CFString) -> CFTypeRef? {
            var result: CFTypeRef?
            let status = AXUIElementCopyAttributeValue(element, key, &result)
            if status != .success && status != .noValue && status != .attributeUnsupported {
                XCTFail("Native AX read failed: \(status.rawValue). No permission/security setting is changed by this test.")
            }
            return result
        }
        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 40 else { return }
            nodes.append(["id": attribute(element, kAXIdentifierAttribute as CFString) as? String ?? "",
                          "role": attribute(element, kAXRoleAttribute as CFString) as? String ?? "",
                          "valueDescription": attribute(element, kAXValueDescriptionAttribute as CFString) as? String ?? ""])
            for child in attribute(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? [] { walk(child, depth: depth + 1) }
        }
        walk(root, depth: 0)
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
        let nodes = try nativeNodes(app)
        assertOrder(nodes, ids)
        XCTAssertEqual(spoken(app.buttons["setup.confirm"]), "I felt it")
        XCTAssertTrue(app.progressIndicators["music.activity"].exists)
        XCTAssertFalse(app.buttons["music.activity"].exists, "Activity is information, not an action.")
        try audit(app)
        for id in ["support.heading", "setup.test.heading", "setup.confirm.heading"] {
            XCTAssertEqual(nodes.first { $0["id"] == id }?["role"], "AXHeading", "Missing native heading trait: \(id)")
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
        let nodes = try nativeNodes(app)
        assertOrder(nodes, ids)
        for title in ["Trackpad", "Audio capture", "Selected app", "Listening state"] {
            XCTAssertEqual(nodes.first { $0["id"] == "recovery.heading." + title }?["role"], "AXHeading")
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
                    let nodes = try nativeNodes(app)
                    XCTAssertTrue(nodes.first { $0["id"] == "music.activity" }?["valueDescription"]?.contains("percent") == true)
                }
                try audit(app)
                app.terminate()
            }
        }
    }
}
