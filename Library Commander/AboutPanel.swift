//
//  AboutPanel.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  About Library Commander: the exact build, and who inspired it.
// REM  His ask, 2026-09-28: "draw inspiration from midnight commander or any file commander open
// REM  source project and cite their inspiration in the about sheet."
// REM  His standing rule (every app, About AND README): credit others and state that his
// REM  copyright does not claim their work. Keep this in step with README.md.
// REM
// REM  WHAT WE TAKE FROM THE COMMANDERS — the design, not the code:
// REM    · two panes; the ACTIVE pane is the source, the other pane is the target
// REM    · Tab switches panes
// REM    · the numbered command row: View, Edit, Copy, Move, New Folder, Delete (F3–F8 there,
// REM      ⌘3–⌘8 here), so a file command is always one key away
// REM  No code from Midnight Commander (GPLv3+) or Norton Commander (proprietary) is used.
//

import AppKit

enum AboutPanel {
    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: "\(BuildStamp.version) (build \(BuildStamp.number))",
            .version: "",
            .credits: credits,
        ])
    }

    private static var credits: NSAttributedString {
        // His rule: nothing under 18 pt — unless HE sets a smaller size in Accessibility….
        let size = CGFloat(TextSize.current)
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: NSColor.labelColor,
        ]
        let bold: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: size),
            .foregroundColor: NSColor.labelColor,
        ]
        let text = NSMutableAttributedString()
        func add(_ s: String, _ a: [NSAttributedString.Key: Any] = body) {
            text.append(NSAttributedString(string: s, attributes: a))
        }

        add("A file commander first, and a media organizer and player second.\n\n")
        add(BuildStamp.summary + "\n\n")

        add("Inspired by\n", bold)
        add("Midnight Commander — started by Miguel de Icaza in 1994 and developed by its contributors. "
            + "Free software under the GNU General Public License, version 3 or later. midnight-commander.org\n\n")
        add("Norton Commander — written by John Socha, released by Peter Norton Computing in 1986. "
            + "The original two-pane file commander.\n\n")
        add("Library Commander borrows their ideas — two panes, the active pane as the source, Tab to "
            + "switch, and numbered file commands — and contains none of their code.\n\n")

        add("Copyright © 2026 Michael Fluharty. This copyright covers Michael Fluharty's original work only. "
            + "It does not claim or intend ownership of the work of the original developers named here. "
            + "Midnight Commander and Norton Commander are the property of their respective owners, and "
            + "Library Commander is not affiliated with or endorsed by them.")
        return text
    }
}
