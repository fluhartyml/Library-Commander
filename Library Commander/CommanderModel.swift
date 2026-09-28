//
//  CommanderModel.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  The two panes and which one is active. The active pane is the one the keys drive
// REM  and (later) the SOURCE of a copy or move; the other pane is the target.
//

import Foundation
import Observation

enum PaneSide {
    case left, right
    var other: PaneSide { self == .left ? .right : .left }
}

@Observable
final class CommanderModel {
    let left = PaneModel()
    let right = PaneModel()
    var activeSide: PaneSide = .left

    var activePane: PaneModel { pane(activeSide) }

    func pane(_ side: PaneSide) -> PaneModel {
        side == .left ? left : right
    }

    /// Tab — the other pane becomes active.
    func switchPanes() {
        activeSide = activeSide.other
    }
}
