//
//  NameFormat.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  THE NAME FORMAT — how a looked-up song or music video gets its file name. His ask,
// REM  2026-09-30: a third toolbar row for the media tools, built one step at a time; this is
// REM  step 1, the format setting. Steps 2 (iTunes) and 3 (Shazam, last resort) will name files
// REM  through fileName(...) below, so the preview he sees IS the name he will get.
// REM
// REM  LIFTED, NOT REINVENTED — his words: "i dont want to reinvent the wheel". The blocks, the
// REM  field list and the Artist - Title - Album default come from NightGard Commander's
// REM  FilenameFormatBuilder.swift + ShazamSettings.swift (Nov 2025). Two of its faults are fixed:
// REM   · its renamers IGNORED the separator blocks and always joined with " - ", so the preview
// REM     and the real name disagreed. Here there is ONE function for both.
// REM   · it offered six fields no renamer ever filled (Explicit, Apple Music ID/URL, Web URL,
// REM     Release Date). Only fields a lookup can fill are offered.
// REM  Name cleaning follows NightGard Library Commander's sanitize(): no / : \ " < > | ? *,
// REM  trimmed, at most 200 characters.
// REM  Saved like every setting (his rule: everything persists).
//

import Foundation

/// One piece of a file name. `separator` prints " - " between two filled pieces.
enum MetadataField: String, CaseIterable, Identifiable, Codable {
    case artist = "Artist"
    case title = "Title"
    case album = "Album"
    case genre = "Genre"
    case year = "Year"
    case trackNumber = "Track #"
    case separator = "-"

    var id: String { rawValue }

    /// What the preview shows for this piece.
    var sampleValue: String {
        switch self {
        case .artist: return "Artist"
        case .title: return "Title"
        case .album: return "Album"
        case .genre: return "Genre"
        case .year: return "YYYY"
        case .trackNumber: return "01"
        case .separator: return " - "
        }
    }
}

/// A block in the builder. The id only tells blocks apart on screen; only the field is saved.
struct FormatBlock: Identifiable, Equatable {
    let id = UUID()
    var field: MetadataField
}

enum NameFormat {
    static let key = "nameFormat.fields"
    /// NightGard Commander's default: Artist - Title - Album.
    static let standard: [MetadataField] = [.artist, .separator, .title, .separator, .album]
    static let maxBlocks = 10
    static let maxLength = 200

    static func load(_ defaults: UserDefaults = .standard) -> [MetadataField] {
        guard let data = defaults.data(forKey: key),
              let fields = try? JSONDecoder().decode([MetadataField].self, from: data),
              !fields.isEmpty else { return standard }
        return fields
    }

    static func save(_ fields: [MetadataField], _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(fields) { defaults.set(data, forKey: key) }
    }

    /// The file name for `values`, laid out by `fields`, with `ext` added. Nil when every
    /// piece is empty — a lookup that found nothing must never rename a file to "".
    /// REM  A separator prints only BETWEEN two filled pieces, so a song with no album is
    /// REM  "Artist - Title", never "Artist - Title - ". Two pieces with no separator between
    /// REM  them get a space.
    static func fileName(_ fields: [MetadataField], values: [MetadataField: String],
                         ext: String) -> String? {
        var name = ""
        var separatorWaiting = false
        for field in fields {
            if field == .separator {
                if !name.isEmpty { separatorWaiting = true }
                continue
            }
            let value = clean(values[field] ?? "")
            guard !value.isEmpty else { continue }
            if !name.isEmpty { name += separatorWaiting ? " - " : " " }
            separatorWaiting = false
            name += value
        }
        name = String(name.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return ext.isEmpty ? name : "\(name).\(ext)"
    }

    /// One piece made safe for a file name: / and : become -, \ " < > | ? * are dropped,
    /// runs of spaces become one, and a leading dot is removed (it would hide the file).
    static func clean(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ":", with: "-")
        s.removeAll { "\\\"<>|?*".contains($0) }
        s = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while s.hasPrefix(".") { s.removeFirst() }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// The preview line, from the sample values.
    static func preview(_ fields: [MetadataField], ext: String) -> String {
        let samples = Dictionary(uniqueKeysWithValues: MetadataField.allCases.map { ($0, $0.sampleValue) })
        return fileName(fields, values: samples, ext: ext) ?? "No format yet — add a block."
    }
}
