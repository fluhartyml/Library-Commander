//
//  Drives.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  The drives the Mac can see right now — for the drive picker, and for the DRIVE LIST a pane
// REM  shows when (^).. is pressed at the top of a drive (his ask, 2026-09-28: "if it is at the
// REM  parent directory and cant go up … it should show the drive list local or network").
// REM  Listing drives needs no permission; OPENING one does, the first time (PaneModel.go).
//

import SwiftUI

/// Where a drive is. REM  Local drives are listed before network ones.
enum DriveKind: Int, Comparable {
    case startup   // the Mac's own disk ("/")
    case local     // plugged in: USB, Thunderbolt, SD card
    case network   // a share on another machine (a NAS, another Mac)

    static func < (a: DriveKind, b: DriveKind) -> Bool { a.rawValue < b.rawValue }

    var symbol: String {
        switch self {
        case .startup: return "internaldrive.fill"
        case .local:   return "externaldrive.fill"
        case .network: return "server.rack"
        }
    }

    var color: Color {
        switch self {
        case .startup: return .gray
        case .local:   return .yellow
        case .network: return .mint
        }
    }

    var title: String {
        switch self {
        case .startup, .local: return "Local"
        case .network:         return "Network"
        }
    }
}

struct Drive: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
    let kind: DriveKind
}

enum Drives {
    /// Every drive the Mac can see: the startup disk, then local drives, then network drives,
    /// each group in name order.
    static func mounted() -> [Drive] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsBrowsableKey, .volumeIsLocalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        let drives: [Drive] = urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.volumeIsBrowsable ?? true else { return nil }
            let kind: DriveKind = url.path == "/" ? .startup
                : (values?.volumeIsLocal ?? true) ? .local : .network
            return Drive(url: url, name: values?.volumeName ?? url.lastPathComponent, kind: kind)
        }
        return drives.sorted {
            $0.kind != $1.kind ? $0.kind < $1.kind
                : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// The drive a path lives on — the longest drive path that holds it ("/" holds everything).
    static func drive(holding path: String, in drives: [Drive]) -> Drive? {
        drives.filter { StateStore.path(path, isInside: $0.url.standardizedFileURL.path) }
            .max { $0.url.path.count < $1.url.path.count }
    }
}
