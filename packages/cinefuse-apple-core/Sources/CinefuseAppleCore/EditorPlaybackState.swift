import AVFoundation
import Combine
import Foundation

/// Shared playback position for editor preview + timeline clip overlays (video / audio).
@MainActor
final class EditorPlaybackState: ObservableObject {
    @Published private(set) var currentTimeSeconds: Double = 0
    @Published private(set) var durationSeconds: Double = 0
    @Published private(set) var activeShotId: String?
    @Published private(set) var isPlaying: Bool = false

    private var timeObserver: Any?
    private weak var observedPlayer: AVQueuePlayer?

    func attach(player: AVQueuePlayer, shotId: String?) {
        detach()
        observedPlayer = player
        activeShotId = shotId
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
        isPlaying = false
    }

    func seek(fraction: Double) {
        guard let observedPlayer, durationSeconds > 0 else { return }
        let clamped = max(0, min(1, fraction))
        let seconds = clamped * durationSeconds
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
            }
        }
        isPlaying = player.timeControlStatus == .playing
    }
}
