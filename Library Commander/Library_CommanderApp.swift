//
//  Library_CommanderApp.swift
//  Library Commander
//
//  Created by Michael Fluharty on 9/27/26.
//  Rebuilt from Hello World 2026-09-28, his word: "lets rebuild from scratch".
//  Everything through build 37 is on the tag archive-build-37.
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
