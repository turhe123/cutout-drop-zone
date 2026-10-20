import AppKit
import UniformTypeIdentifiers

/// App state: the list of images, the background processing queue, and export / clipboard / drag-out actions.
@MainActor
@Observable
final class CutoutStore {
    static let shared = CutoutStore()
    static let dropTypes: [UTType] = [.fileURL, .image]
    nonisolated static var cacheDirectory: URL {
        (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("CutoutDropZone", isDirectory: true)
    }
    private nonisolated static var dragDirectory: URL { cacheDirectory.appendingPathComponent("Drag", isDirectory: true) }
    private nonisolated static var importDirectory: URL { cacheDirectory.appendingPathComponent("Imports", isDirectory: true) }

    var items: [CutoutItem] = []
    var selectedID: UUID?
    var batchTotal = 0
    var batchCompleted = 0
    var notice: String?
    var pickerColor = Prefs.customColor

    @ObservationIgnored private var pending: [CutoutItem] = []
    @ObservationIgnored private var queueTask: Task<Void, Never>?
    @ObservationIgnored private let worker = CutoutWorker()

    var selectedItem: CutoutItem? { items.first { $0.id == selectedID } }
    var isProcessing: Bool { batchTotal > 0 }

    // MARK: Adding images

    func add(urls: [URL]) {
        var files: [URL] = []
        for url in urls {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                                             options: [.skipsHiddenFiles])) ?? []
                files += children.sorted { $0.lastPathComponent < $1.lastPathComponent }.filter(Self.isImage)
            } else if !url.path.hasPrefix(Self.dragDirectory.path) {
                files.append(url)
            }
        }
        guard !files.isEmpty else { return }
        let newItems = files.map { url -> CutoutItem in
            let item = CutoutItem(url: url)
            if !Self.isImage(url) { item.status = .failed("Unsupported file type") }
            return item
        }
        items += newItems
        pending += newItems
        batchTotal += newItems.count
        if selectedID == nil { selectedID = newItems.first?.id }
        if queueTask == nil { queueTask = Task { await runQueue() } }
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .image]
        panel.message = "Choose images to cut out"
        if panel.runModal() == .OK { add(urls: panel.urls) }
    }

    /// Accepts file URLs from Finder and raw image data from browsers or other apps.
    nonisolated func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in CutoutStore.shared.add(urls: [url]) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                    guard let url else { return }
                    // The provided file is deleted when this closure returns, so keep a copy.
                    let folder = Self.importDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    let copy = folder.appendingPathComponent(url.lastPathComponent)
                    do {
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        try FileManager.default.copyItem(at: url, to: copy)
                        Task { @MainActor in CutoutStore.shared.add(urls: [copy]) }
                    } catch {}
                }
            }
        }
        return !providers.isEmpty
    }

    func remove(_ item: CutoutItem) {
        pending.removeAll { $0.id == item.id }
        items.removeAll { $0.id == item.id }
        if selectedID == item.id { selectedID = items.first?.id }
    }

    func removeAll() {
        pending.removeAll()
        items.removeAll()
        selectedID = nil
    }

    private nonisolated static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    // MARK: Processing

    private func runQueue() async {
        while !pending.isEmpty {
            let item = pending.removeFirst()
            defer { batchCompleted += 1 }
            guard item.status == .queued else { continue }
            item.status = .processing
            do {
                let original = try await worker.load(item.url)
                item.original = original
                guard let analysis = try? await worker.analyze(original) else {
                    item.status = .noSubject
                    continue
                }
                item.analysis = analysis
                item.allInstances = analysis.observation.allInstances
                item.selectedInstances = analysis.observation.allInstances
                item.needsRender = true
                await renderLoop(item)
                item.status = item.cutout == nil ? .failed(CutoutError.renderFailed.localizedDescription) : .done
            } catch {
                item.status = .failed(error.localizedDescription)
            }
        }
        batchTotal = 0
        batchCompleted = 0
        queueTask = nil
    }

    /// Re-composites after a per-item setting changes; rapid changes are coalesced.
    func rerender(_ item: CutoutItem) {
        item.needsRender = true
        guard !item.isRendering, item.analysis != nil else { return }
        Task { await renderLoop(item) }
    }

    private func renderLoop(_ item: CutoutItem) async {
        guard let original = item.original, let analysis = item.analysis else { return }
        item.isRendering = true
        while item.needsRender {
            item.needsRender = false
            if let result = try? await worker.render(original, analysis, item.renderOptions) {
                item.cutout = result.0
                item.cropRect = result.1
            }
        }
        item.isRendering = false
    }

    /// Clicking the preview includes or excludes the subject instance under the cursor.
    func toggleInstance(at point: CGPoint, in item: CutoutItem) {
        guard !item.showOriginal, item.allInstances.count > 1, let analysis = item.analysis else { return }
        let crop = item.cropRect
        let p = CGPoint(x: crop.minX + point.x * crop.width, y: crop.minY + point.y * crop.height)
        guard let index = CutoutEngine.instance(at: p, in: analysis.observation.instanceMask) else { return }
        if item.selectedInstances.contains(index) {
            guard item.selectedInstances.count > 1 else { notice = "At least one subject must stay selected."; return }
            item.selectedInstances.remove(index)
        } else {
            item.selectedInstances.insert(index)
        }
        rerender(item)
    }

    func applyPickerColor(_ color: CGColor) {
        pickerColor = color
        Prefs.customColor = color
        guard let item = selectedItem else { return }
        item.customColor = color
        item.background = .color
        rerender(item)
    }

    // MARK: Output

    /// The image to write for an item; JPEG output gets an opaque background.
    private func outputImage(for item: CutoutItem, format: ExportFormat) -> CGImage? {
        guard let image = item.cutout ?? item.original else { return nil }
        if format == .jpeg, item.cutout != nil, item.background == .transparent {
            return ImageWriter.flatten(image, on: CGColor(gray: 1, alpha: 1))
        }
        return image
    }

    func exportAll() {
        let ready = items.filter { $0.cutout != nil }
        guard !ready.isEmpty else { notice = "No cutouts to export yet."; return }
        guard let folder = resolveOutputFolder() else { return }
        let format = Prefs.exportFormat, suffix = Prefs.fileSuffix
        let jobs = ready.compactMap { item in outputImage(for: item, format: format).map { (item.name + suffix, $0) } }
        notice = "Exporting \(jobs.count) image(s)…"
        Task.detached(priority: .userInitiated) {
            var written: [URL] = []
            for (baseName, image) in jobs {
                let url = ImageWriter.uniqueURL(in: folder, baseName: baseName, ext: format.fileExtension)
                if (try? ImageWriter.write(image, as: format, to: url)) != nil { written.append(url) }
            }
            let failures = jobs.count - written.count
            let saved = written
            await MainActor.run {
                CutoutStore.shared.notice = "Exported \(saved.count) image(s)" + (failures > 0 ? ", \(failures) failed." : ".")
                if !saved.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(saved) }
            }
        }
    }

    private func resolveOutputFolder() -> URL? {
        var isDirectory: ObjCBool = false
        let path = Prefs.outputFolderPath
        if !path.isEmpty, FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        guard let url = Self.chooseFolder() else { return nil }
        UserDefaults.standard.set(url.path, forKey: Prefs.outputFolder)
        return url
    }

    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose where cutouts are saved"
        return panel.runModal() == .OK ? panel.url : nil
    }

    func copySelected() {
        guard let item = selectedItem, item.cutout != nil, let image = outputImage(for: item, format: .png),
              let png = ImageWriter.encode(image, as: .png) else { notice = "Nothing to copy yet."; return }
        let entry = NSPasteboardItem()
        entry.setData(png, forType: .png)
        if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation { entry.setData(tiff, forType: .tiff) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([entry])
        notice = "Copied \(item.name) to the clipboard."
    }

    /// Writes the cutout to a temporary file in Caches and hands it to the drag session.
    func dragProvider(for item: CutoutItem) -> NSItemProvider {
        let format = Prefs.exportFormat
        guard let image = outputImage(for: item, format: format),
              let data = ImageWriter.encode(image, as: format) else { return NSItemProvider() }
        let folder = Self.dragDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(item.name + Prefs.fileSuffix).appendingPathExtension(format.fileExtension)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url)
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        } catch {
            return NSItemProvider()
        }
    }
}
