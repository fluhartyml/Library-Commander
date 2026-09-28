//
//  FileOps.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  The file commands themselves — copy, move, delete, rename — as plain functions with no
// REM  views in them, so every rule here is tested (Library CommanderTests/FileOpsTests.swift).
// REM  The quick-access bar (⌘1–⌘9, build 56) and the keys call these through CommanderModel.
// REM
// REM  THE SAFETY RULES, all of them deliberate:
// REM   • NOTHING IS EVER OVERWRITTEN. If the name is already taken at the target, nothing
// REM     changes and the status bar says whether the two are identical or different.
// REM     (No " (2)" suffixes either — that is the bloat he named on 2026-08-25:
// REM     "making numbered suffixed files creates bloat." What to do with a clash is HIS call;
// REM     until he rules, a clash stops and reports.)
// REM   • A MOVE ACROSS DRIVES COPIES FIRST, CHECKS THE COPY'S SIZE, AND ONLY THEN REMOVES THE
// REM     ORIGINAL. If the check fails, the original stays and the partial copy is removed.
// REM   • DELETE GOES TO THE TRASH, never straight to gone — the Mac standard, and he can get it
// REM     back. If a drive has no Trash (some network drives), delete REFUSES; it never falls
// REM     back to a permanent delete on its own.
//

import Foundation

// REM  nonisolated: copies of big videos run OFF the main thread so the window never freezes
// REM  (the project's default is MainActor, which would pin every call here to the UI thread).
nonisolated enum FileOps {
    enum Failure: Error, Equatable {
        /// The name is already taken at the target. `identical` = same size and same bytes.
        case alreadyThere(identical: Bool)
        /// Copying a folder into itself, or into a folder inside itself.
        case intoItself
        /// The target is the folder it is already in.
        case sameFolder
        /// A move's copy did not come out the same size as the original — the original was kept.
        case verifyFailed
        case emptyName
        case badName
        /// Anything macOS itself refused, in macOS's own words.
        case system(String)
    }

    /// Where `item` would land inside `folder`.
    static func destination(of item: URL, in folder: URL) -> URL {
        folder.appendingPathComponent(item.lastPathComponent)
    }

    /// The checks that come BEFORE anything is written. REM  Run first so a refusal costs nothing.
    static func check(_ item: URL, into folder: URL) -> Failure? {
        let src = item.standardizedFileURL.resolvingSymlinksInPath().path
        let dst = folder.standardizedFileURL.resolvingSymlinksInPath().path
        if dst == src || dst.hasPrefix(src.hasSuffix("/") ? src : src + "/") { return .intoItself }
        if item.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path == dst {
            return .sameFolder
        }
        let target = destination(of: item, in: folder)
        if FileManager.default.fileExists(atPath: target.path) {
            return .alreadyThere(identical: identical(item, target))
        }
        return nil
    }

    /// Copy `item` into `folder`. Returns where it landed.
    @discardableResult
    static func copy(_ item: URL, into folder: URL) throws -> URL {
        if let failure = check(item, into: folder) { throw failure }
        let target = destination(of: item, in: folder)
        do {
            // REM  On the same APFS drive this is a clone — instant, and takes no extra space.
            try FileManager.default.copyItem(at: item, to: target)
        } catch {
            throw Failure.system(error.localizedDescription)
        }
        return target
    }

    /// Move `item` into `folder`. Returns where it landed.
    @discardableResult
    static func move(_ item: URL, into folder: URL) throws -> URL {
        if let failure = check(item, into: folder) { throw failure }
        let target = destination(of: item, in: folder)
        if sameVolume(item, folder) {
            // REM  Same drive: a rename, instant, and the original never exists twice.
            do { try FileManager.default.moveItem(at: item, to: target) }
            catch { throw Failure.system(error.localizedDescription) }
            return target
        }
        // REM  Different drives: copy, CHECK, then remove the original — in that order, so a
        // REM  failure at any step leaves the original where it was.
        do { try FileManager.default.copyItem(at: item, to: target) }
        catch { throw Failure.system(error.localizedDescription) }
        guard totalSize(of: item) == totalSize(of: target) else {
            try? FileManager.default.removeItem(at: target)     // the bad copy, never the original
            throw Failure.verifyFailed
        }
        do { try FileManager.default.removeItem(at: item) }
        catch { throw Failure.system("Copied, but the original could not be removed: \(error.localizedDescription)") }
        return target
    }

    /// Delete = move to the Trash. Returns where it went in the Trash.
    @discardableResult
    static func trash(_ item: URL) throws -> URL? {
        var inTrash: NSURL?
        do {
            try FileManager.default.trashItem(at: item, resultingItemURL: &inTrash)
        } catch {
            // REM  No silent fallback to a permanent delete — that is his decision, not the app's.
            throw Failure.system(error.localizedDescription)
        }
        return inTrash as URL?
    }

    /// Rename in place. Never overwrites. Returns the new URL.
    @discardableResult
    static func rename(_ item: URL, to typed: String) throws -> URL {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Failure.emptyName }
        guard !name.contains("/"), !name.contains(":") else { throw Failure.badName }
        let target = item.deletingLastPathComponent().appendingPathComponent(name)
        if name == item.lastPathComponent { return item }                 // nothing to do
        // REM  A change of CAPITALS only ("movie.mp4" → "Movie.mp4") is the same file on the Mac's
        // REM  disk, so fileExists would say "taken" — it is allowed.
        let caseOnly = name.lowercased() == item.lastPathComponent.lowercased()
        if !caseOnly, FileManager.default.fileExists(atPath: target.path) {
            throw Failure.alreadyThere(identical: identical(item, target))
        }
        do { try FileManager.default.moveItem(at: item, to: target) }
        catch { throw Failure.system(error.localizedDescription) }
        return target
    }

    // MARK: - Helpers

    static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let key: URLResourceKey = .volumeIdentifierKey
        guard let va = (try? a.resourceValues(forKeys: [key]))?.volumeIdentifier as? NSObject,
              let vb = (try? b.resourceValues(forKeys: [key]))?.volumeIdentifier as? NSObject else { return false }
        return va.isEqual(vb)
    }

    /// Bytes in a file, or in everything inside a folder.
    static func totalSize(of url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        var total: Int64 = 0
        let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey])
        while let child = walker?.nextObject() as? URL {
            let v = try? child.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if v?.isDirectory != true { total += Int64(v?.fileSize ?? 0) }
        }
        return total
    }

    /// Same size AND same bytes. REM  Two FILES only — folders are never called identical,
    /// because proving that means reading everything inside both.
    static func identical(_ a: URL, _ b: URL) -> Bool {
        var da: ObjCBool = false, db: ObjCBool = false
        let fm = FileManager.default
        guard fm.fileExists(atPath: a.path, isDirectory: &da), fm.fileExists(atPath: b.path, isDirectory: &db),
              !da.boolValue, !db.boolValue,
              totalSize(of: a) == totalSize(of: b) else { return false }
        return fm.contentsEqual(atPath: a.path, andPath: b.path)
    }
}
