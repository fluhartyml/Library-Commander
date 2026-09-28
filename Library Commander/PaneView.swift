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

    @State private var pathText = ""
    @State private var drives: [Drive] = []
    @State private var askingNewFolderName = false
    @State private var newFolderName = "untitled folder"


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
            pathText = pane.currentURL?.path ?? ""
        }
        .onChange(of: pane.currentURL) { _, url in pathText = url?.path ?? "" }
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
                Label(pane.driveName ?? "Drives", systemImage: "externaldrive")
            }
            .fixedSize()
            .help("Choose a drive")

            TextField("Type a path and press Return", text: $pathText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { go(to: pathText, name: nil) }

            Button {
                pane.goUp()
            } label: {
                // (^).. — the same look as the old Library Commander's up button.
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle.fill")
                    Text("..").font(.system(size: 18, design: .monospaced))
                }
            }
            .disabled(!pane.canGoUp)
            .help("Up one folder (⌘↑)")
        }
        .padding(8)
    }

    /// The drive picker and the path box both come here.
    private func go(to path: String, name: String?) {
        onActivate()
        let label = name ?? path
        switch pane.go(toPath: path) {
        case .opened:
            report("Opened \(label).", false)
        case .notFound:
            report("Nothing at \(path).", true)
            pathText = pane.currentURL?.path ?? ""
        case .notAFolder:
            report("\(path) is a file, not a folder.", true)
            pathText = pane.currentURL?.path ?? ""
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
            pathText = pane.currentURL?.path ?? ""
        }
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
                newFolderName = "untitled folder"
                askingNewFolderName = true
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
        .sheet(isPresented: $askingNewFolderName) { newFolderSheet }
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
                Button("Cancel") { askingNewFolderName = false }
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
            askingNewFolderName = false
            report("Made the folder “\(name)”.", false)
        case .emptyName:
            report("A folder needs a name.", true)
        case .badName:
            report("A folder name cannot contain “/” or “:”.", true)
        case .alreadyExists:
            report("“\(name)” already exists here — nothing was changed.", true)
        case .noFolder:
            askingNewFolderName = false
            report("Pick a drive first.", true)
        case .failed(let why):
            askingNewFolderName = false
            report("Could not make “\(name)”: \(why)", true)
        }
    }

    // MARK: - List

    @ViewBuilder
    private var content: some View {
        if pane.currentURL == nil, let missing = pane.missingRootPath {
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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(pane.entries) { entry in
                            row(entry)
                                .id(entry.id)
                        }
                    }
                }
                // Keep the highlighted row on screen as the arrows move it.
                .onChange(of: pane.selectedID) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                }
            }
        }
    }

    private func row(_ entry: FileEntry) -> some View {
        let selected = entry.id == pane.selectedID
        return HStack(spacing: 8) {
            // REM  Glyph and color by file type — his ask, 2026-09-28. See FileKind.swift.
            // REM  HIDDEN = RED, his ask 2026-09-28: "i want hidden files and folder glyphs to be
            // REM  colored red." The glyph keeps its type's SHAPE; only the color says "hidden".
            Image(systemName: entry.kind.symbol)
                .foregroundStyle(entry.isHidden ? Color.red : entry.kind.color)
                .frame(width: 26)
            Text(entry.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
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
    }

    private var footer: some View {
        HStack {
            Text("\(pane.entries.count) items")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
