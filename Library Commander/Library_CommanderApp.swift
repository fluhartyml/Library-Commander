//
//  Library_CommanderApp.swift
//  Library Commander
//
//  Created by Michael Fluharty on 9/27/26.
//  Rebuilt from Hello World 2026-09-28, his word: "lets rebuild from scratch".
//  Everything through build 37 is on the tag archive-build-37.
//
// REM ─────────────────────────────────────────────────────────────────────────────────────
// REM  LIBRARY COMMANDER IS A FILE COMMANDER FIRST, AND A MEDIA ORGANIZER / PLAYER SECOND.
// REM  His words, 2026-09-28: "media is secondary to file commanding."
// REM  Every file command (select, open, move, delete…) must work on what is highlighted,
// REM  whatever its type and whether or not anything is playing. Media features may never
// REM  be the reason a file command fails. When the two conflict, file commanding wins.
// REM ─────────────────────────────────────────────────────────────────────────────────────
//

import SwiftUI

@main
struct Library_CommanderApp: App {
    // REM  ONE commander for the whole app, so the main window and Settings… change the SAME
    // REM  panes. (Two copies would each save, and the last one to save would win.)
    @State private var commander = CommanderModel()
    // REM  The text size he picks in Accessibility… (12–32, starts at 18). See TextSize.swift.
    @AppStorage(TextSize.key) private var textSize = TextSize.standard

    var body: some Scene {
        WindowGroup {
            ContentView(commander: commander)
                // Unstyled text inherits this: 18 pt unless he changes it in Accessibility….
                .font(.system(size: TextSize.clamped(textSize)))
                // The build number, readable off the screen — see BuildStamp.swift.
                .navigationTitle("Library Commander — build \(BuildStamp.number)")
        }
        .commands {
            // REM  THE LIBRARY COMMANDER MENU — his ask, 2026-09-28: "settings, accessability, &
            // REM  about." In the Mac's standard order: About, then Settings… (⌘,, added by the
            // REM  Settings scene below), then Accessibility… (⇧⌘,).
            CommandGroup(replacing: .appInfo) {
                // About names the exact build and credits the file commanders that inspired it.
                Button("About Library Commander") { AboutPanel.show() }
            }
            CommandGroup(after: .appSettings) {
                OpenAccessibilityButton()
            }
        }

        Settings {
            SettingsView(commander: commander)
                .font(.system(size: TextSize.clamped(textSize)))
        }

        Window("Accessibility", id: "accessibility") {
            AccessibilityView()
        }
        .windowResizability(.contentSize)
    }
}

/// A menu item that opens the Accessibility window. REM  It has to be a View to reach openWindow.
private struct OpenAccessibilityButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Accessibility…") { openWindow(id: "accessibility") }
            .keyboardShortcut(",", modifiers: [.command, .shift])
    }
}
