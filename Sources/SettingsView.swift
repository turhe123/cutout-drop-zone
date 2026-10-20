import SwiftUI

/// Settings window: export defaults, output folder, defaults for new images, and the support link.
struct SettingsView: View {
    @AppStorage(Prefs.format) private var format: ExportFormat = .png
    @AppStorage(Prefs.outputFolder) private var outputFolder = ""
    @AppStorage(Prefs.suffix) private var suffix = "-cutout"
    @AppStorage(Prefs.feather) private var feather = 0.0
    @AppStorage(Prefs.background) private var background: BackgroundMode = .transparent
    @AppStorage(Prefs.trim) private var trim = false

    var body: some View {
        Form {
            Section("Export") {
                Picker("Default format", selection: $format) {
                    ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Output folder") {
                    HStack {
                        Text(outputFolder.isEmpty ? "Ask on first export" : (outputFolder as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…") { if let url = CutoutStore.chooseFolder() { outputFolder = url.path } }
                        if !outputFolder.isEmpty { Button("Reset") { outputFolder = "" } }
                    }
                }
                TextField("File name suffix", text: $suffix)
                Text("Originals are never overwritten; a counter is added if a name is taken.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Defaults for new images") {
                Picker("Background", selection: $background) {
                    ForEach(BackgroundMode.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Feather") {
                    HStack {
                        Slider(value: $feather, in: 0...5, step: 0.5)
                        Text(String(format: "%.1f px", feather)).monospacedDigit().frame(width: 46)
                    }
                }
                Toggle("Trim to subject bounds", isOn: $trim)
            }

            Section {
                HStack {
                    Text("CutoutDropZone is free, open source and fully offline.")
                    Spacer()
                    Button("Support / Donate ❤️") { Support.open() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}
