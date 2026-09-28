//
//  ContentView.swift
//  Library Commander
//
//  Created by Michael Fluharty on 9/27/26.
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  Two panes side by side, and the build line along the bottom.
//

import SwiftUI

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
        .onAppear {
            let router = KeyRouter(commander: commander)
            router.start()
            keyRouter = router
        }
    }
}

#Preview {
    ContentView()
}
