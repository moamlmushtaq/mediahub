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
                LazyVStack(alignment: .leading, spacing: Theme.space(10)) {
                    if let featured = featured(in: home) {
                        HeroView(item: featured, onPlay: onPlay, onDetails: onSelect)
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
        ZStack(alignment: .bottomTrailing) {
            RemoteImage(url: item.backdropURL(.backdropLarge), contentMode: .fill)
                .frame(height: 460)
                .clipped()

            // Two gradients, not one. The bottom carries the text and has to
            // reach full opacity; the side only has to keep the first line of
            // a long title readable, and darkening the whole frame to do that
            // would dim the artwork for nothing.
            LinearGradient(
                colors: [.clear, Theme.Palette.ink.opacity(0.75), Theme.Palette.ink],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 460)

            LinearGradient(
                colors: [Theme.Palette.ink.opacity(0.85), .clear],
                startPoint: .trailing, endPoint: .leading
            )
            .frame(height: 460)

            details
        }
        .frame(height: 460)
        .frame(maxWidth: .infinity)
    }

    private var details: some View {
        VStack(alignment: .trailing, spacing: Theme.space(3)) {
            Text(item.name)
                .font(Theme.Typography.display)
                .foregroundStyle(Theme.Palette.bone)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)

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
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 560, alignment: .trailing)
            }

            HStack(spacing: Theme.space(3)) {
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
