//
//  CommanderModel.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  The two panes and which one is active. The active pane is the one the keys drive
// REM  and (later) the SOURCE of a copy or move; the other pane is the target.
// REM  Which pane is active is saved too — everything persists (StateStore.swift).
//

import Foundation
import Observation

enum PaneSide {
    case left, right
    var other: PaneSide { self == .left ? .right : .left }
}

@Observable
final class CommanderModel {
    let left: PaneModel
    let right: PaneModel
    @ObservationIgnored private let store: StateStore

    var activeSide: PaneSide {
        didSet { store.activeSideIsRight = activeSide == .right }
    }

    init(store: StateStore = .shared) {
        self.store = store
        left = PaneModel(side: "left", store: store)
        right = PaneModel(side: "right", store: store)
        activeSide = store.activeSideIsRight ? .right : .left
    }

    var activePane: PaneModel { pane(activeSide) }

    func pane(_ side: PaneSide) -> PaneModel {
        side == .left ? left : right
    }

    /// At launch, and whenever a drive mounts: each pane back to its saved place.
    func restore() {
        left.restore()
        right.restore()
    }

    /// Tab — the other pane becomes active.
    func switchPanes() {
        activeSide = activeSide.other
    }
}
