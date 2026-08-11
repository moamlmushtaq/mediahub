import Foundation

/// Where the posters come from.
///
/// Straight from TMDb's CDN to the Mac — the same rule the video follows.
/// Nothing image-shaped is proxied through the server, which matters more than
/// it sounds: a grid of sixty posters is sixty requests, and routing those
/// through a 4-vCPU box shared with production sites would cost more than
/// streaming the films does.
///
/// The `tag` carried by the API is a TMDb path such as `/abc123.jpg`, including
/// its leading slash. It is stored, not constructed, so that changing the size
/// the app asks for never invalidates anything cached server-side.
public enum Artwork {
    /// TMDb's fixed rendition widths. These are not arbitrary — the CDN only
    /// serves this set, and asking for a width that is not on it returns a 404.
    public enum Size: String, Sendable {
        /// Grid posters.
        case poster = "w342"
        /// Detail-page posters on a Retina display.
        case posterLarge = "w500"
        /// Backdrops behind a hero.
        case backdrop = "w780"
        /// A full-bleed backdrop on a large display.
        case backdropLarge = "w1280"
        /// Cast headshots.
        case headshot = "w185"
        case original
    }

    static let host = "https://image.tmdb.org/t/p"

    /// Builds the URL for one artwork path, or `nil` when there is no artwork.
    ///
    /// Returning an optional rather than a placeholder URL is deliberate: a
    /// personal library always contains files no metadata provider has heard
    /// of, so "no image" is a normal state the interface has to draw, and
    /// handing it a URL that 404s turns a clean fallback into a failed request
    /// and an empty box.
    public static func url(_ tag: String?, size: Size = .poster) -> URL? {
        guard let tag, !tag.isEmpty else { return nil }
        // Defend against a tag stored without its leading slash; TMDb's path
        // needs exactly one and two produces a 404.
        let path = tag.hasPrefix("/") ? tag : "/\(tag)"
        return URL(string: "\(host)/\(size.rawValue)\(path)")
    }
}

extension MediaCard {
    public func posterURL(_ size: Artwork.Size = .poster) -> URL? {
        Artwork.url(imageTags.primary, size: size)
    }

    /// The backdrop, falling back to the poster.
    ///
    /// A hero with nothing behind it is the worst-looking screen in the app, so
    /// a portrait poster stretched behind a gradient beats an empty rectangle.
    public func backdropURL(_ size: Artwork.Size = .backdrop) -> URL? {
        Artwork.url(backdropTag, size: size) ?? Artwork.url(imageTags.primary, size: size)
    }

    public var logoURL: URL? {
        Artwork.url(imageTags.logo, size: .backdrop)
    }
}

extension Episode {
    public func stillURL(_ size: Artwork.Size = .backdrop) -> URL? {
        Artwork.url(imageTag, size: size)
    }
}

extension Person {
    public var headshotURL: URL? {
        Artwork.url(imageTag, size: .headshot)
    }
}

extension Season {
    public func posterURL(_ size: Artwork.Size = .poster) -> URL? {
        Artwork.url(imageTag, size: size)
    }
}
