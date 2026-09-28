//
//  SettingsView.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  Library Commander › Settings… (⌘,) — his ask, 2026-09-28. How the app BEHAVES:
// REM   · each pane's Sort and Show Hidden — the same two settings as the pane's toolbar, so a
// REM     change here shows in the pane at once and the other way round (one saved value each);
// REM   · every drive and folder he has granted, with Forget. Without this list the grants are
// REM     invisible: the sandbox remembers them, and nothing on screen said so.
// REM  Everything here is saved the moment it changes (his rule: everything persists).
//

import SwiftUI

struct SettingsView: View {
    let commander: CommanderModel
    @State private var grants: [String] = []

    var body: some View {
        Form {
            paneSection("Left pane", commander.left)
            paneSection("Right pane", commander.right)

            Section("Drives and folders you have granted") {
                if grants.isEmpty {
                    Text("None yet. Pick a drive in a pane and grant it; it will be listed here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(grants, id: \.self) { path in
                    HStack {
                        Image(systemName: "externaldrive")
                        Text(path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        // REM  Forget only takes away the saved permission. It deletes nothing, and
                        // REM  a pane already showing that place keeps showing it until it moves.
                        Button("Forget") {
                            commander.store.removeGrant(path)
                            grants = commander.store.grantPaths
                            commander.report("Forgot access to \(path). You will be asked again next time.")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 620)
        .frame(minHeight: 460)
        .onAppear { grants = commander.store.grantPaths }
    }

    private func paneSection(_ title: String, _ pane: PaneModel) -> some View {
        Section(title) {
            Picker("Sort by", selection: Binding(get: { pane.sortKey }, set: { pane.sortKey = $0 })) {
                ForEach(SortKey.allCases) { key in Text(key.title).tag(key) }
            }
            Toggle("Show hidden files and folders", isOn: Binding(get: { pane.showHidden },
                                                                 set: { pane.showHidden = $0 }))
        }
    }
}
