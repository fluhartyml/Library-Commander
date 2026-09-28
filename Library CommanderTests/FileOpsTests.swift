//
//  FileOpsTests.swift
//  Library CommanderTests
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM  Build 56: the quick-access bar's file commands. The rules proven here are the safety
// REM  rules in FileOps.swift: nothing is ever overwritten, a clash says whether the two are
// REM  identical, a move never loses the original, delete goes to the Trash, and after a move
// REM  or delete the next row lights up (his ask from the old app).
//

import Foundation
import Testing
@testable import Library_Commander

@MainActor
struct FileOpsTests {
    private func makeStore() -> StateStore {
        StateStore(defaults: UserDefaults(suiteName: "FileOpsTests-\(UUID().uuidString)")!)
    }

    /// Source/{a.mp4 "AAA", b.mp4 "BB", c.mp4 "C", Folder/inner.txt} · Target/
    private func makeTree() throws -> (source: URL, target: URL) {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("FileOpsTests-\(UUID().uuidString)")
        let source = base.appendingPathComponent("Source"), target = base.appendingPathComponent("Target")
        try fm.createDirectory(at: source.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("AAA".utf8).write(to: source.appendingPathComponent("a.mp4"))
        try Data("BB".utf8).write(to: source.appendingPathComponent("b.mp4"))
        try Data("C".utf8).write(to: source.appendingPathComponent("c.mp4"))
        try Data("in".utf8).write(to: source.appendingPathComponent("Folder/inner.txt"))
        return (source, target)
    }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    // MARK: - FileOps

    @Test func copyLeavesTheOriginal() throws {
        let (source, target) = try makeTree()
        try FileOps.copy(source.appendingPathComponent("a.mp4"), into: target)
        #expect(exists(source.appendingPathComponent("a.mp4")))
        #expect(exists(target.appendingPathComponent("a.mp4")))
    }

    @Test func copyAFolderCopiesWhatIsInside() throws {
        let (source, target) = try makeTree()
        try FileOps.copy(source.appendingPathComponent("Folder"), into: target)
        #expect(exists(target.appendingPathComponent("Folder/inner.txt")))
    }

    @Test func moveRemovesTheOriginal() throws {
        let (source, target) = try makeTree()
        try FileOps.move(source.appendingPathComponent("a.mp4"), into: target)
        #expect(!exists(source.appendingPathComponent("a.mp4")))
        #expect(try Data(contentsOf: target.appendingPathComponent("a.mp4")) == Data("AAA".utf8))
    }

    @Test func aClashNeverOverwritesAndSaysIdentical() throws {
        let (source, target) = try makeTree()
        try Data("AAA".utf8).write(to: target.appendingPathComponent("a.mp4"))          // same bytes
        #expect(throws: FileOps.Failure.alreadyThere(identical: true)) {
            try FileOps.copy(source.appendingPathComponent("a.mp4"), into: target)
        }
    }

    @Test func aClashNeverOverwritesAndSaysDifferent() throws {
        let (source, target) = try makeTree()
        try Data("ZZZ".utf8).write(to: target.appendingPathComponent("a.mp4"))          // same size, other bytes
        #expect(throws: FileOps.Failure.alreadyThere(identical: false)) {
            try FileOps.move(source.appendingPathComponent("a.mp4"), into: target)
        }
        #expect(try Data(contentsOf: target.appendingPathComponent("a.mp4")) == Data("ZZZ".utf8))  // untouched
        #expect(exists(source.appendingPathComponent("a.mp4")))                                    // original kept
    }

    @Test func aFolderCannotGoIntoItself() throws {
        let (source, _) = try makeTree()
        let folder = source.appendingPathComponent("Folder")
        #expect(FileOps.check(folder, into: folder) == .intoItself)
    }

    @Test func theSameFolderIsRefused() throws {
        let (source, _) = try makeTree()
        #expect(FileOps.check(source.appendingPathComponent("a.mp4"), into: source) == .sameFolder)
    }

    @Test func renameNeverOverwrites() throws {
        let (source, _) = try makeTree()
        #expect(throws: FileOps.Failure.alreadyThere(identical: false)) {
            try FileOps.rename(source.appendingPathComponent("a.mp4"), to: "b.mp4")
        }
        let renamed = try FileOps.rename(source.appendingPathComponent("a.mp4"), to: "  Alpha.mp4 ")
        #expect(renamed.lastPathComponent == "Alpha.mp4")
        #expect(!exists(source.appendingPathComponent("a.mp4")))
    }

    @Test func renameCanChangeOnlyTheCapitals() throws {
        let (source, _) = try makeTree()
        let renamed = try FileOps.rename(source.appendingPathComponent("a.mp4"), to: "A.mp4")
        #expect(try FileManager.default.contentsOfDirectory(atPath: source.path).contains("A.mp4"))
        #expect(renamed.lastPathComponent == "A.mp4")
    }

    @Test func renameRefusesEmptyAndSlashNames() throws {
        let (source, _) = try makeTree()
        let file = source.appendingPathComponent("a.mp4")
        #expect(throws: FileOps.Failure.emptyName) { try FileOps.rename(file, to: "   ") }
        #expect(throws: FileOps.Failure.badName) { try FileOps.rename(file, to: "a/b") }
    }

    @Test func deleteGoesToTheTrash() throws {
        let (source, _) = try makeTree()
        let inTrash = try FileOps.trash(source.appendingPathComponent("c.mp4"))
        #expect(!exists(source.appendingPathComponent("c.mp4")))
        if let inTrash {
            #expect(exists(inTrash))                                   // it is in the Trash, not gone
            try? FileManager.default.removeItem(at: inTrash)           // tidy up the test's own file
        }
    }

    // MARK: - The quick-access bar, through the commander

    /// Left = Source (active), right = Target.
    private func makeCommander() throws -> (CommanderModel, URL, URL) {
        let (source, target) = try makeTree()
        let commander = CommanderModel(store: makeStore())
        commander.left.choose(root: source)
        commander.right.choose(root: target)
        commander.activeSide = .left
        return (commander, source, target)
    }

    private func highlight(_ pane: PaneModel, _ name: String) {
        pane.selectedID = pane.rows.first { $0.entry.name == name }!.id
    }

    @Test func theBarHasHisKeysAndNoDeadOnes() {
        // REM  ⌘2 waits for his word on what "Menu" opens; ⌘0 is free. No dead buttons.
        #expect(CommanderModel.quickKeys.map(\.number) == [1, 3, 4, 5, 6, 7, 8, 9])
        let commander = CommanderModel(store: makeStore())
        #expect(!commander.runQuickKey(2))
        #expect(!commander.runQuickKey(0))
    }

    @Test func deleteLightsUpTheNextRow() throws {
        let (commander, source, _) = try makeCommander()
        highlight(commander.left, "b.mp4")
        commander.runQuickKey(8)
        #expect(!exists(source.appendingPathComponent("b.mp4")))
        #expect(commander.left.selectedEntry?.name == "c.mp4")
        #expect(!commander.statusIsProblem)
        if let trashed = commander.lastTrashed { try? FileManager.default.removeItem(at: trashed) }
    }

    @Test func nothingHighlightedSaysSo() throws {
        let (commander, _, _) = try makeCommander()
        commander.runQuickKey(5)
        #expect(commander.statusIsProblem)
        #expect(commander.status.contains("Highlight something"))
    }

    @Test func moveGoesToTheTargetAndLightsUpTheNextRow() async throws {
        let (commander, source, target) = try makeCommander()
        highlight(commander.left, "a.mp4")
        commander.runQuickKey(6)
        // REM  The move runs off the main thread; wait for it to report.
        for _ in 0..<100 where commander.busy != nil { try await Task.sleep(for: .milliseconds(50)) }
        #expect(commander.busy == nil)
        #expect(!exists(source.appendingPathComponent("a.mp4")))
        #expect(exists(target.appendingPathComponent("a.mp4")))
        #expect(commander.left.selectedEntry?.name == "b.mp4")
        #expect(commander.right.entries.map(\.name).contains("a.mp4"))
    }

    @Test func copyIntoAHighlightedFolderInTheTarget() async throws {
        let (commander, source, target) = try makeCommander()
        try FileManager.default.createDirectory(at: target.appendingPathComponent("Keep"), withIntermediateDirectories: false)
        commander.right.reload()
        highlight(commander.right, "Keep")                                // the target is now Keep
        highlight(commander.left, "a.mp4")
        commander.runQuickKey(5)
        for _ in 0..<100 where commander.busy != nil { try await Task.sleep(for: .milliseconds(50)) }
        #expect(exists(target.appendingPathComponent("Keep/a.mp4")))
        #expect(exists(source.appendingPathComponent("a.mp4")))
    }

    @Test func renameThroughTheSheetKeepsTheHighlight() throws {
        let (commander, _, _) = try makeCommander()
        highlight(commander.left, "a.mp4")
        commander.runQuickKey(9)
        #expect(commander.left.askingRename)
        #expect(commander.finishRename(to: "Alpha.mp4"))
        #expect(commander.left.selectedEntry?.name == "Alpha.mp4")
    }
}
