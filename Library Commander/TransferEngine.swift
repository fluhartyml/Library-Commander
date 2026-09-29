//
//  TransferEngine.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  COPY AND MOVE, WITH THE CLASH QUESTION (build 57). His design, 2026-09-28:
// REM    "if a namme is already taken, including a folder with identical names, i think it should
// REM     pop up like finder does folder should be replace or merge and duplicate file names
// REM     should be replace or keep both and apply to all checkboxes"
// REM  and the old app's sheet, which he remembered: two cards side by side with a thumbnail,
// REM  newer/older and larger/smaller marked, and a "do the same for the others" checkbox.
// REM
// REM  HIS RULINGS, kept here so a later change cannot quietly undo them:
// REM   • EVERY name clash asks — identical or not. ("i think it should have already asked")
// REM     The sheet SAYS whether they are identical; it does not decide for him.
// REM   • Replace on an EXTERNAL or network drive deletes the old one FOR GOOD; on the Mac's own
// REM     disk it goes to the Trash. ("if its external it should me for good")
// REM   • Keep Both = the standard Mac numbering: "Name 2.mp4", then "Name 3.mp4".
// REM   • "Do the same for the others" keeps SEPARATE answers for identical files, files that
// REM     differ, folders, and file-vs-folder — so one answer never covers a different case.
// REM
// REM  SAFETY, unchanged from build 56: a Replace COPIES the incoming item in under a hidden
// REM  temporary name first, checks its size, and only then removes the old one — so a failure
// REM  never leaves him with neither. A move removes the original only after its copy checks out.
// REM  Packages (.photoslibrary, .app) are one item: never merged inside.
//

import Foundation

/// What the sheet shows about one side of a clash.
nonisolated struct FileFacts: Sendable, Equatable {
    let url: URL
    let name: String
    /// Bytes. 0 for a folder — adding up a folder costs a full read of it.
    let size: Int64
    let modified: Date?
    let isFolder: Bool
    let isPackage: Bool

    /// A folder that can be merged into: a real folder, not a package.
    var isMergeableFolder: Bool { isFolder && !isPackage }

    static func of(_ url: URL) -> FileFacts {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey]
        let v = try? url.resourceValues(forKeys: keys)
        let isFolder = v?.isDirectory ?? false
        return FileFacts(url: url, name: url.lastPathComponent,
                         size: isFolder ? 0 : Int64(v?.fileSize ?? 0),
                         modified: v?.contentModificationDate,
                         isFolder: isFolder, isPackage: v?.isPackage ?? false)
    }
}

/// The four kinds of clash. "Do the same for the others" is remembered per kind.
nonisolated enum ClashKind: Sendable, Hashable {
    /// Two files, same bytes.
    case identicalFiles
    /// Two files that differ.
    case differingFiles
    /// Two real folders — Merge is offered.
    case folders
    /// A file against a folder, or a package on either side — replace, skip or keep both only.
    case mismatch
}

nonisolated enum ClashChoice: Sendable, Equatable {
    case replace, replaceIfNewer, replaceIfSizeDiffers, skip, keepBoth, removeFromSource, merge, stop
}

nonisolated struct ClashAnswer: Sendable, Equatable {
    let choice: ClashChoice
    let applyToAll: Bool
}

/// One question for the sheet.
nonisolated struct Clash: Sendable, Identifiable, Equatable {
    let id = UUID()
    let incoming: FileFacts
    let existing: FileFacts
    let kind: ClashKind
    let isMove: Bool
    /// True when more clashes can still come in this job — only then is "do the same" shown.
    let moreMayFollow: Bool
    /// True when Replace would delete the one already here FOR GOOD (external/network drive).
    let replaceIsPermanent: Bool
    /// What Keep Both would call the incoming one, e.g. "Casablanca 2.mp4".
    let keepBothName: String
}

nonisolated struct TransferSummary: Sendable, Equatable {
    var placed = 0
    var replaced = 0
    var keptBoth = 0
    var skipped = 0
    var removedFromSource = 0
    var stopped = false
    /// Where replaced items went in the Trash. REM  The tests take their own files back out.
    var trashed: [URL] = []

    var total: Int { placed + replaced + keptBoth + removedFromSource }
}

nonisolated final class TransferEngine: @unchecked Sendable {
    // REM  @unchecked: one engine runs one job on one task; nothing else touches its state.
    let isMove: Bool
    private let ask: @Sendable (Clash) async -> ClashAnswer
    private let progress: @Sendable (Int) async -> Void
    private var remembered: [ClashKind: ClashChoice] = [:]
    private var summary = TransferSummary()
    private var moreMayFollow = false

    private struct Stopped: Error {}

    init(move: Bool,
         ask: @escaping @Sendable (Clash) async -> ClashAnswer,
         progress: @escaping @Sendable (Int) async -> Void = { _ in }) {
        self.isMove = move
        self.ask = ask
        self.progress = progress
    }

    /// Copy or move `item` into `folder`, asking about every clash.
    func run(_ item: URL, into folder: URL) async throws -> TransferSummary {
        try await run([item], into: folder)
    }

    /// Copy or move SEVERAL items (multi-select, build 59) as ONE job: one Stop ends all of it,
    /// and a "do the same" answer covers the rest of the job.
    func run(_ items: [URL], into folder: URL) async throws -> TransferSummary {
        // REM  Refuse the impossible for ANY item before touching the first — never half a job.
        for item in items { if let refusal = FileOps.refusal(item, into: folder) { throw refusal } }
        // REM  More clashes can follow when there are several items, or a folder may be merged.
        let clashes = items.filter { FileManager.default.fileExists(atPath: FileOps.destination(of: $0, in: folder).path) }
        moreMayFollow = clashes.count > 1
            || clashes.contains { FileFacts.of($0).isMergeableFolder }
        do {
            for item in items { try await process(item, into: folder) }
        } catch is Stopped {
            summary.stopped = true
        }
        return summary
    }

    // MARK: - One item

    private func process(_ src: URL, into folder: URL) async throws {
        let dst = FileOps.destination(of: src, in: folder)
        guard FileManager.default.fileExists(atPath: dst.path) else {
            try place(src, at: dst)
            summary.placed += 1
            await progress(summary.total)
            return
        }

        let incoming = FileFacts.of(src), existing = FileFacts.of(dst)
        let kind: ClashKind
        if incoming.isMergeableFolder && existing.isMergeableFolder {
            kind = .folders
        } else if !incoming.isFolder && !existing.isFolder {
            kind = FileOps.identical(src, dst) ? .identicalFiles : .differingFiles
        } else {
            kind = .mismatch
        }

        let choice: ClashChoice
        if let answer = remembered[kind] {
            choice = answer
        } else {
            let answer = await ask(Clash(incoming: incoming, existing: existing, kind: kind, isMove: isMove,
                                         moreMayFollow: moreMayFollow,
                                         replaceIsPermanent: !Self.isOnInternalDrive(dst),
                                         keepBothName: Self.keepBothURL(for: src.lastPathComponent, in: folder).lastPathComponent))
            if answer.applyToAll { remembered[kind] = answer.choice }
            choice = answer.choice
        }

        switch choice {
        case .stop:
            throw Stopped()
        case .skip:
            summary.skipped += 1
        case .merge where kind == .folders:
            // REM  MERGE: everything inside comes across; anything that clashes inside asks
            // REM  its own question. Hidden files come too — a merge must not leave them behind.
            let children = (try? FileManager.default.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)) ?? []
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                try await process(child, into: dst)
            }
            // A merged-away source folder is removed only if nothing was left behind in it.
            if isMove, ((try? FileManager.default.contentsOfDirectory(atPath: src.path)) ?? ["x"]).isEmpty {
                try? FileManager.default.removeItem(at: src)
            }
        case .merge:
            summary.skipped += 1                          // merge only means something for two folders
        case .replace:
            try replace(src, dst)
        case .replaceIfNewer:
            if (incoming.modified ?? .distantPast) > (existing.modified ?? .distantPast) {
                try replace(src, dst)
            } else {
                summary.skipped += 1
            }
        case .replaceIfSizeDiffers:
            if incoming.size != existing.size { try replace(src, dst) } else { summary.skipped += 1 }
        case .keepBoth:
            try place(src, at: Self.keepBothURL(for: src.lastPathComponent, in: folder))
            summary.keptBoth += 1
        case .removeFromSource:
            // REM  Only for a MOVE of two IDENTICAL files: the one already there IS the file, so
            // REM  the duplicate in the source is removed — after every byte is compared AGAIN.
            if isMove, FileOps.identical(src, dst) {
                try FileManager.default.removeItem(at: src)
                summary.removedFromSource += 1
            } else {
                summary.skipped += 1
            }
        }
        await progress(summary.total)
    }

    // MARK: - Writing

    /// Copy, or move, `src` to exactly `dst` (which is free).
    private func place(_ src: URL, at dst: URL) throws {
        let fm = FileManager.default
        do {
            if isMove && FileOps.sameVolume(src, dst.deletingLastPathComponent()) {
                try fm.moveItem(at: src, to: dst)          // same drive: a rename, instant
                return
            }
            try fm.copyItem(at: src, to: dst)
        } catch {
            throw FileOps.Failure.system(error.localizedDescription)
        }
        if isMove {
            // REM  Across drives: the original goes only after the copy checks out.
            guard FileOps.totalSize(of: src) == FileOps.totalSize(of: dst) else {
                try? fm.removeItem(at: dst)
                throw FileOps.Failure.verifyFailed
            }
            do { try fm.removeItem(at: src) }
            catch { throw FileOps.Failure.system("Copied, but the original could not be removed: \(error.localizedDescription)") }
        }
    }

    /// The incoming item takes the place of the one already there.
    /// REM  Order is the safety: copy in under a hidden name → check it → remove the old one →
    /// REM  rename into place → (a move) remove the original. A failure at any step leaves the
    /// REM  old one where it was.
    private func replace(_ src: URL, _ dst: URL) throws {
        let fm = FileManager.default
        let temp = dst.deletingLastPathComponent()
            .appendingPathComponent(".\(dst.lastPathComponent).lc-replacing-\(UUID().uuidString)")
        do { try fm.copyItem(at: src, to: temp) }
        catch { throw FileOps.Failure.system(error.localizedDescription) }
        guard FileOps.totalSize(of: src) == FileOps.totalSize(of: temp) else {
            try? fm.removeItem(at: temp)
            throw FileOps.Failure.verifyFailed
        }
        do {
            if let trashed = try Self.discard(dst) { summary.trashed.append(trashed) }
        } catch {
            try? fm.removeItem(at: temp)
            throw FileOps.Failure.system(error.localizedDescription)
        }
        do { try fm.moveItem(at: temp, to: dst) }
        catch { throw FileOps.Failure.system(error.localizedDescription) }
        if isMove { try? fm.removeItem(at: src) }
        summary.replaced += 1
    }

    // MARK: - Helpers

    /// His rule: on the Mac's own disk → the Trash (returned); on an external or network drive →
    /// deleted for good (nil).
    static func discard(_ url: URL) throws -> URL? {
        if isOnInternalDrive(url) {
            var inTrash: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &inTrash)
            return inTrash as URL?
        }
        try FileManager.default.removeItem(at: url)
        return nil
    }

    /// True for a drive inside the Mac. External and network drives are false.
    static func isOnInternalDrive(_ url: URL) -> Bool {
        let probe = FileManager.default.fileExists(atPath: url.path) ? url : url.deletingLastPathComponent()
        return (try? probe.resourceValues(forKeys: [.volumeIsInternalKey]))?.volumeIsInternal ?? false
    }

    /// The standard Mac numbering: "Name 2.mp4", "Name 3.mp4"… — the first one that is free.
    static func keepBothURL(for name: String, in folder: URL) -> URL {
        let ext = (name as NSString).pathExtension
        let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let url = folder.appendingPathComponent(candidate)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            n += 1
        }
    }
}
