import Foundation
import Testing
@testable import MediaHubKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A transport that answers from a script and remembers what it was asked.
///
/// An actor because the tests inspect it after an `await`, and Swift 6 will not
/// let a mutable class cross that boundary — which is the point of the language
/// mode rather than an obstacle to it.
actor FakeTransport: Transport {
    struct Reply: Sendable {
        let status: Int
        let body: Data

        init(status: Int = 200, json: String) {
            self.status = status
            self.body = Data(json.utf8)
        }

        init(status: Int = 200, body: Data) {
            self.status = status
            self.body = body
        }
    }

    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    init(_ reply: Reply) {
        self.replies = [reply]
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let reply = replies.isEmpty ? Reply(status: 500, json: "{}") : replies.removeFirst()
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.invalid")!,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (reply.body, response)
    }

    var lastRequest: URLRequest? { requests.last }
}

private let base = URL(string: "https://mediahub.2msol.com")!

@Suite("Authentication")
struct AuthTests {
    @Test("keeps the token from a successful login")
    func storesToken() async throws {
        let transport = FakeTransport(.init(json: """
        {"token":"abc.def","expiresAt":4102444800,
         "viewer":{"id":3,"slug":"moaml","name":"مؤمل"}}
        """))
        let client = MediaHubClient(baseURL: base, transport: transport)

        let session = try await client.logIn(username: "moaml", password: "secret")

        #expect(session.token == "abc.def")
        #expect(session.viewer.name == "مؤمل")
        #expect(session.isValid())
        // The token has to be retained, or the very next call 401s.
        #expect(await client.currentToken == "abc.def")
    }

    @Test("reports a rejected password as unauthorized, not as a server error")
    func wrongPassword() async throws {
        let transport = FakeTransport(.init(status: 401, json: #"{"error":"بيانات غير صحيحة"}"#))
        let client = MediaHubClient(baseURL: base, transport: transport)

        await #expect(throws: MediaHubError.unauthorized) {
            _ = try await client.logIn(username: "moaml", password: "wrong")
        }
    }

    @Test("refuses to make an authenticated call with no token")
    func noToken() async throws {
        // Without this the request goes out bare, comes back 401, and the UI
        // reports a session expiry that never existed.
        let transport = FakeTransport(.init(json: "{}"))
        let client = MediaHubClient(baseURL: base, transport: transport)

        await #expect(throws: MediaHubError.unauthorized) {
            _ = try await client.home()
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("attaches the bearer token")
    func sendsBearer() async throws {
        let transport = FakeTransport(.init(json: #"{"rails":[],"genres":[]}"#))
        let client = MediaHubClient(baseURL: base, transport: transport, token: "tok123")

        _ = try await client.home()

        let header = await transport.lastRequest?.value(forHTTPHeaderField: "Authorization")
        #expect(header == "Bearer tok123")
    }

    @Test("detects an expired session from its own timestamp")
    func expiry() {
        let past = Session(
            token: "t",
            expiresAt: 1_000_000,
            viewer: Viewer(id: 1, slug: "a", name: "A")
        )
        #expect(!past.isValid())
    }
}

@Suite("Requests")
struct RequestTests {
    @Test("builds the library query")
    func libraryQuery() async throws {
        let transport = FakeTransport(.init(json: #"{"items":[],"total":0}"#))
        let client = MediaHubClient(baseURL: base, transport: transport, token: "t")

        _ = try await client.library(kind: .series, limit: 20, offset: 40, query: "هيل", genre: "دراما")

        let url = try #require(await transport.lastRequest?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let pairs = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        #expect(url.path == "/api/v1/library")
        #expect(pairs["kind"] == "series")
        #expect(pairs["limit"] == "20")
        #expect(pairs["offset"] == "40")
        #expect(pairs["q"] == "هيل")
        #expect(pairs["genre"] == "دراما")
        // Absent filters must not be sent as empty strings — the server treats
        // a present-but-empty `year` as a filter and returns nothing.
        #expect(pairs["year"] == nil)
        #expect(pairs["sort"] == nil)
    }

    @Test("posts progress in seconds, not ticks")
    func progressUnits() async throws {
        // The API takes seconds; everything inside the app is ticks. Getting
        // this backwards writes a resume point ten million times too far in.
        let transport = FakeTransport(.init(json: #"{"ok":true}"#))
        let client = MediaHubClient(baseURL: base, transport: transport, token: "t")

        try await client.reportProgress(id: "m7", position: Ticks(seconds: 125))

        let body = try #require(await transport.lastRequest?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["id"] as? String == "m7")
        #expect((json["positionSeconds"] as? Double) == 125)
    }

    @Test("escapes an id with a slash in it")
    func escapesPath() async throws {
        let transport = FakeTransport(.init(json: #"{"episodes":[]}"#))
        let client = MediaHubClient(baseURL: base, transport: transport, token: "t")

        _ = try await client.episodes(seriesID: "n7-2", season: 2)

        let url = try #require(await transport.lastRequest?.url)
        #expect(url.path == "/api/v1/titles/n7-2/episodes")
        #expect(url.query?.contains("season=2") == true)
    }

    @Test("passes the server's own message through on an error")
    func serverMessage() async throws {
        // The server writes these in Arabic for the viewer; inventing our own
        // wording here would replace a specific reason with a generic one.
        let transport = FakeTransport(.init(status: 403, json: #"{"error":"الحساب موقوف"}"#))
        let client = MediaHubClient(baseURL: base, transport: transport, token: "t")

        await #expect(throws: MediaHubError.server(status: 403, message: "الحساب موقوف")) {
            _ = try await client.playback(id: "m7")
        }
    }

    @Test("does not mistake a transport failure for a server answer")
    func transportFailure() async throws {
        struct Boom: Error {}
        struct Failing: Transport {
            func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw Boom() }
        }
        let client = MediaHubClient(baseURL: base, transport: Failing(), token: "t")

        do {
            _ = try await client.home()
            Issue.record("expected a throw")
        } catch let error as MediaHubError {
            guard case .network = error else {
                Issue.record("expected .network, got \(error)")
                return
            }
        }
    }
}

@Suite("Decoding real payloads")
struct DecodingTests {
    @Test("decodes the home screen")
    func home() async throws {
        let transport = FakeTransport(.init(json: """
        {"rails":[
          {"key":"resume","title":"تابع المشاهدة","items":[
            {"id":"m7","name":"مشروع هيل ماري","originalTitle":"Project Hail Mary",
             "type":"Movie","year":2026,"communityRating":8.7,"officialRating":null,
             "runtimeMinutes":120,"overview":"ملخّص",
             "imageTags":{"primary":"/abc.jpg","logo":null,"thumb":null},
             "backdropTag":"/back.jpg",
             "userData":{"played":false,"playbackPositionTicks":18000000000,"playedPercentage":25}}
          ]}],
         "genres":[{"id":"1","name":"دراما"}]}
        """))
        let client = MediaHubClient(baseURL: base, transport: transport, token: "t")

        let home = try await client.home()

        #expect(home.rails.count == 1)
        #expect(home.rails[0].key == "resume")
        let card = try #require(home.rails[0].items.first)
        #expect(card.name == "مشروع هيل ماري")
        #expect(card.type == .movie)
        #expect(card.communityRating == 8.7)
        #expect(card.officialRating == nil)
        #expect(card.userData.playbackPosition.seconds == 1800)
        // 30 minutes into a 120 minute film: worth resuming.
        #expect(card.startingPoint.seconds == 1800)
        #expect(home.genres.first?.name == "دراما")
    }

    @Test("draws a card that the metadata provider knew nothing about")
    func sparseCard() async throws {
        // Real files in this library have no TMDb match at all. Refusing to
        // decode one would blank the whole grid it appears in.
        let transport = FakeTransport(.init(json: """
        {"items":[{"id":"m99","name":"Some.Release.2019","type":"Movie"}],"total":1}
        """))
        let client = MediaHubClient(baseURL: base, transport: transport, token: "t")

        let page = try await client.library(kind: .movies)

        let card = try #require(page.items.first)
        #expect(card.name == "Some.Release.2019")
        #expect(card.year == nil)
        #expect(card.overview == "")
        #expect(card.imageTags.primary == nil)
        #expect(card.userData.playbackPosition == .zero)
    }

    @Test("drops a card with no identity and keeps the rest of the page")
    func missingID() async throws {
        // A record with no id cannot be opened, so it must not be drawn. What
        // must NOT happen is the rest of the page going with it: the first
        // version of this decoder wrapped the whole array in `try?`, so one bad
        // record emptied the grid and the app reported "no films" — a symptom
        // that points at everything except the actual cause.
        let transport = FakeTransport(.init(json: """
        {"items":[
          {"id":"m1","name":"قبله","type":"Movie"},
          {"name":"لا معرّف","type":"Movie"},
          {"id":"m2","name":"بعده","type":"Movie"}],
         "total":3}
        """))
        let client = MediaHubClient(baseURL: base, transport: transport, token: "t")

        let page = try await client.library(kind: .movies)

        #expect(page.items.map(\.id) == ["m1", "m2"])
        // `total` is the server's count and is left alone: the client dropping
        // a row locally does not change how many the library holds.
        #expect(page.total == 3)
    }

    @Test("keeps the good rails when one is malformed")
    func lossyRails() async throws {
        let transport = FakeTransport(.init(json: """
        {"rails":[
          {"title":"بلا مفتاح","items":[]},
          {"key":"movies","title":"أفلام","items":[{"id":"m1","name":"فيلم","type":"Movie"}]}],
         "genres":[]}
        """))
        let client = MediaHubClient(baseURL: base, transport: transport, token: "t")

        let home = try await client.home()

        #expect(home.rails.map(\.key) == ["movies"])
        #expect(home.rails[0].items.count == 1)
    }

    @Test("decodes a detail page with its flat card fields")
    func detail() async throws {
        let transport = FakeTransport(.init(json: """
        {"item":{"id":"s3","name":"مسلسل","type":"Series","overview":"",
                 "imageTags":{"primary":null,"logo":null,"thumb":null},
                 "userData":{"played":false,"playbackPositionTicks":0,"playedPercentage":0},
                 "genres":["دراما","إثارة"],"studios":[],
                 "people":[{"id":"p1","name":"ممثل","role":"دور","type":"Actor","imageTag":null}],
                 "tagline":"سطر","mediaSources":[
                   {"id":"f1","path":"/Movies/x.mkv","container":"mkv","size":123}]},
         "seasons":[{"id":"n3-1","name":"الموسم 1","indexNumber":1,"imageTag":null,"episodeCount":8}]}
        """))
        let client = MediaHubClient(baseURL: base, transport: transport, token: "t")

        let response = try await client.title(id: "s3")

        #expect(response.item.card.name == "مسلسل")
        #expect(response.item.card.type == .series)
        #expect(response.item.genres == ["دراما", "إثارة"])
        #expect(response.item.people.first?.role == "دور")
        #expect(response.item.mediaSources.first?.container == "mkv")
        #expect(response.seasons.first?.episodeCount == 8)
    }

    @Test("decodes a playback answer and its subtitle tracks")
    func playback() async throws {
        let transport = FakeTransport(.init(json: """
        {"url":"https://mediahub2m.b-cdn.net/Movies/x.mp4?token=abc&expires=123",
         "container":"mp4","direct":true,
         "subtitles":[
           {"url":"https://mediahub2m.b-cdn.net/Movies/Subs/ara.srt?token=d",
            "language":"ar","label":"العربية","forced":false,"isDefault":true},
           {"url":"https://mediahub2m.b-cdn.net/Movies/Subs/eng.srt?token=e",
            "language":"en","label":"English","forced":false,"isDefault":false}]}
        """))
        let client = MediaHubClient(baseURL: base, transport: transport, token: "t")

        let playback = try await client.playback(id: "m7")

        // The URL must point at Bunny, never at the server: that is the rule
        // the entire system exists to keep.
        #expect(playback.url.host == "mediahub2m.b-cdn.net")
        #expect(playback.container == "mp4")
        #expect(playback.subtitles.count == 2)
        #expect(playback.subtitles.first?.isDefault == true)
        #expect(playback.subtitles.first?.language == "ar")
    }

    @Test("fetches and parses a subtitle track in one step")
    func subtitleFetch() async throws {
        var bytes: [UInt8] = Array("1\n00:00:01,000 --> 00:00:04,000\n".utf8)
        bytes += [0xE3, 0xD1, 0xCD, 0xC8, 0xC7]   // مرحبا, in Windows-1256
        let transport = FakeTransport(.init(body: Data(bytes)))
        let client = MediaHubClient(baseURL: base, transport: transport, token: "t")

        let doc = try await client.subtitles(at: URL(string: "https://cdn.invalid/ara.srt")!)

        #expect(doc.cues.count == 1)
        #expect(doc.cues(at: 2).first?.text == "مرحبا")
        // No bearer token on a Bunny URL: the signature in the URL is the
        // authorisation, and sending our token to a CDN would leak it.
        #expect(await transport.lastRequest?.value(forHTTPHeaderField: "Authorization") == nil)
    }
}
