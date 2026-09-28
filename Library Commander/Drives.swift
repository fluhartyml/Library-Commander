//
//  Drives.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  The drives the Mac can see right now, for each pane's drive picker. Listing them needs
// REM  no permission; OPENING one does, the first time (see PaneModel.go(toPath:)).
//

import Foundation

struct Drive: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
}

enum Drives {
    static func mounted() -> [Drive] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.volumeIsBrowsable ?? true else { return nil }
            return Drive(url: url, name: values?.volumeName ?? url.lastPathComponent)
        }
    }
}
