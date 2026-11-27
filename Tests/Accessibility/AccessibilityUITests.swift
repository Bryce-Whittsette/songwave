import Foundation
import XCTest

final class AccessibilityUITests: XCTestCase {
    @MainActor private func launch(_ screen: String, motion: Bool = false, scheme: String = "dark", compact: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["SONGWAVE_AX_SCREEN": screen, "SONGWAVE_AX_REDUCE_MOTION": motion ? "1" : "0", "SONGWAVE_AX_SCHEME": scheme, "SONGWAVE_AX_COMPACT": compact ? "1" : "0"]
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: screen == "player" ? "tools.open" : "support.heading").firstMatch.waitForExistence(timeout: 8))
        return app
    }
    @MainActor private func spoken(_ element: XCUIElement) -> String { element.label.isEmpty ? element.title : element.label }
    @MainActor private func audit(_ app: XCUIApplication, contentID: String? = nil) throws {
        // XCTest audits every window, including the player behind a modal sheet.
        // For sheet tests, match issues to the owned content subtree; do not
        // audit blocked background actions or AppKit's hosting/window wrappers.
        var owned: [XCUIElementSnapshot] = []
        if let contentID {
            let content = app.descendants(matching: .any).matching(identifier: contentID).firstMatch
            XCTAssertTrue(content.waitForExistence(timeout: 4), "Missing audit scope: " + contentID)
            func walk(_ node: XCUIElementSnapshot) {
                owned.append(node)
                for child in node.children { walk(child) }
            }
            walk(try content.snapshot())
            XCTAssertGreaterThan(owned.count, 3, "The active content must expose its children for auditing.")
        }
        let scopedNodes = owned
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .action, .parentChild]) { issue in
            if contentID != nil, let element = issue.element {
                let belongs = scopedNodes.contains { node in
                    node.elementType == element.elementType && node.identifier == element.identifier &&
                    node.label == element.label && node.frame == element.frame
                }
                if !belongs { return true }
            }
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
    @MainActor func testPermissionToExplicitSensationConfirmation() throws {
        let app = launch("permission")
        defer { app.terminate() }
        XCTAssertFalse(app.buttons["setup.confirm"].exists)
        app.buttons["setup.allow"].click()
        XCTAssertTrue(app.buttons["setup.test"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["setup.confirm"].exists, "Permission success cannot imply sensation.")
        XCTAssertTrue(app.progressIndicators["music.activity"].exists)
        app.buttons["setup.test"].click()
        XCTAssertFalse(app.buttons["setup.test"].isEnabled)
        XCTAssertFalse(app.buttons["support.done"].isEnabled)
        app.typeKey("t", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.buttons["setup.confirm"].waitForExistence(timeout: 5))
        app.buttons["setup.confirm"].click()
        XCTAssertTrue(app.buttons["recovery.check"].waitForExistence(timeout: 5))
        XCTAssertEqual(spoken(app.buttons["support.done"]), "Done")
        XCTAssertFalse(app.buttons["setup.confirm"].exists)
    }
    @MainActor func testRecoveryRetriesRemainInOnePlace() throws {
        let app = launch("recovery")
        defer { app.terminate() }
        for id in ["recovery.trackpad.retry", "recovery.capture.retry", "recovery.app.retry", "recovery.pause.retry"] {
            app.buttons[id].click()
            XCTAssertTrue(app.buttons["recovery.check"].waitForExistence(timeout: 4))
            XCTAssertFalse(app.buttons["setup.test"].exists, "Only Run setup check should leave recovery for another sensation check.")
        }
        app.buttons["recovery.check"].click()
        XCTAssertTrue(app.buttons["setup.test"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["setup.confirm"].exists)
        try audit(app)
    }
    @MainActor func testEverydayPlayerGroupsOptionalAndAdvancedControls() throws {
        let app = launch("player")
        defer { app.terminate() }
        let optionalFile = app.buttons["Open audio file…"]
        XCTAssertFalse(optionalFile.exists)
        XCTAssertFalse(app.buttons["Fine Tune…"].exists)
        XCTAssertFalse(app.buttons["Insane Ultra…"].exists)
        XCTAssertFalse(app.staticTexts["Trackpad EQ"].exists)
        let sources = app.buttons["sources.toggle"]
        XCTAssertEqual(spoken(sources), "Other sources · link or file")
        sources.click()
        let revealed = optionalFile.waitForExistence(timeout: 4)
        if !revealed { print(app.debugDescription) }
        XCTAssertTrue(revealed)
        sources.click()
        XCTAssertFalse(optionalFile.exists)
        app.buttons["tools.open"].click()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "tools.heading").firstMatch.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Fine Tune…"].exists)
        XCTAssertFalse(app.staticTexts["tools.eq.heading"].exists)
        app.radioButtons["Trackpad EQ"].click()
        XCTAssertTrue(app.staticTexts["tools.eq.heading"].exists)
    }
    @MainActor func testAdvancedToolCategoriesPreserveSettingsAndRequireUltraConfirmation() throws {
        for motion in [false, true] {
            for scheme in ["light", "dark"] {
                let app = launch("player", motion: motion, scheme: scheme, compact: true)
                let intensity = app.buttons["Intensity"].value as? String
                app.buttons["tools.open"].click()
                XCTAssertTrue(app.staticTexts["tools.sound.heading"].waitForExistence(timeout: 4))
                let genre = app.descendants(matching: .any).matching(identifier: "tools.genre").firstMatch.value as? String
                XCTAssertFalse(app.buttons["tools.ultra.open"].exists)
                XCTAssertFalse(app.buttons["Bass"].exists)
                for title in ["Sound", "Trackpad EQ", "Experiments"] {
                    XCTAssertTrue(app.radioButtons[title].isHittable)
                }
                try audit(app, contentID: "tools.content")
                app.radioButtons["Trackpad EQ"].click()
                XCTAssertTrue(app.staticTexts["tools.eq.heading"].waitForExistence(timeout: 4))
                XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "tools.genre").firstMatch.exists)
                XCTAssertFalse(app.buttons["tools.tuning.open"].exists)
                XCTAssertFalse(app.buttons["tools.ultra.open"].exists)
                let bass = app.buttons["Bass"].value as? String
                XCTAssertTrue(app.buttons["Band Settings…"].isHittable)
                try audit(app, contentID: "tools.content")
                app.buttons["Band Settings…"].click()
                XCTAssertTrue(app.staticTexts["eq.bands.heading"].waitForExistence(timeout: 4))
                assertOrder(try hierarchyNodes(app), ["eq.bands.heading", "eq.band.Bass", "eq.band.Mid", "eq.band.Treble"])
                XCTAssertTrue(app.buttons["Treble width (Q)"].isHittable)
                try audit(app, contentID: "eq.bands.content")
                app.buttons["Done"].click()
                app.buttons["tools.open"].click()
                XCTAssertTrue(app.staticTexts["tools.eq.heading"].waitForExistence(timeout: 4))
                XCTAssertEqual(app.buttons["Bass"].value as? String, bass)
                app.radioButtons["Experiments"].click()
                XCTAssertTrue(app.staticTexts["tools.experiments.heading"].exists)
                XCTAssertTrue(app.buttons["tools.ultra.open"].isHittable)
                XCTAssertFalse(app.buttons["Bass"].exists)
                XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "tools.genre").firstMatch.exists)
                XCTAssertFalse(app.buttons["Start Ultra"].exists)
                try audit(app, contentID: "tools.content")
                app.buttons["tools.ultra.open"].click()
                XCTAssertTrue(app.staticTexts["ultra.heading"].waitForExistence(timeout: 4))
                XCTAssertTrue(app.buttons["Start Ultra"].isHittable)
                XCTAssertTrue(app.buttons["Cancel"].isHittable)
                try audit(app, contentID: "ultra.content")
                app.buttons["Cancel"].click()
                XCTAssertTrue(app.buttons["Listen to Mac audio"].waitForExistence(timeout: 4))
                XCTAssertFalse(app.buttons["Stop Ultra"].exists)
                XCTAssertEqual(app.buttons["Intensity"].value as? String, intensity)
                app.buttons["tools.open"].click()
                app.radioButtons["Sound"].click()
                XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "tools.genre").firstMatch.value as? String, genre)
                app.terminate()
            }
        }
    }
    @MainActor func testFineTuneChunksFollowFeelAndOutput() throws {
        for output in ["Speakers + haptics", "Trackpad only"] {
            for feel in ["Beat", "Voice", "Both"] {
                let app = launch("player", compact: true)
                app.buttons[output].click()
                app.radioButtons[feel].click()
                app.buttons["tools.open"].click()
                XCTAssertTrue(app.buttons["tools.tuning.open"].waitForExistence(timeout: 4))
                XCTAssertEqual(app.checkBoxes["Follow Mac volume"].isEnabled, output != "Trackpad only")
                let quality = app.radioButtons["Isolated"]
                if output == "Trackpad only" && feel == "Voice" {
                    XCTAssertTrue(quality.exists)
                    XCTAssertEqual((quality.value as? NSNumber)?.intValue ?? Int(quality.value as? String ?? ""), 0, "Grouping must not switch the saved isolation choice.")
                } else { XCTAssertFalse(quality.exists) }
                app.buttons["tools.tuning.open"].click()
                XCTAssertTrue(app.staticTexts["tuning.heading"].waitForExistence(timeout: 4))
                XCTAssertEqual(app.staticTexts["tuning.beat.heading"].exists, feel != "Voice")
                XCTAssertEqual(app.staticTexts["tuning.voice.heading"].exists, feel != "Beat")
                XCTAssertEqual(app.staticTexts["tuning.timing.heading"].exists, output != "Trackpad only")
                var order = ["tuning.heading"]
                if feel != "Voice" { order.append("tuning.beat.heading") }
                if feel != "Beat" { order.append("tuning.voice.heading") }
                if output != "Trackpad only" { order.append("tuning.timing.heading") }
                assertOrder(try hierarchyNodes(app), order)
                let last = output == "Trackpad only" ? (feel == "Beat" ? "Transient emphasis" : "Pitch smoothing") : "Timing offset"
                app.descendants(matching: .any).matching(identifier: "tuning.content").firstMatch.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -1000)
                XCTAssertTrue(app.buttons[last].isHittable, "Every applicable section must remain reachable in a compact window.")
                XCTAssertTrue(app.buttons["Reset Tuning"].isHittable)
                XCTAssertTrue(app.buttons["Done"].isHittable)
                try audit(app, contentID: "tuning.content")
                app.buttons["Done"].click()
                XCTAssertTrue(app.buttons["Listen to Mac audio"].waitForExistence(timeout: 4))
                app.terminate()
            }
        }
    }
    @MainActor func testRecoveryStartsAtTopAfterScrollingSetup() throws {
        let app = launch("confirmation", compact: true)
        defer { app.terminate() }
        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -900)
        XCTAssertTrue(app.buttons["setup.recover"].isHittable)
        app.buttons["setup.recover"].click()
        let retry = app.buttons["recovery.trackpad.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 4))
        XCTAssertTrue(retry.isHittable, "Entering recovery must reveal the first connection status, not keep the previous scroll offset.")
    }
    @MainActor func testMainVisualFeedbackWorksWithHapticsOff() throws {
        for motion in [false, true] {
            for scheme in ["light", "dark"] {
                let app = launch("player", motion: motion, scheme: scheme, compact: true)
                app.typeKey("m", modifierFlags: [.command, .shift])
                let activity = app.progressIndicators["music.activity"]
                XCTAssertTrue(activity.waitForExistence(timeout: 4))
                XCTAssertEqual(spoken(activity), "Visual rhythm and music level")
                XCTAssertEqual(app.progressIndicators.matching(identifier: "music.activity").count, 1)
                XCTAssertFalse(app.buttons["music.activity"].exists, "The display must remain passive.")
                func level() -> Double {
                    (activity.value as? NSNumber)?.doubleValue ?? Double(activity.value as? String ?? "") ?? -1
                }
                XCTAssertGreaterThan(level(), 0)
                let off = app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", "Haptics off", "Haptics off")).firstMatch
                XCTAssertTrue(off.exists, "Visual music feedback must work independently of enabled haptics.")
                let stop = app.buttons["Stop listening"]
                XCTAssertTrue(stop.exists)
                XCTAssertGreaterThan(activity.frame.width, 0)
                XCTAssertLessThanOrEqual(app.windows.firstMatch.frame.width, 812, "This test must exercise the compact player, not a restored larger window.")
                XCTAssertTrue(app.windows.firstMatch.frame.contains(activity.frame), "Feedback must stay visible in the minimum player window.")
                XCTAssertFalse(activity.frame.intersects(stop.frame))
                XCTAssertFalse(activity.frame.intersects(app.buttons["Intensity"].frame))
                XCTAssertFalse(app.buttons["setup.test"].exists, "This feedback belongs to listening, outside setup.")
                app.typeKey("s", modifierFlags: [.command, .shift])
                XCTAssertEqual(level(), 0)
                stop.click()
                XCTAssertTrue(app.buttons["Listen to Mac audio"].waitForExistence(timeout: 4))
                app.terminate()
            }
        }
    }
}
