import SwiftUI
import AppKit
import MediaHubKit

/// Renders the app's screens to PNG files and exits.
///
/// WHY THIS EXISTS
/// ===============
/// This project is developed on a Linux server. The author cannot open the app,
/// and has now shipped three clients whose interfaces were never once looked at
/// before they reached the person using them. All three came back the same way:
/// "it looks very bad." Compiling proves a layout is *legal*, not that it is
/// *good*, and no amount of care in the source substitutes for seeing the
/// pixels.
///
/// So the app renders itself. `MediaHub --snapshot <dir>` draws every screen
/// with fixture data straight into image files and quits without ever opening a
/// window. CI runs it on a Mac and uploads the results, and they get looked at
/// before anything is called finished.
///
/// `ImageRenderer` rather than launching the app and screen-capturing it:
/// rendering needs no window server, no login session and no timing guesses,
/// and it produces the same image every run — so two builds can be compared and
/// the difference is a real change rather than a scroll position.
@MainActor
enum Snapshots {
    /// Sizes chosen to match how the app is actually used: a 16-inch window,
    /// and one at the minimum the window allows, because layouts break at the
    /// small end and nobody ever tests there.
    static let wide = CGSize(width: 1_440, height: 900)
    static let narrow = CGSize(width: 900, height: 620)

    private static var folder = URL(fileURLWithPath: ".")

    static func run(into directory: String) {
        folder = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        seedArtwork()

        let app = AppModel(host: URL(string: "https://example.invalid")!)

        write(name: "01-login", size: wide) {
            LoginView(notice: nil).environment(app)
        }

        write(name: "02-login-error", size: narrow) {
            LoginView(notice: "انتهت الجلسة. سجّل الدخول من جديد.").environment(app)
        }

        write(name: "03-home", size: wide) {
            SnapshotHome().environment(app)
        }

        write(name: "03b-shell", size: wide) {
            SnapshotShell().environment(app)
        }

        write(name: "04-hero", size: CGSize(width: 1_440, height: 460)) {
            HeroView(item: Fixtures.complete, onPlay: { _ in }, onDetails: { _ in })
        }

        write(name: "05-grid", size: wide) {
            ScrollView { PosterGrid(items: Fixtures.movies, onSelect: { _ in }) }
                .pageBackground()
        }

        write(name: "06-grid-narrow", size: narrow) {
            ScrollView { PosterGrid(items: Fixtures.movies, onSelect: { _ in }) }
                .pageBackground()
        }

        write(name: "07-rail", size: CGSize(width: 1_440, height: 340)) {
            MediaRail(title: "تابع المشاهدة", items: Fixtures.movies, onSelect: { _ in })
                .padding(.vertical, Theme.space(6))
                .pageBackground()
        }

        write(name: "08-episodes", size: CGSize(width: 900, height: 400)) {
            VStack(spacing: 0) {
                ForEach(Fixtures.episodes) { episode in
                    EpisodeRow(episode: episode, onPlay: {})
                    Divider().background(Theme.Palette.hair)
                }
            }
            .padding(Theme.space(6))
            .pageBackground()
        }

        write(name: "09-states", size: CGSize(width: 900, height: 320)) {
            HStack(spacing: 0) {
                EmptyState(symbol: "film.stack", title: "المكتبة فارغة", message: "لم يُضف أي عمل بعد.")
                FailureState(message: "تعذّر الوصول إلى الخادم.", retry: {})
            }
        }

        write(name: "10-poster-cards", size: CGSize(width: 900, height: 300)) {
            HStack(alignment: .top, spacing: Theme.space(4)) {
                // Deliberately the awkward ones: no artwork, a long title, a
                // half-watched film and a finished one. A row of tidy cards
                // proves nothing.
                PosterCard(item: Fixtures.bare)
                PosterCard(item: Fixtures.longTitle)
                PosterCard(item: Fixtures.inProgress)
                PosterCard(item: Fixtures.finished)
            }
            .padding(Theme.space(6))
            .pageBackground()
        }

        FileHandle.standardOutput.write(Data("wrote snapshots to \(directory)\n".utf8))
    }

    // MARK: Rendering

    private static func write<V: View>(name: String, size: CGSize, @ViewBuilder _ view: () -> V) {
        let content = view()
            .frame(width: size.width, height: size.height)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: content)
        // 2x, because this is judged on a Retina display and hairlines,
        // letterforms and 1-point borders are exactly what goes wrong.
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("failed to render \(name)\n".utf8))
            return
        }

        try? png.write(to: folder.appendingPathComponent("\(name).png"))
    }

    /// Fills the image cache with stand-in artwork.
    ///
    /// Without this every poster renders as the empty placeholder and the
    /// screenshots say nothing about the thing they exist to show — how the
    /// layout behaves when it is full. The stand-ins are flat gradients rather
    /// than real posters on purpose: they carry no detail to be distracted by,
    /// so what is being judged is spacing, proportion and hierarchy.
    private static func seedArtwork() {
        let colours: [(NSColor, NSColor)] = [
            (.init(red: 0.16, green: 0.19, blue: 0.28, alpha: 1), .init(red: 0.30, green: 0.20, blue: 0.22, alpha: 1)),
            (.init(red: 0.22, green: 0.18, blue: 0.14, alpha: 1), .init(red: 0.12, green: 0.16, blue: 0.20, alpha: 1)),
            (.init(red: 0.14, green: 0.22, blue: 0.20, alpha: 1), .init(red: 0.24, green: 0.14, blue: 0.24, alpha: 1)),
        ]

        var index = 0
        let cards = Fixtures.movies + Fixtures.allSeries + [Fixtures.complete]
        for card in cards {
            for url in [card.posterURL(), card.posterURL(.posterLarge),
                        card.backdropURL(), card.backdropURL(.backdropLarge)].compactMap({ $0 }) {
                let pair = colours[index % colours.count]
                ImageCache.shared.seed(gradient(pair.0, pair.1), for: url)
            }
            index += 1
        }

        for person in Fixtures.people {
            if let url = person.headshotURL {
                ImageCache.shared.seed(gradient(.darkGray, .gray), for: url)
            }
        }
        for episode in Fixtures.episodes {
            if let url = episode.stillURL() {
                ImageCache.shared.seed(gradient(colours[1].0, colours[1].1), for: url)
            }
        }
    }

    private static func gradient(_ from: NSColor, _ to: NSColor) -> NSImage {
        let size = NSSize(width: 400, height: 600)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(starting: from, ending: to)?.draw(in: NSRect(origin: .zero, size: size), angle: 300)
        image.unlockFocus()
        return image
    }
}

extension CommandLine {
    /// The directory passed after `--snapshot`, if any.
    static var snapshotDirectory: String? {
        guard let index = arguments.firstIndex(of: "--snapshot"),
              index + 1 < arguments.count
        else { return nil }
        return arguments[index + 1]
    }
}

extension ImageCache {
    /// Puts an image in the cache without going near the network.
    func seed(_ image: NSImage, for url: URL) {
        store(image, for: url)
    }
}
