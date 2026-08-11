import SwiftUI
import MediaHubKit

/// The home screen, composed from fixtures.
///
/// `HomeView` itself cannot be rendered here: it fetches in `.task`, and
/// `ImageRenderer` does not run tasks, so it would draw its loading spinner and
/// tell us nothing. This reproduces the same composition over fixed data.
///
/// The duplication is deliberate and small — a hero and a list of rails. What
/// it buys is a picture of the screen that is actually being judged.
struct SnapshotHome: View {
    var body: some View {
        // Eager stacks, not ScrollView + LazyVStack.
        //
        // `ImageRenderer` lays out into an unbounded offscreen context with no
        // viewport, and a lazy container asked to fill a viewport it does not
        // have produces nothing at all. The first run of this renderer emitted
        // a solid black 1440x900 image for exactly that reason — which read as
        // "the home screen is broken" rather than "the screenshot is".
        VStack(alignment: .leading, spacing: Theme.space(7)) {
            HeroView(item: Fixtures.complete, onPlay: { _ in }, onDetails: { _ in })

            ForEach(Fixtures.rails.prefix(2)) { rail in
                EagerRail(title: rail.title, items: Array(rail.items.prefix(6)))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .pageBackground()
    }
}

/// The whole window, sidebar included — the only view that shows whether the
/// pieces sit together, which is a different question from whether each one
/// looks right on its own.
struct SnapshotShell: View {
    var body: some View {
        HStack(spacing: 0) {
            SnapshotHome()

            VStack(alignment: .leading, spacing: Theme.space(1)) {
                Label("الرئيسية", systemImage: "house")
                Label("أفلام", systemImage: "film")
                Label("مسلسلات", systemImage: "tv")
                Spacer()
                HStack(spacing: Theme.space(2)) {
                    Image(systemName: "person.crop.circle").foregroundStyle(Theme.Palette.gold)
                    Text("مؤمل").font(Theme.Typography.label).foregroundStyle(Theme.Palette.ash)
                    Spacer()
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(Theme.Palette.dim)
                }
            }
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Palette.bone)
            .padding(Theme.space(4))
            .frame(width: 200)
            .background(Theme.Palette.inkPanel)
        }
    }
}


/// A rail without the horizontal `ScrollView`, for rendering offscreen.
struct EagerRail: View {
    let title: String
    let items: [MediaCard]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space(3)) {
            Text(title)
                .font(Theme.Typography.heading)
                .foregroundStyle(Theme.Palette.bone)
                .padding(.horizontal, Theme.space(8))

            HStack(alignment: .top, spacing: Theme.space(4)) {
                ForEach(items) { PosterCard(item: $0) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.space(8))
        }
    }
}

/// A grid without `LazyVGrid`, for the same reason.
struct EagerGrid: View {
    let items: [MediaCard]
    let columns: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space(6)) {
            ForEach(Array(stride(from: 0, to: items.count, by: columns)), id: \.self) { start in
                HStack(alignment: .top, spacing: Theme.space(5)) {
                    ForEach(items[start..<min(start + columns, items.count)]) { PosterCard(item: $0) }
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.space(8))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .pageBackground()
    }
}
