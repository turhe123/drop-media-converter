import AppKit
import SwiftUI

/// App entry point: a single main window plus a Settings window.
@main
struct DropMediaConverterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = JobStore.shared

    var body: some Scene {
        Window("DropMediaConverter", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 680, minHeight: 420)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Files…") { store.presentOpenPanel() }.keyboardShortcut("o")
            }
            CommandGroup(after: .help) {
                Button("Support / Donate ❤️") { Support.openDonationPage() }
            }
        }

        Settings {
            SettingsView()
        }
    }
}

/// Receives files dropped on the Dock icon or opened with the app from Finder.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in JobStore.shared.add(urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
