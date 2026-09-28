//
//  ClashSheet.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  THE CLASH SHEET (build 57) — the old app's design, which he asked for back, 2026-09-28:
// REM    "i think it was side by side with a thumbnail and i think you had each instance newer
// REM     older bigger smaller have a do to all checkbox for similar duplicates"
// REM  Two cards, INCOMING and ALREADY HERE, each with a thumbnail, Show in Finder, the size
// REM  marked larger/smaller and the date marked newer/older, so the NAME is never the only
// REM  thing he has to go on ("how would the user know byte for byte?"). The header says
// REM  whether the two files are identical, compared byte for byte.
// REM  Every button says what it will do in plain words, including whether the old one goes
// REM  to the Trash or is deleted for good (his rule: external = for good).
//

import SwiftUI
import AppKit
import QuickLookThumbnailing

struct ClashSheet: View {
    let clash: Clash
    let answer: (ClashChoice, Bool) -> Void
    @State private var applyToAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(alignment: .top, spacing: 16) {
                card("Incoming", clash.incoming, other: clash.existing)
                card("Already here", clash.existing, other: clash.incoming)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) { choices }
            // REM  "do to all" — only when more clashes can still come (a folder merge).
            // REM  Remembered per KIND, so an answer for identical files never covers files that differ.
            if clash.moreMayFollow {
                Toggle(applyToAllLabel, isOn: $applyToAll)
            }
            HStack {
                Spacer()
                Button("Stop") { answer(.stop, false) }
                    .keyboardShortcut(.cancelAction)
                    .help("Stop here. Everything already copied or moved stays where it is now.")
            }
        }
        .padding(20)
        .frame(width: 820)
        .interactiveDismissDisabled()
    }

    // MARK: - Header

    @ViewBuilder private var header: some View {
        let folderName = clash.existing.url.deletingLastPathComponent().lastPathComponent
        switch clash.kind {
        case .identicalFiles:
            Text("These two files are identical").bold()
            Text("Same name, same size and the same contents, compared byte for byte.")
                .foregroundStyle(.secondary)
        case .differingFiles:
            Text("A different “\(clash.incoming.name)” is already in “\(folderName)”").bold()
            Text("Same name, different contents. Compare the two below.")
                .foregroundStyle(.secondary)
        case .folders:
            Text("A folder named “\(clash.incoming.name)” is already in “\(folderName)”").bold()
            Text("Merge puts what is inside together. Anything inside with the same name asks its own question.")
                .foregroundStyle(.secondary)
        case .mismatch:
            Text("“\(clash.incoming.name)” is already in “\(folderName)”").bold()
            Text(clash.incoming.isPackage || clash.existing.isPackage
                 ? "Libraries and packages are one item and are never merged inside — mixing two leaves one the app cannot open."
                 : "One is a file and the other is a folder, so they can only replace each other or both be kept.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - The cards

    private func card(_ label: String, _ f: FileFacts, other: FileFacts) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).foregroundStyle(.secondary)
            Text(f.name).bold().lineLimit(2)
            Text("in “\(f.url.deletingLastPathComponent().lastPathComponent)”").foregroundStyle(.secondary)
            Thumbnail(url: f.url)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([f.url]) }
                .help("Opens Finder with this one selected. Press Space there to play or preview it.")
            if !f.isFolder {
                HStack(spacing: 6) {
                    Text(ByteCountFormatter.string(fromByteCount: f.size, countStyle: .file))
                    if f.size != other.size && !other.isFolder { tag(f.size > other.size ? "larger" : "smaller") }
                }
                if f.size >= 1000 {
                    Text("\(f.size.formatted()) bytes").foregroundStyle(.secondary).monospacedDigit()
                }
            }
            HStack(spacing: 6) {
                Text("Modified \(f.modified.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "unknown")")
                if let a = f.modified, let b = other.modified, abs(a.timeIntervalSince(b)) >= 1 {
                    tag(a > b ? "newer" : "older")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func tag(_ text: String) -> some View {
        Text(text).padding(.horizontal, 6).background(.quaternary, in: Capsule())
    }

    // MARK: - The choices

    /// What happens to the one already here, in his terms.
    private var oldGoes: String {
        clash.replaceIsPermanent
            ? "The one already here is deleted for good — it is on an external drive, which has no Trash to get it back from."
            : "The one already here goes to the Trash."
    }

    private var incomingGone: String {
        clash.isMove ? " The incoming one leaves the source." : ""
    }

    @ViewBuilder private var choices: some View {
        switch clash.kind {
        case .folders:
            // His words: "folder should be replace or merge".
            row("Merge", "Put everything inside “\(clash.incoming.name)” into the folder already here. Nothing is replaced without asking.", .merge)
            row("Replace", "Remove the folder already here and everything in it, and put the incoming one in its place. \(folderGoes)\(incomingGone)", .replace, destructive: true)
            row("Keep Both", "Bring the incoming folder in too, named “\(clash.keepBothName)”.", .keepBoth)
            row("Skip", "Leave both folders as they are.", .skip)
        case .identicalFiles:
            row("Skip", clash.isMove ? "Leave both. The incoming copy stays in the source." : "Leave the one already here; nothing is copied.", .skip)
            if clash.isMove {
                row("Remove from source", "The same file is already here, so remove the duplicate from the source. Every byte is compared again first — if they differ at all, nothing is removed.", .removeFromSource, destructive: true)
            }
            row("Replace", "Put the incoming file here anyway. \(oldGoes)\(incomingGone)", .replace)
            row("Keep Both", "Keep both. The incoming file is named “\(clash.keepBothName)”.", .keepBoth)
        case .differingFiles:
            row("Replace", "Put the incoming file here. \(oldGoes)\(incomingGone)", .replace, destructive: true)
            row("Replace if newer", "Only replaces when the incoming file is dated later. For this file: \(incomingIsNewer ? "the incoming one is newer, so it would be replaced." : "the one already here is the same age or newer, so it would be kept.")", .replaceIfNewer)
            row("Replace if size differs", "Only replaces when the sizes are not the same. For this file: \(clash.incoming.size != clash.existing.size ? "the sizes differ, so it would be replaced." : "the sizes match, so it would be kept.")", .replaceIfSizeDiffers)
            row("Keep Both", "Keep both. The incoming file is named “\(clash.keepBothName)”.", .keepBoth)
            row("Skip", "Leave the one already here. The incoming file stays where it is.", .skip)
        case .mismatch:
            row("Replace", "Remove what is already here and put the incoming one in its place. \(clash.existing.isFolder ? folderGoes : oldGoes)\(incomingGone)", .replace, destructive: true)
            row("Keep Both", "Keep both. The incoming one is named “\(clash.keepBothName)”.", .keepBoth)
            row("Skip", "Leave both as they are.", .skip)
        }
    }

    private var folderGoes: String {
        clash.replaceIsPermanent
            ? "It is deleted for good, with everything inside — it is on an external drive, which has no Trash."
            : "It goes to the Trash, with everything inside."
    }

    private var incomingIsNewer: Bool {
        (clash.incoming.modified ?? .distantPast) > (clash.existing.modified ?? .distantPast)
    }

    private var applyToAllLabel: String {
        switch clash.kind {
        case .identicalFiles: return "Do the same for every other identical file in this job"
        case .differingFiles: return "Do the same for every other file that differs in this job — “if newer” and “if size differs” are still checked file by file"
        case .folders:        return "Do the same for every other folder with the same name in this job"
        case .mismatch:       return "Do the same for every other file-and-folder clash in this job"
        }
    }

    private func row(_ title: String, _ explanation: String, _ choice: ClashChoice, destructive: Bool = false) -> some View {
        Button {
            answer(choice, applyToAll)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold().foregroundStyle(destructive ? Color.red : Color.primary)
                Text(explanation).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A picture of the file — Quick Look's thumbnail (a video frame, a photo, a page) — or its
/// Finder icon when there is none.
private struct Thumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().aspectRatio(contentMode: .fit)
                    .padding(30)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .task(id: url) {
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 360, height: 180),
                                                       scale: NSScreen.main?.backingScaleFactor ?? 2,
                                                       representationTypes: .thumbnail)
            if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                image = rep.nsImage
            }
        }
    }
}
