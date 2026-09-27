//
//  CommandButton.swift
//  Library Commander
//
//  Created by Michael Fluharty with Claude on 2025 Nov 11 1920
//

import SwiftUI

struct CommandButton: View {
    let label: String
    let shortcut: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(shortcut)
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
                Text(label)
                    .font(.system(size: 18))
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderless)
        .opacity(isEnabled ? 1.0 : 0.5)
        .background(
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
        )
    }
}
