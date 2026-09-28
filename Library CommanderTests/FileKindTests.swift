//
//  FileKindTests.swift
//  Library CommanderTests
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM  Every row's glyph and color comes from its kind; these pin the kinds down.
//

import SwiftUI
import Testing
@testable import Library_Commander

@MainActor
struct FileKindTests {
    @Test(arguments: [
        ("clip.mp4", FileKind.video), ("film.mkv", .video), ("home.mov", .video),
        ("song.mp3", .audio), ("track.flac", .audio), ("tune.m4a", .audio),
        ("photo.heic", .image), ("pic.JPG", .image), ("art.webp", .image),
        ("manual.pdf", .pdf),
        ("notes.txt", .text), ("README.md", .text),
        ("main.swift", .code), ("data.json", .code), ("run.sh", .code),
        ("backup.zip", .archive),
        ("installer.dmg", .diskImage),
        ("mystery.zzq", .other), ("no extension", .other),
    ])
    func fileKinds(name: String, kind: FileKind) {
        #expect(FileKind.of(name: name, isFolder: false) == kind)
    }

    @Test func foldersAndPackages() {
        #expect(FileKind.of(name: "Music Videos", isFolder: true) == .folder)
        #expect(FileKind.of(name: "Safari.app", isFolder: true) == .app)
        #expect(FileKind.of(name: "Photos Library.photoslibrary", isFolder: true) == .package)
        #expect(FileKind.of(name: "v1.2 backups", isFolder: true) == .folder)   // a dot in a folder name is not a type
    }

    @Test func pdfAndHiddenAreDifferentReds() {
        #expect(FileKind.pdf.color == FileKind.pdfRed)
        #expect(FileKind.pdfRed != FileKind.hiddenRed)
    }

    @Test func videoKeepsTheOldPurple() {
        #expect(FileKind.video.color == .purple)
    }
}
