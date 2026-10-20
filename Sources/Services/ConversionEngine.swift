import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// User-facing conversion failures.
enum ConversionError: LocalizedError {
    case unsupported(String), noAudio, protected, failed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let why): return "Unsupported: \(why)"
        case .noAudio: return "This file has no audio track."
        case .protected: return "Protected (DRM) media cannot be converted."
        case .failed(let why): return why
        }
    }

    /// Turns any thrown error into a short reason for the row, calling out low disk space explicitly.
    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        if ns.code == NSFileWriteOutOfSpaceError || underlying?.code == NSFileWriteOutOfSpaceError
            || ns.code == AVError.diskFull.rawValue && ns.domain == AVFoundationErrorDomain {
            return "Not enough disk space to write the output file."
        }
        if let reason = ns.localizedFailureReason, !reason.isEmpty {
            return "\(ns.localizedDescription) \(reason)"
        }
        return error.localizedDescription
    }
}

/// Performs a single conversion with AVFoundation (video/audio) or ImageIO (images).
enum ConversionEngine {
    typealias Progress = @Sendable (Double) -> Void

    static func convert(_ spec: ConversionSpec, to output: URL, progress: @escaping Progress) async throws {
        do {
            switch spec.format {
            case .jpeg, .png, .heic, .tiff:
                try convertImage(spec, to: output)
                progress(1)
            case .wav, .aiff:
                try await convertToPCM(spec, to: output, progress: progress)
            default:
                try await export(spec, to: output, progress: progress)
            }
        } catch {
            try? FileManager.default.removeItem(at: output)   // never leave partial files behind
            throw error
        }
    }

    // MARK: AVAssetExportSession (MP4 / MOV / M4A)

    private static func presetName(for spec: ConversionSpec) -> String {
        switch (spec.format, spec.preset) {
        case (.m4a, _): return AVAssetExportPresetAppleM4A
        case (.mp4HEVC, .original): return AVAssetExportPresetHEVCHighestQuality
        case (.mp4HEVC, _): return AVAssetExportPresetHEVC1920x1080
        case (_, .p1080): return AVAssetExportPreset1920x1080
        case (_, .p720): return AVAssetExportPreset1280x720
        default: return AVAssetExportPresetHighestQuality
        }
    }

    private static func export(_ spec: ConversionSpec, to output: URL, progress: @escaping Progress) async throws {
        let asset = AVURLAsset(url: spec.source)
        try await validate(asset, needsAudio: spec.format.isAudio)
        let preset = presetName(for: spec)
        let fileType: AVFileType = spec.format == .mov ? .mov : spec.format == .m4a ? .m4a : .mp4

        guard await AVAssetExportSession.compatibility(ofExportPreset: preset, with: asset, outputFileType: fileType),
              let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ConversionError.unsupported("\(spec.format.title) is not available for this file's codec.")
        }
        session.outputURL = output
        session.outputFileType = fileType
        session.shouldOptimizeForNetworkUse = true

        let poller = Task {
            while !Task.isCancelled {
                progress(Double(session.progress))
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { poller.cancel() }
        await withTaskCancellationHandler {
            await session.export()
        } onCancel: {
            session.cancelExport()
        }
        switch session.status {
        case .completed: progress(1)
        case .cancelled: throw CancellationError()
        default: throw session.error ?? ConversionError.failed("Export failed for an unknown reason.")
        }
    }

    private static func validate(_ asset: AVURLAsset, needsAudio: Bool) async throws {
        if try await asset.load(.hasProtectedContent) { throw ConversionError.protected }
        let (exportable, readable) = try await asset.load(.isExportable, .isReadable)
        guard exportable || readable else {
            throw ConversionError.unsupported("this media cannot be read by AVFoundation.")
        }
        if needsAudio, try await asset.loadTracks(withMediaType: .audio).isEmpty { throw ConversionError.noAudio }
    }

    // MARK: AVAssetReader → AVAssetWriter (WAV / AIFF)

    private static func convertToPCM(_ spec: ConversionSpec, to output: URL, progress: @escaping Progress) async throws {
        let asset = AVURLAsset(url: spec.source)
        try await validate(asset, needsAudio: true)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw ConversionError.noAudio }
        let duration = try await asset.load(.duration).seconds

        var sampleRate = 44_100.0, channels = 2
        if let desc = try await track.load(.formatDescriptions).first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
            if asbd.mSampleRate > 0 { sampleRate = asbd.mSampleRate }
            channels = max(1, min(2, Int(asbd.mChannelsPerFrame)))
        }
        let pcm: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: spec.format == .aiff,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: pcm)
        guard reader.canAdd(readerOutput) else { throw ConversionError.unsupported("cannot decode this audio codec.") }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: output, fileType: spec.format == .aiff ? .aiff : .wav)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: pcm)
        guard writer.canAdd(input) else { throw ConversionError.unsupported("cannot write \(spec.format.title).") }
        writer.add(input)

        guard reader.startReading() else { throw reader.error ?? ConversionError.failed("Could not read audio.") }
        guard writer.startWriting() else { throw writer.error ?? ConversionError.failed("Could not write audio.") }
        writer.startSession(atSourceTime: .zero)

        var lastReport = Date.distantPast
        while true {
            if Task.isCancelled {
                reader.cancelReading()
                writer.cancelWriting()
                throw CancellationError()
            }
            if !input.isReadyForMoreMediaData {
                try? await Task.sleep(for: .milliseconds(5))
                continue
            }
            guard let buffer = readerOutput.copyNextSampleBuffer() else { break }
            guard input.append(buffer) else { break }
            if duration > 0, Date().timeIntervalSince(lastReport) > 0.2 {   // throttle UI updates
                lastReport = Date()
                progress(min(1, CMSampleBufferGetPresentationTimeStamp(buffer).seconds / duration))
            }
        }
        input.markAsFinished()
        if reader.status == .failed || writer.status == .failed {
            writer.cancelWriting()
            throw writer.error ?? reader.error ?? ConversionError.failed("Audio conversion failed.")
        }
        await writer.finishWriting()
        if writer.status != .completed {
            throw writer.error ?? ConversionError.failed("Audio conversion failed.")
        }
        progress(1)
    }

    // MARK: ImageIO (JPEG / PNG / HEIC / TIFF)

    private static func convertImage(_ spec: ConversionSpec, to output: URL) throws {
        guard let type = spec.format.imageType,
              let source = CGImageSourceCreateWithURL(spec.source as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw ConversionError.unsupported("this image cannot be decoded.")
        }
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        let image: CGImage?
        if spec.maxDimension > 0 {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: spec.maxDimension,
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
            properties[kCGImagePropertyOrientation] = 1   // transform already applied
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image else { throw ConversionError.unsupported("this image cannot be decoded.") }
        guard let dest = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConversionError.unsupported("\(spec.format.title) encoding is not available on this Mac.")
        }
        properties[kCGImageDestinationLossyCompressionQuality] = spec.quality
        properties.removeValue(forKey: kCGImagePropertyPixelWidth)
        properties.removeValue(forKey: kCGImagePropertyPixelHeight)
        CGImageDestinationAddImage(dest, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ConversionError.failed("Could not write the image (check disk space and permissions).")
        }
    }
}
