//
//  ITunesLookupSheet.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  The iTunes button's sheet (step 2, 2026-09-30). It looks the files up ONE AT A TIME, 3 s
// REM  apart (Apple's pace), and lists each as it lands: old name → new name, ticked; or why it
// REM  was left alone. NOTHING IS RENAMED UNTIL HE PRESSES "Rename". The old app renamed on the
// REM  spot (autoRename on by default) and one of its paths deleted whatever already had the new
// REM  name. Here every rename goes through FileOps.rename, which never overwrites: a name already
// REM  taken is reported and the file is left as it was.
// REM  Which files: the highlighted songs and music videos; with nothing highlighted, every song
// REM  and music video in the folder.
//

import SwiftUI

@MainActor @Observable
final class ITunesLookupRun {
    struct Item: Identifiable {
        let url: URL
        let isVideo: Bool
        var id: String { url.path }
        var outcome: ITunesLookup.Outcome?
        var newName: String?
        var ticked = false
        /// After Rename: what happened, in words. Nil = not renamed yet.
        var result: String?
        /// Which lookup gave the outcome — Shazam words its failures differently.
        var bySource: Source = .iTunes
    }

    /// iTunes searches by name; Shazam listens (step 3 — the last resort).
    enum Source { case iTunes, shazam }

    /// What the sheet was opened for.
    let source: Source
    private(set) var items: [Item]
    private(set) var running = false
    /// Files looked up so far in the current pass, and how many that pass holds.
    private(set) var done = 0
    private(set) var passTotal = 0
    private var task: Task<Void, Never>?

    init(files: [FileEntry], source: Source = .iTunes) {
        self.source = source
        items = files.map { Item(url: $0.url, isVideo: $0.kind == .video) }
    }

    var tickedCount: Int { items.filter { $0.ticked && $0.result == nil }.count }

    /// Files the lookups left alone, not yet tried with Shazam — the last resort's list.
    var leftAlone: [Int] {
        items.indices.filter { i in
            guard items[i].result == nil, items[i].bySource == .iTunes, let o = items[i].outcome else { return false }
            if case .found = o { return false }
            return true
        }
    }

    func start() {
        guard task == nil else { return }
        run(Array(items.indices), with: source)
    }

    /// Step 3's hand-off: Shazam the files iTunes could not name.
    func shazamLeftAlone() {
        guard !running else { return }
        run(leftAlone, with: .shazam)
    }

    private func run(_ indices: [Int], with lookup: Source) {
        running = true
        done = 0
        passTotal = indices.count
        let format = NameFormat.load()
        task = Task {
            for (n, i) in indices.enumerated() {
                if Task.isCancelled { break }
                if n > 0 { try? await Task.sleep(for: ITunesLookup.spacing) }
                if Task.isCancelled { break }
                let outcome = lookup == .shazam
                    ? await ShazamLookup.lookup(items[i].url)
                    : await ITunesLookup.lookup(items[i].url, isVideo: items[i].isVideo)
                items[i].outcome = outcome
                items[i].bySource = lookup
                if case .found(let hit) = outcome,
                   let name = NameFormat.fileName(format, values: hit.nameValues,
                                                  ext: items[i].url.pathExtension) {
                    items[i].newName = name
                    // REM  Already named right → nothing to tick.
                    items[i].ticked = name != items[i].url.lastPathComponent
                }
                done = n + 1
            }
            running = false
        }
    }

    func stop() {
        task?.cancel()
        running = false
    }

    /// Renames every ticked file. Returns (renamed, left alone).
    func renameTicked() -> (Int, Int) {
        var renamed = 0, refused = 0
        for i in items.indices where items[i].ticked && items[i].result == nil {
            guard let name = items[i].newName else { continue }
            do {
                try FileOps.rename(items[i].url, to: name)
                items[i].result = "Renamed."
                renamed += 1
            } catch FileOps.Failure.alreadyThere(let identical) {
                items[i].result = identical ? "Left alone — an identical file already has that name."
                                            : "Left alone — a different file already has that name."
                refused += 1
            } catch {
                items[i].result = "Left alone — \(error)"
                refused += 1
            }
            items[i].ticked = false
        }
        return (renamed, refused)
    }
}

struct ITunesLookupSheet: View {
    @Binding var isPresented: Bool
    let run: ITunesLookupRun
    /// Sends a message to the status bar.
    let report: (String, Bool) -> Void
    /// Called after renaming, so the pane shows the new names.
    let reload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(run.source == .shazam ? "Shazam" : "iTunes Lookup").bold()
            Text(progressLine).foregroundStyle(.secondary)

            List {
                ForEach(run.items) { item in row(item) }
            }
            .frame(minHeight: 320)

            HStack {
                Text("Nothing is renamed until you press Rename. A name already taken is never overwritten.")
                    .foregroundStyle(.secondary)
                Spacer()
                if run.running {
                    Button("Stop") { run.stop() }
                } else if run.source == .iTunes, !run.leftAlone.isEmpty {
                    // REM  Step 3 — the last resort: listen to what the name could not identify.
                    Button("Shazam the \(run.leftAlone.count) left alone") { run.shazamLeftAlone() }
                        .help("Shazam listens to each one's sound — songs and music videos — and names it from what it hears.")
                }
                Button("Close") {
                    run.stop()
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                Button("Rename \(run.tickedCount)") {
                    let (renamed, refused) = run.renameTicked()
                    reload()
                    report("Renamed \(renamed)" + (refused > 0 ? ", left \(refused) alone — the list says why." : "."),
                           refused > 0)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(run.tickedCount == 0)
            }
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 520)
        .onAppear { run.start() }
        .onDisappear { run.stop() }
    }

    private var progressLine: String {
        let total = run.passTotal
        if run.running {
            let left = (total - run.done) * 3
            let time = left >= 120 ? "about \(left / 60) minutes left" : "about \(left) seconds left"
            return "Looking up \(run.done) of \(total) — \(time), 3 seconds apart."
        }
        return run.done == total ? "Looked up all \(total)." : "Stopped after \(run.done) of \(total)."
    }

    @ViewBuilder
    private func row(_ item: ITunesLookupRun.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if item.newName != nil, item.result == nil {
                Toggle("", isOn: Binding(get: { item.ticked }, set: { v in tick(item.id, v) }))
                    .labelsHidden()
            } else {
                Image(systemName: icon(item)).foregroundStyle(color(item))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(detail(item)).foregroundStyle(color(item)).lineLimit(2)
            }
        }
    }

    private func tick(_ id: String, _ on: Bool) {
        if let i = run.items.firstIndex(where: { $0.id == id }) { run.setTick(i, on) }
    }

    private func detail(_ item: ITunesLookupRun.Item) -> String {
        if let result = item.result { return result }
        switch item.outcome {
        case nil: return "Waiting…"
        case .found:
            guard let name = item.newName else { return "Found, but the name format gave nothing." }
            let by = item.bySource == .shazam ? " (Shazam)" : ""
            return name == item.url.lastPathComponent ? "Already named right\(by)." : "→ \(name)\(by)"
        case .notTrusted(let hit): return "Left alone — Apple's closest was “\(hit.artist) - \(hit.title)”, not a match."
        case .noResults:
            return item.bySource == .shazam ? "Left alone — Shazam did not recognise it."
                                            : "Left alone — Apple found nothing."
        case .noSearchTerms: return "Left alone — the name says nothing to search for."
        case .failed(let why): return "Left alone — \(why)"
        }
    }

    private func icon(_ item: ITunesLookupRun.Item) -> String {
        if item.result == "Renamed." { return "checkmark.circle.fill" }
        if item.outcome == nil { return "clock" }
        if case .found = item.outcome, item.result == nil { return "checkmark.circle" }
        return "minus.circle"
    }

    private func color(_ item: ITunesLookupRun.Item) -> Color {
        if item.result == "Renamed." { return .green }
        if case .found = item.outcome, item.result == nil { return .primary }
        return .secondary
    }
}

extension ITunesLookupRun {
    func setTick(_ index: Int, _ on: Bool) { items[index].ticked = on }
}

extension ITunesLookupRun: Identifiable {}
