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
import AppKit

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

    // MARK: - Source and destination

    // REM  HIS RULE, 2026-09-28 — never think in LEFT and RIGHT: the ACTIVE pane is the SOURCE, the
    // REM  other pane is the DESTINATION, and either pane can be either one (Tab swaps them).
    // REM  The arrow that points AT the destination will copy or move; the arrow pointing back at
    // REM  the source will undo. So the arrow shown here flips with the active pane.

    var destinationSide: PaneSide { activeSide.other }
    var destinationPane: PaneModel { pane(destinationSide) }

    /// The arrow that points from the source at the destination.
    var arrowTowardDestination: String { destinationSide == .right ? "→" : "←" }

    /// The status bar's standing line: where a copy would land right now.
    /// REM  Always visible (not a message that the next message replaces), because the whole
    /// REM  point is that he can check the target at any moment before acting.
    var copyTargetLine: String {
        guard let target = destinationPane.copyTarget else {
            return "\(arrowTowardDestination) No target yet — open a folder in the other pane"
        }
        let name = FileManager.default.displayName(atPath: target.url.path)
        return "\(arrowTowardDestination) Target: \(name)"
    }

    // MARK: - The quick-access bar: ⌘1–⌘9 (build 56)

    // REM  HIS DESIGN, 2026-09-28: "the command 1 through what ever it was for midnight commander
    // REM  quick action command keys at the bottom of the app." Midnight Commander's F-key row,
    // REM  on ⌘ + the number. He approved this set: ⌘1 Help · ⌘3 View · ⌘4 Edit · ⌘5 Copy ·
    // REM  ⌘6 Move · ⌘7 New Folder · ⌘8 Delete · ⌘9 Rename.
    // REM  ⌘2 ("Menu" in Midnight Commander) is NOT here yet: what it should open is his call, and
    // REM  his rule is no dead buttons. ⌘0 is free — ⌘Q already quits (his point).
    // REM  Every command acts on the HIGHLIGHTED row of the ACTIVE pane (the source). Copy and
    // REM  Move go to the TARGET shown in the status bar (build 55).

    struct QuickKey: Identifiable {
        let number: Int
        let title: String
        var id: Int { number }
    }

    static let quickKeys: [QuickKey] = [
        QuickKey(number: 1, title: "Help"),
        QuickKey(number: 3, title: "View"),
        QuickKey(number: 4, title: "Edit"),
        QuickKey(number: 5, title: "Copy"),
        QuickKey(number: 6, title: "Move"),
        QuickKey(number: 7, title: "New Folder"),
        QuickKey(number: 8, title: "Delete"),
        QuickKey(number: 9, title: "Rename"),
    ]

    /// ⌘ + a number, from the keyboard or a click on the bar. False = no such key.
    @discardableResult
    func runQuickKey(_ number: Int) -> Bool {
        switch number {
        case 1: help()
        case 3: view()
        case 4: edit()
        case 5: transfer(move: false)
        case 6: transfer(move: true)
        case 7: newFolder()
        case 8: deleteHighlighted()
        case 9: rename()
        default: return false
        }
        return true
    }

    /// Set to show a file in Quick Look (⌘3). The window watches it.
    var quickLookURL: URL?

    /// What is running right now — a copy or move of a big file takes time. nil = nothing.
    private(set) var busy: String?
    /// Bytes landed so far and the total, while a single FILE is copying or moving.
    /// REM  His rule: progress must prove it is alive — a number that climbs, not just a spinner.
    private(set) var busyBytes: (done: Int64, total: Int64)?
    @ObservationIgnored private var progressTimer: Timer?

    /// ⌘1 — his support page (the same address as the Help menu).
    func help() {
        NSWorkspace.shared.open(Links.support)
        report("Opened Library Commander Support in your browser.")
    }

    /// ⌘3 — Quick Look the highlighted file, the way the space bar does in Finder.
    func view() {
        guard let item = highlightedItem(for: "view") else { return }
        quickLookURL = item.url
    }

    /// ⌘4 — open the highlighted file in the app macOS uses for it.
    func edit() {
        guard let item = highlightedItem(for: "edit") else { return }
        if item.isFolder && !item.isPackage {
            report("⌘4 opens files — “\(item.name)” is a folder. Press Return to open it here.", problem: true)
            return
        }
        if NSWorkspace.shared.open(item.url) {
            report("Opened “\(item.name)” in its app.")
        } else {
            report("macOS has no app to open “\(item.name)”.", problem: true)
        }
    }

    /// ⌘7 — the New Folder sheet, in the active pane.
    func newFolder() {
        guard activePane.currentURL != nil, !activePane.showingDrives else {
            report("Open a folder first — a new folder is made inside it.", problem: true)
            return
        }
        activePane.askingNewFolderName = true
    }

    /// ⌘9 — the Rename sheet for the highlighted row.
    func rename() {
        guard notBusy(), highlightedItem(for: "rename") != nil else { return }
        activePane.askingRename = true
    }

    /// Called by the Rename sheet. True = done (the sheet closes).
    func finishRename(to name: String) -> Bool {
        let pane = activePane
        guard let item = pane.selectedEntry else { return true }
        do {
            let renamed = try FileOps.rename(item.url, to: name)
            pane.reload(highlighting: renamed.path)
            destinationPane.reload()
            report("Renamed “\(item.name)” to “\(renamed.lastPathComponent)”.")
            return true
        } catch {
            report(Self.explain(error, name: item.name, verb: "rename"), problem: true)
            return false
        }
    }

    /// Where the last deleted item went in the Trash. REM  Kept so it can be found again —
    /// the tests use it to take their own files back out of his Trash.
    private(set) var lastTrashed: URL?

    /// ⌘8 — the highlighted row goes to the Trash, and the next row lights up.
    func deleteHighlighted() {
        guard notBusy(), let item = highlightedItem(for: "delete") else { return }
        let pane = activePane
        let index = pane.selectedIndex
        do {
            lastTrashed = try FileOps.trash(item.url)
            pane.reloadAfterRemoving(rowAt: index)
            destinationPane.reload()
            report("Moved “\(item.name)” to the Trash.")
        } catch {
            report("“\(item.name)” was NOT deleted — \(Self.explain(error, name: item.name, verb: "delete"))", problem: true)
        }
    }

    /// ⌘5 copy / ⌘6 move — the highlighted row of the source into the target.
    /// REM  The work runs off the main thread, so the window stays live during a long copy.
    func transfer(move: Bool) {
        let verb = move ? "move" : "copy"
        guard notBusy(), let item = highlightedItem(for: verb) else { return }
        guard let target = destinationPane.copyTarget else {
            report("Nowhere to \(verb) to — open a folder in the other pane first.", problem: true)
            return
        }
        let source = activePane
        let index = source.selectedIndex
        let targetName = FileManager.default.displayName(atPath: target.url.path)
        let landing = FileOps.destination(of: item.url, in: target.url)

        busy = "\(move ? "Moving" : "Copying") “\(item.name)” to \(targetName)…"
        busyBytes = nil
        report(busy!)
        startProgress(item: item, landing: landing)

        let from = item.url, into = target.url
        Task.detached(priority: .userInitiated) {
            let outcome: Result<URL, Error>
            do {
                outcome = .success(move ? try FileOps.move(from, into: into) : try FileOps.copy(from, into: into))
            } catch {
                outcome = .failure(error)
            }
            await MainActor.run {
                self.stopProgress()
                switch outcome {
                case .success:
                    if move { source.reloadAfterRemoving(rowAt: index) } else { source.reload() }
                    self.destinationPane.reload()
                    self.report("\(move ? "Moved" : "Copied") “\(item.name)” to \(targetName).")
                case .failure(let error):
                    self.report(Self.explain(error, name: item.name, verb: verb, targetName: targetName), problem: true)
                }
            }
        }
    }

    // MARK: - Helpers for the commands

    /// The highlighted row of the active pane, or nil with a status message saying why not.
    private func highlightedItem(for verb: String) -> FileEntry? {
        let pane = activePane
        if pane.showingDrives {
            report("Open a drive first — you can't \(verb) a whole drive from here.", problem: true)
            return nil
        }
        guard let item = pane.selectedEntry else {
            report("Highlight something to \(verb) first.", problem: true)
            return nil
        }
        return item
    }

    /// One long job at a time, so two copies never fight over the same drive.
    private func notBusy() -> Bool {
        guard let busy else { return true }
        report("Still working: \(busy) — wait for it to finish.", problem: true)
        return false
    }

    /// Once a second, how many bytes of a FILE have landed. Folders show the running message only —
    /// adding up a whole folder every second would slow the copy it is measuring.
    private func startProgress(item: FileEntry, landing: URL) {
        guard !item.isFolder else { return }
        let total = item.size
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            let done = Int64((try? landing.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            MainActor.assumeIsolated { self?.busyBytes = (done, total) }
        }
    }

    private func stopProgress() {
        progressTimer?.invalidate()
        progressTimer = nil
        busy = nil
        busyBytes = nil
    }

    /// A failure, in words for the status bar.
    static func explain(_ error: Error, name: String, verb: String, targetName: String? = nil) -> String {
        guard let failure = error as? FileOps.Failure else { return error.localizedDescription }
        let there = targetName.map { " in \($0)" } ?? ""
        switch failure {
        case .alreadyThere(let identical):
            return identical
                ? "“\(name)” is already\(there), identical — nothing was changed."
                : "A different “\(name)” is already\(there) — nothing was changed or overwritten."
        case .intoItself:   return "Can't \(verb) “\(name)” into itself."
        case .sameFolder:   return "“\(name)” is already in \(targetName ?? "that folder") — nothing to \(verb)."
        case .verifyFailed: return "The copy of “\(name)” did not check out, so the original was kept where it was."
        case .emptyName:    return "A name can't be empty."
        case .badName:      return "A name can't contain “/” or “:”."
        case .system(let why): return why
        }
    }

    /// Tab — the other pane becomes active.
    func switchPanes() {
        activeSide = activeSide.other
    }
}
