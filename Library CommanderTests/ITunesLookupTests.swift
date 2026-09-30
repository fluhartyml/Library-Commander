//
//  ITunesLookupTests.swift
//  Library CommanderTests
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM  Step 2 (2026-09-30): the lifted name parsing, the search address for songs vs music videos,
// REM  the trust gate that keeps an unrelated top hit from renaming a file, and reading Apple's
// REM  answer. No network — Apple's answer is canned here.
//

import Foundation
import Testing
@testable import Library_Commander

struct ITunesLookupTests {

    @Test func musicVideoNameIsParsedAndCleaned() throws {
        let (artist, title) = ITunesLookup.parseFilename("Creed - With Arms Wide Open (Official HD Music Video)")
        #expect(artist == "Creed")
        #expect(ITunesLookup.sanitizeSearchTerm(title ?? "") == "With Arms Wide Open")
        #expect(ITunesLookup.sanitizeSearchTerm("Foreigner - Say You Will [HQ]") == "Foreigner - Say You Will")
    }

    @Test func trackNumberAndGenrePrefixesAreDropped() {
        #expect(ITunesLookup.parseFilename("03 - Angles - Taken for a Fool") == ("Angles", "Taken for a Fool"))
        #expect(ITunesLookup.parseFilename("Rock - The Strokes - Taken for a Fool").artist == "The Strokes")
    }

    @Test func videosSearchTheMusicVideoCatalog() throws {
        let video = try #require(ITunesLookup.searchURL(artist: "Creed", title: "With Arms Wide Open", video: true))
        let song = try #require(ITunesLookup.searchURL(artist: "Creed", title: "With Arms Wide Open", video: false))
        #expect(video.absoluteString.contains("media=musicVideo"))
        #expect(video.absoluteString.contains("entity=musicVideo"))
        #expect(song.absoluteString.contains("media=music&"))
        #expect(song.absoluteString.contains("entity=song"))
    }

    @Test func junkTagsFallBackToTheFileName() {
        let terms = ITunesLookup.chooseTerms(fileArtist: "Creed", fileTitle: "With Arms Wide Open",
                                             metaArtist: "Unknown Artist", metaTitle: "Track 01")
        #expect(terms?.artist == "Creed")
        #expect(terms?.title == "With Arms Wide Open")
        #expect(ITunesLookup.chooseTerms(fileArtist: nil, fileTitle: "Track 07",
                                         metaArtist: nil, metaTitle: nil) == nil)
    }

    @Test func anUnrelatedTopHitIsNotTrusted() {
        let right = ITunesLookup.Hit(artist: "Creed", title: "With Arms Wide Open")
        let wrong = ITunesLookup.Hit(artist: "Taylor Swift", title: "Love Story")
        #expect(ITunesLookup.matchIsTrustworthy(artist: "Creed", title: "With Arms Wide Open (Official HD Music Video)", hit: right))
        #expect(!ITunesLookup.matchIsTrustworthy(artist: "Creed", title: "With Arms Wide Open", hit: wrong))
    }

    @Test func applesAnswerIsReadAndNamed() {
        let json = """
        {"resultCount":1,"results":[{"artistName":"The Strokes","trackName":"Taken for a Fool",
        "collectionName":"Angles","primaryGenreName":"Rock","releaseDate":"2011-03-18T12:00:00Z","trackNumber":5}]}
        """
        let hits = ITunesLookup.parse(Data(json.utf8))
        #expect(hits.count == 1)
        #expect(hits.first?.year == "2011")
        #expect(NameFormat.fileName(NameFormat.standard, values: hits[0].nameValues, ext: "mp4")
                == "The Strokes - Taken for a Fool - Angles.mp4")
        #expect(NameFormat.fileName([.trackNumber, .separator, .title], values: hits[0].nameValues, ext: "m4a")
                == "05 - Taken for a Fool.m4a")
    }
}
