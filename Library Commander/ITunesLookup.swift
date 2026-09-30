//
//  ITunesLookup.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  STEP 2 of the media row (2026-09-30): look a song OR a music video up in Apple's catalog and
// REM  propose its proper name. His words: "i want library commander to do both but i dont want to
// REM  reinvent the wheel". So this is LIFTED:
// REM   · parseFilename, the junk-tag checks and stringsMatch — NightGard Commander's
// REM     iTunesSearchService.swift (Nov 2025), unchanged in behaviour;
// REM   · sanitizeSearchTerm and the trust gate (matchIsTrustworthy / normalize /
// REM     sharedTokenRatio) — NightGard Library Commander's LibraryService.swift.
// REM  What is NEW, and why:
// REM   · MUSIC VIDEOS search Apple's music-video catalog (media=musicVideo), songs the song
// REM     catalog. The old app was audio-only.
// REM   · THE TRUST GATE IS APPLIED. The old Commander took the first hit blindly (limit=1), so an
// REM     unrelated top hit renamed the file. Here up to 5 hits come back and only one that
// REM     matches what was searched for is used; otherwise the file is left alone.
// REM   · Nothing is renamed here. This only PROPOSES; the sheet shows old → new and he ticks.
// REM  Apple asks for roughly 20 searches a minute, so searches are spaced 3 seconds apart.
//

import Foundation
import AVFoundation

nonisolated enum ITunesLookup {

    /// One catalog entry.
    struct Hit: Equatable {
        var artist: String
        var title: String
        var album: String?
        var genre: String?
        var year: String?
        var trackNumber: Int?

        /// The values the Name Format lays out.
        var nameValues: [MetadataField: String] {
            var v: [MetadataField: String] = [.artist: artist, .title: title]
            if let album { v[.album] = album }
            if let genre { v[.genre] = genre }
            if let year { v[.year] = year }
            if let trackNumber { v[.trackNumber] = String(format: "%02d", trackNumber) }
            return v
        }
    }

    enum Outcome: Equatable {
        case found(Hit)
        /// Apple answered, but nothing it returned matched what was searched for.
        case notTrusted(closest: Hit)
        case noResults
        /// Neither the file name nor the tags say what it is — a job for Shazam (step 3).
        case noSearchTerms
        case failed(String)
    }

    static let spacing: Duration = .seconds(3)

    // MARK: - Look one file up

    static func lookup(_ file: URL, isVideo: Bool) async -> Outcome {
        guard let (artist, title) = await searchTerms(for: file) else { return .noSearchTerms }
        guard let url = searchURL(artist: artist, title: title, video: isVideo) else { return .noSearchTerms }
        do {
            var (data, response) = try await URLSession.shared.data(from: url)
            // REM  Over the rate limit Apple answers 403 or 429. Wait a minute, try once more.
            if let http = response as? HTTPURLResponse, [403, 429].contains(http.statusCode) {
                try await Task.sleep(for: .seconds(60))
                (data, response) = try await URLSession.shared.data(from: url)
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return .failed("Apple answered \(http.statusCode).")
            }
            let hits = parse(data)
            guard let first = hits.first else { return .noResults }
            if let good = hits.first(where: { matchIsTrustworthy(artist: artist ?? "", title: title, hit: $0) }) {
                return .found(good)
            }
            return .notTrusted(closest: first)
        } catch is CancellationError {
            return .failed("Stopped.")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Artist and title to search for, from the name and the file's own tags — the old app's
    /// cross-check (STEP 1–3 of its lookupFile). Nil when neither is usable.
    static func searchTerms(for file: URL) async -> (artist: String?, title: String)? {
        let (fileArtist, fileTitle) = parseFilename(file.deletingPathExtension().lastPathComponent)
        var metaTitle: String?
        var metaArtist: String?
        if let metadata = try? await AVURLAsset(url: file).load(.metadata) {
            for item in metadata {
                guard let key = item.commonKey, let value = try? await item.load(.stringValue) else { continue }
                if key == .commonKeyTitle { metaTitle = value }
                if key == .commonKeyArtist { metaArtist = value }
            }
        }
        return chooseTerms(fileArtist: fileArtist, fileTitle: fileTitle,
                           metaArtist: metaArtist, metaTitle: metaTitle)
    }

    /// The old app's rule for filename vs tags. One change: where it used a tag that was missing,
    /// this falls back to the file name's piece instead of searching with nothing.
    static func chooseTerms(fileArtist: String?, fileTitle: String?,
                            metaArtist: String?, metaTitle: String?) -> (artist: String?, title: String)? {
        let metaIsGarbage = isGarbageMetadata(title: metaTitle, artist: metaArtist)
        let fileHasInfo = fileArtist != nil || (fileTitle != nil && !isGarbageTitle(fileTitle))
        var artist: String?
        var title: String?
        if metaIsGarbage {
            guard fileHasInfo else { return nil }
            artist = fileArtist; title = fileTitle
        } else if fileArtist != nil, metaArtist != nil, !stringsMatch(fileArtist, metaArtist) {
            // They disagree — the file name wins (what he can see beats a stale tag).
            artist = fileArtist; title = fileTitle ?? metaTitle
        } else if fileArtist != nil, metaArtist != nil {
            artist = metaArtist; title = metaTitle ?? fileTitle
        } else {
            artist = metaArtist ?? fileArtist; title = metaTitle ?? fileTitle
        }
        guard let t = title, !sanitizeSearchTerm(t).isEmpty else { return nil }
        return (artist, t)
    }

    static func searchURL(artist: String?, title: String, video: Bool) -> URL? {
        let term = [sanitizeSearchTerm(artist ?? ""), sanitizeSearchTerm(title)]
            .filter { !$0.isEmpty }.joined(separator: " ")
        let capped = String(term.prefix(120))       // iTunes Search tolerates about this much
        guard !capped.isEmpty else { return nil }
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [URLQueryItem(name: "term", value: capped),
                        URLQueryItem(name: "media", value: video ? "musicVideo" : "music"),
                        URLQueryItem(name: "entity", value: video ? "musicVideo" : "song"),
                        URLQueryItem(name: "limit", value: "5")]
        return c.url
    }

    static func parse(_ data: Data) -> [Hit] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { r in
            guard let artist = r["artistName"] as? String, let title = r["trackName"] as? String else { return nil }
            var year: String?
            if let date = r["releaseDate"] as? String, date.count >= 4 { year = String(date.prefix(4)) }
            return Hit(artist: artist, title: title, album: r["collectionName"] as? String,
                       genre: r["primaryGenreName"] as? String, year: year,
                       trackNumber: r["trackNumber"] as? Int)
        }
    }

    // MARK: - Lifted from NightGard Commander's iTunesSearchService.swift

    /// "Genre - Artist - Title", "Artist - Title", "01 Title", "Title".
    static func parseFilename(_ filename: String) -> (artist: String?, title: String?) {
        let cleaned = filename.replacingOccurrences(of: #"^(\d{1,3}[\.\-\s]+)"#, with: "",
                                                    options: .regularExpression)
        let parts = cleaned.components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespaces) }
        switch parts.count {
        case 3...: return (parts[1], parts[2...].joined(separator: " - "))
        case 2:    return (parts[0], parts[1])
        case 1:    return (nil, parts[0])
        default:   return (nil, nil)
        }
    }

    static func isGarbageMetadata(title: String?, artist: String?) -> Bool {
        (title == nil || isGarbageTitle(title)) && (artist == nil || isGarbageArtist(artist))
    }

    static func isGarbageTitle(_ title: String?) -> Bool {
        guard let t = title?.lowercased().trimmingCharacters(in: .whitespaces) else { return true }
        let patterns = [#"^track\s*\d+"#, #"^audiotrack\s*\d*"#, #"^audio\s*\d+"#, #"^\d{1,3}$"#,
                        #"^untitled"#, #"^unknown"#, #"^m\d{5,}"#]
        return t.count < 2 || patterns.contains { t.range(of: $0, options: .regularExpression) != nil }
    }

    static func isGarbageArtist(_ artist: String?) -> Bool {
        guard let a = artist?.lowercased().trimmingCharacters(in: .whitespaces) else { return true }
        let patterns = [#"^unknown"#, #"^no artist"#, #"^artist"#, #"^--$"#, #"^\-$"#]
        return a.count < 2 || patterns.contains { a.range(of: $0, options: .regularExpression) != nil }
    }

    static func stringsMatch(_ a: String?, _ b: String?) -> Bool {
        guard let a = a?.lowercased().trimmingCharacters(in: .whitespaces),
              let b = b?.lowercased().trimmingCharacters(in: .whitespaces) else { return false }
        if a == b || a.contains(b) || b.contains(a) { return true }
        func loose(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "and").replacingOccurrences(of: "'", with: "")
             .replacingOccurrences(of: "the ", with: "")
        }
        return loose(a) == loose(b)
    }

    // MARK: - Lifted from NightGard Library Commander's LibraryService.swift

    /// Strips ( ) [ ] { } contents — "(Official HD Music Video)", "[HQ]", remix notes — a leading
    /// track number and stray extensions, and collapses spaces. Video extensions added.
    static func sanitizeSearchTerm(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\{[^}]*\}"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"^\d{1,3}\s*[-_.]?\s*"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\.(mp3|m4a|wav|aac|aiff|flac|mp4|m4v|mov|mkv)\b"#, with: "",
                                   options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Guards against an unrelated top hit renaming the file.
    static func matchIsTrustworthy(artist: String, title: String, hit: Hit) -> Bool {
        let q = normalize(sanitizeSearchTerm("\(artist) \(title)"))
        let r = normalize("\(hit.artist) \(hit.title)")
        guard !q.isEmpty, !r.isEmpty else { return false }
        return q.contains(r) || r.contains(q) || sharedTokenRatio(q, r) >= 0.6
    }

    static func normalize(_ s: String) -> String {
        s.lowercased()
         .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
         .joined(separator: " ")
         .components(separatedBy: .whitespaces)
         .filter { !$0.isEmpty }
         .joined(separator: " ")
    }

    static func sharedTokenRatio(_ a: String, _ b: String) -> Double {
        let aTokens = Set(a.split(separator: " ").map(String.init))
        let bTokens = Set(b.split(separator: " ").map(String.init))
        guard !aTokens.isEmpty, !bTokens.isEmpty else { return 0 }
        return Double(aTokens.intersection(bTokens).count) / Double(min(aTokens.count, bTokens.count))
    }
}
