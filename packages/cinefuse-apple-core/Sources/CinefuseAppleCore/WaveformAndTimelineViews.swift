import AVFoundation
import SwiftUI

/// Downsampled peak envelope for drawing a waveform (one max-abs value per bucket).
enum WaveformPeakLoader {
    /// Reads linear PCM via `AVAssetReader`, buckets by sample index. Caps CPU for very long files.
    static func loadPeaks(from url: URL, bucketCount: Int = 180) async throws -> [Float] {
        guard bucketCount > 1 else { return [] }
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            return placeholderPeaks(bucketCount: bucketCount)
        }

        let duration = try await asset.load(.duration)
        /// Rough estimate when not decoding sample-rate metadata (bucket indices still align visually).
        let estimatedSamples = max(1, Int(48_000.0 * duration.seconds))
        let maxSamplesToRead = min(estimatedSamples, 1_200_000)

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)
        guard reader.startReading() else {
            return placeholderPeaks(bucketCount: bucketCount)
        }

        var bucketMax = [Float](repeating: 0, count: bucketCount)
        var globalIndex = 0

        while globalIndex < maxSamplesToRead,
              let sampleBuffer = output.copyNextSampleBuffer()
        {
            defer { CMSampleBufferInvalidate(sampleBuffer) }
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var lengthAtOffset = 0
            var totalLength = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(
                block,
                atOffset: 0,
                lengthAtOffsetOut: &lengthAtOffset,
                totalLengthOut: &totalLength,
                dataPointerOut: &dataPointer
            ) == kCMBlockBufferNoErr,
                let dataPointer,
                totalLength > 0
            else { continue }

            let floatCount = totalLength / MemoryLayout<Float>.size
            let floats = dataPointer.withMemoryRebound(to: Float.self, capacity: floatCount) { $0 }
            let stepLimit = min(floatCount, maxSamplesToRead - globalIndex)
            for i in 0 ..< stepLimit {
                let g = globalIndex + i
                let b = min(bucketCount - 1, g * bucketCount / max(estimatedSamples, 1))
                let v = abs(floats[i])
                if v > bucketMax[b] {
                    bucketMax[b] = v
                }
            }
            globalIndex += stepLimit
        }

        let maxPeak = bucketMax.max() ?? 1
        if maxPeak < 1e-6 {
            return placeholderPeaks(bucketCount: bucketCount)
        }
        return bucketMax.map { min(1, $0 / maxPeak) }
    }

    private static func placeholderPeaks(bucketCount: Int) -> [Float] {
        (0 ..< bucketCount).map { index in
            0.15 + 0.85 * Float(sin(Double(index) * 0.31) * 0.5 + 0.5)
        }
    }
}

struct AudioWaveformWithPlayhead: View {
    let peaks: [Float]
    let progressFraction: Double
    let onSeekFraction: (Double) -> Void
    /// When false, waveform is display-only (e.g. timeline clip cards).
    var interactive: Bool = true

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let stack = ZStack(alignment: .leading) {
                Canvas { context, size in
                    guard !peaks.isEmpty else { return }
                    let barW = max(1, size.width / CGFloat(peaks.count) - 1)
                    for (i, peak) in peaks.enumerated() {
                        let x = CGFloat(i) / CGFloat(max(peaks.count - 1, 1)) * (size.width - barW)
                        let barH = max(2, CGFloat(peak) * size.height * 0.92)
                        let rect = CGRect(
                            x: x,
                            y: (size.height - barH) / 2,
                            width: barW,
                            height: barH
                        )
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: 1.5),
                            with: .color(CinefuseTokens.ColorRole.accent.opacity(0.35))
                        )
                    }
                }
                .allowsHitTesting(false)

                Rectangle()
                    .fill(CinefuseTokens.ColorRole.accent.opacity(0.28))
                    .frame(width: max(0, w * CGFloat(max(0, min(1, progressFraction)))))
                    .frame(maxHeight: .infinity, alignment: .center)

                Rectangle()
                    .fill(CinefuseTokens.ColorRole.accent)
                    .frame(width: 2)
                    .offset(x: max(0, min(w - 2, w * CGFloat(progressFraction) - 1)))
            }
            .contentShape(Rectangle())

            if interactive {
                stack.gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let x = value.location.x
                            guard w > 0 else { return }
                            onSeekFraction(Double(x / w))
                        }
                        .onEnded { value in
                            let x = value.location.x
                            guard w > 0 else { return }
                            onSeekFraction(Double(x / w))
                        }
                )
            } else {
                stack
            }
        }
    }
}

struct PlaybackTimelineScrubber: View {
    @ObservedObject var playback: EditorPlaybackState
    var onSeek: (Double) -> Void

    @State private var scrubFraction: Double?

    private var displayFraction: Double {
        if let scrubFraction {
            return scrubFraction
        }
        guard playback.durationSeconds > 0 else { return 0 }
        return min(1, max(0, playback.currentTimeSeconds / playback.durationSeconds))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CinefuseTokens.Spacing.xxs) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CinefuseTokens.ColorRole.borderSubtle.opacity(0.55))
                        .frame(height: 6)
                    Capsule()
                        .fill(CinefuseTokens.ColorRole.accent)
                        .frame(width: max(4, w * CGFloat(displayFraction)), height: 6)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard w > 0 else { return }
                            let f = Double(value.location.x / w)
                            scrubFraction = max(0, min(1, f))
                            onSeek(scrubFraction!)
                        }
                        .onEnded { _ in
                            scrubFraction = nil
                        }
                )
            }
            .frame(height: 14)
            HStack {
                Text(formatClock(playback.currentTimeSeconds))
                    .font(CinefuseTokens.Typography.nano)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                    .monospacedDigit()
                Spacer()
                Text(formatClock(playback.durationSeconds))
                    .font(CinefuseTokens.Typography.nano)
                    .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                    .monospacedDigit()
            }
        }
    }

    private func formatClock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Compact current / duration labels (no scrub slider).
struct PlaybackTimeLabels: View {
    @ObservedObject var playback: EditorPlaybackState

    var body: some View {
        HStack(spacing: CinefuseTokens.Spacing.xxs) {
            Text(Self.formatClock(playback.labelCurrentSeconds))
                .font(CinefuseTokens.Typography.nano)
                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                .monospacedDigit()
            Text("/")
                .font(CinefuseTokens.Typography.nano)
                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary.opacity(0.75))
            Text(Self.formatClock(playback.labelDurationSeconds))
                .font(CinefuseTokens.Typography.nano)
                .foregroundStyle(CinefuseTokens.ColorRole.textSecondary)
                .monospacedDigit()
        }
    }

    private static func formatClock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Whole-second duration as `m:ss` (matches preview clock labels).
enum CinefuseDurationFormatting {
    static func minutesSeconds(totalWholeSeconds: Int) -> String {
        let s = max(0, totalWholeSeconds)
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}

/// Yellow in/out trim handles (normalized `0...1` along media width).
struct PreviewTrimHandlesOverlay: View {
    @Binding var trimStartFraction: Double
    @Binding var trimEndFraction: Double
    var onDragEnded: () -> Void = {}

    private let minGap: Double = 0.02

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let h = geo.size.height
            let x0 = CGFloat(trimStartFraction) * w
            let x1 = CGFloat(trimEndFraction) * w
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.black.opacity(0.2))
                    .frame(width: max(0, x0))
                Rectangle()
                    .fill(Color.black.opacity(0.2))
                    .frame(width: max(0, w - x1))
                    .offset(x: x1)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.yellow.opacity(0.95))
                    .frame(width: 11, height: min(h, 132))
                    .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                    .offset(x: x0 - 5.5, y: (h - min(h, 132)) / 2)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let f = Double(value.location.x / w)
                                let c = min(1, max(0, f))
                                trimStartFraction = min(c, trimEndFraction - minGap)
                            }
                            .onEnded { _ in
                                onDragEnded()
                            }
                    )
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.yellow.opacity(0.95))
                    .frame(width: 11, height: min(h, 132))
                    .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                    .offset(x: x1 - 5.5, y: (h - min(h, 132)) / 2)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let f = Double(value.location.x / w)
                                let c = min(1, max(0, f))
                                trimEndFraction = max(c, trimStartFraction + minGap)
                            }
                            .onEnded { _ in
                                onDragEnded()
                            }
                    )
            }
        }
        .allowsHitTesting(true)
    }
}
