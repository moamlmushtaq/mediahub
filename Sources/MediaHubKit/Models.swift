import Foundation

/// The shapes `/api/v1` returns.
///
/// ON LENIENCY
/// ===========
/// Identity is decoded strictly and everything else is decoded with a default.
/// That split is deliberate. A card with no `id` is not a card and silently
/// inventing one would put a row on screen that cannot be opened — so that
/// throws. But a card whose `overview` is absent because the metadata provider
/// had nothing to say is an ordinary Tuesday, and a client that refuses to draw
/// the entire library over it is worse than one that draws a film with no
/// summary.
///
/// The practical consequence: adding a field to the server never breaks a
/// shipped copy of this app, and removing an optional one never does either.

// MARK: - Decoding helpers

extension KeyedDecodingContainer {
    /// Decodes, or falls back — for fields whose absence is not an error.
    ///
    /// Also treats an explicit `null` as absent, which the server does emit:
    /// `originalTitle`, `year` and `communityRating` are all nullable by design.
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }

    /// Decodes an optional field, turning a decoding failure into `nil` rather
    /// than into a thrown error.
    func optional<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// Decodes a list, dropping only the entries that fail.
    ///
    /// The obvious implementation — `value(.items, or: [])` — is wrong here in
    /// a way that took a test to see: `try?` around the *whole array* means one
    /// unusable card turns a page of sixty films into a page of none, and does
    /// it silently. The failure that gets reported is then "the library is
    /// empty", which points at the server, the account, the network, and at
    /// everything except the one malformed record actually responsible.
    ///
    /// Element by element, the same bad record costs exactly itself.
    func lossyArray<T: Decodable>(_ key: Key) -> [T] {
        guard var container = try? nestedUnkeyedContainer(forKey: key) else { return [] }

        var result: [T] = []
        while !container.isAtEnd {
            let position = container.currentIndex

            if let element = try? container.decode(T.self) {
                result.append(element)
            } else {
                // The entry still has to be consumed, or the loop sits on it
                // forever. `Skip` decodes from any JSON value at all.
                _ = try? container.decode(Skip.self)
            }

            // A container that will neither decode nor skip cannot be walked;
            // stopping is the only option that terminates.
            if container.currentIndex == position { break }
        }
        return result
    }
}

/// Consumes one entry of any shape without looking at it.
private struct Skip: Decodable {
    init(from decoder: any Decoder) throws {}
}

// MARK: - Primitives

public enum MediaType: String, Codable, Sendable, CaseIterable {
    case movie = "Movie"
    case series = "Series"
    case episode = "Episode"
}

/// TMDb image paths for one item. `nil` means the item genuinely has no art of
/// that kind — which the UI must handle, because a personal library always has
/// a few files the metadata providers have never heard of.
public struct ImageTags: Codable, Hashable, Sendable {
    public let primary: String?
    public let logo: String?
    public let thumb: String?

    public init(primary: String? = nil, logo: String? = nil, thumb: String? = nil) {
        self.primary = primary
        self.logo = logo
        self.thumb = thumb
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.primary = c.optional(.primary)
        self.logo = c.optional(.logo)
        self.thumb = c.optional(.thumb)
    }
}

/// What the server remembers about this viewer and this item.
public struct UserItemData: Codable, Hashable, Sendable {
    public let played: Bool
    public let playbackPosition: Ticks
    public let playedPercentage: Double

    public init(played: Bool = false, playbackPosition: Ticks = .zero, playedPercentage: Double = 0) {
        self.played = played
        self.playbackPosition = playbackPosition
        self.playedPercentage = playedPercentage
    }

    private enum CodingKeys: String, CodingKey {
        case played
        case playbackPosition = "playbackPositionTicks"
        case playedPercentage
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.played = c.value(.played, or: false)
        self.playbackPosition = c.value(.playbackPosition, or: Ticks.zero)
        self.playedPercentage = c.value(.playedPercentage, or: 0)
    }
}

// MARK: - Cards and details

/// The compact shape behind every poster, row and grid cell.
public struct MediaCard: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let originalTitle: String?
    public let type: MediaType
    public let year: Int?
    public let communityRating: Double?
    public let officialRating: String?
    public let runtimeMinutes: Int?
    public let overview: String
    public let imageTags: ImageTags
    public let backdropTag: String?
    public let userData: UserItemData

    public var runtime: Runtime? {
        runtimeMinutes.map { Runtime(minutes: $0) }
    }

    /// Where playback should begin. See ``Resume``.
    public var startingPoint: Ticks {
        Resume.startingPoint(position: userData.playbackPosition, runtime: runtime)
    }

    public init(
        id: String,
        name: String,
        originalTitle: String? = nil,
        type: MediaType,
        year: Int? = nil,
        communityRating: Double? = nil,
        officialRating: String? = nil,
        runtimeMinutes: Int? = nil,
        overview: String = "",
        imageTags: ImageTags = ImageTags(),
        backdropTag: String? = nil,
        userData: UserItemData = UserItemData()
    ) {
        self.id = id
        self.name = name
        self.originalTitle = originalTitle
        self.type = type
        self.year = year
        self.communityRating = communityRating
        self.officialRating = officialRating
        self.runtimeMinutes = runtimeMinutes
        self.overview = overview
        self.imageTags = imageTags
        self.backdropTag = backdropTag
        self.userData = userData
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, originalTitle, type, year, communityRating
        case officialRating, runtimeMinutes, overview, imageTags, backdropTag, userData
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Strict: without these there is nothing to draw or open.
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.type = try c.decode(MediaType.self, forKey: .type)
        // Lenient: everything a metadata provider might not know.
        self.originalTitle = c.optional(.originalTitle)
        self.year = c.optional(.year)
        self.communityRating = c.optional(.communityRating)
        self.officialRating = c.optional(.officialRating)
        self.runtimeMinutes = c.optional(.runtimeMinutes)
        self.overview = c.value(.overview, or: "")
        self.imageTags = c.value(.imageTags, or: ImageTags())
        self.backdropTag = c.optional(.backdropTag)
        self.userData = c.value(.userData, or: UserItemData())
    }
}

public struct Person: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let role: String
    public let type: String
    public let imageTag: String?

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.role = c.value(.role, or: "")
        self.type = c.value(.type, or: "")
        self.imageTag = c.optional(.imageTag)
    }

    private enum CodingKeys: String, CodingKey { case id, name, role, type, imageTag }
}

/// One physical file behind an item.
public struct MediaSource: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let path: String
    public let container: String
    public let size: Int

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = c.value(.id, or: "")
        self.path = c.value(.path, or: "")
        self.container = c.value(.container, or: "")
        self.size = c.value(.size, or: 0)
    }

    private enum CodingKeys: String, CodingKey { case id, path, container, size }
}

/// The full shape behind a detail page. The card's fields arrive flat in the
/// same JSON object, so it is decoded from the same container rather than
/// nested — which keeps one definition of what a card is.
public struct MediaDetail: Codable, Sendable, Identifiable {
    public let card: MediaCard
    public let genres: [String]
    public let studios: [String]
    public let people: [Person]
    public let tagline: String
    public let mediaSources: [MediaSource]

    public var id: String { card.id }

    public init(from decoder: any Decoder) throws {
        self.card = try MediaCard(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.genres = c.lossyArray(.genres)
        self.studios = c.value(.studios, or: [])
        self.people = c.lossyArray(.people)
        self.tagline = c.value(.tagline, or: "")
        self.mediaSources = c.lossyArray(.mediaSources)
    }

    public func encode(to encoder: any Encoder) throws {
        try card.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(genres, forKey: .genres)
        try c.encode(studios, forKey: .studios)
        try c.encode(people, forKey: .people)
        try c.encode(tagline, forKey: .tagline)
        try c.encode(mediaSources, forKey: .mediaSources)
    }

    private enum CodingKeys: String, CodingKey {
        case genres, studios, people, tagline, mediaSources
    }
}

// MARK: - Series structure

public struct Season: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let indexNumber: Int?
    public let imageTag: String?
    public let episodeCount: Int

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = c.value(.name, or: "")
        self.indexNumber = c.optional(.indexNumber)
        self.imageTag = c.optional(.imageTag)
        self.episodeCount = c.value(.episodeCount, or: 0)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, indexNumber, imageTag, episodeCount
    }
}

public struct Episode: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let indexNumber: Int?
    public let seasonNumber: Int?
    public let overview: String
    public let runtimeMinutes: Int?
    public let imageTag: String?
    public let userData: UserItemData

    public var runtime: Runtime? { runtimeMinutes.map { Runtime(minutes: $0) } }

    public var startingPoint: Ticks {
        Resume.startingPoint(position: userData.playbackPosition, runtime: runtime)
    }

    /// `S02E07`, or `nil` when the file could not be ordered. Padded to two
    /// digits because an unpadded list sorts `E10` before `E2` to the eye.
    public var episodeCode: String? {
        guard let seasonNumber, let indexNumber else { return nil }
        return String(format: "S%02dE%02d", seasonNumber, indexNumber)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = c.value(.name, or: "")
        self.indexNumber = c.optional(.indexNumber)
        self.seasonNumber = c.optional(.seasonNumber)
        self.overview = c.value(.overview, or: "")
        self.runtimeMinutes = c.optional(.runtimeMinutes)
        self.imageTag = c.optional(.imageTag)
        self.userData = c.value(.userData, or: UserItemData())
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, indexNumber, seasonNumber, overview, runtimeMinutes, imageTag, userData
    }
}

public struct Genre: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
}

// MARK: - Endpoint payloads

public struct Viewer: Codable, Hashable, Sendable {
    public let id: Int
    public let slug: String
    public let name: String
}

public struct Session: Codable, Hashable, Sendable {
    public let token: String
    /// Unix seconds. The server issues thirty days.
    public let expiresAt: Int
    public let viewer: Viewer

    public var expiry: Date { Date(timeIntervalSince1970: TimeInterval(expiresAt)) }

    public func isValid(at moment: Date = Date()) -> Bool {
        expiry > moment
    }
}

/// One horizontal row on the home screen. The server decides which rows exist
/// and what they are called, and omits any that would be empty — so the client
/// renders what it is given rather than asking for named rows it might not get.
public struct Rail: Codable, Hashable, Sendable, Identifiable {
    public let key: String
    public let title: String
    public let items: [MediaCard]

    public var id: String { key }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.key = try c.decode(String.self, forKey: .key)
        self.title = c.value(.title, or: "")
        self.items = c.lossyArray(.items)
    }

    private enum CodingKeys: String, CodingKey { case key, title, items }
}

public struct Home: Codable, Hashable, Sendable {
    public let rails: [Rail]
    public let genres: [Genre]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.rails = c.lossyArray(.rails)
        self.genres = c.lossyArray(.genres)
    }

    private enum CodingKeys: String, CodingKey { case rails, genres }
}

public struct Page: Codable, Hashable, Sendable {
    public let items: [MediaCard]
    public let total: Int

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.items = c.lossyArray(.items)
        self.total = c.value(.total, or: 0)
    }

    private enum CodingKeys: String, CodingKey { case items, total }
}

public struct TitleResponse: Codable, Sendable {
    public let item: MediaDetail
    public let seasons: [Season]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.item = try c.decode(MediaDetail.self, forKey: .item)
        self.seasons = c.lossyArray(.seasons)
    }

    private enum CodingKeys: String, CodingKey { case item, seasons }
}

/// A sidecar subtitle track, already signed and fetchable straight from Bunny.
public struct SubtitleTrack: Codable, Hashable, Sendable, Identifiable {
    public let url: String
    public let language: String?
    public let label: String
    public let forced: Bool
    public let isDefault: Bool

    public var id: String { url }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try c.decode(String.self, forKey: .url)
        self.language = c.optional(.language)
        self.label = c.value(.label, or: "")
        self.forced = c.value(.forced, or: false)
        self.isDefault = c.value(.isDefault, or: false)
    }

    private enum CodingKeys: String, CodingKey { case url, language, label, forced, isDefault }
}

/// The answer to "play this".
///
/// `url` points at Bunny and is signed for a few hours. Nothing here passes
/// through the server — that is the rule the whole system is built on, and it
/// holds on macOS because AVPlayer fetches the bytes itself.
public struct Playback: Codable, Sendable {
    public let url: URL
    public let container: String
    public let subtitles: [SubtitleTrack]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .url)
        guard let url = URL(string: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .url, in: c, debugDescription: "not a URL: \(raw)"
            )
        }
        self.url = url
        self.container = c.value(.container, or: "")
        self.subtitles = c.lossyArray(.subtitles)
    }

    private enum CodingKeys: String, CodingKey { case url, container, subtitles }
}
