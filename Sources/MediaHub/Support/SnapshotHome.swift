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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.space(10)) {
                HeroView(item: Fixtures.complete, onPlay: { _ in }, onDetails: { _ in })

                ForEach(Fixtures.rails) { rail in
                    MediaRail(title: rail.title, items: rail.items, onSelect: { _ in })
                }
            }
            .padding(.bottom, Theme.space(12))
        }
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
