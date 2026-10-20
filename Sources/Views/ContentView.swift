import AppKit
import SwiftUI

/// Opens the project's donation page.
enum Support {
    static func openDonationPage() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}

/// Main window: drop zone / job list on top, destination + actions in the bottom bar.
struct ContentView: View {
    @Environment(JobStore.self) private var store
    @AppStorage("destinationPath") private var destinationPath = ""
    @State private var isTargeted = false

    private var destinationURL: URL? {
        destinationPath.isEmpty ? nil : URL(fileURLWithPath: destinationPath, isDirectory: true)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if store.jobs.isEmpty {
                    DropZoneView(isTargeted: isTargeted)
                } else {
                    List(store.jobs) { job in
                        JobRowView(job: job)
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                    .overlay {
                        if isTargeted {
                            RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: 3).padding(4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dropDestination(for: URL.self) { urls, _ in
                store.add(urls.filter(\.isFileURL))
                return true
            } isTargeted: { isTargeted = $0 }

            Divider()
            bottomBar
        }
        .toolbar {
            ToolbarItem {
                Button { store.presentOpenPanel() } label: { Label("Add Files…", systemImage: "plus") }
                    .help("Add files or folders to convert")
            }
            ToolbarItem {
                Button("Support / Donate ❤️") { Support.openDonationPage() }
                    .help("Support development on Ko-fi")
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Text("Save to:").foregroundStyle(.secondary)
            Menu {
                Button("Next to Original") { destinationPath = "" }
                Button("Choose Folder…") { chooseFolder() }
            } label: {
                Label(destinationURL?.lastPathComponent ?? "Next to Original",
                      systemImage: destinationURL == nil ? "arrow.turn.down.right" : "folder")
            }
            .fixedSize()
            .help(destinationURL?.path ?? "Output is written beside each original file")

            Spacer()
            Button("Clear Finished") { store.clearFinished() }
                .disabled(!store.hasFinishedJobs)
            Button {
                store.convertAll(destination: destinationURL)
            } label: {
                if store.isRunning {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Converting…") }
                } else {
                    Text("Convert All")
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(store.isRunning || !store.hasPendingJobs)
        }
        .padding(12)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { destinationPath = url.path }
    }
}

/// Empty-state drop target shown before any files are added.
struct DropZoneView: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            Text("Drop files here").font(.title2.weight(.semibold))
            Text("Videos, audio and images — or whole folders.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
                .background(RoundedRectangle(cornerRadius: 16).fill(isTargeted ? Color.accentColor.opacity(0.08) : .clear))
                .padding(20)
        }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}
