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
    // REM  Handed in by the app, so Settings… changes these same panes.
    let commander: CommanderModel
    @State private var keyRouter: KeyRouter?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                PaneView(pane: commander.left,
                         isActive: commander.activeSide == .left,
                         onActivate: { commander.activeSide = .left },
                         report: { commander.report($0, problem: $1) })
                Divider()
                PaneView(pane: commander.right,
                         isActive: commander.activeSide == .right,
                         onActivate: { commander.activeSide = .right },
                         report: { commander.report($0, problem: $1) })
            }
            Divider()
            statusBar
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

    // REM  THE STATUS BAR — his ask, 2026-09-28: "a user status / feedback bottom bar that uses
    // REM  the version 1.0 build 41 text bar." Left: what just happened, or what went wrong
    // REM  (orange). Right: the build line, which stays — it is how a build is told apart.
    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: commander.statusIsProblem ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(commander.statusIsProblem ? Color.orange : Color.secondary)
            Text(commander.status)
                .foregroundStyle(commander.statusIsProblem ? Color.orange : Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 16)
            // Build number, commit and build time, readable out loud — see BuildStamp.swift.
            Text(BuildStamp.summary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
    ContentView(commander: CommanderModel())
}
