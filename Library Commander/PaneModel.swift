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
    /// Bytes (0 for a folder) and last change — for sorting by size and date.
    var size: Int64 = 0
    var modified: Date? = nil
    /// Hidden by a leading dot OR by macOS's hidden flag (like ~/Library) — macOS's own check.
    var isHidden: Bool = false
    /// A folder macOS treats as one item (.photoslibrary, .app) — read from the disk.
    var isPackage: Bool = false
    /// Set only on the rows of the DRIVE LIST: which kind of drive this row is.
    var drive: DriveKind? = nil
    // REM  What kind of file it is — picks the row's glyph and color (FileKind.swift).
    var kind: FileKind { FileKind.of(name: name, isFolder: isFolder, isPackage: isPackage) }
}

/// One line on screen: a file or folder, and how deep it sits under opened folders.
/// REM  REVEAL, his ask 2026-09-28: "the folders should have a reveal to expand its contents below
/// REM  so you dont need to open the folder, like the finder." depth 0 = the folder being shown,
/// REM  1 = inside a revealed folder, and so on.
struct Row: Identifiable, Hashable {
    let entry: FileEntry
    let depth: Int
    var id: String { entry.id }
}

/// How a pane orders its rows. REM  Folders ALWAYS come first, whatever the order — a
/// commander finds folders at the top.
enum SortKey: String, CaseIterable, Identifiable {
    case name, kind, date, size
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: return "Name"
        case .kind: return "Kind"
        case .date: return "Date Modified (newest first)"
        case .size: return "Size (largest first)"
        }
    }
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
    /// What is in the folder being shown — the top level only.
    private(set) var entries: [FileEntry] = []
    /// Every line on screen: `entries` with the contents of each revealed folder under it.
    /// REM  The highlight, the arrows and "open" all work on ROWS, so a file inside a revealed
    /// REM  folder is highlighted, stepped through and opened exactly like a top-level one.
    private(set) var rows: [Row] = []
    /// Folders whose contents are revealed, by path. Saved (everything persists).
    private(set) var revealed: Set<String> = []
    /// True while the pane shows the DRIVE LIST instead of a folder. Saved.
    /// REM  His ask, 2026-09-28: at the top of a drive, (^).. "should show the drive list local or
    /// REM  network." So "up" never dead-ends: above a drive's top is every drive.
    private(set) var showingDrives = false
    /// What happened when a row was opened from the keyboard or a double-click — so the view can
    /// report it, or ask him for permission when a drive has never been granted.
    @ObservationIgnored var onOpen: ((GoResult, URL) -> Void)?
    /// The CURSOR row, by path — the one the arrows move from and single-item commands use.
    /// nil = nothing highlighted. Saved on every change.
    /// REM  Setting it the ordinary way (a plain click, an arrow, opening a folder) makes it the ONLY
    /// REM  highlighted row, as in Finder. ⌘-click and ⇧-click go through `click(_:command:shift:)`,
    /// REM  which grows `selection` instead.
    var selectedID: FileEntry.ID? {
        didSet {
            store.save(selectedPath: selectedID, for: side)
            if !extending {
                selection = selectedID.map { [$0] } ?? []
                anchorID = selectedID
            }
        }
    }

    // REM  MULTI-SELECT, LIKE FINDER — his ask, 2026-09-28: "i cant multi select" → "yes like finder".
    // REM   • click            → just that row
    // REM   • ⌘-click          → add or remove that row
    // REM   • ⇧-click          → every row from the anchor to that row
    // REM   • ⇧↑ / ⇧↓          → grow or shrink the range from the anchor
    // REM  Every file command then acts on ALL highlighted rows. Saved, like everything else.
    /// Every highlighted row, by path.
    private(set) var selection: Set<FileEntry.ID> = [] {
        didSet { store.save(selectedPaths: Array(selection), for: side) }
    }
    /// Where a ⇧ range starts — the last row clicked without ⇧.
    private(set) var anchorID: FileEntry.ID?
    /// True while `selectedID` is being moved WITHOUT resetting the selection.
    @ObservationIgnored private var extending = false
    /// Shown in the pane when a folder cannot be read.
    private(set) var errorMessage: String?
    /// Set when the saved folder is not reachable — usually a drive that is not connected.
    /// Its saved place is kept; `restore()` tries again (the pane calls it when a drive mounts).
    private(set) var missingRootPath: String?

    // REM  TOOLBAR SETTINGS — per pane, and SAVED (his rule: everything persists). Changing
    // REM  either re-reads the folder at once, keeping the highlight on the same file.
    var sortKey: SortKey {
        didSet { store.save(sort: sortKey.rawValue, for: side); reload() }
    }
    var showHidden: Bool {
        didSet { store.save(showHidden: showHidden, for: side); reload() }
    }

    init(side: String, store: StateStore = .shared) {
        self.side = side
        self.store = store
        // REM  Read in init, so these didSets do not fire (and do not re-save) at launch.
        sortKey = SortKey(rawValue: store.sort(for: side) ?? "") ?? .name
        showHidden = store.showHidden(for: side)
        revealed = Set(store.revealed(for: side))
    }

    var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return rows.firstIndex { $0.id == selectedID }
    }

    var selectedEntry: FileEntry? {
        selectedIndex.map { rows[$0].entry }
    }

    func isSelected(_ id: FileEntry.ID) -> Bool { selection.contains(id) }

    /// Every highlighted row, top to bottom.
    /// REM  A folder AND something inside it (both revealed and highlighted) → only the folder:
    /// REM  it already carries what is inside, and copying both would copy the inner one twice.
    var selectedEntries: [FileEntry] {
        let picked = rows.filter { selection.contains($0.id) }.map(\.entry)
        return picked.filter { entry in
            !picked.contains { other in other.id != entry.id && other.isFolder
                && StateStore.path(entry.id, isInside: other.id) }
        }
    }

    // MARK: - Clicks and ranges (multi-select)

    /// A click on a row, with the modifier keys that were held.
    func click(_ id: FileEntry.ID, command: Bool, shift: Bool) {
        // REM  The drive list is one-at-a-time: a drive is opened, never copied as a batch.
        guard !showingDrives, command || shift else { selectedID = id; return }
        if shift {
            select(rangeTo: id)
        } else {                                                   // ⌘-click: add or remove
            var next = selection
            if next.contains(id) { next.remove(id) } else { next.insert(id) }
            setCursor(next.contains(id) ? id : rows.last { next.contains($0.id) }?.id, keeping: next)
            anchorID = id
        }
    }

    /// Every row from the anchor to `id`. The anchor stays where it is.
    private func select(rangeTo id: FileEntry.ID) {
        guard let anchor = anchorID ?? selectedID,
              let a = rows.firstIndex(where: { $0.id == anchor }),
              let b = rows.firstIndex(where: { $0.id == id }) else { selectedID = id; return }
        let range = rows[min(a, b)...max(a, b)].map(\.id)
        setCursor(id, keeping: Set(range))
    }

    /// Moves the cursor without the plain-click reset, and sets the whole selection.
    private func setCursor(_ id: FileEntry.ID?, keeping set: Set<FileEntry.ID>) {
        extending = true
        selectedID = id
        extending = false
        selection = set
    }

    /// (^).. and ⌘↑. Inside the chosen folder it goes up one folder; at its top it shows the
    /// drive list. Only the drive list itself has nothing above it.
    var canGoUp: Bool {
        !showingDrives && currentURL != nil
    }

    /// At the top of the drive or folder he chose — the next "up" is the drive list.
    var isAtTop: Bool {
        guard let rootURL, let currentURL else { return false }
        return currentURL.standardizedFileURL.path == rootURL.standardizedFileURL.path
    }

    // MARK: - Saved place

    /// At launch (and when a drive mounts): back to the saved folder and highlight.
    /// Does nothing if the pane is already showing its folder.
    func restore() {
        guard currentURL == nil, !showingDrives else { return }
        let place = store.place(for: side)
        // REM  Quit while showing the drive list → it opens on the drive list again.
        let wasShowingDrives = store.showingDrives(for: side)
        guard let data = place.rootBookmark else {             // never chosen — stays empty…
            if wasShowingDrives { showDrives() }               // …unless it was on the drive list
            return
        }

        guard let (root, stale) = StateStore.resolve(data),
              FileManager.default.fileExists(atPath: root.path) else {
            if wasShowingDrives { showDrives(); return }       // the drive list needs no drive
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
        if wasShowingDrives {
            currentURL = folder
            showDrives()
            return
        }
        // REM  Read the saved multi-highlight BEFORE show(): show() sets the cursor row, which
        // REM  saves a one-row highlight over it.
        let savedSelection = Set(store.selectedPaths(for: side))
        show(folder: folder, highlight: place.selectedPath)
        keepSelection(savedSelection, anchor: place.selectedPath)
    }

    private func isInsideRoot(_ path: String) -> Bool {
        guard let rootURL else { return false }
        return StateStore.path(URL(fileURLWithPath: path).standardizedFileURL.path,
                               isInside: rootURL.standardizedFileURL.path)
    }

    // MARK: - Folders

    /// A new root, chosen by him. Shows it with NOTHING highlighted, and saves the permission —
    /// both as this pane's place and in the list of everything he has granted.
    func choose(root: URL) {
        setRoot(root, bookmark: StateStore.bookmark(for: root))
        store.addGrant(root)
        show(folder: root, highlight: nil)
    }

    private func setRoot(_ root: URL, bookmark: Data?) {
        if let old = rootURL, old != root { old.stopAccessingSecurityScopedResource() }
        _ = root.startAccessingSecurityScopedResource()
        rootURL = root
        missingRootPath = nil
        store.save(root: bookmark, rootPath: root.path, for: side)
    }

    // MARK: - Going to a path or a drive

    enum GoResult: Equatable {
        case opened
        /// Nothing is there.
        case notFound
        /// It is a file, not a folder.
        case notAFolder
        /// Outside everything he has granted — the sandbox needs him to grant it first.
        case needsPermission
    }

    /// The path box and the drive picker both come here. Inside this pane's folder, or inside
    /// anything he granted before, it opens straight away; anywhere else he is asked first.
    /// "~" means his real home folder, not the sandbox's.
    func go(toPath typed: String) -> GoResult {
        var raw = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("~") { raw = Self.realHome + raw.dropFirst() }
        guard raw.hasPrefix("/") else { return .notFound }
        let target = URL(fileURLWithPath: raw).standardizedFileURL

        if !isInsideRoot(target.path) {
            guard let grant = store.grantCovering(target.path),
                  let (url, _) = StateStore.resolve(grant.bookmark) else { return .needsPermission }
            // A different granted folder becomes this pane's ceiling.
            guard exists(target).found else { return .notFound }
            setRoot(url, bookmark: grant.bookmark)
        }
        let (found, isFolder) = exists(target)
        guard found else { return .notFound }
        guard isFolder else { return .notAFolder }
        show(folder: target, highlight: nil)
        return .opened
    }

    private func exists(_ url: URL) -> (found: Bool, isFolder: Bool) {
        var isDir: ObjCBool = false
        let found = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return (found, isDir.boolValue)
    }

    /// His home folder. Inside the sandbox NSHomeDirectory() is the app's container, so the
    /// real one comes from the user database.
    static var realHome: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }

    /// The name of the drive this pane is on, for the drive picker's label.
    var driveName: String? {
        guard let currentURL else { return nil }
        return (try? currentURL.resourceValues(forKeys: [.volumeNameKey]))?.volumeName
    }

    /// Opens the highlighted row if it is a folder. Files do nothing yet (step one).
    func openSelected() {
        guard let entry = selectedEntry, entry.isFolder else { return }
        if showingDrives {
            // REM  Opening a drive may need his permission the first time, which only the view
            // REM  can ask for — so the result goes back to it.
            let result = go(toPath: entry.url.path)
            onOpen?(result, entry.url)
            return
        }
        show(folder: entry.url, highlight: nil)
    }

    /// Up one folder, never above the chosen root. The folder just left stays highlighted,
    /// the way Finder does it.
    func goUp() {
        guard canGoUp, let currentURL else { return }
        if isAtTop { showDrives(); return }
        show(folder: currentURL.deletingLastPathComponent(), highlight: currentURL.path)
    }

    // MARK: - The drive list

    /// Every drive, local first then network, as rows. The drive the pane was on is highlighted,
    /// so pressing Return goes straight back.
    func showDrives() {
        let drives = Drives.mounted()
        showingDrives = true
        store.save(showingDrives: true, for: side)
        errorMessage = nil
        entries = drives.map { FileEntry(url: $0.url, name: $0.name, isFolder: true, drive: $0.kind) }
        rows = entries.map { Row(entry: $0, depth: 0) }
        let here = currentURL.flatMap { Drives.drive(holding: $0.standardizedFileURL.path, in: drives) }
        selectedID = here?.id ?? rows.first?.id
    }

    /// Re-reads the folder, keeping the highlight on the same files if they are still there.
    func reload() {
        if showingDrives { showDrives(); return }
        guard let currentURL else { return }
        let kept = selection, anchor = anchorID
        show(folder: currentURL, highlight: selectedID)
        keepSelection(kept, anchor: anchor)
    }

    /// After a re-read: every highlighted row that still exists stays highlighted.
    private func keepSelection(_ kept: Set<FileEntry.ID>, anchor: FileEntry.ID?) {
        let still = kept.filter { id in rows.contains { $0.id == id } }
        guard still.count > 1 else { return }
        setCursor(selectedID ?? rows.last { still.contains($0.id) }?.id, keeping: still)
        anchorID = anchor.flatMap { a in still.contains(a) ? a : nil } ?? selectedID
    }

    /// Re-reads the folder and highlights one particular file — e.g. a file he just renamed.
    func reload(highlighting id: FileEntry.ID?) {
        guard !showingDrives, let currentURL else { return }
        show(folder: currentURL, highlight: id)
    }

    /// After the highlighted file was moved away or deleted: re-read the folder and highlight the
    /// row that took its place (the next one down, or the new last row).
    /// REM  HIS ASK (the old app, 2026-09-28): after ⌘6 the next file in line should be highlighted,
    /// REM  and he noticed ⌘8 never did it. Here both do, through this one function, so move and
    /// REM  delete can never drift apart. This is not an auto-highlight of a row he never chose:
    /// REM  he had a row highlighted, and the highlight stays at that SPOT in the list.
    func reloadAfterRemoving(rowAt index: Int?) {
        reload()
        guard let index, !rows.isEmpty, selectedID == nil else { return }
        selectedID = rows[min(index, rows.count - 1)].id
    }

    // REM  THE TWO NAME SHEETS. They live on the model, not the view, so the KEYS (⌘7, ⌘9 — the
    // REM  quick-access bar, build 56) can open them as well as the buttons.
    /// True while the New Folder name sheet is up.
    var askingNewFolderName = false
    /// True while the Rename sheet is up for the highlighted row.
    var askingRename = false

    private func show(folder: URL, highlight: FileEntry.ID?) {
        if showingDrives {                                     // leaving the drive list
            showingDrives = false
            store.save(showingDrives: false, for: side)
        }
        currentURL = folder
        store.save(currentPath: folder.path, for: side)
        do {
            entries = try Self.listing(of: folder, sort: sortKey, showHidden: showHidden)
            errorMessage = nil
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
        rebuildRows()
        // REM  NO AUTO-HIGHLIGHT — his ruling, 2026-09-28 (build 55). Opening a folder used to
        // REM  highlight its first row by itself. That was a TRAP once copies land in a highlighted
        // REM  folder (his rule): open Video Convert and Classic Cinema lit up on its own, so a copy
        // REM  would have gone INTO Classic Cinema instead of Video Convert without him choosing it.
        // REM  So a highlight only appears when HE makes one (a click or an arrow key) — or when it
        // REM  is one he already made: the saved highlight at launch, the folder just left on (^)..,
        // REM  the folder he just made, the same file after a re-sort or Refresh.
        // REM  If that file is gone, the highlight goes to NOTHING, never to a row he did not pick.
        if let highlight, rows.contains(where: { $0.id == highlight }) {
            selectedID = highlight
        } else {
            selectedID = nil
        }
    }

    /// Folders first, then files, each in Finder's name order (so "Track 2" comes before
    /// "Track 10"). Hidden files are left out.
    static func listing(of folder: URL, sort: SortKey = .name, showHidden: Bool = false) throws -> [FileEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey, .isPackageKey]
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: showHidden ? [] : [.skipsHiddenFiles])
        let entries = urls.map { url in
            let v = try? url.resourceValues(forKeys: Set(keys))
            let isFolder = v?.isDirectory ?? false
            return FileEntry(url: url, name: url.lastPathComponent, isFolder: isFolder,
                             size: isFolder ? 0 : Int64(v?.fileSize ?? 0),
                             modified: v?.contentModificationDate,
                             isHidden: v?.isHidden ?? url.lastPathComponent.hasPrefix("."),
                             isPackage: v?.isPackage ?? false)
        }
        // REM  Finder's name order ("Track 2" before "Track 10") breaks every tie, so rows never
        // REM  jump around between reloads.
        let byName: (FileEntry, FileEntry) -> Bool = {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return entries.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            switch sort {
            case .name:
                return byName(a, b)
            case .kind:
                let ka = FileKind.allCases.firstIndex(of: a.kind)!, kb = FileKind.allCases.firstIndex(of: b.kind)!
                return ka != kb ? ka < kb : byName(a, b)
            case .date:
                let da = a.modified ?? .distantPast, db = b.modified ?? .distantPast
                return da != db ? da > db : byName(a, b)
            case .size:
                return a.size != b.size ? a.size > b.size : byName(a, b)
            }
        }
    }

    // MARK: - New Folder

    enum NewFolderResult: Equatable {
        case created
        case emptyName
        /// A name macOS will not take in a folder name ("/" or ":").
        case badName
        case alreadyExists
        case noFolder
        case failed(String)
    }

    /// Makes a folder in the folder the pane is showing, then highlights it.
    /// REM  Never overwrites: a name already in use is refused, not replaced.
    func newFolder(named typed: String) -> NewFolderResult {
        guard let currentURL else { return .noFolder }
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .emptyName }
        guard !name.contains("/"), !name.contains(":") else { return .badName }
        let url = currentURL.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: url.path) else { return .alreadyExists }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            return .failed(error.localizedDescription)
        }
        show(folder: currentURL, highlight: url.path)
        return .created
    }

    // MARK: - Highlight

    /// ↑ is -1, ↓ is +1. Stops at the first and last rows — it does not wrap around.
    /// With nothing highlighted, any move highlights the first row.
    func moveSelection(by offset: Int, extend: Bool = false) {
        guard !rows.isEmpty else { selectedID = nil; return }
        guard let index = selectedIndex else { selectedID = rows.first?.id; return }
        let target = min(max(index + offset, 0), rows.count - 1)
        // REM  ⇧↑ / ⇧↓ grow or shrink the range from the anchor, the way Finder does.
        if extend && !showingDrives {
            select(rangeTo: rows[target].id)
        } else {
            selectedID = rows[target].id
        }
    }

    // MARK: - Copy target (where a copy or move INTO this pane lands)

    // REM  HIS RULE, 2026-09-28: a copy goes into "the highlighted folder if one is highlighted" —
    // REM  otherwise into the folder the pane has open. This pane is the DESTINATION when the
    // REM  OTHER pane is active (the source). The target is SHOWN on screen before anything is
    // REM  copied (build 55) — a marker on the folder row or on the path box, and its name in the
    // REM  status bar — so he never has to guess where a file will go.
    // REM  Copy and move themselves are NOT built yet; this only decides and shows the target.

    enum CopyTarget: Equatable {
        /// A folder row highlighted in this pane — copies go INTO it.
        case highlightedFolder(URL)
        /// Nothing, or a file, is highlighted — copies go into the open folder.
        case openFolder(URL)

        var url: URL {
            switch self {
            case .highlightedFolder(let url), .openFolder(let url): return url
            }
        }
    }

    /// Where a copy into this pane would land. nil = nowhere yet (no folder open, or the pane is
    /// showing the drive list — a drive must be opened first, which may need his permission).
    var copyTarget: CopyTarget? {
        guard !showingDrives, let currentURL else { return nil }
        // REM  Several rows highlighted in the destination → no one folder is THE target, so the
        // REM  open folder is. (Only a single highlighted folder is dropped INTO.)
        if selection.count <= 1, let entry = selectedEntry, Self.canReceive(entry) {
            return .highlightedFolder(entry.url)
        }
        return .openFolder(currentURL)
    }

    /// A row a copy can go INTO: a real folder. REM  Not a package (.app, .photoslibrary) —
    /// dropping files inside one of those would damage it; macOS shows them as one item. Not a
    /// drive-list row. Same test as the reveal triangle: if you can see inside it, you can drop in it.
    static func canReceive(_ entry: FileEntry) -> Bool { canReveal(entry) }

    // MARK: - Reveal (Finder's disclosure triangle)

    // REM  HIS RULE FOR THE HIGHLIGHT, 2026-09-28: the folder "should stay highlighted unless the
    // REM  mouse selects a different folder." So revealing or hiding a folder NEVER moves the
    // REM  highlight. The one exception is forced: if the highlighted file is inside a folder being
    // REM  hidden, it would vanish from the screen, so the highlight goes to that folder (as Finder
    // REM  does) instead of pointing at nothing.

    /// True for a folder that can be revealed. Packages (.app, .photoslibrary) show as one item,
    /// the way Finder shows them, so they get no triangle.
    static func canReveal(_ entry: FileEntry) -> Bool {
        // REM  Drives in the drive list get no triangle: opening one may need his permission first.
        entry.isFolder && !entry.isPackage && entry.kind == .folder && entry.drive == nil
    }

    func isRevealed(_ entry: FileEntry) -> Bool { revealed.contains(entry.id) }

    func toggleReveal(_ entry: FileEntry) {
        guard Self.canReveal(entry) else { return }
        if revealed.contains(entry.id) {
            revealed.remove(entry.id)
            if let selectedID, StateStore.path(selectedID, isInside: entry.id), selectedID != entry.id {
                self.selectedID = entry.id
            }
        } else {
            revealed.insert(entry.id)
        }
        store.save(revealed: Array(revealed), for: side)
        let kept = selection, anchor = anchorID
        rebuildRows()
        keepSelection(kept, anchor: anchor)
    }

    /// `entries`, with each revealed folder's contents under it — read fresh from the disk,
    /// in this pane's sort order and hidden-file setting.
    private func rebuildRows() {
        var out: [Row] = []
        func add(_ list: [FileEntry], depth: Int) {
            for entry in list {
                out.append(Row(entry: entry, depth: depth))
                // REM  A depth cap, so a folder that links back into itself cannot loop forever.
                if depth < 32, Self.canReveal(entry), revealed.contains(entry.id),
                   let inside = try? Self.listing(of: entry.url, sort: sortKey, showHidden: showHidden) {
                    add(inside, depth: depth + 1)
                }
            }
        }
        add(entries, depth: 0)
        rows = out
    }
}
