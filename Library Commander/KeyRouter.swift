//
//  KeyRouter.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  WHY THE KEYS ARE CAUGHT HERE AND NOT ON THE LIST (the lesson of 2026-09-28):
// REM  In the old app each key lived on the file list, so it only worked while the list
// REM  held the keyboard. Clicking the video, the preview or a toggle took the keyboard
// REM  away, and Delete and the arrows silently did nothing.
// REM  Here the WINDOW catches the keys and hands them to the ACTIVE pane, so a file key
// REM  works whatever was clicked last. The one exception is typing into a text box
// REM  (a rename, later): then the keys belong to the text box.
// REM  ⚠️ Do not move these keys back onto a view with .onKeyPress — that is the old bug.
//

import AppKit
import os

final class KeyRouter {
    private var monitor: Any?
    private let commander: CommanderModel

    init(commander: CommanderModel) {
        self.commander = commander
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let used = self.handle(event)
            self.log(event, used: used)
            return used ? nil : event
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    /// The number keys along the top row, by their hardware key code.
    private static let digit: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 0,
    ]

    // REM  DEBUG LOG (build 58) — his ⌘6 bonked on build 57 and the code alone could not say why.
    // REM  Every key the window sees is written with its key code, its modifiers, what held the
    // REM  keyboard, whether a sheet was up, and whether the router USED it. Key codes only —
    // REM  never the characters, so nothing he types into a box is recorded.
    // REM  Read it: log show --last 10m --predicate 'subsystem == "com.fluharty.Library-Commander"'
    // REM  Remove once the bonk is explained.
    private static let logger = Logger(subsystem: "com.fluharty.Library-Commander", category: "keys")

    private func log(_ event: NSEvent, used: Bool) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let responder = event.window?.firstResponder.map { String(describing: type(of: $0)) } ?? "no window"
        let sheet = event.window?.attachedSheet != nil
        let modal = NSApp.modalWindow != nil
        let line = "key \(event.keyCode) flags 0x\(String(flags.rawValue, radix: 16)) responder \(responder) sheet \(sheet) modal \(modal) → \(used ? "USED" : "passed on")"
        Self.logger.notice("\(line, privacy: .public)")
        print("[keys] " + line)
    }

    /// True = the key was a file command and was used here.
    private func handle(_ event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        // A sheet, alert or other window is in front — the keys are not ours.
        if NSApp.modalWindow != nil || window.attachedSheet != nil { return false }
        let typing = window.firstResponder is NSText

        // REM  macOS marks the ARROW keys with two flags of its own — .function and .numericPad —
        // REM  that no one is holding. Left in, "↑ with no modifiers" and "⇧↑" never match.
        // REM  Only keys the person holds (⌘ ⇧ ⌥ ⌃) count. The debug log still records the raw flags.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.function, .numericPad])
        let command = flags.contains(.command)
        let pane = commander.activePane

        // REM  THE QUICK-ACCESS BAR, ⌘1–⌘9 (build 56) — Midnight Commander's F-key row. Caught by
        // REM  the physical key, so it works on any keyboard layout. ⌘ alone, no other modifier.
        // REM  THE ⌘6 BONK, FOUND 2026-09-28 by the build-58 key log: every ⌘6 arrived while the
        // REM  PATH BOX's text editor held the keyboard (_SystemTextFieldFieldEditor) — so this router
        // REM  handed it to the box, and the box bonked. ⌘1–⌘9 now work EVEN WHILE a text box has the
        // REM  keyboard, the way a Mac menu shortcut does; a text box has no use for ⌘-numbers.
        if flags == .command, let number = Self.digit[event.keyCode] {
            return commander.runQuickKey(number)
        }
        // Typing into a text box — every OTHER key (arrows, Return, Tab) belongs to it.
        if typing { return false }

        switch event.keyCode {
        // REM  ⌘↑ / ⌘↓ — his ask, 2026-09-28, build 63: "can command up and down move up one and down
        // REM  one too so i dont have to release the sticky keys?" With Sticky Keys, ⌘ stays latched
        // REM  between ⌘-arrow moves, so while ARROW MOVE AND COPY is on, ⌘↑/⌘↓ step the highlight
        // REM  one row. With it off they keep Finder's meaning (up a folder / open the folder).
        case 126 where flags == .command, 125 where flags == .command:
            commander.commandUpDown(up: event.keyCode == 126)
        case 126 where flags.isEmpty:    // ↑
            pane.moveSelection(by: -1)
        case 125 where flags.isEmpty:    // ↓
            pane.moveSelection(by: 1)
        // REM  ARROW MOVE AND COPY (build 62): ⌘ + ← / → moves, ⇧⌘ copies — toward the destination.
        // REM  The same arrow back toward the source undoes. CommanderModel works out which is which.
        case 123 where flags == .command, 124 where flags == .command:
            commander.arrow(towardRight: event.keyCode == 124, copy: false)
        case 123 where flags == [.command, .shift], 124 where flags == [.command, .shift]:
            commander.arrow(towardRight: event.keyCode == 124, copy: true)
        case 126 where flags == .shift:  // ⇧↑  grow the highlight upward (multi-select, build 59)
            pane.moveSelection(by: -1, extend: true)
        case 125 where flags == .shift:  // ⇧↓  grow the highlight downward
            pane.moveSelection(by: 1, extend: true)
        case 36, 76:                     // Return, Enter  open the highlighted folder
            guard flags.isEmpty else { return false }
            pane.openSelected()
        case 48:                         // Tab  the other pane becomes active
            guard flags.isEmpty || flags == .shift else { return false }
            commander.switchPanes()
        default:
            return false
        }
        return true
    }
}
