//
//  AccessibilityView.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  Library Commander › Accessibility… (⇧⌘,) — his ask, 2026-09-28: three items under the app
// REM  menu, "settings, accessability, & about." Accessibility holds what helps him SEE and USE
// REM  the app; Settings holds how the app behaves. Kept apart so neither buries the other.
// REM  Today: text size (see TextSize.swift for why 12–32 is allowed here and nowhere else).
//

import SwiftUI

struct AccessibilityView: View {
    @AppStorage(TextSize.key) private var textSize = TextSize.standard

    var body: some View {
        Form {
            Section("Text size") {
                HStack(spacing: 12) {
                    Text("A").font(.system(size: 18))
                    // REM  Whole points only, so the number he reads is the number he gets.
                    Slider(value: $textSize, in: TextSize.range, step: 1)
                    Text("A").font(.system(size: 32))
                }
                HStack {
                    Text("\(Int(textSize)) pt")
                    Spacer()
                    Button("Back to 18 pt") { textSize = TextSize.standard }
                        .disabled(textSize == TextSize.standard)
                }
                Text("This is how file names and messages will look.")
                    .font(.system(size: textSize))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .font(.system(size: 18))
        .frame(width: 520)
        .padding()
    }
}
