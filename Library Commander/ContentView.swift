//
//  ContentView.swift
//  Library Commander
//
//  Created by Michael Fluharty on 9/27/26.
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  Two panes side by side, and the build line along the bottom.
// REM  At launch each pane goes back to its saved place; when a drive mounts, a pane
// REM  waiting for it comes back. The window's size and position are saved too.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @State private var commander = CommanderModel()
    @State private var keyRouter: KeyRouter?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                PaneView(pane: commander.left,
                         isActive: commander.activeSide == .left,
                         onActivate: { commander.activeSide = .left })
                Divider()
                PaneView(pane: commander.right,
                         isActive: commander.activeSide == .right,
                         onActivate: { commander.activeSide = .right })
            }
            Divider()
            // Build number, commit and build time, readable out loud — see BuildStamp.swift.
            Text(BuildStamp.summary)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .frame(minWidth: 900, minHeight: 500)
        .background(WindowFrameSaver(name: "LibraryCommanderMain"))
        .onAppear {
            commander.restore()
            let router = KeyRouter(commander: commander)
            router.start()
            keyRouter = router
        }
        // A drive plugged in — a pane waiting for it comes back to its saved place.
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            commander.restore()
        }
    }
}

/// Saves the window's size and position under a name, and puts it back at launch.
// REM  Everything persists — the window included (his rule, 2026-09-28).
private struct WindowFrameSaver: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.setFrameAutosaveName(name)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

#Preview {
    ContentView()
}
