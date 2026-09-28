//
//  StateStore.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  EVERYTHING PERSISTS. His words, 2026-09-28: "i would like every setting and drive or
// REM  folder state persistant wether you open or close the app multiple times."
// REM  So every setting and every pane's place is saved the moment it changes, and read back
// REM  at launch. A NEW SETTING IS BORN PERSISTENT — never a plain @State default that
// REM  resets on launch (the old app's Autoplay and Next did exactly that, and it was a bug).
// REM
// REM  Drives and folders are saved as SECURITY-SCOPED BOOKMARKS. The sandbox only lets the app
// REM  into what he picked; a bookmark is the saved permission, so he is not asked again.
// REM  (Same method the old app used from build 20 on; it worked on his Mac.)
//

import Foundation

/// Where saved state lives. The app uses UserDefaults.standard; tests pass their own.
final class StateStore {
    static let shared = StateStore(defaults: .standard)
    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: - Pane places

    struct PanePlace {
        /// The saved permission for the folder he chose.
        var rootBookmark: Data?
        /// The chosen folder's path, kept as plain text so a missing drive can still be named.
        var rootPath: String?
        /// The folder the pane was showing.
        var currentPath: String?
        /// The highlighted row.
        var selectedPath: String?
    }

    private func key(_ side: String, _ name: String) -> String { "pane.\(side).\(name)" }

    func place(for side: String) -> PanePlace {
        PanePlace(rootBookmark: defaults.data(forKey: key(side, "rootBookmark")),
                  rootPath: defaults.string(forKey: key(side, "rootPath")),
                  currentPath: defaults.string(forKey: key(side, "currentPath")),
                  selectedPath: defaults.string(forKey: key(side, "selectedPath")))
    }

    func save(root bookmark: Data?, rootPath: String, for side: String) {
        defaults.set(bookmark, forKey: key(side, "rootBookmark"))
        defaults.set(rootPath, forKey: key(side, "rootPath"))
    }

    func save(currentPath: String?, for side: String) {
        defaults.set(currentPath, forKey: key(side, "currentPath"))
    }

    func save(selectedPath: String?, for side: String) {
        defaults.set(selectedPath, forKey: key(side, "selectedPath"))
    }

    // MARK: - Granted folders and drives

    // REM  Every drive or folder he has ever granted, as [path: bookmark]. Picking a drive or
    // REM  typing a path inside any of them opens it without asking again. A grant that cannot be
    // REM  opened right now (drive unplugged) is KEPT — it works again when the drive is back.

    private var grants: [String: Data] {
        get { defaults.dictionary(forKey: "grants") as? [String: Data] ?? [:] }
        set { defaults.set(newValue, forKey: "grants") }
    }

    /// Every granted path, for Settings…, in name order.
    var grantPaths: [String] {
        grants.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Forget a grant — only the saved permission. Nothing on disk is touched.
    func removeGrant(_ path: String) {
        grants[path] = nil
    }

    func addGrant(_ url: URL) {
        guard let data = Self.bookmark(for: url) else { return }
        grants[url.standardizedFileURL.path] = data
    }

    /// The closest granted folder that holds `path` (or is it), if any.
    func grantCovering(_ path: String) -> (path: String, bookmark: Data)? {
        let target = URL(fileURLWithPath: path).standardizedFileURL.path
        return grants
            .filter { Self.path(target, isInside: $0.key) }
            .max { $0.key.count < $1.key.count }
            .map { ($0.key, $0.value) }
    }

    /// True when `path` is `folder` or somewhere inside it.
    static func path(_ path: String, isInside folder: String) -> Bool {
        if path == folder { return true }
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        return path.hasPrefix(prefix)
    }

    // MARK: - Pane toolbar settings

    func sort(for side: String) -> String? { defaults.string(forKey: key(side, "sort")) }
    func save(sort: String, for side: String) { defaults.set(sort, forKey: key(side, "sort")) }
    /// True when the pane was showing the drive list.
    func showingDrives(for side: String) -> Bool { defaults.bool(forKey: key(side, "showingDrives")) }
    func save(showingDrives: Bool, for side: String) { defaults.set(showingDrives, forKey: key(side, "showingDrives")) }
    /// Folders revealed in this pane (Finder's disclosure triangle), by path.
    func revealed(for side: String) -> [String] { defaults.stringArray(forKey: key(side, "revealed")) ?? [] }
    func save(revealed: [String], for side: String) { defaults.set(revealed, forKey: key(side, "revealed")) }
    func showHidden(for side: String) -> Bool { defaults.bool(forKey: key(side, "showHidden")) }
    func save(showHidden: Bool, for side: String) { defaults.set(showHidden, forKey: key(side, "showHidden")) }

    // MARK: - Active pane

    var activeSideIsRight: Bool {
        get { defaults.bool(forKey: "activeSideIsRight") }
        set { defaults.set(newValue, forKey: "activeSideIsRight") }
    }

    // MARK: - Bookmarks

    /// Read/write permission first; read-only as a fallback (a drive he can only read).
    /// A plain bookmark is the last resort, for a folder the app can already reach.
    static func bookmark(for url: URL) -> Data? {
        (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
        ?? (try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                  includingResourceValuesForKeys: nil, relativeTo: nil))
        ?? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
    }

    /// Opens a saved permission. nil = the folder is not reachable right now (drive not
    /// connected, folder renamed away) — the caller KEEPS the bookmark for next time.
    static func resolve(_ data: Data) -> (url: URL, stale: Bool)? {
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                              relativeTo: nil, bookmarkDataIsStale: &stale) {
            _ = url.startAccessingSecurityScopedResource()
            return (url, stale)
        }
        if let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI],
                              relativeTo: nil, bookmarkDataIsStale: &stale) {
            return (url, stale)
        }
        return nil
    }
}
