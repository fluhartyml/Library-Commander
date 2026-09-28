//
//  TransferEngineTests.swift
//  Library CommanderTests
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM  Build 57: copy and move with the clash question. A scripted list of answers stands in
// REM  for him at the sheet, so every choice is proven on real files. His rulings under test:
// REM  every clash asks · folders merge or replace · Keep Both = "Name 2" · "do the same" is
// REM  per kind · Replace never leaves him with neither.
//

import Foundation
import Testing
@testable import Library_Commander

/// Hands out scripted answers and records every question asked.
nonisolated private final class ScriptedAsker: @unchecked Sendable {
    private var answers: [ClashAnswer]
    private(set) var asked: [Clash] = []
    init(_ answers: [ClashAnswer]) { self.answers = answers }
    func ask(_ clash: Clash) -> ClashAnswer {
        asked.append(clash)
        return answers.isEmpty ? ClashAnswer(choice: .stop, applyToAll: false) : answers.removeFirst()
    }
}

@MainActor
struct TransferEngineTests {
    private let fm = FileManager.default

    private func base() throws -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent("TransferEngineTests-\(UUID().uuidString)")
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, _ url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    private func run(_ item: URL, into folder: URL, move: Bool,
                     _ answers: [ClashAnswer]) async throws -> (TransferSummary, ScriptedAsker) {
        let asker = ScriptedAsker(answers)
        let engine = TransferEngine(move: move, ask: { asker.ask($0) })
        let summary = try await engine.run(item, into: folder)
        for trashed in summary.trashed { try? fm.removeItem(at: trashed) }     // tidy his Trash
        return (summary, asker)
    }

    private func a(_ choice: ClashChoice, all: Bool = false) -> ClashAnswer {
        ClashAnswer(choice: choice, applyToAll: all)
    }

    @Test func noClashAsksNothing() async throws {
        let root = try base()
        try write("A", root.appendingPathComponent("src/a.mp4"))
        let (s, asker) = try await run(root.appendingPathComponent("src/a.mp4"), into: root, move: false, [])
        #expect(asker.asked.isEmpty)
        #expect(s.placed == 1)
    }

    @Test func identicalFilesStillAsk() async throws {
        // REM  His ruling: "i think it should have already asked".
        let root = try base()
        try write("same", root.appendingPathComponent("src/a.mp4"))
        try write("same", root.appendingPathComponent("dst/a.mp4"))
        let (s, asker) = try await run(root.appendingPathComponent("src/a.mp4"),
                                       into: root.appendingPathComponent("dst"), move: false, [a(.skip)])
        #expect(asker.asked.first?.kind == .identicalFiles)
        #expect(s.skipped == 1)
    }

    @Test func replaceSwapsTheFileAndTheOldOneLeaves() async throws {
        let root = try base()
        try write("new", root.appendingPathComponent("src/a.mp4"))
        try write("old!", root.appendingPathComponent("dst/a.mp4"))
        let (s, asker) = try await run(root.appendingPathComponent("src/a.mp4"),
                                       into: root.appendingPathComponent("dst"), move: true, [a(.replace)])
        #expect(asker.asked.first?.kind == .differingFiles)
        #expect(read(root.appendingPathComponent("dst/a.mp4")) == "new")
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("src/a.mp4").path))   // it was a move
        #expect(s.replaced == 1)
        // REM  No hidden temporary file is left behind.
        #expect(try fm.contentsOfDirectory(atPath: root.appendingPathComponent("dst").path) == ["a.mp4"])
    }

    @Test func theMacDiskSendsTheOldOneToTheTrash() async throws {
        // REM  His rule: internal disk → Trash; external → for good. The test folder is on the Mac.
        let root = try base()
        try write("new", root.appendingPathComponent("src/a.mp4"))
        try write("old!", root.appendingPathComponent("dst/a.mp4"))
        let asker = ScriptedAsker([a(.replace)])
        let summary = try await TransferEngine(move: false, ask: { asker.ask($0) })
            .run(root.appendingPathComponent("src/a.mp4"), into: root.appendingPathComponent("dst"))
        #expect(asker.asked.first?.replaceIsPermanent == false)
        #expect(summary.trashed.count == 1)
        for t in summary.trashed {
            #expect(read(t) == "old!")                                   // the old one, safe in the Trash
            try? fm.removeItem(at: t)
        }
    }

    @Test func keepBothUsesMacNumbering() async throws {
        let root = try base()
        try write("new", root.appendingPathComponent("src/Casablanca.mp4"))
        try write("old", root.appendingPathComponent("dst/Casablanca.mp4"))
        try write("older", root.appendingPathComponent("dst/Casablanca 2.mp4"))
        let (s, asker) = try await run(root.appendingPathComponent("src/Casablanca.mp4"),
                                       into: root.appendingPathComponent("dst"), move: false, [a(.keepBoth)])
        #expect(asker.asked.first?.keepBothName == "Casablanca 3.mp4")
        #expect(read(root.appendingPathComponent("dst/Casablanca 3.mp4")) == "new")
        #expect(s.keptBoth == 1)
    }

    @Test func replaceIfNewerKeepsTheNewerOne() async throws {
        let root = try base()
        let src = root.appendingPathComponent("src/a.mp4"), dst = root.appendingPathComponent("dst/a.mp4")
        try write("incoming", src)
        try write("already", dst)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: src.path)
        let (s, _) = try await run(src, into: root.appendingPathComponent("dst"), move: false, [a(.replaceIfNewer)])
        #expect(read(dst) == "already")                                  // incoming was older
        #expect(s.skipped == 1)
    }

    @Test func foldersMergeAndInsideClashesAskTheirOwnQuestion() async throws {
        let root = try base()
        try write("1", root.appendingPathComponent("src/Movies/one.mp4"))
        try write("2", root.appendingPathComponent("src/Movies/two.mp4"))
        try write("X", root.appendingPathComponent("dst/Movies/two.mp4"))
        try write("3", root.appendingPathComponent("dst/Movies/three.mp4"))
        let (s, asker) = try await run(root.appendingPathComponent("src/Movies"),
                                       into: root.appendingPathComponent("dst"), move: true,
                                       [a(.merge), a(.skip)])
        #expect(asker.asked.map(\.kind) == [.folders, .differingFiles])
        #expect(asker.asked.first?.moreMayFollow == true)
        let merged = Set(try fm.contentsOfDirectory(atPath: root.appendingPathComponent("dst/Movies").path))
        #expect(merged == ["one.mp4", "two.mp4", "three.mp4"])
        #expect(read(root.appendingPathComponent("dst/Movies/two.mp4")) == "X")          // skipped, untouched
        // The skipped file is still in the source, so the source folder stays.
        #expect(fm.fileExists(atPath: root.appendingPathComponent("src/Movies/two.mp4").path))
        #expect(s.placed == 1 && s.skipped == 1)
    }

    @Test func doTheSameIsRememberedPerKind() async throws {
        let root = try base()
        try write("a", root.appendingPathComponent("src/M/a.mp4"))
        try write("b", root.appendingPathComponent("src/M/b.mp4"))
        try write("c", root.appendingPathComponent("src/M/c.mp4"))
        try write("A!", root.appendingPathComponent("dst/M/a.mp4"))       // differs
        try write("B!", root.appendingPathComponent("dst/M/b.mp4"))       // differs
        try write("c", root.appendingPathComponent("dst/M/c.mp4"))        // identical
        let (_, asker) = try await run(root.appendingPathComponent("src/M"),
                                       into: root.appendingPathComponent("dst"), move: false,
                                       [a(.merge), a(.keepBoth, all: true), a(.skip)])
        // Merge → a (differs, keep both for ALL differing) → b answered silently → c (identical) asks.
        #expect(asker.asked.map(\.kind) == [.folders, .differingFiles, .identicalFiles])
        #expect(fm.fileExists(atPath: root.appendingPathComponent("dst/M/b 2.mp4").path))
    }

    @Test func stopLeavesWhatIsDoneAndStopsTheRest() async throws {
        let root = try base()
        try write("1", root.appendingPathComponent("src/M/1.mp4"))
        try write("2", root.appendingPathComponent("src/M/2.mp4"))
        try write("3", root.appendingPathComponent("src/M/3.mp4"))
        try write("X", root.appendingPathComponent("dst/M/2.mp4"))
        let (s, _) = try await run(root.appendingPathComponent("src/M"),
                                   into: root.appendingPathComponent("dst"), move: false,
                                   [a(.merge), a(.stop)])
        #expect(s.stopped)
        #expect(fm.fileExists(atPath: root.appendingPathComponent("dst/M/1.mp4").path))    // done before Stop
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("dst/M/3.mp4").path))   // never reached
    }

    @Test func removeFromSourceOnlyForIdenticalMoves() async throws {
        let root = try base()
        try write("same", root.appendingPathComponent("src/a.mp4"))
        try write("same", root.appendingPathComponent("dst/a.mp4"))
        let (s, _) = try await run(root.appendingPathComponent("src/a.mp4"),
                                   into: root.appendingPathComponent("dst"), move: true, [a(.removeFromSource)])
        #expect(s.removedFromSource == 1)
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("src/a.mp4").path))
        #expect(read(root.appendingPathComponent("dst/a.mp4")) == "same")
    }

    @Test func aPackageIsNeverMergedInside() async throws {
        let root = try base()
        try write("x", root.appendingPathComponent("src/Photos.photoslibrary/db"))
        try write("y", root.appendingPathComponent("dst/Photos.photoslibrary/db"))
        let (_, asker) = try await run(root.appendingPathComponent("src/Photos.photoslibrary"),
                                       into: root.appendingPathComponent("dst"), move: false, [a(.skip)])
        #expect(asker.asked.first?.kind == .mismatch)
    }
}
