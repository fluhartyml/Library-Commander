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
    // REM  Readable by Settings… (the list of granted drives and folders).
    @ObservationIgnored let store: StateStore

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

    // MARK: - Status bar

    // REM  The bottom bar talks to him: what just happened, or why something could not.
    // REM  A message stays until the next one, so he can read it at his own pace.
    // REM  Not saved — it describes this session, not a setting.
    private(set) var status = "Ready."
    private(set) var statusIsProblem = false

    func report(_ message: String, problem: Bool = false) {
        status = message
        statusIsProblem = problem
    }

    /// At launch, and whenever a drive mounts: each pane back to its saved place — and the
    /// status bar says what came back or what is still missing.
    func restore() {
        for pane in [left, right] {
            let wasMissing = pane.missingRootPath
            pane.restore()
            let name: (String) -> String = { FileManager.default.displayName(atPath: $0) }
            if let missing = pane.missingRootPath {
                report("“\(name(missing))” is not connected. The \(pane.side) pane will go back to it when it is.",
                       problem: true)
            } else if let was = wasMissing, pane.currentURL != nil {
                report("“\(name(was))” is back in the \(pane.side) pane.")
            }
        }
    }

    /// Tab — the other pane becomes active.
    func switchPanes() {
        activeSide = activeSide.other
    }
}
