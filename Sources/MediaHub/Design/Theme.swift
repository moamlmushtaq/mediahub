import SwiftUI

/// The app's visual language.
///
/// The website's palette, value for value, because someone who watches on a
/// laptop browser and then opens this app should see one product rather than
/// two that share a name.
///
/// WHY THE TYPE SCALE IS NAMED AND NOT NUMERIC
/// ==========================================
/// Every screen written by hand drifts: 15 here, 16 there, 17 because it looked
/// better that afternoon. Named steps make "this heading is one level above
/// that one" true rather than approximately true, and they make a later change
/// to the whole hierarchy one edit instead of forty.
///
/// The fonts themselves are the system's. On a Mac set to Arabic that means
/// SF Arabic, and the single loudest signal that an app is not native is text
/// set in something else.
enum Theme {
    enum Palette {
        static let ink = Color(red: 0.043, green: 0.039, blue: 0.035)        // #0b0a09
        static let inkPanel = Color(red: 0.075, green: 0.067, blue: 0.063)   // #131110
        static let inkRaised = Color(red: 0.102, green: 0.090, blue: 0.082)  // #1a1715
        static let hair = Color(red: 0.149, green: 0.129, blue: 0.125)       // #262120
        static let hairStrong = Color(red: 0.216, green: 0.188, blue: 0.176) // #37302d
        static let bone = Color(red: 0.949, green: 0.937, blue: 0.914)       // #f2efe9
        static let ash = Color(red: 0.659, green: 0.635, blue: 0.608)        // #a8a29b
        static let dim = Color(red: 0.518, green: 0.490, blue: 0.463)        // #847d76
        static let gold = Color(red: 0.788, green: 0.635, blue: 0.302)       // #c9a24d
        static let goldBright = Color(red: 0.886, green: 0.757, blue: 0.475) // #e2c179
        static let rose = Color(red: 0.890, green: 0.365, blue: 0.416)       // #e35d6a
    }

    /// Named `Typography` and not `Type`: Swift reserves `Foo.Type` for the
    /// metatype, so `Theme.Type.heading` does not parse as a member lookup at
    /// all — the compiler reports it as "type member must not be named Type".
    enum Typography {
        /// A hero title, and nothing else.
        static let display = Font.system(size: 40, weight: .bold)
        static let title = Font.system(size: 24, weight: .bold)
        static let heading = Font.system(size: 17, weight: .semibold)
        static let body = Font.system(size: 14, weight: .regular)
        static let label = Font.system(size: 13, weight: .medium)
        static let caption = Font.system(size: 11, weight: .regular)
    }

    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 14
    }

    /// A 4pt grid. `space(3)` is 12 — the app's default gap.
    static func space(_ steps: CGFloat) -> CGFloat { steps * 4 }

    /// Posters are 2:3. Not negotiable — TMDb renders them at that ratio, and
    /// any other shape either letterboxes or crops someone's face.
    static let posterAspect: CGFloat = 2.0 / 3.0
}

// MARK: - Shared modifiers

extension View {
    /// The app's page background.
    func pageBackground() -> some View {
        background(Theme.Palette.ink)
    }

    /// A hairline that reads at one pixel on Retina rather than two.
    func hairlineBorder(_ radius: CGFloat = Theme.Radius.medium) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Theme.Palette.hair, lineWidth: 1)
        )
    }
}

/// Text that is genuinely absent, drawn as absent rather than as an empty box.
struct Placeholder: View {
    var systemImage: String = "film"

    var body: some View {
        ZStack {
            Theme.Palette.inkRaised
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.Palette.dim)
        }
    }
}
