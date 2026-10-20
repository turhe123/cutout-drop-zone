import SwiftUI
import AppKit

/// Application entry point: owns the single main window, menu commands and the Settings scene.
@main
struct CutoutDropZoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = CutoutStore.shared

    init() { Prefs.registerDefaults() }

    var body: some Scene {
        Window("CutoutDropZone", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 860, minHeight: 540)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Files…") { store.presentOpenPanel() }.keyboardShortcut("o")
                Button("Export All") { store.exportAll() }.keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Copy Cutout") { store.copySelected() }.keyboardShortcut("c", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Support / Donate ❤️") { Support.open() }
            }
        }

        Settings { SettingsView() }
    }
}

/// Receives images dropped on the Dock icon or opened from Finder and forwards them to the store.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Drag-out files from earlier sessions are no longer needed.
        try? FileManager.default.removeItem(at: CutoutStore.cacheDirectory)
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        Task { @MainActor in CutoutStore.shared.add(urls: urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Opens the project's donation page.
enum Support {
    static func open() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}
