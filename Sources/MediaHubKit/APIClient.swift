import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Errors

/// What can go wrong, in the terms the interface needs to react to.
///
/// The distinction that earns its keep is `unauthorized`: it is the one failure
/// with a specific answer — throw the session away and show the login screen —
/// and collapsing it into a generic HTTP error means every call site has to
/// re-derive that from a status code.
public enum MediaHubError: Error, Sendable, Equatable {
    /// The token is missing, expired, or the viewer has been switched off.
    case unauthorized
    /// The server answered, and said no.
    case server(status: Int, message: String)
    /// The request never got an answer. Carries a description rather than the
    /// original error because `Error` is not `Sendable`.
    case network(String)
    /// The answer did not have the shape it claims to have.
    case decoding(String)

    public var message: String {
        switch self {
        case .unauthorized:
            return "انتهت الجلسة. سجّل الدخول من جديد."
        case let .server(status, message):
            return message.isEmpty ? "الخادم ردّ بالرمز \(status)" : message
        case let .network(detail):
            return "تعذّر الوصول إلى الخادم — \(detail)"
        case let .decoding(detail):
            return "ردّ غير متوقّع من الخادم — \(detail)"
        }
    }
}

// MARK: - Transport

/// One HTTP round trip.
///
/// Abstracted so the client can be tested without a server. This is not
/// ceremony: `URLProtocol`-based stubbing is unreliable on Linux, and this
/// project's tests run on Linux. A closure-shaped seam works identically
/// everywhere and makes the tests read as "given this response, expect this".
public protocol Transport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: Transport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MediaHubError.network("لم يصل ردّ HTTP")
        }
        return (data, http)
    }
}

// MARK: - Client

/// The whole of the server, as this app sees it.
///
/// An `actor` because the token is mutable state that a video player, a library
/// grid and a background progress reporter all touch at once. Making it an
/// actor is what makes "the token was replaced mid-request" impossible rather
/// than merely unlikely.
public actor MediaHubClient {
    public let baseURL: URL
    private let transport: any Transport
    private var token: String?

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(baseURL: URL, transport: any Transport = URLSessionTransport(), token: String? = nil) {
        self.baseURL = baseURL
        self.transport = transport
        self.token = token
    }

    public var currentToken: String? { token }

    public func setToken(_ value: String?) {
        token = value
    }

    // MARK: Endpoints

    /// Exchanges a name and password for a bearer token good for thirty days.
    public func logIn(username: String, password: String) async throws -> Session {
        let session: Session = try await send(
            "auth/login",
            method: "POST",
            body: ["username": .string(username), "password": .string(password)],
            authenticated: false
        )
        token = session.token
        return session
    }

    /// The home screen: whatever rows the server decided exist, plus genres.
    public func home() async throws -> Home {
        try await send("home")
    }

    public enum Kind: String, Sendable {
        case movies
        case series
    }

    /// One page of the library.
    public func library(
        kind: Kind,
        limit: Int = 60,
        offset: Int = 0,
        query: String? = nil,
        genre: String? = nil,
        year: Int? = nil,
        sort: String? = nil
    ) async throws -> Page {
        var items = [
            URLQueryItem(name: "kind", value: kind.rawValue),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        if let genre, !genre.isEmpty { items.append(URLQueryItem(name: "genre", value: genre)) }
        if let year { items.append(URLQueryItem(name: "year", value: String(year))) }
        if let sort, !sort.isEmpty { items.append(URLQueryItem(name: "sort", value: sort)) }

        return try await send("library", query: items)
    }

    public func title(id: String) async throws -> TitleResponse {
        try await send("titles/\(escape(id))")
    }

    public func episodes(seriesID: String, season: Int) async throws -> [Episode] {
        struct Wrapper: Decodable { let episodes: [Episode] }
        let wrapper: Wrapper = try await send(
            "titles/\(escape(seriesID))/episodes",
            query: [URLQueryItem(name: "season", value: String(season))]
        )
        return wrapper.episodes
    }

    /// Mints a signed URL for one item.
    ///
    /// The URL points at Bunny, not at this server, and is valid for a few
    /// hours. Nothing about the file passes through the VPS — the whole system
    /// is built on that, and this call is where it is kept on macOS: AVPlayer
    /// takes the URL and fetches the bytes itself.
    public func playback(id: String) async throws -> Playback {
        try await send("playback", method: "POST", body: ["id": .string(id)])
    }

    /// Records where the viewer got to.
    ///
    /// Deliberately returns nothing and swallows nothing: a failed progress
    /// report is not worth interrupting playback over, but the caller should be
    /// able to decide that, so the error is thrown rather than eaten here.
    public func reportProgress(id: String, position: Ticks) async throws {
        struct Ack: Decodable { let ok: Bool? }
        let _: Ack = try await send(
            "progress",
            method: "POST",
            body: ["id": .string(id), "positionSeconds": .number(position.seconds)]
        )
    }

    /// Downloads and parses a subtitle track.
    ///
    /// Fetched straight from Bunny under its own signed URL, so this does not
    /// go through `send` — there is no bearer token to attach and no JSON
    /// envelope to unwrap.
    public func subtitles(at url: URL) async throws -> SubtitleDocument {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw MediaHubError.network(String(describing: error))
        }

        guard (200..<300).contains(response.statusCode) else {
            throw MediaHubError.server(status: response.statusCode, message: "تعذّر جلب ملف الترجمة")
        }
        return SubtitleParser.parse(data)
    }

    // MARK: Plumbing

    private func escape(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
    }

    private func send<T: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: [String: JSONValue]? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/v1/\(path)"),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }

        guard let url = components?.url else {
            throw MediaHubError.network("عنوان غير صالح: \(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if authenticated {
            guard let token else { throw MediaHubError.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? encoder.encode(body)
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as MediaHubError {
            throw error
        } catch {
            throw MediaHubError.network(String(describing: error))
        }

        // 401 first, and before any body parsing: it is the one status with a
        // specific remedy, and the body on a 401 is not worth reading.
        if response.statusCode == 401 {
            throw MediaHubError.unauthorized
        }

        guard (200..<300).contains(response.statusCode) else {
            let message = (try? decoder.decode(ServerErrorBody.self, from: data))?.error ?? ""
            throw MediaHubError.server(status: response.statusCode, message: message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MediaHubError.decoding(String(describing: error))
        }
    }
}

/// The server's error envelope: `{ "error": "…" }`.
private struct ServerErrorBody: Decodable {
    let error: String?
}

// MARK: - JSON bodies

/// A minimal JSON value, so request bodies can be written as dictionary
/// literals without reaching for `Any` and losing `Sendable` with it.
public enum JSONValue: Encodable, Sendable, ExpressibleByStringLiteral, ExpressibleByFloatLiteral,
                       ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    case string(String)
    case number(Double)
    case bool(Bool)

    public init(stringLiteral value: String) { self = .string(value) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        }
    }
}
