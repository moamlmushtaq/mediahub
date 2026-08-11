import Foundation
import Observation
import MediaHubKit

/// Who is signed in, and the client that speaks for them.
///
/// One object, owned by the scene, passed down through the environment. It is
/// the only thing in the app that knows a token exists — screens ask it for a
/// client and never see the credential.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        /// Reading the Keychain. Brief, but it must not flash the login screen
        /// on every launch of an app that is already signed in.
        case restoring
        case signedOut(message: String?)
        case signedIn(Viewer)
    }

    private(set) var phase: Phase = .restoring
    private(set) var client: MediaHubClient

    /// Overridable so a developer can point at a local server, and so no host
    /// is baked into a binary that gets published.
    static var host: URL {
        if let raw = ProcessInfo.processInfo.environment["MEDIAHUB_URL"],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://mediahub.2msol.com")!
    }

    init(host: URL = AppModel.host) {
        self.client = MediaHubClient(baseURL: host)
    }

    var viewer: Viewer? {
        if case let .signedIn(viewer) = phase { return viewer }
        return nil
    }

    /// Restores a session from the Keychain, if there is one.
    ///
    /// Deliberately does **not** verify the token with the server first. A
    /// round trip before the first frame means a spinner on every launch on a
    /// slow connection; instead the app trusts the stored token, draws, and
    /// lets the first real request discover an expiry — at which point
    /// ``handle(_:)`` sends the viewer to the login screen with a reason.
    func restore() async {
        guard let token = Keychain.read(Keychain.Account.token),
              let data = Keychain.read(Keychain.Account.viewer)?.data(using: .utf8),
              let viewer = try? JSONDecoder().decode(Viewer.self, from: data)
        else {
            phase = .signedOut(message: nil)
            return
        }

        await client.setToken(token)
        phase = .signedIn(viewer)
    }

    func signIn(username: String, password: String) async throws {
        let session = try await client.logIn(username: username, password: password)

        Keychain.write(session.token, account: Keychain.Account.token)
        if let encoded = try? JSONEncoder().encode(session.viewer),
           let json = String(data: encoded, encoding: .utf8) {
            Keychain.write(json, account: Keychain.Account.viewer)
        }

        phase = .signedIn(session.viewer)
    }

    func signOut(message: String? = nil) async {
        await client.setToken(nil)
        Keychain.write(nil, account: Keychain.Account.token)
        Keychain.write(nil, account: Keychain.Account.viewer)
        phase = .signedOut(message: message)
    }

    /// Routes an error that came back from any screen.
    ///
    /// Centralised because exactly one kind of failure changes what the whole
    /// app should be showing — an expired or revoked session — and having every
    /// screen decide that for itself is how one of them ends up not deciding it
    /// and showing an empty grid forever.
    func handle(_ error: Error) async {
        if let error = error as? MediaHubError, error == .unauthorized {
            await signOut(message: MediaHubError.unauthorized.message)
        }
    }

    /// The subtitle language chosen last time, across launches.
    var preferredSubtitleLanguage: String? {
        get { Keychain.read(Keychain.Account.subtitleLanguage) }
        set { Keychain.write(newValue, account: Keychain.Account.subtitleLanguage) }
    }
}
