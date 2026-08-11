import SwiftUI
import MediaHubKit

@MainActor
@Observable
final class HomeModel {
    enum State {
        case loading
        case ready(Home)
        case failed(String)
    }

    private(set) var state: State = .loading

    func load(_ app: AppModel, force: Bool = false) async {
        if case .ready = state, !force { return }
        if force { state = .loading }

        do {
            state = .ready(try await app.client.home())
        } catch {
            await app.handle(error)
            state = .failed((error as? MediaHubError)?.message ?? "تعذّر تحميل المكتبة.")
        }
    }
}

/// The first screen: one featured title, then rows.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var model = HomeModel()

    let onSelect: (MediaCard) -> Void
    let onPlay: (MediaCard) -> Void

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                LoadingState()
            case let .failed(message):
                FailureState(message: message) {
                    Task { await model.load(app, force: true) }
                }
            case let .ready(home):
                content(home)
            }
        }
        .pageBackground()
        .task { await model.load(app) }
    }

    @ViewBuilder
    private func content(_ home: Home) -> some View {
        if home.rails.isEmpty {
            EmptyState(
                symbol: "film.stack",
                title: "المكتبة فارغة",
                message: "لم يُضف أي عمل بعد."
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.space(7)) {
                    if let featured = featured(in: home) {
                        HeroView(item: featured, onPlay: onPlay, onDetails: onSelect)
                            .padding(.bottom, -Theme.space(3))
                    }

                    ForEach(home.rails) { rail in
                        MediaRail(title: rail.title, items: rail.items, onSelect: onSelect)
                    }
                }
                .padding(.bottom, Theme.space(12))
            }
            .refreshable { await model.load(app, force: true) }
        }
    }

    /// What gets the hero.
    ///
    /// The newest arrival that actually has a backdrop — not a random pick,
    /// because a home screen that reshuffles on every refresh reads as broken
    /// rather than lively, and not the highest rated, because in a personal
    /// library the newest arrival is usually the thing nobody has seen yet.
    private func featured(in home: Home) -> MediaCard? {
        let candidates = home.rails
            .first { $0.key != "resume" }?
            .items ?? home.rails.first?.items ?? []

        return candidates.first { $0.backdropTag != nil } ?? candidates.first
    }
}

/// The featured title.
struct HeroView: View {
    let item: MediaCard
    let onPlay: (MediaCard) -> Void
    let onDetails: (MediaCard) -> Void

    private var isResuming: Bool { item.startingPoint.rawValue > 0 }

    var body: some View {
        // `.leading`, not `.trailing`. In a right-to-left layout SwiftUI maps
        // leading to the RIGHT edge — the first version used trailing and put
        // the title, the summary and both buttons in the bottom-left corner of
        // an Arabic screen.
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: item.backdropURL(.backdropLarge), contentMode: .fill)

            // The scrims exist to make text legible, and the first version made
            // them so heavy that the artwork behind them was invisible — the
            // hero read as a black rectangle with words on it, which is the
            // opposite of what a hero is for. Both are lighter now, and both
            // hold `.clear` for the first half so the top of the frame is the
            // picture itself.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Theme.Palette.ink.opacity(0.30), location: 0.48),
                    .init(color: Theme.Palette.ink.opacity(0.88), location: 0.84),
                    .init(color: Theme.Palette.ink, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )

            // Explicit unit points rather than `.leading`/`.trailing`: those are
            // flipped by the layout direction, and a scrim needs to sit under
            // the text wherever the text actually is — which here is the right.
            LinearGradient(
                stops: [
                    .init(color: Theme.Palette.ink.opacity(0.72), location: 0),
                    .init(color: Theme.Palette.ink.opacity(0.25), location: 0.45),
                    .init(color: .clear, location: 0.8),
                ],
                startPoint: UnitPoint(x: 1, y: 0.5),
                endPoint: UnitPoint(x: 0, y: 0.5)
            )

            details
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .clipped()
    }

    /// Tall enough to be a statement, short enough that the first rail shows
    /// underneath and says there is more below.
    static let height: CGFloat = 520

    private var details: some View {
        VStack(alignment: .leading, spacing: Theme.space(3)) {
            Text(item.name)
                .font(Theme.Typography.display)
                .foregroundStyle(Theme.Palette.bone)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if !meta.isEmpty {
                Text(meta)
                    .font(Theme.Typography.label)
                    .foregroundStyle(Theme.Palette.ash)
            }

            if !item.overview.isEmpty {
                Text(item.overview)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.ash)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 560, alignment: .leading)
            }

            HStack(spacing: Theme.space(3)) {
                Button {
                    item.type == .series ? onDetails(item) : onPlay(item)
                } label: {
                    Label(
                        item.type == .series ? "استعراض" : (isResuming ? "متابعة" : "تشغيل"),
                        systemImage: item.type == .series ? "square.grid.2x2" : "play.fill"
                    )
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.horizontal, Theme.space(6))
                    .padding(.vertical, Theme.space(2.5))
                    .background(Theme.Palette.gold)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    onDetails(item)
                } label: {
                    Label("التفاصيل", systemImage: "info.circle")
                        .font(Theme.Typography.label)
                        .foregroundStyle(Theme.Palette.bone)
                        .padding(.horizontal, Theme.space(5))
                        .padding(.vertical, Theme.space(2.5))
                        .background(.white.opacity(0.14))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, Theme.space(2))
        }
        .padding(Theme.space(8))
    }

    private var meta: String {
        var parts: [String] = []
        if let year = item.year { parts.append(String(year)) }
        if let rating = item.communityRating { parts.append("★ " + String(format: "%.1f", rating)) }
        if let runtime = item.runtimeMinutes { parts.append("\(runtime) دقيقة") }
        parts.append(item.type == .series ? "مسلسل" : "فيلم")
        return parts.joined(separator: "  ·  ")
    }
}
