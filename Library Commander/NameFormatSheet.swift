//
//  NameFormatSheet.swift
//  Library Commander
//
// REM  FILE COMMANDER FIRST, MEDIA SECOND — see Library_CommanderApp.swift.
// REM
// REM  The Name Format builder, opened from the media row's "Name Format…" button (step 1,
// REM  2026-09-30). LIFTED from NightGard Commander's FilenameFormatBuilder: a row of blocks,
// REM  each a menu of fields; drag to reorder; Add Block puts a separator after the selected
// REM  block; × removes one; at most 10. Finished saves, Cancel changes nothing.
// REM  Changed from the old one: no caption-size text (his 18 pt rule — the sheet uses the
// REM  app's text size), and the preview comes from NameFormat.fileName, the same function the
// REM  renamers will use, so what he sees is exactly what he gets.
//

import SwiftUI
import UniformTypeIdentifiers

struct NameFormatSheet: View {
    @Binding var isPresented: Bool
    /// Sends a message to the status bar.
    let report: (String, Bool) -> Void

    @State private var blocks: [FormatBlock] = []
    @State private var selectedBlockID: UUID?
    @State private var draggedBlock: FormatBlock?

    private var fields: [MetadataField] { blocks.map(\.field) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Name Format").bold()
            Text("How a song or music video is named when it is looked up.")
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 8) {
                    if blocks.isEmpty {
                        Text("Add Block to start.").foregroundStyle(.secondary).italic().padding()
                    }
                    ForEach(blocks) { block in
                        NameBlockView(
                            block: block,
                            isSelected: selectedBlockID == block.id,
                            onSelect: { selectedBlockID = block.id },
                            onFieldChange: { newField in
                                if let i = blocks.firstIndex(where: { $0.id == block.id }) {
                                    blocks[i].field = newField
                                }
                            },
                            onRemove: {
                                blocks.removeAll { $0.id == block.id }
                                if selectedBlockID == block.id { selectedBlockID = nil }
                            }
                        )
                        .onDrag {
                            draggedBlock = block
                            return NSItemProvider(object: block.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: NameBlockDropDelegate(block: block, blocks: $blocks,
                                                                            draggedBlock: $draggedBlock))
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 6)
            }
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 16) {
                Button(action: addBlock) { Label("Add Block", systemImage: "plus.circle.fill") }
                    .disabled(blocks.count >= NameFormat.maxBlocks)
                Button(action: removeSelected) { Label("Remove Block", systemImage: "minus.circle.fill") }
                    .disabled(selectedBlockID == nil)
                Spacer()
                Button("Artist - Title - Album") {
                    blocks = NameFormat.standard.map { FormatBlock(field: $0) }
                    selectedBlockID = nil
                }
                .help("Put back the standard format")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Preview").foregroundStyle(.secondary)
                Text(NameFormat.preview(fields, ext: "mp3")).monospaced()
                Text(NameFormat.preview(fields, ext: "mp4")).monospaced()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Finished") {
                    NameFormat.save(fields)
                    report("Name format saved: \(NameFormat.preview(fields, ext: "mp3"))", false)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                // Separators alone would name nothing.
                .disabled(!fields.contains { $0 != .separator })
            }
        }
        .padding(24)
        .frame(minWidth: 760)
        .onAppear { blocks = NameFormat.load().map { FormatBlock(field: $0) } }
    }

    private func addBlock() {
        let new = FormatBlock(field: .separator)
        if let id = selectedBlockID, let i = blocks.firstIndex(where: { $0.id == id }) {
            blocks.insert(new, at: i + 1)
        } else {
            blocks.append(new)
        }
        selectedBlockID = new.id
    }

    private func removeSelected() {
        guard let id = selectedBlockID else { return }
        blocks.removeAll { $0.id == id }
        selectedBlockID = nil
    }
}

/// One block: a menu of fields, a selection bar, and × to remove.
private struct NameBlockView: View {
    let block: FormatBlock
    let isSelected: Bool
    let onSelect: () -> Void
    let onFieldChange: (MetadataField) -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                Picker("", selection: Binding(get: { block.field },
                                              set: { onSelect(); onFieldChange($0) })) {
                    ForEach(MetadataField.allCases) { field in Text(field.rawValue).tag(field) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(minWidth: 110)
                Rectangle().fill(isSelected ? Color.accentColor : .clear).frame(height: 3)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2))
            .simultaneousGesture(TapGesture().onEnded { onSelect() })

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .red)
            }
            .buttonStyle(.plain)
            .help("Remove this block")
            .offset(x: 6, y: -6)
        }
    }
}

/// Drag a block onto another to move it there.
private struct NameBlockDropDelegate: DropDelegate {
    let block: FormatBlock
    @Binding var blocks: [FormatBlock]
    @Binding var draggedBlock: FormatBlock?

    func performDrop(info: DropInfo) -> Bool {
        draggedBlock = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedBlock, dragged.id != block.id,
              let from = blocks.firstIndex(where: { $0.id == dragged.id }),
              let to = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        withAnimation {
            blocks.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }
}
