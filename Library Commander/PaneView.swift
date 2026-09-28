//
//  PaneView.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  One pane on screen. Header, his layout and ORDER (2026-09-28): a DRIVE PICKER, then a PATH
// REM  BOX he can type a path into, then the (^).. up-one-folder button. Then a plain list of what is in
// REM  the folder. The list does NOT take the keyboard — KeyRouter.swift drives it. A click
// REM  highlights a row and makes this pane active; a double-click opens a folder.
// REM  WHY THIS ORDER, his reasoning: "it causes the users eyes to start at the drive look at
// REM  the path then up or previous" — the eye reads left to right from the widest place (the
// REM  drive) to the exact place (the path) to where you can go next (up). Keep the order.
// REM  What happens (or why it could not) is told in the status bar at the bottom.
//

import SwiftUI
import AppKit

struct PaneView: View {
    let pane: PaneModel
    let isActive: Bool
    let onActivate: () -> Void
    /// Sends a message to the status bar. `true` = a problem.
    let report: (String, Bool) -> Void
    /// Handed in so the Rename sheet can run the rename and report it (CommanderModel).
    let finishRename: (String) -> Bool
    /// Runs a quick-access command (⌘ + number) — the right-click menu uses the same commands.
    let command: (Int) -> Void

    // REM  His text size (Accessibility…), for the few places that set a font of their own.
    @AppStorage(TextSize.key) private var textSize = TextSize.standard
    @State private var pathText = ""
    /// True while he is typing in the path box.
    @FocusState private var pathFocused: Bool
    @State private var drives: [Drive] = []
    @State private var newFolderName = "untitled folder"
    @State private var renameText = ""


    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            toolbar
            Divider()
            content
            Divider()
            footer
        }
        .overlay(
            // The active pane — the one the keys drive — has the accent border.
            Rectangle().stroke(isActive ? Color.accentColor : .clear, lineWidth: 2)
        )
        // A click anywhere in the pane makes it active.
        .simultaneousGesture(TapGesture().onEnded { onActivate() })
        .onAppear {
            drives = Drives.mounted()
            syncPath()
            // REM  Opening a drive from the drive list (Return / double-click) reports here, and
            // REM  asks for permission when that drive has never been granted.
            pane.onOpen = { result, url in
                let name = FileManager.default.displayName(atPath: url.path)
                switch result {
                case .opened:          report("Opened \(name).", false)
                case .needsPermission: askForFolder(startingAt: url)
                case .notFound:        report("“\(name)” is not there any more.", true)
                case .notAFolder:      report("“\(name)” is not a folder.", true)
                }
                syncPath()
            }
        }
        .onChange(of: pane.currentURL) { _, _ in syncPath() }
        .onChange(of: pane.showingDrives) { _, _ in syncPath() }
        // REM  THE PATH-BOX FIX (build 54). His bug, 2026-09-28: he cleared the box by accident, then
        // REM  picked the drive the pane was ALREADY on — nothing changed, so nothing refilled it, and
        // REM  it sat empty. Now the box shows the real place again after every drive pick or path,
        // REM  and whenever he clicks away from it without pressing Return.
        .onChange(of: pathFocused) { _, typing in if !typing { syncPath() } }
        // The drive list follows what is plugged in.
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            drives = Drives.mounted()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            drives = Drives.mounted()
        }
    }

    // MARK: - Header: drive picker · path box · (^)..  (his order, 2026-09-28)

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(drives) { drive in
                    Button(drive.name) { go(to: drive.url.path, name: drive.name) }
                }
                Divider()
                Button("Other Folder…") { askForFolder(startingAt: nil) }
            } label: {
                Label(pane.showingDrives ? "Drives" : (pane.driveName ?? "Drives"), systemImage: "externaldrive")
            }
            .fixedSize()
            .help("Choose a drive")

            TextField(pane.showingDrives ? "Drives — pick one below, or type a path" : "Type a path and press Return",
                      text: $pathText)
                .focused($pathFocused)
                .textFieldStyle(.roundedBorder)
                .onSubmit { go(to: pathText, name: nil) }
                // REM  TARGET MARKER ON THE PATH BOX (build 55): when this pane is the destination and
                // REM  nothing — or a file — is highlighted, copies land in the OPEN folder, so the
                // REM  marker sits on the path box that names it. An overlay, so it never shifts his
                // REM  drive → path → (^).. order.
                .overlay(alignment: .trailing) {
                    if isOpenFolderTarget {
                        targetMarker.padding(.trailing, 6).allowsHitTesting(false)
                    }
                }

            Button {
                pane.goUp()
            } label: {
                // (^).. — the same look as the old Library Commander's up button.
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                    Text("..").font(.system(size: TextSize.clamped(textSize), design: .monospaced))
                }
            }
            .disabled(!pane.canGoUp)
            .help(pane.isAtTop ? "Show all drives (⌘↑)" : "Up one folder (⌘↑)")
        }
        .padding(8)
    }

    // MARK: - Copy target marker (build 55)

    // REM  This pane is the DESTINATION whenever it is NOT the active pane — his rule: the active
    // REM  pane is the source, and either side can be either. The marker shows only on the
    // REM  destination, and only in ONE place at a time: the highlighted folder row, or else the
    // REM  path box. One marker = one answer to "where will it go?".

    private var isDestination: Bool { !isActive }

    private var isOpenFolderTarget: Bool {
        guard isDestination, case .openFolder = pane.copyTarget else { return false }
        return true
    }

    private func isTargetRow(_ entry: FileEntry) -> Bool {
        isDestination && pane.copyTarget == .highlightedFolder(entry.url)
    }

    /// A tray with an arrow into it — "files land here".
    private var targetMarker: some View {
        Label("Target", systemImage: "tray.and.arrow.down.fill")
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Color.accentColor)
            .help("Copies and moves from the other pane will go here")
    }

    /// The drive picker and the path box both come here.
    private func go(to path: String, name: String?) {
        onActivate()
        let label = name ?? path
        switch pane.go(toPath: path) {
        case .opened:
            report("Opened \(label).", false)
            syncPath()
        case .notFound:
            report("Nothing at \(path).", true)
            syncPath()
        case .notAFolder:
            report("\(path) is a file, not a folder.", true)
            syncPath()
        case .needsPermission:
            // The sandbox needs him to grant it once; after that it opens without asking.
            askForFolder(startingAt: URL(fileURLWithPath: path))
        }
    }

    /// The sandbox only lets the app into folders he picks here, so this is the way in.
    private func askForFolder(startingAt start: URL?) {
        onActivate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = start
        panel.prompt = "Grant Access"
        if let start {
            panel.message = "Library Commander needs your permission once to open “\(FileManager.default.displayName(atPath: start.path))”. Select it and click Grant Access."
        }
        if panel.runModal() == .OK, let url = panel.url {
            pane.choose(root: url)
            report("Opened \(FileManager.default.displayName(atPath: url.path)). You will not be asked for it again.", false)
        } else {
            report("Nothing opened — access was not granted.", true)
        }
        syncPath()
    }

    /// The path box shows where the pane really is: the folder's path, or empty on the drive list.
    private func syncPath() {
        pathText = pane.showingDrives ? "" : (pane.currentURL?.path ?? "")
    }

    // MARK: - Toolbar: Sort · New Folder · Refresh · Show Hidden

    // REM  His ask, 2026-09-28: "a tool bar below the drive path and previous up folder bar" — one
    // REM  per pane, under that pane's header. FILE TOOLS ONLY, because the app is a file commander
    // REM  first; media tools come later and never crowd these out. Sort and Show Hidden are saved
    // REM  per pane (everything persists).
    private var toolbar: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Sort by", selection: Binding(get: { pane.sortKey },
                                                     set: { pane.sortKey = $0 })) {
                    ForEach(SortKey.allCases) { key in Text(key.title).tag(key) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort: \(pane.sortKey.title)", systemImage: "arrow.up.arrow.down")
            }
            .fixedSize()
            .help("How this pane orders its files. Folders always come first.")

            Button {
                onActivate()
                pane.askingNewFolderName = true
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            .disabled(pane.currentURL == nil)
            .help("Make a folder here")

            Button {
                pane.reload()
                report("Refreshed \(pane.currentURL?.lastPathComponent ?? "").", false)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(pane.currentURL == nil)
            .help("Read this folder again")

            Button {
                pane.showHidden.toggle()
                report(pane.showHidden ? "Showing hidden files." : "Hiding hidden files.", false)
            } label: {
                Label(pane.showHidden ? "Hide Hidden" : "Show Hidden",
                      systemImage: pane.showHidden ? "eye.fill" : "eye.slash")
            }
            .help("Show or hide hidden files and folders — a name starting with a dot, or hidden by macOS. Hidden ones show in red.")

            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        // REM  The sheets are opened by the model's flags, so ⌘7 and ⌘9 (the quick-access bar) open
        // REM  them exactly as the buttons do.
        .sheet(isPresented: Binding(get: { pane.askingNewFolderName },
                                    set: { pane.askingNewFolderName = $0 })) { newFolderSheet }
        .sheet(isPresented: Binding(get: { pane.askingRename },
                                    set: { pane.askingRename = $0 })) { renameSheet }
        .onChange(of: pane.askingNewFolderName) { _, up in if up { newFolderName = "untitled folder" } }
        .onChange(of: pane.askingRename) { _, up in if up { renameText = pane.selectedEntry?.name ?? "" } }
    }

    // REM  A sheet, so the name is typed into its own box. KeyRouter leaves the keys alone while
    // REM  a sheet is up, so Return and the arrows belong to the name field here.
    private var newFolderSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Folder").bold()
            Text("in \(pane.currentURL?.path ?? "")")
                .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            TextField("Folder name", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(createNewFolder)
            HStack {
                Spacer()
                Button("Cancel") { pane.askingNewFolderName = false }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: createNewFolder)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func createNewFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch pane.newFolder(named: name) {
        case .created:
            pane.askingNewFolderName = false
            report("Made the folder “\(name)”.", false)
        case .emptyName:
            report("A folder needs a name.", true)
        case .badName:
            report("A folder name cannot contain “/” or “:”.", true)
        case .alreadyExists:
            report("“\(name)” already exists here — nothing was changed.", true)
        case .noFolder:
            pane.askingNewFolderName = false
            report("Pick a drive first.", true)
        case .failed(let why):
            pane.askingNewFolderName = false
            report("Could not make “\(name)”: \(why)", true)
        }
    }

    // REM  ⌘9 RENAME (build 56). The whole name is shown and editable, extension included, so
    // REM  nothing is hidden from him. Never overwrites: a name already taken is refused and
    // REM  the sheet stays up so he can fix it.
    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename").bold()
            Text("“\(pane.selectedEntry?.name ?? "")”")
                .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            TextField("New name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commitRename)
            HStack {
                Spacer()
                Button("Cancel") { pane.askingRename = false }
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: commitRename)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func commitRename() {
        if finishRename(renameText) { pane.askingRename = false }
    }

    // MARK: - List

    @ViewBuilder
    private var content: some View {
        if pane.showingDrives {
            fileList
        } else if pane.currentURL == nil, let missing = pane.missingRootPath {
            // The saved folder is not reachable — usually a drive that is not connected.
            // Its place is kept; it comes back by itself when the drive mounts.
            VStack(spacing: 12) {
                Spacer()
                Text("“\(FileManager.default.displayName(atPath: missing))” is not connected.")
                Text(missing).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Text("It will come back here when it is.").foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity)
        } else if pane.currentURL == nil {
            VStack(spacing: 12) {
                Spacer()
                Text("Pick a drive above, or type a path.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let error = pane.errorMessage {
            VStack {
                Spacer()
                Text(error).foregroundStyle(.red).multilineTextAlignment(.center).padding()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            fileList
        }
    }

    /// The rows — a folder's contents, or the drive list.
    private var fileList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(pane.rows) { line in
                        row(line.entry, depth: line.depth)
                            .id(line.id)
                    }
                }
            }
            // REM  RIGHT-CLICK ON EMPTY SPACE — the old app's: this folder in Finder, and New Folder.
            .contextMenu {
                if !pane.showingDrives, let here = pane.currentURL {
                    Button("Show This Folder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([here]) }
                    Divider()
                    Button("New Folder") { onActivate(); command(7) }
                }
            }
            // Keep the highlighted row on screen as the arrows move it.
            .onChange(of: pane.selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    private func row(_ entry: FileEntry, depth: Int) -> some View {
        let selected = entry.id == pane.selectedID
        return HStack(spacing: 8) {
            // REM  Indent one step per revealed level, like Finder's list view.
            Color.clear.frame(width: CGFloat(depth) * 22, height: 1)
            // REM  THE REVEAL TRIANGLE. It is its own button, so clicking it opens or closes the
            // REM  folder and does NOT touch the highlight (his rule — see PaneModel's Reveal).
            if PaneModel.canReveal(entry) {
                Button {
                    onActivate()
                    pane.toggleReveal(entry)
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(pane.isRevealed(entry) ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }
                .buttonStyle(.borderless)
                .help(pane.isRevealed(entry) ? "Hide what is inside" : "Show what is inside")
            } else {
                Color.clear.frame(width: 20, height: 1)
            }
            // REM  Glyph and color by file type — his ask, 2026-09-28. See FileKind.swift.
            // REM  HIDDEN = RED, his ask 2026-09-28: "i want hidden files and folder glyphs to be
            // REM  colored red." The glyph keeps its type's SHAPE; only the color says "hidden".
            // REM  Drive-list rows show the drive's own glyph: startup disk, plugged-in drive, network.
            Image(systemName: entry.drive?.symbol ?? entry.kind.symbol)
                .foregroundStyle(entry.drive?.color ?? (entry.isHidden ? FileKind.hiddenRed : entry.kind.color))
                .frame(width: 26)
            Text(entry.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            // REM  "local or network" — his words; each drive row says which.
            if let drive = entry.drive {
                Text(drive.title).foregroundStyle(.secondary)
            }
            // REM  TARGET MARKER ON A FOLDER ROW (build 55): this folder is highlighted in the
            // REM  destination pane, so copies go INTO it (his rule).
            if isTargetRow(entry) {
                targetMarker
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(selected ? Color.accentColor.opacity(isActive ? 0.45 : 0.2) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onActivate()
            pane.selectedID = entry.id
            pane.openSelected()
        }
        .onTapGesture {
            onActivate()
            pane.selectedID = entry.id
        }
        .contextMenu { rowMenu(entry) }
    }

    // REM  RIGHT-CLICK ON A ROW (build 57) — his ask: "we also need the right click back". The old
    // REM  app's FILE items only; media items (Scan for Media, Playlists, Shazam) return when those
    // REM  features do — his order: "file management first the media bells and whistles come after".
    // REM  Every item runs the SAME command as its ⌘-number key, so the two can never disagree.
    // REM  Right-clicking a row highlights it and makes this pane the source first, as Finder does,
    // REM  so the command acts on the row he clicked.
    @ViewBuilder
    private func rowMenu(_ entry: FileEntry) -> some View {
        let pick = { onActivate(); pane.selectedID = entry.id }
        if entry.drive != nil {
            Button("Open") { pick(); pane.openSelected() }
        } else {
            if entry.isFolder && !entry.isPackage {
                Button("Open") { pick(); pane.openSelected() }
            } else {
                Button("Open") { pick(); command(4) }
            }
            Button("Quick Look") { pick(); command(3) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
            Divider()
            Button("Rename…") { pick(); command(9) }
            Divider()
            Button("Copy to Other Pane") { pick(); command(5) }
            Button("Move to Other Pane") { pick(); command(6) }
            Divider()
            Button("Move to Trash") { pick(); command(8) }
            Divider()
            Button("New Folder") { onActivate(); command(7) }
        }
    }

    private var footer: some View {
        HStack {
            Text(pane.showingDrives ? "\(pane.entries.count) drives" : "\(pane.entries.count) items")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
