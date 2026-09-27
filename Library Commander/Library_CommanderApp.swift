//
//  Library_CommanderApp.swift
//  Library Commander
//
//  Created by Michael Fluharty on 9/27/26.
//

import SwiftUI

@main
struct Library_CommanderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // The build number, readable off the screen — see BuildStamp.swift.
                .navigationTitle("Library Commander — build \(BuildStamp.number)")
        }
    }
}
