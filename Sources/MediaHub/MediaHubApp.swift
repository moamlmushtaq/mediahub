import SwiftUI
import MediaHubKit

/// The application.
///
/// Thin by design. Everything this file can hand to `MediaHubKit` it hands to
/// `MediaHubKit`, because this target can only be compiled on a Mac and the kit
/// can be compiled and tested anywhere — so every decision that lives here is a
/// decision that stops being covered by tests.
///
/// What legitimately belongs here: windows, scenes, views, and the player.
@main
struct MediaHubApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                // The library is dark artwork on a dark ground; a light window
                // behind it would flash white on every launch.
                .preferredColorScheme(.dark)
                // Arabic first. `.rightToLeft` here rather than per-view so a
                // screen added later cannot forget it — the last client got
                // this wrong in the opposite direction and mirrored its own
                // player controls.
                .environment(\.layoutDirection, .rightToLeft)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_360, height: 860)
        .commands {
            // Replaces "New Window", which a library app has no use for.
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Who is signed in, and the client that speaks for them.
///
/// `@Observable` and `@MainActor`: it is read by views, so it belongs to the
/// main actor, and every call it makes hops to the client's actor and back.
@MainActor
@Observable
final class SessionStore {
    private(set) var viewer: Viewer?
    private(set) var client: MediaHubClient

    /// Overridable so a developer can point the app at a local server, and so
    /// no host is compiled into a binary that gets published.
    static let defaultHost = URL(string: "https://mediahub.2msol.com")!

    init(host: URL = SessionStore.defaultHost) {
        self.client = MediaHubClient(baseURL: host)
    }

    var isSignedIn: Bool { viewer != nil }

    func signIn(username: String, password: String) async throws {
        let session = try await client.logIn(username: username, password: password)
        viewer = session.viewer
    }

    func signOut() async {
        await client.setToken(nil)
        viewer = nil
    }
}

/// Placeholder root.
///
/// Present so the macOS build has something real to compile while the interface
/// is being written, and so CI proves the toolchain end to end from the first
/// commit rather than from the last one.
struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(spacing: 12) {
            Text("ميديا هَب")
                .font(.system(size: 28, weight: .bold))
            Text(session.isSignedIn ? "جاهز" : "لم يبدأ تسجيل الدخول بعد")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.043, green: 0.039, blue: 0.035))
    }
}
