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
    @AppStorage(ArrowMoveCopy.key) private var arrowMoveCopy = false

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
            // REM  ARROW MOVE AND COPY (build 62) — his design, 2026-09-28. Stated as SOURCE and
            // REM  DESTINATION, never left and right: either pane can be either (his correction).
            Section("Arrow keys") {
                Toggle("Move and copy with the arrow keys", isOn: $arrowMoveCopy)
                Text("⌘ + the arrow pointing at the other pane moves the highlighted files there. ⇧⌘ + that arrow copies them. The arrow pointing back at the active pane undoes that last move or copy — all of its files at once.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .font(.system(size: 18))
        .frame(width: 520)
        .padding()
    }
}
