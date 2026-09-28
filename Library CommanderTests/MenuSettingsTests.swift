//
//  MenuSettingsTests.swift
//  Library CommanderTests
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM  Settings… and Accessibility… (build 51): text size limits, and forgetting a grant.
//

import Foundation
import Testing
@testable import Library_Commander

@MainActor
struct MenuSettingsTests {
    private func makeStore() -> StateStore {
        StateStore(defaults: UserDefaults(suiteName: "MenuSettingsTests-\(UUID().uuidString)")!)
    }

    @Test func textSizeStartsAt18AndStaysInItsRange() {
        #expect(TextSize.clamped(nil) == 18)
        #expect(TextSize.clamped(0) == 18)
        #expect(TextSize.clamped(4) == 12)
        #expect(TextSize.clamped(99) == 32)
        #expect(TextSize.clamped(24) == 24)
    }

    @Test func grantsAreListedAndForgotten() throws {
        let store = makeStore()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Grant-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        PaneModel(side: "left", store: store).choose(root: root)
        let path = root.standardizedFileURL.path
        #expect(store.grantPaths == [path])
        store.removeGrant(path)
        #expect(store.grantPaths.isEmpty)
        #expect(FileManager.default.fileExists(atPath: root.path))       // forgetting deletes nothing
        #expect(PaneModel(side: "right", store: store).go(toPath: path) == .needsPermission)
    }

    @Test func settingsAndToolbarShareOneValue() {
        // REM  Settings… binds straight to the pane, so both show the same saved setting.
        let store = makeStore()
        let commander = CommanderModel(store: store)
        commander.left.sortKey = .size                                   // as if set in Settings…
        #expect(PaneModel(side: "left", store: store).sortKey == .size)  // the toolbar reads the same
    }
}
