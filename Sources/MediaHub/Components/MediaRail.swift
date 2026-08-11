import SwiftUI
import MediaHubKit

/// A horizontal row of titles.
///
/// Scrolls with the trackpad, which on this platform is how a row like this is
/// actually used — so there are no arrow buttons hanging off the ends. They
/// exist on the website because a mouse without horizontal scroll is common in
/// a browser; on a Mac they would be furniture nobody touches.
///
/// The row keeps its own `ScrollView`, so one rail scrolled sideways does not
/// drag the others with it.
struct MediaRail: View {
    let title: String
    let items: [MediaCard]
    var onSelect: (MediaCard) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space(3)) {
            Text(title)
                .font(Theme.Typography.heading)
                .foregroundStyle(Theme.Palette.bone)
                .padding(.horizontal, Theme.space(8))

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.space(4)) {
                    ForEach(items) { item in
                        Button { onSelect(item) } label: {
                            PosterCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.space(8))
                // Room for the hover lift and its shadow. Without it the scale
                // is clipped by the ScrollView and the card appears to flatten
                // against the edge of the row.
                .padding(.vertical, Theme.space(2))
            }
        }
    }
}

/// A grid of titles that pages as it is scrolled.
struct PosterGrid: View {
    let items: [MediaCard]
    var onSelect: (MediaCard) -> Void
    /// Called when the last row comes into view. `nil` when everything is loaded.
    var onReachEnd: (() -> Void)?

    private let columns = [GridItem(.adaptive(minimum: 168, maximum: 200), spacing: Theme.space(5))]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.space(6)) {
            ForEach(items) { item in
                Button { onSelect(item) } label: {
                    PosterCard(item: item, width: 168)
                }
                .buttonStyle(.plain)
                .onAppear {
                    // Paging is triggered from the item itself rather than from
                    // a sentinel view at the bottom: a sentinel inside a
                    // `LazyVGrid` is only laid out once the grid has already
                    // run out of content, which is one scroll too late.
                    if item.id == items.last?.id { onReachEnd?() }
                }
            }
        }
        .padding(.horizontal, Theme.space(8))
        .padding(.vertical, Theme.space(6))
    }
}
