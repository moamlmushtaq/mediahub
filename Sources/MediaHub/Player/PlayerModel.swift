import Foundation
import AVFoundation
import MediaPlayer
import Observation
import MediaHubKit

/// Everything the player does that is not drawing.
///
/// WHY `AVPlayer` AND NOT A CUSTOM PIPELINE
/// =======================================
/// Because it is the reason to write a native app at all. AVPlayer gives
/// hardware decoding, Picture-in-Picture, AirPlay to the television in the same
/// room, the system's own volume and output routing, and correct behaviour when
/// the lid closes — none of which a web player in a window can do, and all of
/// which a household with a Mac and a TV will actually use.
///
/// THE RULE THIS KEEPS
/// ==================
/// The signed URL goes straight into `AVPlayer`, which fetches the bytes from
/// the CDN itself. No frame passes through the server, exactly as on every
/// other client. This is the line the whole system is built on.
@MainActor
@Observable
final class PlayerModel {
    enum State: Equatable {
        case preparing
        case playing
        case failed(String)
    }

    private(set) var state: State = .preparing
    private(set) var player: AVPlayer?

    /// Subtitle tracks offered by the server, and the one on screen.
    private(set) var tracks: [SubtitleTrack] = []
    private(set) var activeTrack: SubtitleTrack?
    private(set) var visibleCues: [Cue] = []

    private var document: SubtitleDocument?
    private var reporter = ProgressReporter()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    private let request: PlayRequest
    private weak var app: AppModel?

    init(request: PlayRequest, app: AppModel) {
        self.request = request
        self.app = app
    }

    // MARK: Lifecycle

    func start() async {
        guard let app else { return }

        do {
            let playback = try await app.client.playback(id: request.id)
            tracks = playback.subtitles

            let item = AVPlayerItem(url: playback.url)
            let player = AVPlayer(playerItem: item)
            // Nothing else in this app makes sound, and pausing for a
            // notification chime would be worse than mixing with it.
            player.automaticallyWaitsToMinimizeStalling = true
            self.player = player

            if request.startAt.rawValue > 0 {
                await player.seek(
                    to: CMTime(seconds: request.startAt.seconds, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
            }

            attachObservers(to: player)
            configureNowPlaying()

            player.play()
            state = .playing

            await chooseInitialSubtitles()
        } catch {
            await app.handle(error)
            state = .failed((error as? MediaHubError)?.message ?? "تعذّر تشغيل هذا العنوان.")
        }
    }

    /// Called when the player closes. Commits the position and tears everything
    /// down — an observer left attached to a released player is a crash, and a
    /// position not committed here is the ten minutes the viewer just watched.
    func finish() async {
        if let player {
            let position = Ticks(seconds: player.currentTime().seconds)
            await report(position, moment: .finished)
            player.pause()
        }

        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil

        clearNowPlaying()
        player = nil
    }

    // MARK: Observation

    private func attachObservers(to player: AVPlayer) {
        // Four times a second: fine enough that a subtitle appears on the frame
        // it belongs to, coarse enough to cost nothing.
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)

        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            // The queue is `.main`, so this is the main actor; the assumption
            // is checked at runtime rather than assumed silently.
            MainActor.assumeIsolated {
                self?.tick(at: time.seconds)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let player = self.player else { return }
                Task { await self.report(Ticks(seconds: player.currentTime().seconds), moment: .finished) }
            }
        }
    }

    private func tick(at seconds: Double) {
        guard seconds.isFinite else { return }

        if let document {
            let cues = document.cues(at: seconds)
            // Only publish on change: assigning an identical array every
            // quarter second re-renders the overlay 240 times a minute for
            // nothing.
            if cues.map(\.id) != visibleCues.map(\.id) {
                visibleCues = cues
            }
        }

        let position = Ticks(seconds: seconds)
        let paused = player?.timeControlStatus != .playing

        if reporter.shouldReport(position: position, moment: paused ? .paused : .tick, now: seconds) {
            Task { await report(position, moment: paused ? .paused : .tick, throttled: false) }
        }

        updateNowPlaying(position: seconds)
    }

    private func report(_ position: Ticks, moment: ProgressReporter.Moment, throttled: Bool = true) async {
        guard let app else { return }
        if throttled, !reporter.shouldReport(position: position, moment: moment, now: position.seconds) {
            return
        }
        // A failed progress report is not worth interrupting a film over.
        try? await app.client.reportProgress(id: request.id, position: position)
    }

    // MARK: Subtitles

    private func chooseInitialSubtitles() async {
        let preferred = SubtitlePicker.preferred(
            from: tracks,
            remembering: app?.preferredSubtitleLanguage
        )
        guard let preferred else { return }
        await select(preferred)
    }

    func select(_ track: SubtitleTrack?) async {
        activeTrack = track
        visibleCues = []

        guard let track, let url = URL(string: track.url), let app else {
            document = nil
            return
        }

        app.preferredSubtitleLanguage = SubtitlePicker.language(track.language)
        document = try? await app.client.subtitles(at: url)
    }

    // MARK: Now Playing

    /// Puts the film in the system's Now Playing panel and wires the media keys.
    ///
    /// This is the difference between an app that plays video and an app that
    /// belongs to the machine: the title appears in Control Centre, the F8 key
    /// pauses it, and a Bluetooth remote works without knowing anything about
    /// this app.
    private func configureNowPlaying() {
        let centre = MPRemoteCommandCenter.shared()

        centre.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player?.play() }
            return .success
        }
        centre.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player?.pause() }
            return .success
        }
        centre.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayback() }
            return .success
        }
        centre.skipForwardCommand.preferredIntervals = [10]
        centre.skipBackwardCommand.preferredIntervals = [10]
        centre.skipForwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(by: 10) }
            return .success
        }
        centre.skipBackwardCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.skip(by: -10) }
            return .success
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: request.subtitle ?? request.title,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if request.subtitle != nil {
            info[MPMediaItemPropertyAlbumTitle] = request.title
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlaying(position: Double) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
        if let duration = player?.currentItem?.duration.seconds, duration.isFinite {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = player?.rate ?? 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        let centre = MPRemoteCommandCenter.shared()
        // Removing our targets matters: they capture `self`, and leaving them
        // attached keeps a finished player alive and lets the media keys drive
        // a film nobody is watching.
        centre.playCommand.removeTarget(nil)
        centre.pauseCommand.removeTarget(nil)
        centre.togglePlayPauseCommand.removeTarget(nil)
        centre.skipForwardCommand.removeTarget(nil)
        centre.skipBackwardCommand.removeTarget(nil)
    }

    // MARK: Transport

    func togglePlayback() {
        guard let player else { return }
        player.timeControlStatus == .playing ? player.pause() : player.play()
    }

    func skip(by seconds: Double) {
        guard let player else { return }
        let target = max(0, player.currentTime().seconds + seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        Task { await report(Ticks(seconds: target), moment: .seeked, throttled: false) }
    }
}
