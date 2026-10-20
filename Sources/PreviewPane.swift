import SwiftUI
import AppKit

/// Large before/after preview of the selected image with its per-image cutout controls.
struct PreviewPane: View {
    @Environment(CutoutStore.self) private var store
    let item: CutoutItem

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let image = item.displayImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .background(Checkerboard())
                        .overlay(GeometryReader { geo in
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { location in
                                    store.toggleInstance(at: CGPoint(x: location.x / geo.size.width,
                                                                     y: location.y / geo.size.height), in: item)
                                }
                                .onDrag { store.dragProvider(for: item) }
                        })
                        .shadow(color: .black.opacity(0.15), radius: 6)
                        .padding(24)
                } else if case .failed(let message) = item.status {
                    ContentUnavailableView("Can't Open Image", systemImage: "exclamationmark.triangle",
                                           description: Text(message))
                } else {
                    ProgressView("Removing background…")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if item.status == .noSubject {
                Label("No subject was found in this image. The original is kept.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .padding(.bottom, 8)
            }
            Divider()
            controls.padding(12)
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button(item.showOriginal ? "Showing Before" : "Showing After") { item.showOriginal.toggle() }
                .keyboardShortcut(.space, modifiers: [])
                .help("Toggle original and cutout (Space)")
                .frame(minWidth: 120)

            Picker("Background", selection: binding(\.background)) {
                ForEach(BackgroundMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .frame(width: 190)

            HStack(spacing: 6) {
                Text("Feather")
                Slider(value: binding(\.feather), in: 0...5, step: 0.5).frame(width: 110)
                Text(String(format: "%.1f px", item.feather)).monospacedDigit().frame(width: 46, alignment: .leading)
            }

            Toggle("Trim to subject", isOn: binding(\.trim))

            Spacer(minLength: 0)

            if item.allInstances.count > 1 {
                Text("Click a subject to include or exclude it")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(item.analysis == nil)
    }

    /// Binding that re-renders the cutout whenever a per-image setting changes.
    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<CutoutItem, T>) -> Binding<T> {
        Binding(get: { item[keyPath: keyPath] },
                set: { item[keyPath: keyPath] = $0; store.rerender(item) })
    }
}

/// Tiled grey/white checkerboard used to visualize transparency.
struct Checkerboard: View {
    private static let tile: NSImage = {
        let size: CGFloat = 16
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            NSColor(white: 1, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: size, height: size).fill()
            NSColor(white: 0.82, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: size / 2, height: size / 2).fill()
            NSRect(x: size / 2, y: size / 2, width: size / 2, height: size / 2).fill()
            return true
        }
    }()

    var body: some View {
        Image(nsImage: Self.tile).resizable(resizingMode: .tile)
    }
}
