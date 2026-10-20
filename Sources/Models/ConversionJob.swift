import AppKit
import AVFoundation
import Observation
import UniformTypeIdentifiers

/// Broad category of an input file, which decides the output formats it can offer.
enum MediaKind: String {
    case video = "Video", audio = "Audio", image = "Image", unknown = "Unknown"
}

/// Every output format the app can produce.
enum OutputFormat: String, CaseIterable, Identifiable {
    case mp4H264, mp4HEVC, mov, m4a, wav, aiff, jpeg, png, heic, tiff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mp4H264: return "MP4 (H.264)"
        case .mp4HEVC: return "MP4 (HEVC)"
        case .mov: return "MOV"
        case .m4a: return "M4A (AAC)"
        case .wav: return "WAV"
        case .aiff: return "AIFF"
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        }
    }

    var fileExtension: String {
        switch self {
        case .mp4H264, .mp4HEVC: return "mp4"
        case .mov: return "mov"
        case .m4a: return "m4a"
        case .wav: return "wav"
        case .aiff: return "aiff"
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .tiff: return "tiff"
        }
    }

    var isVideo: Bool { [.mp4H264, .mp4HEVC, .mov].contains(self) }
    var isAudio: Bool { [.m4a, .wav, .aiff].contains(self) }
    var isImage: Bool { [.jpeg, .png, .heic, .tiff].contains(self) }

    /// Image destination type for ImageIO.
    var imageType: UTType? {
        switch self {
        case .jpeg: return .jpeg
        case .png: return .png
        case .heic: return .heic
        case .tiff: return .tiff
        default: return nil
        }
    }

    /// Size presets this format supports (no 720p HEVC preset exists in AVFoundation).
    var presets: [VideoPreset] {
        guard isVideo else { return [] }
        return self == .mp4HEVC ? [.p1080, .original] : VideoPreset.allCases
    }

    static func formats(for kind: MediaKind, hasAudio: Bool) -> [OutputFormat] {
        switch kind {
        case .video: return [.mp4H264, .mp4HEVC, .mov] + (hasAudio ? [.m4a, .wav, .aiff] : [])
        case .audio: return [.m4a, .wav, .aiff]
        case .image: return [.jpeg, .png, .heic, .tiff]
        case .unknown: return []
        }
    }
}

/// Video size presets offered in the per-row settings popover.
enum VideoPreset: String, CaseIterable, Identifiable {
    case p1080 = "1080p", p720 = "720p", original = "Original Size"
    var id: String { rawValue }
}

/// Lifecycle of a single conversion row.
enum JobState: Equatable {
    case inspecting, ready, queued, converting, finished(URL), failed(String), cancelled

    var isActive: Bool { self == .queued || self == .converting }
    var isFinished: Bool { if case .finished = self { return true } else { return false } }
}

/// Immutable snapshot of a job's settings, handed to the conversion engine off the main actor.
struct ConversionSpec: Sendable {
    let source: URL
    let format: OutputFormat
    let preset: VideoPreset
    let quality: Double
    let maxDimension: Int
}

/// One dropped file plus its chosen output settings and live conversion state.
@Observable
final class ConversionJob: Identifiable {
    let id = UUID()
    let source: URL
    var kind: MediaKind = .unknown
    var hasAudio = false
    var fileSize: Int64 = 0
    var thumbnail: NSImage?
    var format: OutputFormat = .jpeg {
        didSet { if !format.presets.isEmpty && !format.presets.contains(preset) { preset = .p1080 } }
    }
    var preset: VideoPreset = .original
    var quality: Double = 0.85
    var maxDimension: Int = 0
    var state: JobState = .inspecting
    var progress: Double = 0
    @ObservationIgnored var cancelWork: (() -> Void)?

    init(source: URL) { self.source = source }

    var availableFormats: [OutputFormat] { OutputFormat.formats(for: kind, hasAudio: hasAudio) }

    var spec: ConversionSpec {
        ConversionSpec(source: source, format: format, preset: preset, quality: quality, maxDimension: maxDimension)
    }

    var subtitle: String {
        let size = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        return "\(kind.rawValue) · \(source.pathExtension.uppercased()) · \(size)"
    }
}
