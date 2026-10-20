import SwiftUI

/// Preferences: defaults applied to newly added files, plus the support link.
struct SettingsView: View {
    @AppStorage("defaultImageQuality") private var imageQuality = 0.85
    @AppStorage("defaultMaxDimension") private var maxDimension = 0
    @AppStorage("defaultVideoPreset") private var videoPreset = VideoPreset.original.rawValue

    var body: some View {
        Form {
            Section("Defaults for new files") {
                Picker("Video size", selection: $videoPreset) {
                    ForEach(VideoPreset.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                LabeledContent("Image quality") {
                    HStack {
                        Slider(value: $imageQuality, in: 0.1...1)
                        Text("\(Int(imageQuality * 100))%").monospacedDigit().frame(width: 40)
                    }
                }
                Picker("Image max size", selection: $maxDimension) {
                    Text("Original").tag(0)
                    ForEach([4096, 2048, 1600, 1024, 512], id: \.self) { Text("\($0) px").tag($0) }
                }
            }
            Section {
                HStack {
                    Text("DropMediaConverter is free and open source.")
                    Spacer()
                    Button("Support / Donate ❤️") { Support.openDonationPage() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
