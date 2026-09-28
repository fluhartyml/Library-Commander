//
//  DriveListTests.swift
//  Library CommanderTests
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM  The drive list (build 54): above a drive's top, "local or network", saved like everything.
//

import Foundation
import Testing
@testable import Library_Commander

@MainActor
struct DriveListTests {
    private func makeStore() -> StateStore {
        StateStore(defaults: UserDefaults(suiteName: "DriveListTests-\(UUID().uuidString)")!)
    }

    private func makeFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DriveListTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Inside"), withIntermediateDirectories: true)
        return root
    }

    @Test func localDrivesComeBeforeNetworkDrives() {
        let kinds = Drives.mounted().map(\.kind)
        #expect(kinds == kinds.sorted())
        #expect(kinds.first == .startup)
    }

    @Test func theDriveHoldingAPathIsTheLongestMatch() {
        let drives = [Drive(url: URL(fileURLWithPath: "/"), name: "Macintosh HD", kind: .startup),
                      Drive(url: URL(fileURLWithPath: "/Volumes/Lexar 3 TB"), name: "Lexar 3 TB", kind: .local)]
        #expect(Drives.drive(holding: "/Volumes/Lexar 3 TB/Video Convert", in: drives)?.name == "Lexar 3 TB")
        #expect(Drives.drive(holding: "/Users/michael", in: drives)?.name == "Macintosh HD")
        #expect(Drives.drive(holding: "/Volumes/Lexar 3 TB Backup", in: drives)?.name == "Macintosh HD")  // not a prefix trick
    }

    @Test func theDriveListComesBackAfterReopening() throws {
        let store = makeStore()
        let first = PaneModel(side: "left", store: store)
        first.choose(root: try makeFolder())
        first.goUp()
        let reopened = PaneModel(side: "left", store: store)
        reopened.restore()
        #expect(reopened.showingDrives)
    }

    @Test func openingAFolderLeavesTheDriveList() throws {
        let store = makeStore()
        let pane = PaneModel(side: "left", store: store)
        let root = try makeFolder()
        pane.choose(root: root)
        pane.goUp()
        #expect(pane.go(toPath: root.path) == .opened)                   // e.g. typed into the path box
        #expect(!pane.showingDrives)
        #expect(!store.showingDrives(for: "left"))
        #expect(pane.entries.map(\.name) == ["Inside"])
    }

    @Test func anUngrantedDriveAsksForPermission() throws {
        let pane = PaneModel(side: "left", store: makeStore())
        pane.choose(root: try makeFolder())
        pane.goUp()
        var asked: URL?
        pane.onOpen = { result, url in if result == .needsPermission { asked = url } }
        pane.selectedID = pane.rows.first { $0.entry.drive == .startup }?.id
        pane.openSelected()
        #expect(asked?.path == "/")
    }

    @Test func drivesHaveNoRevealTriangle() {
        let drive = FileEntry(url: URL(fileURLWithPath: "/"), name: "Macintosh HD", isFolder: true, drive: .startup)
        #expect(!PaneModel.canReveal(drive))
    }
}
