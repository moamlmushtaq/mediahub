import SwiftUI
import MediaHubKit

/// One title, as a poster.
///
/// The unit the whole library is built out of, so its details matter more than
/// its size suggests:
///
/// * **The title sits under the poster, not over it.** Overlaid text needs a
///   scrim, a scrim dims the artwork, and the artwork is the thing that makes a
///   library browsable at a glance.
/// * **Two lines, always reserved.** A grid where some cards are one line tall
///   and others two has a ragged bottom edge that reads as broken. The space is
///   held whether or not it is used.
/// * **The resume bar is on the poster.** It is the one piece of state worth
///   seeing without reading, and it belongs to the image, not the caption.
struct PosterCard: View {
    let item: MediaCard
    var width: CGFloat = 168

    @State private var isHovering = false

    private var progress: Double? {
        guard item.startingPoint.rawValue > 0,
              let runtime = item.runtime, runtime.seconds > 0
        else { return nil }
        return min(1, item.startingPoint.seconds / runtime.seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space(2)) {
            poster
            caption
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var poster: some View {
        ZStack(alignment: .bottom) {
            RemoteImage(url: item.posterURL(), placeholderSymbol: symbol)
                .frame(width: width, height: width / Theme.posterAspect)
                .clipped()

            if let progress {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.black.opacity(0.55))
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Theme.Palette.gold)
                            .frame(width: geometry.size.width * progress)
                    }
                }
                .frame(height: 3)
            }

            if item.userData.played {
                watchedBadge
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .hairlineBorder()
        // A lift rather than a glow: the hover state has to be legible against
        // artwork of every possible colour, and scale is the only cue that is.
        .scaleEffect(isHovering ? 1.035 : 1)
        .shadow(color: .black.opacity(isHovering ? 0.45 : 0), radius: 14, y: 6)
        .animation(.easeOut(duration: 0.16), value: isHovering)
    }

    private var watchedBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Theme.Palette.ink)
            .padding(4)
            .background(Theme.Palette.gold, in: Circle())
            .padding(Theme.space(2))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.name)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Palette.bone)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.dim)
                .lineLimit(1)
        }
    }

    private var symbol: String {
        item.type == .series ? "tv" : "film"
    }

    /// Year and rating, and nothing when neither is known — an empty line is
    /// better than the string "—" repeated down a column.
    private var subtitle: String {
        var parts: [String] = []
        if let year = item.year { parts.append(String(year)) }
        if let rating = item.communityRating {
            parts.append("★ " + String(format: "%.1f", rating))
        }
        return parts.joined(separator: "  ·  ")
    }
}
