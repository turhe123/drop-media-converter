import AppKit
import Observation

/// Owns the list of jobs, runs them with a concurrency limit of two and picks non-clashing output names.
@MainActor
@Observable
final class JobStore {
    static let shared = JobStore()
    static let maxConcurrent = 2

    private(set) var jobs: [ConversionJob] = []
    private(set) var isRunning = false
    @ObservationIgnored private var reservedOutputs: Set<String> = []

    var hasPendingJobs: Bool { jobs.contains { [.ready, .cancelled].contains($0.state) || isRetryable($0) } }
    var hasFinishedJobs: Bool { jobs.contains { $0.state.isFinished || $0.state == .cancelled } }

    // MARK: Adding files

    func add(_ urls: [URL]) {
        let existing = Set(jobs.map(\.source.standardizedFileURL))
        let files = urls.flatMap(expand).filter { !existing.contains($0.standardizedFileURL) }
        for url in files {
            let job = ConversionJob(source: url)
            jobs.append(job)
            Task { await inspect(job) }
        }
    }

    /// Expands dropped folders into the regular, non-hidden files they contain.
    private func expand(_ url: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        guard isDir.boolValue else { return [url] }
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        return walker.compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: Set(keys)).isRegularFile) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func inspect(_ job: ConversionJob) async {
        let info = await MediaInspector.inspect(job.source)
        job.kind = info.kind
        job.hasAudio = info.hasAudio
        job.fileSize = info.size
        job.thumbnail = info.thumbnail
        let defaults = UserDefaults.standard
        job.quality = defaults.object(forKey: "defaultImageQuality") as? Double ?? 0.85
        job.maxDimension = defaults.integer(forKey: "defaultMaxDimension")
        job.format = job.availableFormats.first ?? .jpeg
        if let raw = defaults.string(forKey: "defaultVideoPreset"), let preset = VideoPreset(rawValue: raw),
           job.format.presets.contains(preset) {
            job.preset = preset
        }
        job.state = info.problem.map { .failed($0) } ?? .ready
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.audiovisualContent, .image, .folder]
        if panel.runModal() == .OK { add(panel.urls) }
    }

    // MARK: Running

    /// Converts every ready (or previously failed/cancelled) job, two at a time.
    func convertAll(destination: URL?) {
        guard !isRunning else { return }
        let pending = jobs.filter { $0.state == .ready || $0.state == .cancelled || isRetryable($0) }
        guard !pending.isEmpty else { return }
        pending.forEach { $0.state = .queued; $0.progress = 0 }
        isRunning = true
        Task {
            await withTaskGroup(of: Void.self) { group in
                var iterator = pending.makeIterator()
                for _ in 0..<Self.maxConcurrent {
                    guard let job = iterator.next() else { break }
                    group.addTask { await self.run(job, destination: destination) }
                }
                while await group.next() != nil {
                    guard let job = iterator.next() else { continue }
                    group.addTask { await self.run(job, destination: destination) }
                }
            }
            isRunning = false
        }
    }

    /// A failed job is retryable only if it failed during conversion, not because the input is unsupported.
    private func isRetryable(_ job: ConversionJob) -> Bool {
        if case .failed = job.state { return job.kind != .unknown && !job.availableFormats.isEmpty }
        return false
    }

    private func run(_ job: ConversionJob, destination: URL?) async {
        guard job.state == .queued else { return }   // cancelled while waiting
        let output = reserveOutputURL(for: job, in: destination ?? job.source.deletingLastPathComponent())
        defer { reservedOutputs.remove(output.path) }
        job.state = .converting
        let spec = job.spec
        let work = Task.detached(priority: .userInitiated) { () -> Result<Void, Error> in
            do {
                try await ConversionEngine.convert(spec, to: output) { value in
                    Task { @MainActor in if job.state == .converting { job.progress = value } }
                }
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        job.cancelWork = { work.cancel() }
        let result = await work.value
        job.cancelWork = nil
        switch result {
        case .success:
            job.progress = 1
            job.state = .finished(output)
        case .failure(let error):
            if error is CancellationError || job.state == .cancelled {
                job.state = .cancelled
            } else {
                job.state = .failed(ConversionError.describe(error))
            }
        }
    }

    func cancel(_ job: ConversionJob) {
        guard job.state.isActive else { return }
        job.state = .cancelled
        job.progress = 0
        job.cancelWork?()
    }

    /// Picks `name.ext`, then `name 2.ext`, `name 3.ext`… so nothing on disk (or in flight) is overwritten.
    private func reserveOutputURL(for job: ConversionJob, in folder: URL) -> URL {
        let base = job.source.deletingPathExtension().lastPathComponent
        let ext = job.format.fileExtension
        var counter = 1
        while true {
            let name = counter == 1 ? "\(base).\(ext)" : "\(base) \(counter).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) && !reservedOutputs.contains(candidate.path) {
                reservedOutputs.insert(candidate.path)
                return candidate
            }
            counter += 1
        }
    }

    // MARK: Row actions

    func reveal(_ job: ConversionJob) {
        if case .finished(let url) = job.state { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func remove(_ job: ConversionJob) {
        guard !job.state.isActive else { return }
        jobs.removeAll { $0.id == job.id }
    }

    func clearFinished() {
        jobs.removeAll { $0.state.isFinished || $0.state == .cancelled }
    }
}
