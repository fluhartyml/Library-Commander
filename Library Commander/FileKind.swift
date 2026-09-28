//
//  FileKind.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  What kind of file a row is, and the glyph and color it shows. His ask, 2026-09-28:
// REM  "the mini glyph icons should be changed to glyphs and colors relative to the file type."
// REM
// REM  The kind comes from macOS's own type system (UTType), not a hand-made list of extensions,
// REM  so every extension macOS knows is sorted correctly — .mkv, .flac, .heic, .webp, all of it.
// REM  Video keeps the old Library Commander's purple, so his eye does not have to relearn it.
// REM  One place to change a glyph or color: the two switches below.
//

import SwiftUI
import UniformTypeIdentifiers

enum FileKind: String, CaseIterable {
    case folder, video, audio, image, pdf, text, code, archive, diskImage, app, package, other

    /// Decides the kind from the name alone — no disk read, so a big folder lists fast.
    static func of(name: String, isFolder: Bool) -> FileKind {
        let ext = (name as NSString).pathExtension.lowercased()
        // REM  A folder with a known package extension (.app, .photoslibrary) is shown as what
        // REM  it is; Finder does the same. It still opens like a folder here — a commander may
        // REM  look inside.
        guard let type = ext.isEmpty ? nil : UTType(filenameExtension: ext) else {
            return isFolder ? .folder : .other
        }
        if isFolder {
            if type.conforms(to: .application) { return .app }
            if type.conforms(to: .package) { return .package }
            return .folder
        }
        // REM  Order matters: the more specific types are checked first (PDF before "document",
        // REM  source code before plain text).
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script)
            || type.conforms(to: .json) || type.conforms(to: .xml) { return .code }
        if type.conforms(to: .text) || type.conforms(to: .rtf) { return .text }
        if type.conforms(to: .diskImage) { return .diskImage }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .application) { return .app }
        return .other
    }

    /// The SF Symbol for the row.
    var symbol: String {
        switch self {
        case .folder:    return "folder.fill"
        case .video:     return "video.fill"          // REM  the old app's purple camera
        case .audio:     return "music.note"
        case .image:     return "photo.fill"
        case .pdf:       return "doc.richtext.fill"
        case .text:      return "doc.text.fill"
        case .code:      return "chevron.left.forwardslash.chevron.right"
        case .archive:   return "archivebox.fill"
        case .diskImage: return "externaldrive.fill"
        case .app:       return "app.fill"
        case .package:   return "shippingbox.fill"
        case .other:     return "doc.fill"
        }
    }

    /// The glyph's color. REM  Each kind a different hue, so a mixed folder reads at a glance.
    var color: Color {
        switch self {
        case .folder:    return .blue
        case .video:     return .purple
        case .audio:     return .pink
        case .image:     return .green
        case .pdf:       return .red
        case .text:      return .gray
        case .code:      return .orange
        case .archive:   return .brown
        case .diskImage: return .teal
        case .app:       return .cyan
        case .package:   return .indigo
        case .other:     return .secondary
        }
    }
}
