//
//  PaneModelTests.swift
//  Library CommanderTests
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  The rules of steps one and two, checked on a real folder made for each test. If a
// REM  later change breaks one of these, the test fails before the build ever reaches him —
// REM  that is the point of the rebuild: no more fixing one thing and breaking another.
// REM  Each test saves into its OWN settings store, never the app's real one.
//

import Foundation
import Testing
@testable import Library_Commander

@MainActor
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

    /// A settings store of its own, so tests never touch the app's saved state.
    private func makeStore() -> StateStore {
        let name = "PaneModelTests-\(UUID().uuidString)"
        return StateStore(defaults: UserDefaults(suiteName: name)!)
    }

    private func makePane(_ store: StateStore? = nil) -> PaneModel {
        PaneModel(side: "left", store: store ?? makeStore())
    }

    // MARK: - Step one

    @Test func foldersFirstThenFinderNameOrder_hiddenLeftOut() throws {
        let pane = makePane()
        pane.choose(root: try makeFolder())
        #expect(pane.entries.map(\.name) == ["Alpha Folder", "Zeta Folder", "Track 2.mp4", "Track 10.mp4"])
    }

    @Test func choosingAFolderHighlightsTheFirstRow() throws {
        let pane = makePane()
        pane.choose(root: try makeFolder())
        #expect(pane.selectedEntry?.name == "Alpha Folder")
    }

    @Test func arrowsMoveOneRowAndStopAtBothEnds() throws {
        let pane = makePane()
        pane.choose(root: try makeFolder())
        pane.moveSelection(by: -1)                 // already at the top — stays
        #expect(pane.selectedIndex == 0)
        pane.moveSelection(by: 1)
        #expect(pane.selectedIndex == 1)
        for _ in 0..<10 { pane.moveSelection(by: 1) }  // past the bottom — stops on the last
        #expect(pane.selectedEntry?.name == "Track 10.mp4")
    }

    @Test func openingAFolderAndGoingUpReturnsToIt() throws {
        let pane = makePane()
        let root = try makeFolder()
        pane.choose(root: root)
        pane.openSelected()                        // Alpha Folder
        #expect(pane.entries.map(\.name) == ["inside.txt"])
        #expect(pane.canGoUp)
        pane.goUp()
        #expect(pane.currentURL?.standardizedFileURL.path == root.standardizedFileURL.path)
        #expect(pane.selectedEntry?.name == "Alpha Folder")   // the folder just left stays highlighted
    }

    @Test func upFromTheTopShowsTheDriveList() throws {
        // REM  Build 54, his ask: at the top of a drive, (^).. shows the drive list — never a dead end.
        let pane = makePane()
        let root = try makeFolder()
        pane.choose(root: root)
        #expect(pane.isAtTop)
        #expect(pane.canGoUp)
        pane.goUp()
        #expect(pane.showingDrives)
        #expect(pane.rows.contains { $0.entry.drive == .startup })        // the Mac's own disk is listed
        #expect(pane.selectedEntry?.drive != nil)                          // a drive is highlighted
        #expect(!pane.canGoUp)                                            // nothing above the drive list
        #expect(pane.currentURL?.standardizedFileURL.path == root.standardizedFileURL.path)  // place kept
    }

    @Test func openingAFileDoesNothing() throws {
        let pane = makePane()
        let root = try makeFolder()
        pane.choose(root: root)
        pane.moveSelection(by: 2)                  // Track 2.mp4
        pane.openSelected()
        #expect(pane.currentURL?.standardizedFileURL.path == root.standardizedFileURL.path)
    }

    @Test func reloadKeepsTheHighlightOnTheSameFile() throws {
        let pane = makePane()
        let root = try makeFolder()
        pane.choose(root: root)
        pane.moveSelection(by: 3)                  // Track 10.mp4
        try Data().write(to: root.appendingPathComponent("Track 1.mp4"))  // a new file lands above it
        pane.reload()
        #expect(pane.selectedEntry?.name == "Track 10.mp4")
    }

    @Test func tabSwitchesTheActivePane() {
        let commander = CommanderModel(store: makeStore())
        #expect(commander.activeSide == .left)
        commander.switchPanes()
        #expect(commander.activeSide == .right)
    }

    // MARK: - Step two: everything persists

    @Test func folderAndHighlightComeBackAfterReopening() throws {
        let store = makeStore()
        let root = try makeFolder()
        let first = makePane(store)
        first.choose(root: root)
        first.openSelected()                       // into Alpha Folder, inside.txt highlighted

        let reopened = makePane(store)             // the app launched again
        reopened.restore()
        #expect(reopened.rootURL?.standardizedFileURL.path == root.standardizedFileURL.path)
        #expect(reopened.currentURL?.lastPathComponent == "Alpha Folder")
        #expect(reopened.selectedEntry?.name == "inside.txt")
        #expect(reopened.canGoUp)                  // the chosen folder is still the ceiling
    }

    @Test func highlightMovedWithTheArrowsComesBack() throws {
        let store = makeStore()
        let first = makePane(store)
        first.choose(root: try makeFolder())
        first.moveSelection(by: 3)                 // Track 10.mp4

        let reopened = makePane(store)
        reopened.restore()
        #expect(reopened.selectedEntry?.name == "Track 10.mp4")
    }

    @Test func aMissingFolderIsNamedAndItsPlaceIsKept() throws {
        let store = makeStore()
        let root = try makeFolder()
        makePane(store).choose(root: root)
        try FileManager.default.removeItem(at: root)   // like a drive that is not connected

        let reopened = makePane(store)
        reopened.restore()
        #expect(reopened.currentURL == nil)
        #expect(reopened.missingRootPath == root.path)
        #expect(store.place(for: "left").rootBookmark != nil)   // not forgotten
    }

    @Test func activePaneComesBack() {
        let store = makeStore()
        CommanderModel(store: store).switchPanes()     // right is active
        #expect(CommanderModel(store: store).activeSide == .right)
    }

    @Test func aPaneNeverChosenStaysEmpty() {
        let pane = makePane()
        pane.restore()
        #expect(pane.currentURL == nil)
        #expect(pane.missingRootPath == nil)
    }

    // MARK: - Step three: path box, drive picker, status bar

    @Test func typingAPathInsideTheFolderOpensIt() throws {
        let pane = makePane()
        let root = try makeFolder()
        pane.choose(root: root)
        #expect(pane.go(toPath: root.appendingPathComponent("Zeta Folder").path) == .opened)
        #expect(pane.currentURL?.lastPathComponent == "Zeta Folder")
    }

    @Test func typingAPathThatIsNotThereSaysSoAndStaysPut() throws {
        let pane = makePane()
        let root = try makeFolder()
        pane.choose(root: root)
        #expect(pane.go(toPath: root.appendingPathComponent("No Such Folder").path) == .notFound)
        #expect(pane.go(toPath: "not a path") == .notFound)
        #expect(pane.currentURL?.standardizedFileURL.path == root.standardizedFileURL.path)
    }

    @Test func typingAFilePathSaysItIsNotAFolder() throws {
        let pane = makePane()
        let root = try makeFolder()
        pane.choose(root: root)
        #expect(pane.go(toPath: root.appendingPathComponent("Track 2.mp4").path) == .notAFolder)
    }

    @Test func aPathOutsideEverythingGrantedAsksFirst() throws {
        let pane = makePane()
        pane.choose(root: try makeFolder())
        let elsewhere = try makeFolder()           // never granted
        #expect(pane.go(toPath: elsewhere.path) == .needsPermission)
    }

    @Test func aFolderGrantedEarlierOpensWithoutAsking() throws {
        let store = makeStore()
        let first = try makeFolder()
        let second = try makeFolder()
        let pane = makePane(store)
        pane.choose(root: second)                  // granted once…
        pane.choose(root: first)                   // …then he moved on
        #expect(pane.go(toPath: second.appendingPathComponent("Alpha Folder").path) == .opened)
        #expect(pane.rootURL?.standardizedFileURL.path == second.standardizedFileURL.path)  // new ceiling
        #expect(pane.canGoUp)
    }

    @Test func aGrantIsSharedByBothPanes() throws {
        let store = makeStore()
        let root = try makeFolder()
        PaneModel(side: "left", store: store).choose(root: root)
        let right = PaneModel(side: "right", store: store)
        #expect(right.go(toPath: root.path) == .opened)
    }

    @Test func tildeMeansTheRealHomeNotTheSandbox() {
        #expect(!PaneModel.realHome.contains("/Library/Containers/"))
    }

    @Test func statusBarKeepsTheLastMessage() {
        let commander = CommanderModel(store: makeStore())
        #expect(commander.status == "Ready.")
        commander.report("Nothing at /nowhere.", problem: true)
        #expect(commander.status == "Nothing at /nowhere.")
        #expect(commander.statusIsProblem)
        commander.report("Opened Lexar 3 TB.")
        #expect(!commander.statusIsProblem)
    }

    @Test func statusBarNamesADriveThatIsNotConnected() throws {
        let store = makeStore()
        let root = try makeFolder()
        CommanderModel(store: store).left.choose(root: root)
        try FileManager.default.removeItem(at: root)
        let commander = CommanderModel(store: store)
        commander.restore()
        #expect(commander.statusIsProblem)
        #expect(commander.status.contains(root.lastPathComponent))
    }
}
