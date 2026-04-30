import AVFoundation
import Combine
import Foundation

/// Shared playback position for editor preview + timeline clip overlays (video / audio).
@MainActor
final class EditorPlaybackState: ObservableObject {
    /// Absolute position within the current `AVPlayerItem` (full asset timeline).
    @Published private(set) var currentTimeSeconds: Double = 0
    /// Full asset duration for the current item (same scale as ``currentTimeSeconds``).
    @Published private(set) var durationSeconds: Double = 0
    /// Trim-window-relative time for preview labels (0 … trim span).
    @Published private(set) var labelCurrentSeconds: Double = 0
    /// Length of the active trim window in seconds (for preview labels).
    @Published private(set) var labelDurationSeconds: Double = 0
    @Published private(set) var activeShotId: String?
    @Published private(set) var isPlaying: Bool = false

    /// Normalized trim window on the full asset (`0...1`). Defaults to full length.
    private(set) var trimStartFraction: Double = 0
    private(set) var trimEndFraction: Double = 1

    private var timeObserver: Any?
    private weak var observedPlayer: AVQueuePlayer?

    func attach(player: AVQueuePlayer, shotId: String?) {
        detach()
        observedPlayer = player
        activeShotId = shotId
        trimStartFraction = 0
        trimEndFraction = 1
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.tick(player: player)
            }
        }
        tick(player: player)
    }

    func detach() {
        if let timeObserver, let observedPlayer {
            observedPlayer.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        observedPlayer = nil
        activeShotId = nil
        currentTimeSeconds = 0
        durationSeconds = 0
        labelCurrentSeconds = 0
        labelDurationSeconds = 0
        trimStartFraction = 0
        trimEndFraction = 1
        isPlaying = false
    }

    /// Sets preview trim as fractions of full asset duration (used by timeline card playhead + preview handles).
    func setPreviewTrim(startFraction: Double, endFraction: Double) {
        trimStartFraction = max(0, min(1, startFraction))
        let minGap = 1e-4
        trimEndFraction = max(trimStartFraction + minGap, min(1, endFraction))
        if let observedPlayer {
            tick(player: observedPlayer)
        }
    }

    /// Seek within the active trim window (`fraction` 0 = trim in, 1 = trim out).
    func seek(fraction: Double) {
        guard let observedPlayer, durationSeconds > 0 else { return }
        let clamped = max(0, min(1, fraction))
        let span = max(trimEndFraction - trimStartFraction, 1e-9)
        let absoluteFraction = trimStartFraction + clamped * span
        let seconds = absoluteFraction * durationSeconds
        let t = CMTime(seconds: seconds, preferredTimescale: 600)
        observedPlayer.seek(
            to: t,
            toleranceBefore: CMTime(seconds: 0.05, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.05, preferredTimescale: 600)
        )
        tick(player: observedPlayer)
    }

    private func tick(player: AVQueuePlayer) {
        let t = player.currentTime().seconds
        currentTimeSeconds = t.isFinite && t >= 0 ? t : 0
        if let item = player.currentItem {
            let d = item.duration.seconds
            if d.isFinite, d > 0 {
                durationSeconds = d
                let startAbs = d * trimStartFraction
                let endAbs = d * trimEndFraction
                let span = max(0, endAbs - startAbs)
                labelDurationSeconds = span > 1e-6 ? span : d
                if span > 1e-6 {
                    labelCurrentSeconds = min(max(0, currentTimeSeconds - startAbs), span)
                } else {
                    labelCurrentSeconds = min(max(0, currentTimeSeconds), d)
                }
            }
        }
        isPlaying = player.timeControlStatus == .playing
    }
}
