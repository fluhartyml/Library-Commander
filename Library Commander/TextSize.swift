//
//  TextSize.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  THE ONE EXCEPTION TO THE 18 PT RULE. His rule for every app: "NO SMALLER THAN 18 POINTS…
// REM  unless explicitly given permission to deviate." He granted this exception in the old
// REM  Library Commander (build 12): the USER may set the text size, 12 to 32, and it starts at 18.
// REM  The app itself never picks anything under 18 — only he can, in Accessibility….
// REM  Saved like every setting (his rule: everything persists).
//

import Foundation

enum TextSize {
    /// The UserDefaults key. REM  Views read it with @AppStorage(TextSize.key) so the whole app
    /// redraws the moment he moves the slider.
    static let key = "textSize"
    static let standard: Double = 18
    static let range: ClosedRange<Double> = 12...32

    /// Any stored value, forced into the allowed range. A missing value is the 18 pt standard.
    static func clamped(_ value: Double?) -> Double {
        guard let value, value > 0 else { return standard }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// The size right now, for AppKit text (the About panel), which cannot use @AppStorage.
    static var current: Double {
        clamped(UserDefaults.standard.object(forKey: key) as? Double)
    }
}
