//
//  ShazamLookup.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  STEP 3 of the media row (2026-09-30): SHAZAM, THE LAST RESORT — for the files iTunes left
// REM  alone (a name with nothing to search for, or no trustworthy match). SONGS AND MUSIC VIDEOS.
// REM  ⚠️ This REVERSES his 2026-09-24 ruling for NightGard Commander ("staying clear of shazam for
// REM  video"). His words today: "that was for that time, times hve changed because then we were
// REM  excluding music videos because i had few if not zero music videos." He now has 2,302.
// REM
// REM  LIFTED from NightGard Commander's ShazamService.swift (Nov 2025): ShazamKit signature from
// REM  the file, 44.1 kHz mono; its Deep Dive's sample positions (20 s, 45 s, 70 s in); the
// REM  Apple Music ID from Shazam handed to iTunes `lookup?id=` for album, year and track;
// REM  "Music" dropped from Shazam's genres. What changed, and why:
// REM   · AUDIO IS READ WITH AVAssetReader, not AVAudioFile — so the sound track of a VIDEO is
// REM     read the same way as a song. (AVAudioFile cannot open an .mp4 video.)
// REM   · NOT the first 10 seconds. The old default sampled from 0:00 and hit intros and silence;
// REM     here the Deep Dive positions are tried in turn, 12 s each, stopping at the first match.
// REM   · SHSession.result(from:) (macOS 14+). The old 10-second "timeout" raced a continuation
// REM     that could never be cancelled, so it could hang for ever.
// REM  Needs the sandbox's audio-input entitlement — the old app's fix for Shazam error 202
// REM  (commit eb32022). Nothing listens to the microphone; files only.
//

import Foundation
import AVFoundation
import ShazamKit

nonisolated enum ShazamLookup {

    /// Seconds into the file to try, in order — the old Deep Dive's fixed positions.
    static let positions: [Double] = [20, 45, 70]
    static let sampleLength: Double = 12

    static func lookup(_ file: URL) async -> ITunesLookup.Outcome {
        let asset = AVURLAsset(url: file)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        guard duration > 0 else { return .failed("Could not read how long it is.") }
        // REM  A short file gets one sample from its start; a long one the three positions.
        var starts = positions.filter { $0 + sampleLength <= duration }
        if starts.isEmpty { starts = [0] }

        var lastError: String?
        for start in starts {
            if Task.isCancelled { return .failed("Stopped.") }
            let signature: SHSignature
            do {
                signature = try await makeSignature(asset: asset, start: start,
                                                    length: min(sampleLength, duration - start))
            } catch {
                return .failed("Could not read its sound — \(error.localizedDescription)")
            }
            switch await SHSession().result(from: signature) {
            case .match(let match):
                guard let item = match.mediaItems.first, let title = item.title, let artist = item.artist else {
                    continue
                }
                if let id = item.appleMusicID, let full = await catalogEntry(id: id) {
                    return .found(full)
                }
                return .found(ITunesLookup.Hit(artist: artist, title: title,
                                               genre: item.genres.first { $0 != "Music" }))
            case .noMatch:
                continue
            case .error(let error, _):
                lastError = error.localizedDescription
            }
        }
        if let lastError { return .failed("Shazam: \(lastError)") }
        return .noResults
    }

    /// Album, year, track and genre for Shazam's Apple Music ID — iTunes `lookup?id=`.
    static func catalogEntry(id: String) async -> ITunesLookup.Hit? {
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(id)"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return ITunesLookup.parse(data).first
    }

    /// A signature from `length` seconds of the file's sound, starting at `start`.
    static func makeSignature(asset: AVURLAsset, start: Double, length: Double) async throws -> SHSignature {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw LookupError.noSound
        }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                       duration: CMTime(seconds: length, preferredTimescale: 600))
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM,
                                       AVSampleRateKey: 44_100,
                                       AVNumberOfChannelsKey: 1,
                                       AVLinearPCMBitDepthKey: 32,
                                       AVLinearPCMIsFloatKey: true,
                                       AVLinearPCMIsNonInterleaved: false,
                                       AVLinearPCMIsBigEndianKey: false]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? LookupError.noSound }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100,
                                   channels: 1, interleaved: false)!
        let generator = SHSignatureGenerator()
        while let sample = output.copyNextSampleBuffer() {
            let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
            guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { continue }
            buffer.frameLength = frames
            let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames),
                                                                      into: buffer.mutableAudioBufferList)
            guard status == noErr else { continue }
            try generator.append(buffer, at: nil)
        }
        if reader.status == .failed { throw reader.error ?? LookupError.noSound }
        return generator.signature()
    }

    enum LookupError: LocalizedError {
        case noSound
        var errorDescription: String? { "it has no sound track" }
    }
}
