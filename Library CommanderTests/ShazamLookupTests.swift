//
//  ShazamLookupTests.swift
//  Library CommanderTests
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM  Step 3 (2026-09-30): Shazam's fingerprint is taken from the MIDDLE of a file (not 0:00),
// REM  from a sample of the right length, through AVAssetReader — the reader that also opens a
// REM  video's sound track. No network: matching is Apple's side and is not tested here.
//

import Foundation
import AVFoundation
import ShazamKit
import Testing
@testable import Library_Commander

struct ShazamLookupTests {
    /// A 30-second 440 Hz tone, written as a WAV.
    private func makeTone(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tone-\(UUID().uuidString).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = Float(sin(2 * .pi * 440 * Double(i) / 44_100) * 0.5) }
        try file.write(from: buffer)
        return url
    }

    @Test func signatureIsTakenFromTheMiddle() async throws {
        let url = try makeTone(seconds: 30)
        defer { try? FileManager.default.removeItem(at: url) }
        let sig = try await ShazamLookup.makeSignature(asset: AVURLAsset(url: url), start: 15, length: 12)
        #expect(abs(sig.duration - 12) < 0.5)
    }

    @Test func samplePositionsSkipTheIntro() {
        #expect(ShazamLookup.positions.first == 20)
        #expect(ShazamLookup.positions.allSatisfy { $0 > 0 })
    }
}
