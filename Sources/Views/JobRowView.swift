import SwiftUI

/// One row of the job list: thumbnail, file info, format picker, settings popover and status actions.
struct JobRowView: View {
    @Bindable var job: ConversionJob
    @Environment(JobStore.self) private var store
    @State private var showSettings = false

    private var isLocked: Bool { job.state.isActive || job.state == .inspecting }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image = job.thumbnail {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(job.source.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(job.subtitle).font(.caption).foregroundStyle(.secondary)
                status
            }
            Spacer(minLength: 8)

            if !job.availableFormats.isEmpty {
                Picker("Format", selection: $job.format) {
                    ForEach(job.availableFormats) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 130)
                .disabled(isLocked)

                Button { showSettings.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.borderless)
                    .help("Quality and size options")
                    .disabled(isLocked || job.format.isAudio)
                    .popover(isPresented: $showSettings, arrowEdge: .trailing) { JobSettingsView(job: job) }
            }
            actions.frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var status: some View {
        switch job.state {
        case .inspecting: Text("Reading…").font(.caption).foregroundStyle(.secondary)
        case .ready: EmptyView()
        case .queued: Text("Waiting…").font(.caption).foregroundStyle(.secondary)
        case .converting: ProgressView(value: job.progress).progressViewStyle(.linear).frame(maxWidth: 260)
        case .finished(let url): Text("Saved as \(url.lastPathComponent)").font(.caption).foregroundStyle(.green)
        case .failed(let reason): Text(reason).font(.caption).foregroundStyle(.red).lineLimit(2)
        case .cancelled: Text("Cancelled").font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var actions: some View {
        if job.state.isActive {
            Button("Cancel") { store.cancel(job) }
        } else if job.state.isFinished {
            Button("Reveal") { store.reveal(job) }
        } else {
            Button { store.remove(job) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove from list")
        }
    }
}

/// Per-row popover with the video size preset or the image quality / maximum dimension.
struct JobSettingsView: View {
    @Bindable var job: ConversionJob

    var body: some View {
        Form {
            if job.format.isVideo {
                Picker("Size", selection: $job.preset) {
                    ForEach(job.format.presets) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.radioGroup)
            } else if job.format.isImage {
                if job.format == .png || job.format == .tiff {
                    Text("\(job.format.title) is lossless.").font(.caption).foregroundStyle(.secondary)
                } else {
                    LabeledContent("Quality") {
                        HStack {
                            Slider(value: $job.quality, in: 0.1...1)
                            Text("\(Int(job.quality * 100))%").monospacedDigit().frame(width: 40)
                        }
                    }
                }
                Picker("Max size", selection: $job.maxDimension) {
                    Text("Original").tag(0)
                    ForEach([4096, 2048, 1600, 1024, 512], id: \.self) { Text("\($0) px").tag($0) }
                }
            }
        }
        .padding()
        .frame(width: 300)
    }
}
