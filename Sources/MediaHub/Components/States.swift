import SwiftUI

/// The three screens that are not the content.
///
/// Written once and shared, because the failure mode they exist to prevent is
/// inconsistency: a library that shows a spinner, a search that shows nothing
/// at all, and a detail page that shows a raw error string are three different
/// apps as far as anyone using them is concerned.

struct LoadingState: View {
    var body: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .pageBackground()
    }
}

struct EmptyState: View {
    var symbol: String = "tray"
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: Theme.space(3)) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.Palette.dim)

            Text(title)
                .font(Theme.Type.heading)
                .foregroundStyle(Theme.Palette.bone)

            if let message {
                Text(message)
                    .font(Theme.Type.body)
                    .foregroundStyle(Theme.Palette.dim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pageBackground()
    }
}

struct FailureState: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.space(4)) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.Palette.rose)

            // The server's own words, verbatim. It writes these in Arabic for
            // the viewer, and replacing them with something generic throws away
            // the only specific thing on the screen.
            Text(message)
                .font(Theme.Type.body)
                .foregroundStyle(Theme.Palette.ash)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .textSelection(.enabled)

            if let retry {
                Button("إعادة المحاولة", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Palette.gold)
                    .foregroundStyle(Theme.Palette.ink)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pageBackground()
    }
}
