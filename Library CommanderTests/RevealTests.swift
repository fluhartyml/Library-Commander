//
//  RevealTests.swift
//  Library CommanderTests
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM  Finder's reveal triangle (build 53) and HIS highlight rule: revealing or hiding a folder
// REM  never moves the highlight — only choosing a different row does.
//

import Foundation
import Testing
@testable import Library_Commander

@MainActor
struct RevealTests {
    private func makeStore() -> StateStore {
        StateStore(defaults: UserDefaults(suiteName: "RevealTests-\(UUID().uuidString)")!)
    }

    /// Classic Cinema/{Casablanca.mp4, Noir/Detour.mp4} · Holding/ · readme.txt
    private func makeFolder() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("RevealTests-\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent("Classic Cinema/Noir"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Holding"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("Classic Cinema/Casablanca.mp4"))
        try Data().write(to: root.appendingPathComponent("Classic Cinema/Noir/Detour.mp4"))
        try Data().write(to: root.appendingPathComponent("readme.txt"))
        return root
    }

    private func lines(_ pane: PaneModel) -> [String] {
        pane.rows.map { String(repeating: "  ", count: $0.depth) + $0.entry.name }
    }

    private func entry(_ pane: PaneModel, _ name: String) -> FileEntry {
        pane.rows.first { $0.entry.name == name }!.entry
    }

    @Test func revealShowsTheContentsIndentedBelow() throws {
        let pane = PaneModel(side: "left", store: makeStore())
        pane.choose(root: try makeFolder())
        pane.toggleReveal(entry(pane, "Classic Cinema"))
        #expect(lines(pane) == ["Classic Cinema", "  Noir", "  Casablanca.mp4", "Holding", "readme.txt"])
    }

    @Test func revealingNeverMovesTheHighlight() throws {
        let pane = PaneModel(side: "left", store: makeStore())
        pane.choose(root: try makeFolder())
        pane.moveSelection(by: 1)                                   // Holding
        pane.toggleReveal(entry(pane, "Classic Cinema"))
        #expect(pane.selectedEntry?.name == "Holding")
        pane.toggleReveal(entry(pane, "Classic Cinema"))            // hide it again
        #expect(pane.selectedEntry?.name == "Holding")
    }

    @Test func theRevealedFolderItselfStaysHighlighted() throws {
        let pane = PaneModel(side: "left", store: makeStore())
        pane.choose(root: try makeFolder())                         // Classic Cinema highlighted
        pane.toggleReveal(entry(pane, "Classic Cinema"))
        #expect(pane.selectedEntry?.name == "Classic Cinema")
    }

    @Test func arrowsStepThroughRevealedContents() throws {
        let pane = PaneModel(side: "left", store: makeStore())
        pane.choose(root: try makeFolder())
        pane.toggleReveal(entry(pane, "Classic Cinema"))
        pane.moveSelection(by: 2)
        #expect(pane.selectedEntry?.name == "Casablanca.mp4")
    }

    @Test func hidingAFolderWithTheHighlightInsideMovesItToTheFolder() throws {
        let pane = PaneModel(side: "left", store: makeStore())
        pane.choose(root: try makeFolder())
        pane.toggleReveal(entry(pane, "Classic Cinema"))
        pane.toggleReveal(entry(pane, "Noir"))
        pane.selectedID = entry(pane, "Detour.mp4").id
        pane.toggleReveal(entry(pane, "Classic Cinema"))            // Detour would vanish
        #expect(pane.selectedEntry?.name == "Classic Cinema")
    }

    @Test func openingARevealedChildFolderGoesIntoIt() throws {
        let pane = PaneModel(side: "left", store: makeStore())
        pane.choose(root: try makeFolder())
        pane.toggleReveal(entry(pane, "Classic Cinema"))
        pane.selectedID = entry(pane, "Noir").id
        pane.openSelected()
        #expect(pane.currentURL?.lastPathComponent == "Noir")
    }

    @Test func revealedFoldersComeBackAfterReopening() throws {
        let store = makeStore()
        let first = PaneModel(side: "left", store: store)
        first.choose(root: try makeFolder())
        first.toggleReveal(entry(first, "Classic Cinema"))
        let reopened = PaneModel(side: "left", store: store)
        reopened.restore()
        #expect(lines(reopened).contains("  Casablanca.mp4"))
    }

    @Test func refreshKeepsFoldersRevealedAndPicksUpNewFiles() throws {
        let pane = PaneModel(side: "left", store: makeStore())
        let root = try makeFolder()
        pane.choose(root: root)
        pane.toggleReveal(entry(pane, "Classic Cinema"))
        try Data().write(to: root.appendingPathComponent("Classic Cinema/Metropolis.mp4"))
        pane.reload()
        #expect(lines(pane).contains("  Metropolis.mp4"))
    }

    @Test func filesAndPackagesHaveNoTriangle() {
        let file = FileEntry(url: URL(fileURLWithPath: "/x/a.mp4"), name: "a.mp4", isFolder: false)
        let package = FileEntry(url: URL(fileURLWithPath: "/x/P.photoslibrary"), name: "P.photoslibrary",
                                isFolder: true, isPackage: true)
        #expect(!PaneModel.canReveal(file))
        #expect(!PaneModel.canReveal(package))
    }
}
