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
import QuickLook

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
                         report: { commander.report($0, problem: $1) },
                         finishRename: { commander.finishRename(to: $0) },
                         command: { commander.runQuickKey($0) })
                Divider()
                PaneView(pane: commander.right,
                         isActive: commander.activeSide == .right,
                         onActivate: { commander.activeSide = .right },
                         report: { commander.report($0, problem: $1) },
                         finishRename: { commander.finishRename(to: $0) },
                         command: { commander.runQuickKey($0) })
            }
            Divider()
            quickBar
            Divider()
            statusBar
        }
        // ⌘3 View — Quick Look, the same preview Finder's space bar gives.
        .quickLookPreview(Binding(get: { commander.quickLookURL },
                                  set: { commander.quickLookURL = $0 }),
                          in: commander.quickLookURLs)
        // REM  THE CLASH SHEET (build 57): a copy or move waits here while he decides.
        .sheet(item: Binding(get: { commander.pendingClash }, set: { _ in })) { clash in
            ClashSheet(clash: clash) { choice, all in commander.answer(choice, applyToAll: all) }
        }
        .frame(minWidth: 900, minHeight: 500)
        .background(WindowFrameSaver(name: "LibraryCommanderMain"))
        .onAppear {
            commander.restore()
            let router = KeyRouter(commander: commander)
            router.start()
            keyRouter = router
            // REM  At launch SwiftUI hands the keyboard to the FIRST text box — the left path box —
            // REM  though nothing shows it. That is why ⌘6 and the arrows went to the box. The
            // REM  keyboard starts with the panes; the box gets it only when he clicks into it.
            DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
        }
        // A drive plugged in — a pane waiting for it comes back to its saved place.
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            commander.restore()
        }
    }

    // REM  THE QUICK-ACCESS BAR (build 56) — his ask, 2026-09-28: the Midnight Commander quick
    // REM  action keys "at the bottom of the app". Each is a real button AND a ⌘-number key
    // REM  (KeyRouter.swift). The key is drawn first and bold so the eye finds the number.
    // REM  Buttons never take the keyboard from the panes — the window routes the keys.
    private var quickBar: some View {
        HStack(spacing: 0) {
            ForEach(CommanderModel.quickKeys) { key in
                Button {
                    commander.runQuickKey(key.number)
                } label: {
                    HStack(spacing: 4) {
                        Text("⌘\(key.number)").bold()
                        Text(key.title)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .help("⌘\(key.number) — \(key.title)")
                if key.number != CommanderModel.quickKeys.last?.number { Divider() }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // REM  THE STATUS BAR — his ask, 2026-09-28: "a user status / feedback bottom bar that uses
    // REM  the version 1.0 build 41 text bar." Left: what just happened, or what went wrong
    // REM  (orange). Right: the build line, which stays — it is how a build is told apart.
    private var statusBar: some View {
        HStack(spacing: 8) {
            // REM  While a copy or move runs: a spinner, and for a file the bytes landed so far,
            // REM  climbing once a second — proof it is alive (his rule).
            if commander.busy != nil {
                ProgressView().controlSize(.regular).scaleEffect(0.6).frame(width: 22, height: 22)
                if let count = commander.busyCount, count > 0 {
                    Text("\(count) done").foregroundStyle(.secondary).monospacedDigit()
                }
                if let bytes = commander.busyBytes, bytes.total > 0 {
                    Text("\(ByteCountFormatter.string(fromByteCount: bytes.done, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: bytes.total, countStyle: .file))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                Image(systemName: commander.statusIsProblem ? "exclamationmark.triangle.fill" : "info.circle")
                    .foregroundStyle(commander.statusIsProblem ? Color.orange : Color.secondary)
            }
            Text(commander.status)
                .foregroundStyle(commander.statusIsProblem ? Color.orange : Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 16)
            // REM  WHERE A COPY WOULD LAND (build 55) — always showing, so he can check it before he
            // REM  acts. The arrow points from the source (active pane) at the destination and flips
            // REM  when Tab swaps them.
            HStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down.fill")
                Text(commander.copyTargetLine)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(commander.destinationPane.copyTarget == nil ? Color.secondary : Color.accentColor)
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
