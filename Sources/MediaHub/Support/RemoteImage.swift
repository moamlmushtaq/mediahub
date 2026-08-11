import SwiftUI
import AppKit

/// Artwork, loaded once and kept.
///
/// WHY NOT `AsyncImage`
/// ===================
/// SwiftUI's built-in has no cache. Scroll a grid of sixty posters down and
/// back up and it re-downloads all sixty — which on a library grid means the
/// images visibly flicker away and return every time a row leaves the screen.
/// It also restarts the request when the view's identity changes, which a
/// `LazyVGrid` does constantly.
///
/// Sixty posters is also sixty requests to TMDb's CDN, and the images are
/// immutable: a poster path never changes content. Caching is not an
/// optimisation here, it is the difference between a grid that feels solid and
/// one that shimmers.
@MainActor
@Observable
final class ImageCache {
    static let shared = ImageCache()

    /// Bounded so a long session browsing a large library cannot grow without
    /// limit. `NSCache` evicts under memory pressure on its own, which is the
    /// behaviour wanted here — dropping a poster costs one re-download.
    private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 400
        return cache
    }()

    /// In-flight downloads carry `Data`, not `NSImage`.
    ///
    /// `NSImage` is not `Sendable` — it is a mutable AppKit object — so a
    /// `Task<NSImage?, Never>` cannot have its result awaited from the main
    /// actor under Swift 6. `Data` is `Sendable`, so the download crosses the
    /// boundary and the image is constructed on this side of it. The compiler
    /// caught this; it is a real rule, not a formality.
    private var inFlight: [URL: Task<Data?, Never>] = [:]

    func cached(_ url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    /// Places an image in the cache directly. Used by the snapshot renderer so
    /// screenshots show a full layout rather than a grid of empty placeholders.
    func store(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }

    func load(_ url: URL) async -> NSImage? {
        if let hit = cached(url) { return hit }

        // Coalesce: a rail and a grid can ask for the same poster in the same
        // frame, and without this that is two downloads of identical bytes.
        let task: Task<Data?, Never>
        if let existing = inFlight[url] {
            task = existing
        } else {
            task = Task<Data?, Never> {
                do {
                    var request = URLRequest(url: url)
                    request.cachePolicy = .returnCacheDataElseLoad
                    let (payload, response) = try await URLSession.shared.data(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    return (200..<300).contains(status) ? payload : nil
                } catch {
                    return nil
                }
            }
            inFlight[url] = task
        }

        let data = await task.value
        inFlight[url] = nil

        // Re-check the cache: a second caller that joined the same download
        // will have stored it already, and two `NSImage`s of the same bytes is
        // twice the memory for nothing.
        if let hit = cached(url) { return hit }

        guard let data, let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// An image that fades in once, and never flickers afterwards.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var placeholderSymbol: String = "film"

    @State private var image: NSImage?

    /// Resolved on every evaluation rather than only in `.task`.
    ///
    /// Two things this fixes. A cached poster now appears in the *first* frame
    /// instead of one frame of placeholder followed by a pop — which is what
    /// made a scrolled grid shimmer. And it is what lets the snapshot renderer
    /// see anything at all: `ImageRenderer` never runs `.task`, so an image
    /// that is only assigned there renders as an empty box, which is exactly
    /// how the first set of screenshots came back.
    private var resolved: NSImage? {
        if let image { return image }
        guard let url else { return nil }
        return ImageCache.shared.cached(url)
    }

    var body: some View {
        ZStack {
            if let image = resolved {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Placeholder(systemImage: placeholderSymbol)
            }
        }
        // Without this the view has no intrinsic size of its own and collapses
        // to whatever the placeholder glyph measures — which is how a 460-point
        // hero rendered as a tiny film icon floating in a black rectangle.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.22), value: resolved != nil)
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            // Synchronous cache hit: no flash of placeholder at all.
            if ImageCache.shared.cached(url) != nil { return }
            image = await ImageCache.shared.load(url)
        }
    }
}
