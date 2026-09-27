//
//  SandboxAccess.swift
//  Library Commander
//
//  The App Sandbox stays ON — his ruling, 2026-09-27: "im not turning off the sandbox
//  untill we need to". So a drive or folder outside the app's container has to be granted
//  by him, once, through an Open panel. This file asks, remembers the grant as a
//  security-scoped bookmark, and re-opens every saved grant at launch.
//
//  Why it exists: the copied Commander code fell back to the home folder when a folder
//  could not be read. Inside the sandbox that is the container, so picking a drive
//  bounced straight back — "the drives are not changing" / "it never asked permission".
//

import AppKit
import Foundation

@MainActor
enum SandboxAccess {
    private static let key = "sandboxGrants"   // [path: bookmark data]
    private static var restored = false
    private static var asking = false

    /// Re-open every folder he has granted before. Safe to call more than once.
    static func restoreSavedGrants() {
        guard !restored else { return }
        restored = true
        // Build 20: grants saved while user-selected files were READ-ONLY (builds 7–18) may
        // reopen read-only. He switched the target to Read/Write; drop those once so each
        // drive is asked for again and saved with write access.
        if UserDefaults.standard.string(forKey: "sandboxGrantsMode") != "readwrite" {
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.set("readwrite", forKey: "sandboxGrantsMode")
        }
        var grants = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
        for (path, data) in grants {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                     relativeTo: nil, bookmarkDataIsStale: &stale),
                  url.startAccessingSecurityScopedResource() else {
                NSLog("Library Commander: saved grant for %@ could not be reopened — dropped", path)
                grants[path] = nil
                continue
            }
            if stale, let fresh = bookmark(for: url) { grants[path] = fresh }
        }
        UserDefaults.standard.set(grants, forKey: key)
    }

    /// Ask him to grant `path`. Returns the folder he actually granted (he may choose a
    /// different one in the panel), or nil if he cancelled.
    static func requestAccess(to path: String) -> URL? {
        guard !asking else { return nil }
        asking = true
        defer { asking = false }

        let target = URL(fileURLWithPath: path)
        let name = FileManager.default.displayName(atPath: path)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = target
        panel.prompt = "Grant Access"
        panel.message = "Library Commander needs your permission to open “\(name)”. Select it and click Grant Access. You only have to do this once."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        _ = url.startAccessingSecurityScopedResource()
        if let data = bookmark(for: url) {
            var grants = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
            grants[url.path] = data
            UserDefaults.standard.set(grants, forKey: key)
        } else {
            NSLog("Library Commander: granted %@ for this run, but the grant could not be saved", url.path)
        }
        return url
    }

    /// True when `error` is the sandbox (or file permissions) refusing a read.
    static func isPermissionDenied(_ error: Error) -> Bool {
        let e = error as NSError
        if e.domain == NSCocoaErrorDomain && e.code == NSFileReadNoPermissionError { return true }
        if let u = e.userInfo[NSUnderlyingErrorKey] as? NSError, u.domain == NSPOSIXErrorDomain,
           u.code == Int(EPERM) || u.code == Int(EACCES) { return true }
        return false
    }

    private static func bookmark(for url: URL) -> Data? {
        // Read/Write since build 19; the read-only form stays as a fallback.
        (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
        ?? (try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                  includingResourceValuesForKeys: nil, relativeTo: nil))
    }
}
