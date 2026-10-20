# DropMediaConverter — specification

**Tagline:** Drop videos, audio or images and convert them to common formats with simple presets and a progress list.

**Category:** Files & Conversion

**Inspired by (paid):** Permute ($15 one-time)

**Frameworks:** SwiftUI, AppKit, AVFoundation, ImageIO, UniformTypeIdentifiers, CoreGraphics

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: Permute by Chaotic Software is a drag and drop converter for video, audio and images, sold at about 15 dollars one-time with a strong rating and many mentions in Mac app roundups as the simple way to convert files without command line tools. Our free clean-room version supports the most common conversions using only system frameworks.

Feature set: A window with a large drop zone accepts any number of files. Each row shows a thumbnail, the file name, type, size, and a format picker appropriate to its type. Video outputs: MP4 H.264, MP4 HEVC, and MOV with presets of 1080p, 720p and original size. Audio outputs: M4A AAC, and WAV or AIFF. Image outputs: JPEG, PNG, HEIC and TIFF with a quality slider and optional maximum dimension. A Convert All button runs jobs with a progress bar per row, a cancel button, and a Reveal button when finished. Output goes next to the original or to a chosen folder, never overwriting existing files.

UI spec: A standard single window app with a toolbar, the drop zone as an empty state with the text drop files here, and a list once files are added. A bottom bar has the destination picker, the Convert All button, and a clear finished button. Settings are inline in a side popover per row for quality or preset. A Dock icon drop also adds files. Errors show as red text on a row with the reason.

Technical approach: For video and audio use AVAssetExportSession with presets such as AVAssetExportPresetHighestQuality, AVAssetExportPreset1920x1080, AVAssetExportPreset1280x720 and AVAssetExportPresetHEVCHighestQuality and AVAssetExportPresetAppleM4A for audio only, checking compatibility using the asset export presets compatible with. Observe export progress by polling the progress property on a timer or the states async sequence. For WAV and AIFF use AVAssetReader and AVAssetWriter with linear PCM output settings. For images load with CGImageSource, optionally create a thumbnail at the maximum size, and write with CGImageDestination using the destination type identifier from UniformTypeIdentifiers and a compression quality property. Handle the drop with the SwiftUI dropDestination for file URLs. A job queue limits concurrency to two with Swift concurrency task groups. Output names append the new extension and a counter if the file exists. The app is not sandboxed or uses user selected read write entitlement.

Edge cases and error handling: Unsupported inputs such as unusual codecs show an unsupported message rather than crashing. Files with no audio track skip the audio only presets. Cancel removes partial output files. Low disk space errors are surfaced from the export error. Large batches remain responsive because progress updates are throttled. Protected media is rejected with a clear reason. About 600 lines.
