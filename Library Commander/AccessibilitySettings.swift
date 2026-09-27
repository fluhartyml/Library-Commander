//
//  AccessibilitySettings.swift
//  Library Commander
//
//  His idea, 2026-09-27: "change the Arrow Key Sorting into a library commanders accessabily
//  options toggle as well as a font size slider for accessability".
//
//  TEXT SIZE — his 18 pt rule has ONE granted exception, and this is it:
//  "since its accessability setting it can be allowed to be smaller than 18 ONLY because
//  the user has control of the font size". Range 12–32, DEFAULT 18. Every font in the app
//  is written as `.lc(<size at the 18 pt baseline>)` and scales with this setting; a
//  literal under 18 is still refused by Scripts/check-font-floor.sh.
//

import SwiftUI

@MainActor
@Observable
final class AccessibilitySettings {
    static let shared = AccessibilitySettings()

    static let baseline: Double = 18
    static let range: ClosedRange<Double> = 12...32

    /// The body text size he has chosen, in points.
    var textSize: Double {
        didSet {
            let clamped = min(max(textSize.rounded(), Self.range.lowerBound), Self.range.upperBound)
            if clamped != textSize { textSize = clamped; return }
            UserDefaults.standard.set(textSize, forKey: "textSize")
        }
    }

    /// Arrow Key Sorting, for both panes: ↑ ↓ step through tracks, the arrow toward the other pane
    /// moves the playing track there and plays the next, the arrow away undoes.
    var arrowKeySorting: Bool {
        didSet { UserDefaults.standard.set(arrowKeySorting, forKey: "nuclearMode") }
    }

    /// Multiplier applied to every `.lc(...)` size.
    var scale: Double { textSize / Self.baseline }

    /// Build 15 — "Don't ask again" on the delete question, for Trash deletes.
    var skipDeleteConfirm: Bool {
        didSet { UserDefaults.standard.set(skipDeleteConfirm, forKey: "skipDeleteConfirm") }
    }

    /// Build 16 — his call: "the network drive also gets the dont ask again checkmark".
    /// Kept apart from the Trash one so ticking it on a Trash delete never silences a
    /// permanent one.
    var skipPermanentDeleteConfirm: Bool {
        didSet { UserDefaults.standard.set(skipPermanentDeleteConfirm, forKey: "skipPermanentDeleteConfirm") }
    }

    /// True when any "Don't ask again" / "Don't tell me again" box has been ticked.
    var anyQuestionSilenced: Bool {
        _ = resetTick
        return skipDeleteConfirm || skipPermanentDeleteConfirm || [FileOpKind.copy, .move, .delete].contains { QuietSummaries.isQuiet($0) }
    }
    private var resetTick = 0

    /// His ask: "the settings nneeds a reset never ask again check boxes everywhere".
    func resetAllDontAskAgain() {
        skipDeleteConfirm = false
        skipPermanentDeleteConfirm = false
        QuietSummaries.showAllAgain()
        resetTick += 1
    }

    private init() {
        let saved = UserDefaults.standard.double(forKey: "textSize")
        textSize = saved == 0 ? Self.baseline : min(max(saved, Self.range.lowerBound), Self.range.upperBound)
        arrowKeySorting = UserDefaults.standard.bool(forKey: "nuclearMode")
        skipDeleteConfirm = UserDefaults.standard.bool(forKey: "skipDeleteConfirm")
        skipPermanentDeleteConfirm = UserDefaults.standard.bool(forKey: "skipPermanentDeleteConfirm")
    }
}

extension Font {
    /// Library Commander's font: `size` is the size at the 18 pt default, scaled by the
    /// Accessibility text-size setting. Reading `shared.scale` inside a view's body makes
    /// that view redraw when he moves the slider.
    @MainActor
    static func lc(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size * AccessibilitySettings.shared.scale, weight: weight, design: design)
    }
}

/// The Accessibility window — Library Commander › Accessibility… (⇧⌘,).
struct AccessibilitySettingsView: View {
    @State private var settings = AccessibilitySettings.shared

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Text size")
                        Spacer()
                        Text("\(Int(settings.textSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.textSize, in: AccessibilitySettings.range, step: 1) {
                        Text("Text size")
                    } minimumValueLabel: {
                        Text("A").font(.system(size: 12))  // font-ok: the slider's own small end — he granted sub-18 for this setting
                    } maximumValueLabel: {
                        Text("A").font(.system(size: 32))
                    }
                    .labelsHidden()
                    Button("Reset to 18 pt") { settings.textSize = AccessibilitySettings.baseline }
                        .disabled(settings.textSize == AccessibilitySettings.baseline)
                    Text("The quick brown fox jumps over the lazy dog.")
                        .font(.lc(18))
                        .padding(.top, 4)
                }
            }

            Section {
                Toggle("Arrow Key Sorting", isOn: $settings.arrowKeySorting)
                Text("↑ and ↓ step through tracks. The arrow pointing at the other pane moves the playing track there and plays the next one; the arrow pointing away undoes the last move.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Questions")
                        Text(settings.anyQuestionSilenced
                             ? "Some questions and messages are set to “Don’t ask again”."
                             : "Every question and message is showing.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset All “Don’t Ask Again”") { settings.resetAllDontAskAgain() }
                        .disabled(!settings.anyQuestionSilenced)
                }
            }
        }
        .formStyle(.grouped)
        .font(.lc(18))
        .frame(width: 520)
        .padding(.vertical, 8)
    }
}
