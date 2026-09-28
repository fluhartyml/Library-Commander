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
    var body: some Scene {
        WindowGroup {
            ContentView()
                // His rule: no text under 18 pt unless he says otherwise. Unstyled text inherits this.
                .font(.system(size: 18))
                // The build number, readable off the screen — see BuildStamp.swift.
                .navigationTitle("Library Commander — build \(BuildStamp.number)")
        }
    }
}
