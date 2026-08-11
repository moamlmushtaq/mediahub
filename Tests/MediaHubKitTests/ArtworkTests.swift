import Foundation
import Testing
@testable import MediaHubKit

@Suite("Artwork URLs")
struct ArtworkTests {
    @Test("builds a TMDb URL at the requested size")
    func buildsURL() {
        #expect(Artwork.url("/abc.jpg")?.absoluteString == "https://image.tmdb.org/t/p/w342/abc.jpg")
        #expect(Artwork.url("/abc.jpg", size: .backdrop)?.absoluteString
                == "https://image.tmdb.org/t/p/w780/abc.jpg")
        #expect(Artwork.url("/abc.jpg", size: .original)?.absoluteString
                == "https://image.tmdb.org/t/p/original/abc.jpg")
    }

    @Test("returns nothing when there is no artwork")
    func noArtwork() {
        // Normal, not exceptional: a personal library always holds files no
        // metadata provider recognises.
        #expect(Artwork.url(nil) == nil)
        #expect(Artwork.url("") == nil)
    }

    @Test("does not produce a double slash")
    func normalisesSlash() {
        // TMDb 404s on `//abc.jpg`, and the failure looks like a missing image
        // rather than a malformed URL.
        #expect(Artwork.url("abc.jpg")?.absoluteString == "https://image.tmdb.org/t/p/w342/abc.jpg")
    }

    @Test("falls back from a missing backdrop to the poster")
    func backdropFallback() {
        // A hero with nothing behind it is the worst-looking screen in the app.
        let card = MediaCard(
            id: "m1", name: "فيلم", type: .movie,
            imageTags: ImageTags(primary: "/poster.jpg"),
            backdropTag: nil
        )
        #expect(card.backdropURL()?.absoluteString == "https://image.tmdb.org/t/p/w780/poster.jpg")
    }

    @Test("prefers a real backdrop when there is one")
    func prefersBackdrop() {
        let card = MediaCard(
            id: "m1", name: "فيلم", type: .movie,
            imageTags: ImageTags(primary: "/poster.jpg"),
            backdropTag: "/back.jpg"
        )
        #expect(card.backdropURL()?.absoluteString == "https://image.tmdb.org/t/p/w780/back.jpg")
    }

    @Test("has nothing to show when neither exists")
    func neither() {
        let card = MediaCard(id: "m1", name: "فيلم", type: .movie)
        #expect(card.backdropURL() == nil)
        #expect(card.posterURL() == nil)
        #expect(card.logoURL == nil)
    }
}
