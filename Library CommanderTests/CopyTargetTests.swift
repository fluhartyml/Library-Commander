//
//  CopyTargetTests.swift
//  Library CommanderTests
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM  Build 55: where a copy or move would land, decided and SHOWN before anything is copied.
// REM  HIS RULES, 2026-09-28:
// REM   • a copy goes into "the highlighted folder if one is highlighted", else the open folder;
// REM   • the ACTIVE pane is the source, the other is the destination — either side can be either;
// REM   • opening a folder highlights NOTHING, so a target is never picked for him.
//

import Foundation
import Testing
@testable import Library_Commander

@MainActor
struct CopyTargetTests {
    private func makeStore() -> StateStore {
        StateStore(defaults: UserDefaults(suiteName: "CopyTargetTests-\(UUID().uuidString)")!)
    }

    /// Video Convert/{Classic Cinema/, Photos.photoslibrary/, trailer.mp4}
    private func makeFolder() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("CopyTargetTests-\(UUID().uuidString)")
            .appendingPathComponent("Video Convert")
        try fm.createDirectory(at: root.appendingPathComponent("Classic Cinema"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Photos.photoslibrary"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("trailer.mp4"))
        return root
    }

    /// "open:<path>" or "into:<path>" — compared as standardized paths, because a URL listed from
    /// the disk can differ from a built one (trailing slash, /private) while naming the same folder.
    private func describe(_ target: PaneModel.CopyTarget?) -> String? {
        switch target {
        case .openFolder(let url)?:        return "open:" + url.standardizedFileURL.resolvingSymlinksInPath().path
        case .highlightedFolder(let url)?: return "into:" + url.standardizedFileURL.resolvingSymlinksInPath().path
        case nil:                          return nil
        }
    }

    private func open(_ url: URL) -> String { "open:" + url.standardizedFileURL.resolvingSymlinksInPath().path }
    private func into(_ url: URL) -> String { "into:" + url.standardizedFileURL.resolvingSymlinksInPath().path }

    private func highlight(_ pane: PaneModel, _ name: String) {
        pane.selectedID = pane.rows.first { $0.entry.name == name }!.id
    }

    @Test func openingAFolderTargetsTheOpenFolderNotItsFirstRow() throws {
        // REM  THE TRAP this build closes: Classic Cinema used to light up by itself.
        let pane = PaneModel(side: "right", store: makeStore())
        let root = try makeFolder()
        pane.choose(root: root)
        #expect(pane.selectedID == nil)
        #expect(describe(pane.copyTarget) == open(root))
    }

    @Test func aHighlightedFolderIsTheTarget() throws {
        let pane = PaneModel(side: "right", store: makeStore())
        let root = try makeFolder()
        pane.choose(root: root)
        highlight(pane, "Classic Cinema")
        #expect(describe(pane.copyTarget) == into(root.appendingPathComponent("Classic Cinema")))
    }

    @Test func aHighlightedFileLeavesTheOpenFolderAsTarget() throws {
        let pane = PaneModel(side: "right", store: makeStore())
        let root = try makeFolder()
        pane.choose(root: root)
        highlight(pane, "trailer.mp4")
        #expect(describe(pane.copyTarget) == open(root))
    }

    @Test func aPackageIsNeverATarget() throws {
        // REM  Dropping files inside a .photoslibrary would damage it.
        let pane = PaneModel(side: "right", store: makeStore())
        let root = try makeFolder()
        pane.choose(root: root)
        highlight(pane, "Photos.photoslibrary")
        #expect(describe(pane.copyTarget) == open(root))
    }

    @Test func theDriveListHasNoTarget() throws {
        let pane = PaneModel(side: "right", store: makeStore())
        pane.choose(root: try makeFolder())
        pane.goUp()                                                     // above the top: drive list
        #expect(pane.showingDrives)
        #expect(describe(pane.copyTarget) == nil)
    }

    @Test func theDestinationIsWhicheverPaneIsNotActive() throws {
        // REM  Source and destination, never left and right — Tab swaps them.
        let commander = CommanderModel(store: makeStore())
        #expect(commander.activeSide == .left)
        #expect(commander.destinationSide == .right)
        #expect(commander.arrowTowardDestination == "→")
        commander.switchPanes()
        #expect(commander.destinationSide == .left)
        #expect(commander.arrowTowardDestination == "←")
    }

    @Test func theStatusBarNamesTheTarget() throws {
        let commander = CommanderModel(store: makeStore())
        #expect(commander.copyTargetLine.contains("No target yet"))     // nothing open on the right
        let root = try makeFolder()
        commander.right.choose(root: root)
        #expect(commander.copyTargetLine == "→ Target: Video Convert")
        highlight(commander.right, "Classic Cinema")
        #expect(commander.copyTargetLine == "→ Target: Classic Cinema")
    }
}
