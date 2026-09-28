//
//  PaneModelTests.swift
//  Library CommanderTests
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  Step one's rules, checked on a real folder made for each test. If a later change
// REM  breaks one of these, the test fails before the build ever reaches him — that is
// REM  the point of the rebuild: no more fixing one thing and breaking another.
//

import Foundation
import Testing
@testable import Library_Commander

struct PaneModelTests {
    /// A throwaway folder: two folders and three files, one of them hidden.
    private func makeFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaneModelTests-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("Zeta Folder"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Alpha Folder"), withIntermediateDirectories: true)
        for name in ["Track 10.mp4", "Track 2.mp4", ".hidden"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        try Data().write(to: root.appendingPathComponent("Alpha Folder/inside.txt"))
        return root
    }

    @Test func foldersFirstThenFinderNameOrder_hiddenLeftOut() throws {
        let pane = PaneModel()
        pane.choose(root: try makeFolder())
        #expect(pane.entries.map(\.name) == ["Alpha Folder", "Zeta Folder", "Track 2.mp4", "Track 10.mp4"])
    }

    @Test func choosingAFolderHighlightsTheFirstRow() throws {
        let pane = PaneModel()
        pane.choose(root: try makeFolder())
        #expect(pane.selectedEntry?.name == "Alpha Folder")
    }

    @Test func arrowsMoveOneRowAndStopAtBothEnds() throws {
        let pane = PaneModel()
        pane.choose(root: try makeFolder())
        pane.moveSelection(by: -1)                 // already at the top — stays
        #expect(pane.selectedIndex == 0)
        pane.moveSelection(by: 1)
        #expect(pane.selectedIndex == 1)
        for _ in 0..<10 { pane.moveSelection(by: 1) }  // past the bottom — stops on the last
        #expect(pane.selectedEntry?.name == "Track 10.mp4")
    }

    @Test func openingAFolderAndGoingUpReturnsToIt() throws {
        let pane = PaneModel()
        let root = try makeFolder()
        pane.choose(root: root)
        pane.openSelected()                        // Alpha Folder
        #expect(pane.entries.map(\.name) == ["inside.txt"])
        #expect(pane.canGoUp)
        pane.goUp()
        #expect(pane.currentURL?.standardizedFileURL.path == root.standardizedFileURL.path)
        #expect(pane.selectedEntry?.name == "Alpha Folder")   // the folder just left stays highlighted
    }

    @Test func neverGoesAboveTheChosenFolder() throws {
        let pane = PaneModel()
        let root = try makeFolder()
        pane.choose(root: root)
        #expect(!pane.canGoUp)
        pane.goUp()
        #expect(pane.currentURL?.standardizedFileURL.path == root.standardizedFileURL.path)
    }

    @Test func openingAFileDoesNothing() throws {
        let pane = PaneModel()
        let root = try makeFolder()
        pane.choose(root: root)
        pane.moveSelection(by: 2)                  // Track 2.mp4
        pane.openSelected()
        #expect(pane.currentURL?.standardizedFileURL.path == root.standardizedFileURL.path)
    }

    @Test func reloadKeepsTheHighlightOnTheSameFile() throws {
        let pane = PaneModel()
        let root = try makeFolder()
        pane.choose(root: root)
        pane.moveSelection(by: 3)                  // Track 10.mp4
        try Data().write(to: root.appendingPathComponent("Track 1.mp4"))  // a new file lands above it
        pane.reload()
        #expect(pane.selectedEntry?.name == "Track 10.mp4")
    }

    @Test func tabSwitchesTheActivePane() {
        let commander = CommanderModel()
        #expect(commander.activeSide == .left)
        commander.switchPanes()
        #expect(commander.activeSide == .right)
    }
}
