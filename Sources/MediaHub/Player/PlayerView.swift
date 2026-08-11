import SwiftUI
import AVKit
import MediaHubKit

/// The player window's contents.
///
/// WHY THE CONTROLS ARE APPLE'S AND NOT OURS
/// ========================================
/// `AVPlayerView` is the control bar every Mac video app uses, and it arrives
/// with the Picture-in-Picture button, the AirPlay routing picker, the
/// full-screen toggle, volume, scrubbing with thumbnail previews, and the exact
/// motion and hit targets people already expect. Rebuilding that in SwiftUI
/// would take weeks and the result would be recognisably not-quite-right — the
/// specific failure the previous client was rejected for.
///
/// What is ours is the part Apple does not offer: subtitles from a loose `.srt`
/// file, drawn with the size, background and position this app chooses.
struct PlayerView: View {
    @Environment(AppModel.self) private var app

    let request: PlayRequest
    let onClose: () -> Void

    @State private var model: PlayerModel?
    @State private var isShowingTracks = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let model {
                switch model.state {
                case .preparing:
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)

                case let .failed(message):
                    FailureState(message: message, retry: nil)

                case .playing:
                    if let player = model.player {
                        VideoSurface(player: player)
                            .ignoresSafeArea()
                    }
                }

                subtitleLayer(model)
                chrome(model)
            }
        }
        .task {
            let created = PlayerModel(request: request, app: app)
            model = created
            await created.start()
        }
        .onDisappear {
            // Captured before the view goes away, because `model` is nil by the
            // time the task would run otherwise — and this is what commits the
            // watched position.
            let closing = model
            Task { await closing?.finish() }
        }
    }

    // MARK: Subtitles

    /// Drawn above the video and below nothing.
    ///
    /// Hit testing is off for the whole layer: it sits over `AVPlayerView`, and
    /// a transparent view that swallows clicks would make the native controls
    /// underneath stop responding — which would read as the player being
    /// broken rather than as an overlay being in the way.
    private func subtitleLayer(_ model: PlayerModel) -> some View {
        VStack {
            Spacer()
            if !model.visibleCues.isEmpty {
                VStack(spacing: Theme.space(1)) {
                    ForEach(model.visibleCues) { cue in
                        Text(cue.text)
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.space(3))
                            .padding(.vertical, Theme.space(1.5))
                            .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 5))
                            // A shadow as well as a background: a bright frame
                            // behind a translucent panel still washes text out.
                            .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
                    }
                }
                .padding(.horizontal, Theme.space(12))
                // Clear of the floating control bar, which sits about 90 points
                // from the bottom — otherwise the last line of dialogue in
                // every scene hides behind the scrubber.
                .padding(.bottom, 112)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.visibleCues.map(\.id))
        .allowsHitTesting(false)
    }

    // MARK: Chrome

    private func chrome(_ model: PlayerModel) -> some View {
        VStack {
            HStack(alignment: .top, spacing: Theme.space(3)) {
                Button(action: onClose) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("رجوع")

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(request.title)
                        .font(Theme.Typography.heading)
                        .foregroundStyle(.white)
                    if let subtitle = request.subtitle {
                        Text(subtitle)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                if !model.tracks.isEmpty {
                    subtitleMenu(model)
                }
            }
            .padding(Theme.space(4))
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.65), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
            )

            Spacer()
        }
    }

    /// A `Menu`, not a sheet.
    ///
    /// Deliberate, and from experience: the previous client presented its track
    /// picker as a modal, and on a screen that was itself presented modally and
    /// orientation-locked, opening it dismissed the player. "Pressing the
    /// subtitles button throws me out" was the first bug reported. A menu is
    /// part of the window and cannot dismiss anything.
    private func subtitleMenu(_ model: PlayerModel) -> some View {
        Menu {
            Button {
                Task { await model.select(nil) }
            } label: {
                Label("بلا ترجمة", systemImage: model.activeTrack == nil ? "checkmark" : "")
            }

            Divider()

            ForEach(model.tracks) { track in
                Button {
                    Task { await model.select(track) }
                } label: {
                    Label(
                        track.label.isEmpty ? (track.language ?? "?") : track.label,
                        systemImage: model.activeTrack?.url == track.url ? "checkmark" : ""
                    )
                }
            }
        } label: {
            Image(systemName: "captions.bubble")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(model.activeTrack == nil ? .white : Theme.Palette.goldBright)
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.45), in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 34, height: 34)
        .help("الترجمة")
    }
}

/// `AVPlayerView`, wrapped.
///
/// Everything switched on here is a capability the shell around the website
/// could not offer at all.
struct VideoSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        // The modern floating bar rather than the inline one: it overlays the
        // picture and auto-hides, which is what a film wants.
        view.controlsStyle = .floating
        view.allowsPictureInPicturePlayback = true
        view.showsFullScreenToggleButton = true
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
