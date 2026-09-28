//
//  Links.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  His three web addresses, exactly as he gave them, 2026-09-28:
// REM    "fluharty.me fluharty.me/support/librarycommander fluharty.me/privacy"
// REM  Shown in About and in the Help menu. Defined ONCE here so the two can never disagree.
// REM  · Privacy is his SHARED page — it covers all his apps and names none (his rule).
// REM  · ⚠️ The support page did not exist yet on 2026-09-28 (checked: "not found"). It is his
// REM    address, so it is used as given; the page itself is to be made on his site.
//

import Foundation

enum Links {
    static let portfolio = URL(string: "https://fluharty.me")!
    static let support = URL(string: "https://fluharty.me/support/librarycommander")!
    static let privacy = URL(string: "https://fluharty.me/privacy")!
}
