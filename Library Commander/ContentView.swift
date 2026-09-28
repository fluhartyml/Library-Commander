//
//  ContentView.swift
//  Library Commander
//
//  Created by Michael Fluharty on 9/27/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
            // Build number, commit and build time, readable out loud — see BuildStamp.swift.
            Text(BuildStamp.summary)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
