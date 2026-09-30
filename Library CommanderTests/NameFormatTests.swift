//
//  NameFormatTests.swift
//  Library CommanderTests
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM  The Name Format (step 1 of the media row, 2026-09-30): the name the renamers will give,
// REM  the separator rule the old app broke, safe characters, and the setting surviving a relaunch.
//

import Foundation
import Testing
@testable import Library_Commander

struct NameFormatTests {
    private let song: [MetadataField: String] = [.artist: "The Strokes", .title: "Taken for a Fool",
                                                 .album: "Angles", .genre: "Rock", .year: "2011",
                                                 .trackNumber: "05"]

    @Test func standardIsArtistTitleAlbum() {
        #expect(NameFormat.fileName(NameFormat.standard, values: song, ext: "mp3")
                == "The Strokes - Taken for a Fool - Angles.mp3")
    }

    @Test func missingPieceLeavesNoDanglingSeparator() {
        var noAlbum = song
        noAlbum[.album] = nil
        #expect(NameFormat.fileName(NameFormat.standard, values: noAlbum, ext: "mp4")
                == "The Strokes - Taken for a Fool.mp4")
    }

    @Test func separatorsAreHonoured() {
        // The old app ignored separator blocks; two pieces with none between them get a space.
        #expect(NameFormat.fileName([.trackNumber, .title, .separator, .artist], values: song, ext: "m4a")
                == "05 Taken for a Fool - The Strokes.m4a")
    }

    @Test func unsafeCharactersAreCleaned() {
        let values: [MetadataField: String] = [.artist: "AC/DC", .title: "What?  Is: \"This\" <x>|*"]
        #expect(NameFormat.fileName(NameFormat.standard, values: values, ext: "mp3")
                == "AC-DC - What Is- This x.mp3")
        #expect(NameFormat.clean("...hidden") == "hidden")
    }

    @Test func nothingFoundNamesNothing() {
        #expect(NameFormat.fileName(NameFormat.standard, values: [:], ext: "mp3") == nil)
    }

    @Test func formatSurvivesARelaunch() {
        let defaults = UserDefaults(suiteName: "NameFormatTests-\(UUID().uuidString)")!
        #expect(NameFormat.load(defaults) == NameFormat.standard)
        NameFormat.save([.year, .separator, .title], defaults)
        #expect(NameFormat.load(defaults) == [.year, .separator, .title])
    }
}
