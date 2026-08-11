import SwiftUI
import MediaHubKit

@MainActor
@Observable
final class TitleModel {
    enum State {
        case loading
        case ready(MediaDetail, [Season])
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var episodes: [Episode] = []
    private(set) var isLoadingEpisodes = false
    var selectedSeason: Int?

    func load(_ app: AppModel, id: String) async {
        state = .loading
        do {
            let response = try await app.client.title(id: id)
            state = .ready(response.item, response.seasons)

            // Open on the first season rather than on nothing: a series page
            // that shows a season picker and an empty space below it looks
            // like it failed to load.
            if let first = response.seasons.first?.indexNumber {
                selectedSeason = first
                await loadEpisodes(app, seriesID: id, season: first)
            }
        } catch {
            await app.handle(error)
            state = .failed((error as? MediaHubError)?.message ?? "تعذّر تحميل هذا العنوان.")
        }
    }

    func loadEpisodes(_ app: AppModel, seriesID: String, season: Int) async {
        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }
        episodes = (try? await app.client.episodes(seriesID: seriesID, season: season)) ?? []
    }
}

/// One title, in full.
struct TitleView: View {
    @Environment(AppModel.self) private var app

    let card: MediaCard
    let onPlay: (MediaCard) -> Void
    let onPlayEpisode: (Episode, MediaDetail) -> Void

    @State private var model = TitleModel()

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                LoadingState()
            case let .failed(message):
                FailureState(message: message) {
                    Task { await model.load(app, id: card.id) }
                }
            case let .ready(detail, seasons):
                content(detail, seasons)
            }
        }
        .pageBackground()
        .navigationTitle(card.name)
        .task { await model.load(app, id: card.id) }
    }

    private func content(_ detail: MediaDetail, _ seasons: [Season]) -> some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: Theme.space(9)) {
                header(detail)

                if !seasons.isEmpty {
                    seasonSection(detail, seasons)
                }

                if !detail.people.isEmpty {
                    castSection(detail.people)
                }
            }
            .padding(.bottom, Theme.space(12))
        }
    }

    // MARK: Header

    private func header(_ detail: MediaDetail) -> some View {
        ZStack(alignment: .bottom) {
            RemoteImage(url: detail.card.backdropURL(.backdropLarge))
                .frame(height: 420)
                .clipped()

            LinearGradient(
                colors: [.clear, Theme.Palette.ink.opacity(0.85), Theme.Palette.ink],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 420)

            HStack(alignment: .bottom, spacing: Theme.space(6)) {
                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: Theme.space(3)) {
                    Text(detail.card.name)
                        .font(Theme.Type.display)
                        .foregroundStyle(Theme.Palette.bone)
                        .multilineTextAlignment(.trailing)

                    // Shown only when it differs from the displayed title —
                    // repeating the same string twice looks like a bug.
                    if let original = detail.card.originalTitle, original != detail.card.name {
                        Text(original)
                            .font(Theme.Type.body)
                            .foregroundStyle(Theme.Palette.dim)
                    }

                    Text(meta(detail))
                        .font(Theme.Type.label)
                        .foregroundStyle(Theme.Palette.ash)

                    if !detail.tagline.isEmpty {
                        Text(detail.tagline)
                            .font(Theme.Type.body.italic())
                            .foregroundStyle(Theme.Palette.gold)
                    }

                    if !detail.card.overview.isEmpty {
                        Text(detail.card.overview)
                            .font(Theme.Type.body)
                            .foregroundStyle(Theme.Palette.ash)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 620, alignment: .trailing)
                    }

                    if detail.card.type == .movie {
                        playButton(detail)
                            .padding(.top, Theme.space(2))
                    }
                }

                RemoteImage(url: detail.card.posterURL(.posterLarge))
                    .frame(width: 180, height: 270)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                    .hairlineBorder()
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
            }
            .padding(.horizontal, Theme.space(8))
            .padding(.bottom, Theme.space(6))
        }
    }

    private func playButton(_ detail: MediaDetail) -> some View {
        let resuming = detail.card.startingPoint.rawValue > 0

        return HStack(spacing: Theme.space(3)) {
            Button {
                onPlay(detail.card)
            } label: {
                Label(resuming ? "متابعة" : "تشغيل", systemImage: "play.fill")
                    .font(Theme.Type.heading)
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.horizontal, Theme.space(7))
                    .padding(.vertical, Theme.space(3))
                    .background(Theme.Palette.gold)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            if resuming {
                Text("من \(detail.card.startingPoint.timecode)")
                    .font(Theme.Type.label)
                    .foregroundStyle(Theme.Palette.dim)
            }
        }
    }

    private func meta(_ detail: MediaDetail) -> String {
        var parts: [String] = []
        if let year = detail.card.year { parts.append(String(year)) }
        if let rating = detail.card.communityRating {
            parts.append("★ " + String(format: "%.1f", rating))
        }
        if let runtime = detail.card.runtimeMinutes { parts.append("\(runtime) دقيقة") }
        if let official = detail.card.officialRating { parts.append(official) }
        if !detail.genres.isEmpty { parts.append(detail.genres.prefix(3).joined(separator: "، ")) }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: Seasons

    private func seasonSection(_ detail: MediaDetail, _ seasons: [Season]) -> some View {
        VStack(alignment: .trailing, spacing: Theme.space(4)) {
            HStack {
                Picker("", selection: Binding(
                    get: { model.selectedSeason ?? seasons.first?.indexNumber ?? 1 },
                    set: { season in
                        model.selectedSeason = season
                        Task { await model.loadEpisodes(app, seriesID: detail.card.id, season: season) }
                    }
                )) {
                    ForEach(seasons) { season in
                        Text(season.name).tag(season.indexNumber ?? 0)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 200)

                Spacer()

                Text("الحلقات")
                    .font(Theme.Type.heading)
                    .foregroundStyle(Theme.Palette.bone)
            }
            .padding(.horizontal, Theme.space(8))

            if model.isLoadingEpisodes {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            } else if model.episodes.isEmpty {
                Text("لا توجد حلقات في هذا الموسم.")
                    .font(Theme.Type.body)
                    .foregroundStyle(Theme.Palette.dim)
                    .padding(.horizontal, Theme.space(8))
            } else {
                VStack(spacing: 0) {
                    ForEach(model.episodes) { episode in
                        EpisodeRow(episode: episode) {
                            onPlayEpisode(episode, detail)
                        }
                        if episode.id != model.episodes.last?.id {
                            Divider().background(Theme.Palette.hair)
                        }
                    }
                }
                .padding(.horizontal, Theme.space(8))
            }
        }
    }

    // MARK: Cast

    private func castSection(_ people: [Person]) -> some View {
        VStack(alignment: .trailing, spacing: Theme.space(4)) {
            Text("طاقم العمل")
                .font(Theme.Type.heading)
                .foregroundStyle(Theme.Palette.bone)
                .padding(.horizontal, Theme.space(8))

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.space(5)) {
                    ForEach(people) { person in
                        VStack(spacing: Theme.space(2)) {
                            RemoteImage(url: person.headshotURL, placeholderSymbol: "person.fill")
                                .frame(width: 92, height: 92)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Theme.Palette.hair, lineWidth: 1))

                            Text(person.name)
                                .font(Theme.Type.caption)
                                .foregroundStyle(Theme.Palette.bone)
                                .lineLimit(2, reservesSpace: true)
                                .multilineTextAlignment(.center)

                            if !person.role.isEmpty {
                                Text(person.role)
                                    .font(Theme.Type.caption)
                                    .foregroundStyle(Theme.Palette.dim)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 110)
                    }
                }
                .padding(.horizontal, Theme.space(8))
            }
        }
    }
}

/// One episode in the list.
struct EpisodeRow: View {
    let episode: Episode
    let onPlay: () -> Void

    @State private var isHovering = false

    private var progress: Double? {
        guard episode.startingPoint.rawValue > 0,
              let runtime = episode.runtime, runtime.seconds > 0
        else { return nil }
        return min(1, episode.startingPoint.seconds / runtime.seconds)
    }

    var body: some View {
        Button(action: onPlay) {
            HStack(alignment: .top, spacing: Theme.space(4)) {
                VStack(alignment: .trailing, spacing: Theme.space(1.5)) {
                    HStack(spacing: Theme.space(2)) {
                        Spacer()
                        if episode.userData.played {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Palette.gold)
                        }
                        Text(episode.name)
                            .font(Theme.Type.label)
                            .foregroundStyle(Theme.Palette.bone)
                            .lineLimit(1)
                    }

                    if !episode.overview.isEmpty {
                        Text(episode.overview)
                            .font(Theme.Type.caption)
                            .foregroundStyle(Theme.Palette.dim)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack(spacing: Theme.space(2)) {
                        Spacer()
                        if let runtime = episode.runtimeMinutes {
                            Text("\(runtime) دقيقة")
                                .font(Theme.Type.caption)
                                .foregroundStyle(Theme.Palette.dim)
                        }
                        if let code = episode.episodeCode {
                            Text(code)
                                .font(Theme.Type.caption.monospaced())
                                .foregroundStyle(Theme.Palette.dim)
                        }
                    }
                }

                ZStack(alignment: .bottom) {
                    RemoteImage(url: episode.stillURL(), placeholderSymbol: "tv")
                        .frame(width: 148, height: 84)
                        .clipped()

                    if let progress {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.black.opacity(0.55))
                                Rectangle()
                                    .fill(Theme.Palette.gold)
                                    .frame(width: geometry.size.width * progress)
                            }
                        }
                        .frame(height: 3)
                    }
                }
                .frame(width: 148, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            }
            .padding(.vertical, Theme.space(3))
            .padding(.horizontal, Theme.space(3))
            .background(isHovering ? Theme.Palette.inkPanel : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
