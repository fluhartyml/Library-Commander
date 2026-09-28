//
//  PaneModel.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  One pane: the folder it shows, what is in it, and which row is highlighted.
// REM  Plain Swift with no views in it, so every rule here can be tested
// REM  (Library CommanderTests/PaneModelTests.swift). Step one of the rebuild, 2026-09-28.
// REM
// REM  Step two: the pane's place — drive, folder, highlight — is SAVED ON EVERY CHANGE and
// REM  RESTORED AT LAUNCH (his rule; see StateStore.swift). A drive that is not connected
// REM  keeps its saved place and comes back when it mounts; it is never quietly forgotten.
//

import Foundation
import Observation

/// One row in a pane.
struct FileEntry: Identifiable, Hashable {
    // REM  The id is the PATH, never a random UUID. The old app gave every file a new id on
    // REM  every reload, so a highlight could not survive a refresh (build 30's next-file
    // REM  highlight failed that way). A path names the same file before and after.
    var id: String { url.path }
    let url: URL
    let name: String
    let isFolder: Bool
}

@Observable
final class PaneModel {
    /// "left" or "right" — the name its saved state is filed under.
    let side: String
    @ObservationIgnored private let store: StateStore

    /// The folder he chose with Choose Folder…. The sandbox only lets the app into what he
    /// picks, so the pane never goes above this one.
    private(set) var rootURL: URL?
    /// The folder the pane is showing — the root or somewhere inside it.
    private(set) var currentURL: URL?
    private(set) var entries: [FileEntry] = []
    /// The highlighted row, by path. nil = nothing highlighted. Saved on every change.
    var selectedID: FileEntry.ID? {
        didSet { store.save(selectedPath: selectedID, for: side) }
    }
    /// Shown in the pane when a folder cannot be read.
    private(set) var errorMessage: String?
    /// Set when the saved folder is not reachable — usually a drive that is not connected.
    /// Its saved place is kept; `restore()` tries again (the pane calls it when a drive mounts).
    private(set) var missingRootPath: String?

    init(side: String, store: StateStore = .shared) {
        self.side = side
        self.store = store
    }

    var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return entries.firstIndex { $0.id == selectedID }
    }

    var selectedEntry: FileEntry? {
        selectedIndex.map { entries[$0] }
    }

    var canGoUp: Bool {
        guard let rootURL, let currentURL else { return false }
        return currentURL.standardizedFileURL.path != rootURL.standardizedFileURL.path
    }

    // MARK: - Saved place

    /// At launch (and when a drive mounts): back to the saved folder and highlight.
    /// Does nothing if the pane is already showing its folder.
    func restore() {
        guard currentURL == nil else { return }
        let place = store.place(for: side)
        guard let data = place.rootBookmark else { return }   // never chosen — stays empty

        guard let (root, stale) = StateStore.resolve(data),
              FileManager.default.fileExists(atPath: root.path) else {
            missingRootPath = place.rootPath
            return
        }
        missingRootPath = nil
        rootURL = root
        if stale { store.save(root: StateStore.bookmark(for: root), rootPath: root.path, for: side) }

        // The saved folder, if it still exists and is inside the root; else the root.
        var folder = root
        if let saved = place.currentPath, isInsideRoot(saved),
           FileManager.default.fileExists(atPath: saved) {
            folder = URL(fileURLWithPath: saved)
        }
        show(folder: folder, highlight: place.selectedPath)
    }

    private func isInsideRoot(_ path: String) -> Bool {
        guard let rootURL else { return false }
        let root = rootURL.standardizedFileURL.path
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        return p == root || p.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    // MARK: - Folders

    /// A new root, chosen by him. Shows it, highlights the first row, and saves the permission.
    func choose(root: URL) {
        rootURL?.stopAccessingSecurityScopedResource()
        _ = root.startAccessingSecurityScopedResource()
        rootURL = root
        missingRootPath = nil
        store.save(root: StateStore.bookmark(for: root), rootPath: root.path, for: side)
        show(folder: root, highlight: nil)
    }

    /// Opens the highlighted row if it is a folder. Files do nothing yet (step one).
    func openSelected() {
        guard let entry = selectedEntry, entry.isFolder else { return }
        show(folder: entry.url, highlight: nil)
    }

    /// Up one folder, never above the chosen root. The folder just left stays highlighted,
    /// the way Finder does it.
    func goUp() {
        guard canGoUp, let currentURL else { return }
        show(folder: currentURL.deletingLastPathComponent(), highlight: currentURL.path)
    }

    /// Re-reads the folder, keeping the highlight on the same file if it is still there.
    func reload() {
        guard let currentURL else { return }
        show(folder: currentURL, highlight: selectedID)
    }

    private func show(folder: URL, highlight: FileEntry.ID?) {
        currentURL = folder
        store.save(currentPath: folder.path, for: side)
        do {
            entries = try Self.listing(of: folder)
            errorMessage = nil
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
        if let highlight, entries.contains(where: { $0.id == highlight }) {
            selectedID = highlight
        } else {
            selectedID = entries.first?.id
        }
    }

    /// Folders first, then files, each in Finder's name order (so "Track 2" comes before
    /// "Track 10"). Hidden files are left out.
    static func listing(of folder: URL) throws -> [FileEntry] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        let entries = urls.map { url in
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return FileEntry(url: url, name: url.lastPathComponent, isFolder: isFolder)
        }
        return entries.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - Highlight

    /// ↑ is -1, ↓ is +1. Stops at the first and last rows — it does not wrap around.
    /// With nothing highlighted, any move highlights the first row.
    func moveSelection(by offset: Int) {
        guard !entries.isEmpty else { selectedID = nil; return }
        guard let index = selectedIndex else { selectedID = entries.first?.id; return }
        let target = min(max(index + offset, 0), entries.count - 1)
        selectedID = entries[target].id
    }
}
