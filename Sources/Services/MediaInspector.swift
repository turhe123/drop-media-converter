import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Classifies input files, reads their size and builds a small row thumbnail.
enum MediaInspector {
    struct Info {
        var kind: MediaKind
        var hasAudio: Bool
        var size: Int64
        var thumbnail: NSImage?
        var problem: String?
    }

    static func inspect(_ url: URL) async -> Info {
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
        var info = Info(kind: .unknown, hasAudio: false, size: Int64(values?.fileSize ?? 0), thumbnail: nil)

        if type.conforms(to: .image) {
            info.kind = .image
            info.thumbnail = imageThumbnail(url)
            if info.thumbnail == nil { info.problem = "Unsupported image format." }
        } else if type.conforms(to: .audiovisualContent) {
            let asset = AVURLAsset(url: url)
            do {
                if try await asset.load(.hasProtectedContent) {
                    info.problem = "Protected (DRM) media cannot be converted."
                }
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                info.hasAudio = !audioTracks.isEmpty
                info.kind = videoTracks.isEmpty ? .audio : .video
                if videoTracks.isEmpty && audioTracks.isEmpty { info.problem = "No audio or video tracks found." }
                if info.kind == .video { info.thumbnail = await videoThumbnail(asset) }
            } catch {
                info.problem = "Unsupported media: \(error.localizedDescription)"
            }
        } else {
            info.problem = "Unsupported file type."
        }
        if info.thumbnail == nil { info.thumbnail = NSWorkspace.shared.icon(forFile: url.path) }
        return info
    }

    private static func imageThumbnail(_ url: URL) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(src) > 0 else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 96,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }

    private static func videoThumbnail(_ asset: AVAsset) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 96, height: 96)
        guard let result = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)) else { return nil }
        return NSImage(cgImage: result.image, size: .zero)
    }
}
