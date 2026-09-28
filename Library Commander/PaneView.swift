//
//  PaneView.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  One pane on screen: Choose Folder…, the folder's path, and a plain list of what is
// REM  in it. The list does NOT take the keyboard — KeyRouter.swift drives it. A click
// REM  highlights a row and makes this pane active; a double-click opens a folder.
//

import SwiftUI
import AppKit

struct PaneView: View {
    let pane: PaneModel
    let isActive: Bool
    let onActivate: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
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
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button("Choose Folder…") { chooseFolder() }
            Button {
                pane.goUp()
            } label: {
                Image(systemName: "arrow.up")
            }
            .disabled(!pane.canGoUp)
            .help("Up one folder (⌘↑)")
            Text(pane.currentURL?.path ?? "No folder chosen")
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(8)
    }

    @ViewBuilder
    private var content: some View {
        if pane.currentURL == nil {
            VStack(spacing: 12) {
                Spacer()
                Text("Choose a folder or drive to show here.")
                    .foregroundStyle(.secondary)
                Button("Choose Folder…") { chooseFolder() }
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
            Image(systemName: entry.isFolder ? "folder.fill" : "doc")
                .foregroundStyle(entry.isFolder ? Color.blue : Color.secondary)
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

    /// The sandbox only lets the app into folders he picks here, so this is the way in.
    private func chooseFolder() {
        onActivate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Show in Pane"
        if panel.runModal() == .OK, let url = panel.url {
            pane.choose(root: url)
        }
    }
}
