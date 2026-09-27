//
//  BatchShazamDialog.swift
//  Library Commander
//
//  Created by Michael Fluharty with Claude on 2025 Nov 18 1055
//

import SwiftUI

struct BatchShazamDialog: View {
    @Binding var isPresented: Bool
    let folderPath: String
    let folderName: String
    let onFileRenamed: (() -> Void)?
    @State private var service = ShazamService()
    @State private var showResults = false
    @State private var showUnifiedQueue = false

    var body: some View {
        VStack(spacing: 20) {
            // Title with spinner
            HStack {
                Image(systemName: "shazam.logo.fill")
                    .font(.title)
                    .foregroundColor(.blue)
                Text("Shazaming Folder")
                    .font(.system(size: 22))
                    .fontWeight(.semibold)

                if service.isProcessing {
                    ProgressView()
                        .controlSize(.regular)
                        .padding(.leading, 8)
                }
            }

            Text(folderName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.secondary)

            Divider()

            // Progress bar
            if service.isProcessing {
                VStack(spacing: 12) {
                    ProgressView(value: Double(service.processedFiles), total: Double(service.totalFiles))
                        .progressViewStyle(.linear)

                    Text("\(service.processedFiles) / \(service.totalFiles)")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }

                Divider()

                // Currently processing
                VStack(alignment: .leading, spacing: 8) {
                    Text("Currently detecting:")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)

                    Text(service.currentFile)
                        .font(.system(size: 18, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // Stats
                HStack(spacing: 24) {
                    StatView(icon: "checkmark.circle.fill", color: .green, label: "Matched", value: service.matchedCount)
                    StatView(icon: "pencil.circle.fill", color: .purple, label: "Review", value: service.genreReviewCount)
                    StatView(icon: "exclamationmark.triangle.fill", color: .orange, label: "Queued", value: service.queuedCount)

                    if service.totalFiles > 0 {
                        let remaining = service.totalFiles - service.processedFiles
                        let estimatedMinutes = remaining * 7 / 60 // ~7 seconds per file
                        StatView(icon: "clock.fill", color: .blue, label: "Remaining", value: estimatedMinutes, suffix: "min")
                    }
                }

                Divider()

                // Cancel button
                Button("Cancel") {
                    service.cancel()
                    isPresented = false
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 500, height: 400)
        .onAppear {
            startProcessing()
        }
        .sheet(isPresented: $showResults) {
            ShazamResultsDialog(
                isPresented: $showResults,
                matchedCount: service.matchedCount,
                genreReviewCount: service.genreReviewCount,
                queuedCount: service.queuedCount,
                onViewQueue: {
                    showResults = false
                    showUnifiedQueue = true
                }
            )
        }
        .sheet(isPresented: $showUnifiedQueue) {
            UnifiedQueueReviewPanel(
                isPresented: $showUnifiedQueue,
                onFileRenamed: onFileRenamed
            )
        }
    }

    private func startProcessing() {
        // Set up file rename callback
        service.onFileRenamed = onFileRenamed

        Task {
            await service.processFolder(path: folderPath)

            // Show results when complete
            if !service.results.isEmpty {
                await MainActor.run {
                    showResults = true
                }
            }
        }
    }
}

// Stat display view
struct StatView: View {
    let icon: String
    let color: Color
    let label: String
    let value: Int
    var suffix: String = ""

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 22))

            if suffix.isEmpty {
                Text("\(value)")
                    .font(.system(size: 20))
                    .fontWeight(.semibold)
            } else {
                Text("\(value) \(suffix)")
                    .font(.system(size: 20))
                    .fontWeight(.semibold)
            }

            Text(label)
                .font(.system(size: 18))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    @Previewable @State var isPresented = true
    BatchShazamDialog(
        isPresented: $isPresented,
        folderPath: "/Users/test/Music",
        folderName: "My Music",
        onFileRenamed: nil
    )
}
