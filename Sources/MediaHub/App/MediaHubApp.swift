import SwiftUI
import MediaHubKit

/// The application.
///
/// Thin by design. Everything that can be handed to `MediaHubKit` is handed to
/// `MediaHubKit`, because this target can only be compiled on a Mac while the
/// kit compiles and tests anywhere — so every decision that lives up here is a
/// decision that stops being covered by tests.
@main
struct MediaHubApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                // The library is dark artwork on dark ground; a light window
                // behind it would flash white on every launch.
                .preferredColorScheme(.dark)
                // Arabic first, set once at the root so a screen added later
                // cannot forget it. (The last client got this exactly wrong in
                // the other direction and mirrored its own player controls.)
                .environment(\.layoutDirection, .rightToLeft)
                .task { await app.restore() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_360, height: 860)
        .commands {
            // A library app has no use for "New Window", and leaving the
            // default in place offers a command that does nothing useful.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {}
        }
    }
}

/// The window's contents: login, or the library.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.phase {
        case .restoring:
            // Deliberately blank rather than a spinner. Reading the Keychain
            // takes milliseconds, and a spinner that appears and vanishes in
            // one frame reads as a flicker, not as progress.
            Color.clear.pageBackground()

        case let .signedOut(message):
            LoginView(notice: message)
                .transition(.opacity)

        case .signedIn:
            LibraryShell()
                .transition(.opacity)
        }
    }
}

/// The signed-in app: a sidebar and whatever it selects.
struct LibraryShell: View {
    @Environment(AppModel.self) private var app

    enum Section: Hashable {
        case home
        case movies
        case series
    }

    @State private var selection: Section? = .home
    @State private var path: [MediaCard] = []

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack(path: $path) {
                content
                    .navigationDestination(for: MediaCard.self) { card in
                        // Placeholder until the detail screen lands; it is
                        // named honestly rather than left as an empty view, so
                        // an unfinished path is obvious rather than looking
                        // like a bug.
                        EmptyState(
                            symbol: "rectangle.stack",
                            title: card.name,
                            message: "صفحة التفاصيل قيد الإنشاء."
                        )
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var content: some View {
        switch selection ?? .home {
        case .home:
            HomeView(onSelect: open, onPlay: open)
                .navigationTitle("الرئيسية")
        case .movies:
            LibraryView(title: "أفلام", kind: .movies, onSelect: open)
        case .series:
            LibraryView(title: "مسلسلات", kind: .series, onSelect: open)
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Label("الرئيسية", systemImage: "house").tag(Section.home)
            Label("أفلام", systemImage: "film").tag(Section.movies)
            Label("مسلسلات", systemImage: "tv").tag(Section.series)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        .safeAreaInset(edge: .bottom) {
            accountRow
        }
    }

    private var accountRow: some View {
        HStack(spacing: Theme.space(2)) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(Theme.Palette.gold)

            Text(app.viewer?.name ?? "")
                .font(Theme.Type.label)
                .foregroundStyle(Theme.Palette.ash)
                .lineLimit(1)

            Spacer()

            Button {
                Task { await app.signOut() }
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Palette.dim)
            .help("تسجيل الخروج")
        }
        .padding(.horizontal, Theme.space(4))
        .padding(.vertical, Theme.space(3))
    }

    private func open(_ card: MediaCard) {
        path.append(card)
    }
}
