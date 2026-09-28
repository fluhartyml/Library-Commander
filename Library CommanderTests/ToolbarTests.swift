//
//  ToolbarTests.swift
//  Library CommanderTests
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM  The pane toolbar (build 47): Sort, New Folder, Refresh, Show Hidden — each rule pinned,
// REM  and the two settings proven to survive a relaunch (everything persists).
//

import Foundation
import Testing
@testable import Library_Commander

@MainActor
struct ToolbarTests {
    private func makeStore() -> StateStore {
        StateStore(defaults: UserDefaults(suiteName: "ToolbarTests-\(UUID().uuidString)")!)
    }

    /// small.txt (older, 1 byte) · big.mp4 (newer, 3 bytes) · a folder · a hidden file.
    private func makeFolder() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ToolbarTests-\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        try Data([1]).write(to: root.appendingPathComponent("small.txt"))
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("big.mp4"))
        try Data().write(to: root.appendingPathComponent(".hidden"))
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)],
                             ofItemAtPath: root.appendingPathComponent("small.txt").path)
        return root
    }

    private func names(_ pane: PaneModel) -> [String] { pane.entries.map(\.name) }

    @Test func sortOrdersKeepFoldersFirst() throws {
        let pane = PaneModel(side: "left", store: makeStore())
        pane.choose(root: try makeFolder())
        #expect(names(pane) == ["Folder", "big.mp4", "small.txt"])          // name
        pane.sortKey = .size
        #expect(names(pane) == ["Folder", "big.mp4", "small.txt"])          // largest first
        pane.sortKey = .date
        #expect(names(pane) == ["Folder", "big.mp4", "small.txt"])          // newest first
        pane.sortKey = .kind
        #expect(names(pane) == ["Folder", "big.mp4", "small.txt"])          // video before text
    }

    @Test func sortKeepsTheHighlight() throws {
        let pane = PaneModel(side: "left", store: makeStore())
        pane.choose(root: try makeFolder())
        pane.moveSelection(by: 2)                                          // small.txt
        pane.sortKey = .size
        #expect(pane.selectedEntry?.name == "small.txt")
    }

    @Test func showHiddenShowsDotFiles() throws {
        let pane = PaneModel(side: "left", store: makeStore())
        pane.choose(root: try makeFolder())
        #expect(!names(pane).contains(".hidden"))
        pane.showHidden = true
        #expect(names(pane).contains(".hidden"))
    }

    @Test func sortAndHiddenComeBackAfterReopening() throws {
        let store = makeStore()
        let first = PaneModel(side: "right", store: store)
        first.sortKey = .date
        first.showHidden = true
        let reopened = PaneModel(side: "right", store: store)
        #expect(reopened.sortKey == .date)
        #expect(reopened.showHidden)
        #expect(PaneModel(side: "left", store: store).sortKey == .name)     // per pane
    }

    @Test func newFolderIsMadeAndHighlighted() throws {
        let pane = PaneModel(side: "left", store: makeStore())
        let root = try makeFolder()
        pane.choose(root: root)
        #expect(pane.newFolder(named: "  Holding  ") == .created)
        #expect(pane.selectedEntry?.name == "Holding")
        #expect(pane.selectedEntry?.isFolder == true)
    }

    @Test func newFolderNeverOverwrites() throws {
        let pane = PaneModel(side: "left", store: makeStore())
        let root = try makeFolder()
        pane.choose(root: root)
        #expect(pane.newFolder(named: "small.txt") == .alreadyExists)
        #expect(pane.newFolder(named: "Folder") == .alreadyExists)
        #expect(try Data(contentsOf: root.appendingPathComponent("small.txt")) == Data([1]))
    }

    @Test func newFolderRefusesBadNames() throws {
        let pane = PaneModel(side: "left", store: makeStore())
        pane.choose(root: try makeFolder())
        #expect(pane.newFolder(named: "   ") == .emptyName)
        #expect(pane.newFolder(named: "a/b") == .badName)
        #expect(pane.newFolder(named: "a:b") == .badName)
        #expect(PaneModel(side: "right", store: makeStore()).newFolder(named: "x") == .noFolder)
    }

    @Test func refreshPicksUpNewFiles() throws {
        let pane = PaneModel(side: "left", store: makeStore())
        let root = try makeFolder()
        pane.choose(root: root)
        try Data().write(to: root.appendingPathComponent("arrived.pdf"))
        pane.reload()
        #expect(names(pane).contains("arrived.pdf"))
    }
}
