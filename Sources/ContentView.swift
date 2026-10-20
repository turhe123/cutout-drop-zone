import SwiftUI
import AppKit

/// Main window: drop zone and thumbnail list on the left, preview with per-image controls on the right.
struct ContentView: View {
    @Environment(CutoutStore.self) private var store
    @State private var detailTargeted = false

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 380)
        } detail: {
            Group {
                if let item = store.selectedItem {
                    PreviewPane(item: item)
                } else {
                    DropZone(isTargeted: detailTargeted).padding(32)
                }
            }
            .onDrop(of: CutoutStore.dropTypes, isTargeted: $detailTargeted) { store.handleDrop($0) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { store.presentOpenPanel() } label: { Label("Add Files", systemImage: "plus") }
                    .help("Add images (⌘O)")
                Button { store.exportAll() } label: { Label("Export All", systemImage: "square.and.arrow.down.on.square") }
                    .help("Save every cutout to the output folder")
                    .disabled(!store.items.contains { $0.cutout != nil })
                Button { store.copySelected() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .help("Copy the selected cutout to the clipboard")
                    .disabled(store.selectedItem?.cutout == nil)
                ColorPicker("Background Color", selection: Binding(
                    get: { Color(cgColor: store.pickerColor) },
                    set: { store.applyPickerColor(NSColor($0).cgColor) }
                ), supportsOpacity: false)
                .help("Apply a solid background color to the selected image")
            }
        }
    }
}

/// Left column: compact drop zone, thumbnail list and batch status.
struct Sidebar: View {
    @Environment(CutoutStore.self) private var store
    @State private var zoneTargeted = false
    @State private var listTargeted = false

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            DropZone(isTargeted: zoneTargeted, compact: true)
                .frame(height: 96)
                .padding(10)
                .onDrop(of: CutoutStore.dropTypes, isTargeted: $zoneTargeted) { store.handleDrop($0) }

            List(selection: $store.selectedID) {
                ForEach(store.items) { item in
                    ItemRow(item: item)
                        .tag(item.id)
                        .onDrag { store.dragProvider(for: item) }
                        .contextMenu {
                            Button("Copy Cutout") { store.selectedID = item.id; store.copySelected() }
                            Button("Show Original in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                            Divider()
                            Button("Remove") { store.remove(item) }
                            Button("Remove All") { store.removeAll() }
                        }
                }
            }
            .onDrop(of: CutoutStore.dropTypes, isTargeted: $listTargeted) { store.handleDrop($0) }

            Divider()
            VStack(alignment: .leading, spacing: 6) {
                if store.isProcessing {
                    ProgressView(value: Double(store.batchCompleted), total: Double(max(store.batchTotal, 1))) {
                        Text("Processing \(min(store.batchCompleted + 1, store.batchTotal)) of \(store.batchTotal)…")
                            .font(.caption)
                    }
                }
                if let notice = store.notice {
                    Text(notice).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Button("Support / Donate ❤️") { Support.open() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }
}

/// Dashed "Drop images here" target; clicking it opens the file picker.
struct DropZone: View {
    @Environment(CutoutStore.self) private var store
    var isTargeted: Bool
    var compact = false

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.6),
                                  style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            )
            .overlay {
                VStack(spacing: compact ? 4 : 10) {
                    Image(systemName: "photo.badge.plus").font(.system(size: compact ? 22 : 44))
                    Text("Drop images here").font(compact ? .headline : .title2.weight(.semibold))
                    Text("PNG, JPEG, HEIC, TIFF — or click to choose").font(.caption).foregroundStyle(.secondary)
                }
                .foregroundStyle(isTargeted ? Color.accentColor : Color.primary)
            }
            .contentShape(Rectangle())
            .onTapGesture { store.presentOpenPanel() }
    }
}

/// One thumbnail row with name and processing status.
struct ItemRow: View {
    let item: CutoutItem

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Checkerboard()
                if let image = item.displayImage {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                statusLabel.font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            badge
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var statusLabel: some View {
        switch item.status {
        case .queued: Text("Waiting…")
        case .processing: Text("Removing background…")
        case .done: Text(item.allInstances.count == 1 ? "1 subject" : "\(item.selectedInstances.count) of \(item.allInstances.count) subjects")
        case .noSubject: Text("No subject found — original kept")
        case .failed(let message): Text(message)
        }
    }

    @ViewBuilder private var badge: some View {
        switch item.status {
        case .processing: ProgressView().controlSize(.small)
        case .noSubject: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow).help("No subject found")
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        default: EmptyView()
        }
    }
}
