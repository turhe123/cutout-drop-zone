import AppKit
import UniformTypeIdentifiers

/// Replacement background composited behind a cutout.
enum BackgroundMode: String, CaseIterable, Identifiable {
    case transparent, white, black, color

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    func cgColor(custom: CGColor) -> CGColor? {
        switch self {
        case .transparent: nil
        case .white: CGColor(gray: 1, alpha: 1)
        case .black: CGColor(gray: 0, alpha: 1)
        case .color: custom
        }
    }
}

/// File format used when exporting, copying or dragging cutouts.
enum ExportFormat: String, CaseIterable, Identifiable {
    case png, jpeg

    var id: String { rawValue }
    var title: String { self == .png ? "PNG (transparent)" : "JPEG (with background)" }
    var fileExtension: String { self == .png ? "png" : "jpg" }
    var utType: UTType { self == .png ? .png : .jpeg }
}

/// UserDefaults keys and typed accessors for app preferences (shared with `@AppStorage`).
enum Prefs {
    static let format = "exportFormat"
    static let outputFolder = "outputFolder"
    static let feather = "defaultFeather"
    static let background = "defaultBackground"
    static let trim = "trimToBounds"
    static let suffix = "fileSuffix"
    static let color = "customColorHex"

    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            format: ExportFormat.png.rawValue, outputFolder: "", feather: 0.0,
            background: BackgroundMode.transparent.rawValue, trim: false,
            suffix: "-cutout", color: "#3B82F6",
        ])
    }

    static var exportFormat: ExportFormat { ExportFormat(rawValue: defaults.string(forKey: format) ?? "") ?? .png }
    static var outputFolderPath: String { defaults.string(forKey: outputFolder) ?? "" }
    static var defaultFeather: Double { min(max(defaults.double(forKey: feather), 0), 5) }
    static var defaultBackground: BackgroundMode { BackgroundMode(rawValue: defaults.string(forKey: background) ?? "") ?? .transparent }
    static var trimToBounds: Bool { defaults.bool(forKey: trim) }
    static var fileSuffix: String { defaults.string(forKey: suffix) ?? "-cutout" }
    static var customColor: CGColor {
        get { CGColor.fromHex(defaults.string(forKey: color) ?? "") ?? CGColor(srgbRed: 0.23, green: 0.51, blue: 0.96, alpha: 1) }
        set { defaults.set(newValue.hexString, forKey: color) }
    }
}

/// One dropped image: its processing status, analysis, per-image settings and latest rendered cutout.
@Observable
final class CutoutItem: Identifiable {
    /// Processing state shown in the thumbnail list.
    enum Status: Equatable {
        case queued, processing, done, noSubject
        case failed(String)
    }

    let id = UUID()
    let url: URL
    var status: Status = .queued
    var original: CGImage?
    var cutout: CGImage?
    /// Visible region of `cutout` inside the original, normalized with a top-left origin.
    var cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    var background = Prefs.defaultBackground
    var customColor = Prefs.customColor
    var feather = Prefs.defaultFeather
    var trim = Prefs.trimToBounds
    var showOriginal = false
    var allInstances = IndexSet()
    var selectedInstances = IndexSet()

    @ObservationIgnored var analysis: SubjectAnalysis?
    @ObservationIgnored var needsRender = false
    @ObservationIgnored var isRendering = false

    init(url: URL) { self.url = url }

    var name: String { url.deletingPathExtension().lastPathComponent }
    var displayImage: CGImage? { showOriginal ? original : (cutout ?? original) }

    var renderOptions: RenderOptions {
        RenderOptions(background: background.cgColor(custom: customColor), feather: feather,
                      trim: trim, instances: selectedInstances)
    }
}

extension CGColor {
    static func fromHex(_ hex: String) -> CGColor? {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        guard let c = NSColor(cgColor: self)?.usingColorSpace(.sRGB) else { return "#000000" }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}
