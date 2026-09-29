//
//  MultiSelectTests.swift
//  Library CommanderTests
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM  Build 59: multi-select like Finder — his ask, 2026-09-28: "yes like finder".
// REM  click = one row · ⌘-click = add/remove · ⇧-click = range · ⇧↑/⇧↓ = grow the range ·
// REM  every command acts on all highlighted rows · the highlight is saved.
//

import Foundation
import Testing
@testable import Library_Commander

@MainActor
struct MultiSelectTests {
    private func makeStore() -> StateStore {
        StateStore(defaults: UserDefaults(suiteName: "MultiSelectTests-\(UUID().uuidString)")!)
    }

    /// Source/{a, b, c, d, e}.mp4 and Target/
    private func makeTree() throws -> (URL, URL) {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("MultiSelectTests-\(UUID().uuidString)")
        let source = base.appendingPathComponent("Source"), target = base.appendingPathComponent("Target")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        for n in ["a", "b", "c", "d", "e"] { try Data(n.utf8).write(to: source.appendingPathComponent("\(n).mp4")) }
        return (source, target)
    }

    private func id(_ pane: PaneModel, _ name: String) -> String {
        pane.rows.first { $0.entry.name == name }!.id
    }

    private func picked(_ pane: PaneModel) -> [String] { pane.selectedEntries.map(\.name) }

    @Test func aPlainClickPicksOneRow() throws {
        let pane = PaneModel(side: "left", store: makeStore())
        pane.choose(root: try makeTree().0)
        pane.click(id(pane, "b.mp4"), command: false, shift: false)
        pane.click(id(pane, "d.mp4"), command: false, shift: false)
        #expect(picked(pane) == ["d.mp4"])
    }

    @Test func commandClickAddsAndRemoves() throws {
        let pane = PaneModel(side: "left", store: makeStore())
        pane.choose(root: try makeTree().0)
        pane.click(id(pane, "a.mp4"), command: false, shift: false)
        pane.click(id(pane, "c.mp4"), command: true, shift: false)
        pane.click(id(pane, "e.mp4"), command: true, shift: false)
        #expect(picked(pane) == ["a.mp4", "c.mp4", "e.mp4"])
        pane.click(id(pane, "c.mp4"), command: true, shift: false)       // ⌘-click again removes it
        #expect(picked(pane) == ["a.mp4", "e.mp4"])
    }

    @Test func shiftClickTakesTheRange() throws {
        let pane = PaneModel(side: "left", store: makeStore())
        pane.choose(root: try makeTree().0)
        pane.click(id(pane, "b.mp4"), command: false, shift: false)
        pane.click(id(pane, "d.mp4"), command: false, shift: true)
        #expect(picked(pane) == ["b.mp4", "c.mp4", "d.mp4"])
        pane.click(id(pane, "a.mp4"), command: false, shift: true)       // the anchor stays on b
        #expect(picked(pane) == ["a.mp4", "b.mp4"])
    }

    @Test func shiftArrowsGrowAndShrinkTheRange() throws {
        let pane = PaneModel(side: "left", store: makeStore())
        pane.choose(root: try makeTree().0)
        pane.click(id(pane, "b.mp4"), command: false, shift: false)
        pane.moveSelection(by: 1, extend: true)
        pane.moveSelection(by: 1, extend: true)
        #expect(picked(pane) == ["b.mp4", "c.mp4", "d.mp4"])
        pane.moveSelection(by: -1, extend: true)
        #expect(picked(pane) == ["b.mp4", "c.mp4"])
        pane.moveSelection(by: 1)                                          // a plain arrow: one row again
        #expect(picked(pane) == ["d.mp4"])
    }

    @Test func theMultiSelectionComesBackAfterReopening() throws {
        let store = makeStore()
        let first = PaneModel(side: "left", store: store)
        first.choose(root: try makeTree().0)
        first.click(id(first, "a.mp4"), command: false, shift: false)
        first.click(id(first, "c.mp4"), command: true, shift: false)
        let reopened = PaneModel(side: "left", store: store)
        reopened.restore()
        #expect(picked(reopened) == ["a.mp4", "c.mp4"])
    }

    @Test func deleteTrashesEveryHighlightedRow() throws {
        let (source, target) = try makeTree()
        let commander = CommanderModel(store: makeStore())
        commander.left.choose(root: source)
        commander.right.choose(root: target)
        commander.left.click(id(commander.left, "b.mp4"), command: false, shift: false)
        commander.left.click(id(commander.left, "d.mp4"), command: true, shift: false)
        commander.runQuickKey(8)
        for t in commander.trashedThisTime.compactMap({ $0 }) { try? FileManager.default.removeItem(at: t) }
        #expect(commander.left.entries.map(\.name) == ["a.mp4", "c.mp4", "e.mp4"])
        #expect(commander.left.selectedEntry?.name == "c.mp4")          // the row after the first removed
    }

    @Test func moveTakesEveryHighlightedRowAsOneJob() async throws {
        let (source, target) = try makeTree()
        let commander = CommanderModel(store: makeStore())
        commander.left.choose(root: source)
        commander.right.choose(root: target)
        commander.left.click(id(commander.left, "a.mp4"), command: false, shift: false)
        commander.left.click(id(commander.left, "c.mp4"), command: false, shift: true)
        commander.runQuickKey(6)
        for _ in 0..<100 where commander.busy != nil { try await Task.sleep(for: .milliseconds(50)) }
        #expect(commander.right.entries.map(\.name) == ["a.mp4", "b.mp4", "c.mp4"])
        #expect(commander.left.entries.map(\.name) == ["d.mp4", "e.mp4"])
    }

    @Test func renameNeedsExactlyOneRow() throws {
        let commander = CommanderModel(store: makeStore())
        commander.left.choose(root: try makeTree().0)
        commander.left.click(id(commander.left, "a.mp4"), command: false, shift: false)
        commander.left.click(id(commander.left, "b.mp4"), command: true, shift: false)
        commander.runQuickKey(9)
        #expect(!commander.left.askingRename)
        #expect(commander.statusIsProblem)
    }

    @Test func severalHighlightedInTheDestinationTargetTheOpenFolder() throws {
        let (source, _) = try makeTree()
        try FileManager.default.createDirectory(at: source.appendingPathComponent("F1"), withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("F2"), withIntermediateDirectories: false)
        let pane = PaneModel(side: "right", store: makeStore())
        pane.choose(root: source)
        pane.click(id(pane, "F1"), command: false, shift: false)
        pane.click(id(pane, "F2"), command: true, shift: false)
        guard case .openFolder = pane.copyTarget else { Issue.record("expected the open folder"); return }
    }
}
