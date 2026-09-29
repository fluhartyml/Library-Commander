//
//  ArrowMoveCopyTests.swift
//  Library CommanderTests
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM  Build 62: arrow move and copy, and the arrow back. His rules, 2026-09-28:
// REM   • ⌘ + arrow toward the destination MOVES, ⇧⌘ COPIES ("command moves and shift command copies")
// REM   • the arrow back toward the source UNDOES the whole last forward, all of its files
// REM   • "its only one for one no histories" — one undo, never two
// REM   • off until turned on in Accessibility
//

import Foundation
import Testing
@testable import Library_Commander

@MainActor
struct ArrowMoveCopyTests {
    private let fm = FileManager.default

    /// Left = Source/{a, b, c}.mp4 (active), right = Target/. Arrow move and copy ON.
    private func setUp(on: Bool = true) throws -> (CommanderModel, URL, URL) {
        let base = fm.temporaryDirectory.appendingPathComponent("ArrowMoveCopyTests-\(UUID().uuidString)")
        let source = base.appendingPathComponent("Source"), target = base.appendingPathComponent("Target")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        for n in ["a", "b", "c"] { try Data(n.utf8).write(to: source.appendingPathComponent("\(n).mp4")) }
        let store = StateStore(defaults: UserDefaults(suiteName: "ArrowMoveCopyTests-\(UUID().uuidString)")!)
        store.defaults.set(on, forKey: ArrowMoveCopy.key)
        let commander = CommanderModel(store: store)
        commander.left.choose(root: source)
        commander.right.choose(root: target)
        commander.activeSide = .left
        return (commander, source, target)
    }

    private func pick(_ commander: CommanderModel, _ names: [String]) {
        let pane = commander.left
        for (i, name) in names.enumerated() {
            pane.click(pane.rows.first { $0.entry.name == name }!.id, command: i > 0, shift: false)
        }
    }

    private func settle(_ commander: CommanderModel) async throws {
        for _ in 0..<100 where commander.busy != nil { try await Task.sleep(for: .milliseconds(50)) }
    }

    private func names(_ url: URL) -> [String] {
        ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }

    @Test func offMeansNothingMovesAndItSaysWhere() throws {
        let (commander, source, _) = try setUp(on: false)
        pick(commander, ["a.mp4"])
        commander.arrow(towardRight: true, copy: false)
        #expect(names(source) == ["a.mp4", "b.mp4", "c.mp4"])
        #expect(commander.status.contains("Accessibility"))
    }

    @Test func commandArrowTowardTheDestinationMoves() async throws {
        let (commander, source, target) = try setUp()
        pick(commander, ["a.mp4", "c.mp4"])
        commander.arrow(towardRight: true, copy: false)                     // ⌘→, left is the source
        try await settle(commander)
        #expect(names(source) == ["b.mp4"])
        #expect(names(target) == ["a.mp4", "c.mp4"])
    }

    @Test func shiftCommandArrowCopies() async throws {
        let (commander, source, target) = try setUp()
        pick(commander, ["b.mp4"])
        commander.arrow(towardRight: true, copy: true)                      // ⇧⌘→
        try await settle(commander)
        #expect(names(source) == ["a.mp4", "b.mp4", "c.mp4"])
        #expect(names(target) == ["b.mp4"])
    }

    @Test func theArrowBackPutsAWholeMoveBack() async throws {
        let (commander, source, target) = try setUp()
        pick(commander, ["a.mp4", "b.mp4", "c.mp4"])
        commander.arrow(towardRight: true, copy: false)
        try await settle(commander)
        commander.arrow(towardRight: false, copy: false)                    // ⌘← — back toward the source
        #expect(names(source) == ["a.mp4", "b.mp4", "c.mp4"])
        #expect(names(target).isEmpty)
    }

    @Test func theArrowBackRemovesWhatACopyMade() async throws {
        let (commander, source, target) = try setUp()
        pick(commander, ["a.mp4", "b.mp4"])
        commander.arrow(towardRight: true, copy: true)
        try await settle(commander)
        commander.arrow(towardRight: false, copy: true)
        #expect(names(target).isEmpty)
        #expect(names(source) == ["a.mp4", "b.mp4", "c.mp4"])               // originals untouched
    }

    @Test func oneUndoNoHistory() async throws {
        // REM  "its only one for one no histories"
        let (commander, source, target) = try setUp()
        pick(commander, ["a.mp4"])
        commander.arrow(towardRight: true, copy: false)
        try await settle(commander)
        pick(commander, ["b.mp4"])
        commander.arrow(towardRight: true, copy: false)
        try await settle(commander)
        commander.arrow(towardRight: false, copy: false)                    // undoes b only
        #expect(names(target) == ["a.mp4"])
        commander.arrow(towardRight: false, copy: false)                    // nothing left to undo
        #expect(names(target) == ["a.mp4"])
        #expect(commander.status == "Nothing to undo.")
        #expect(names(source) == ["b.mp4", "c.mp4"])
    }

    @Test func theDirectionFlipsWhenTheRightPaneIsTheSource() async throws {
        let (commander, _, target) = try setUp()
        try Data("z".utf8).write(to: target.appendingPathComponent("z.mp4"))
        commander.right.reload()
        commander.activeSide = .right                                       // right is now the source
        commander.right.click(commander.right.rows.first { $0.entry.name == "z.mp4" }!.id, command: false, shift: false)
        commander.arrow(towardRight: false, copy: false)                    // ⌘← now points at the destination
        try await settle(commander)
        #expect(names(target).isEmpty)
        commander.arrow(towardRight: true, copy: false)                     // ⌘→ points back — undo
        #expect(names(target) == ["z.mp4"])
    }

    @Test func undoingAReplaceBringsTheOldOneBackFromTheTrash() async throws {
        let base = fm.temporaryDirectory.appendingPathComponent("ArrowUndoReplace-\(UUID().uuidString)")
        let src = base.appendingPathComponent("s/a.mp4"), dst = base.appendingPathComponent("d/a.mp4")
        try fm.createDirectory(at: src.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("new".utf8).write(to: src)
        try Data("old!".utf8).write(to: dst)
        let summary = try await TransferEngine(move: true, ask: { _ in ClashAnswer(choice: .replace, applyToAll: false) })
            .run(src, into: dst.deletingLastPathComponent())
        let result = TransferEngine.undo(summary.journal, wasMove: true)
        #expect(result.problems.isEmpty)
        #expect(String(decoding: try Data(contentsOf: src), as: UTF8.self) == "new")    // back in the source
        #expect(String(decoding: try Data(contentsOf: dst), as: UTF8.self) == "old!")   // old one restored
    }

    @Test func commandUpDownStepOneRowWhenOn() throws {
        // REM  Build 63: "so i dont have to release the sticky keys"
        let (commander, source, _) = try setUp()
        pick(commander, ["a.mp4"])
        commander.commandUpDown(up: false)
        #expect(commander.left.selectedEntry?.name == "b.mp4")
        commander.commandUpDown(up: true)
        #expect(commander.left.selectedEntry?.name == "a.mp4")
        #expect(commander.left.currentURL?.standardizedFileURL.path == source.standardizedFileURL.path)
    }

    @Test func commandUpKeepsFindersMeaningWhenOff() throws {
        let (commander, _, _) = try setUp(on: false)
        commander.commandUpDown(up: true)                                   // at the top: the drive list
        #expect(commander.left.showingDrives)
    }

    @Test func quickLookFollowsTheHighlightWhileOpen() async throws {
        // REM  Build 64 — his goal: step with ⌘↓/⌘↑, send with ⌘←, the preview keeps up.
        let (commander, _, _) = try setUp()
        pick(commander, ["a.mp4"])
        commander.commandUpDown(up: false)
        commander.quickLookFollow()
        #expect(commander.quickLookURL == nil)                              // closed: stays closed
        commander.runQuickKey(3)                                            // ⌘3 opens it on b
        #expect(commander.quickLookURL?.lastPathComponent == "b.mp4")
        commander.commandUpDown(up: false)
        commander.quickLookFollow()
        #expect(commander.quickLookURL?.lastPathComponent == "c.mp4")
        commander.commandUpDown(up: true)
        commander.quickLookFollow()
        commander.arrow(towardRight: true, copy: false)                     // ⌘→ sends b to the target
        try await settle(commander)
        commander.quickLookFollow()
        #expect(commander.quickLookURL?.lastPathComponent == "c.mp4")       // the next file, previewed
    }
}
