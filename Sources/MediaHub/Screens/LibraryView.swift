import SwiftUI
import MediaHubKit

/// A paged, filterable list of one kind of title.
///
/// The paging is the part with rules, so it is worth stating them: pages are
/// requested one at a time, never concurrently, and a request that arrives
/// after the filter changed is discarded. Without the second rule, typing in
/// the search box produces a grid holding results for three different queries
/// at once, in whatever order the network happened to answer.
@MainActor
@Observable
final class LibraryModel {
    private(set) var items: [MediaCard] = []
    private(set) var total = 0
    private(set) var isLoading = false
    private(set) var failure: String?

    /// Bumped on every filter change. A response carrying a stale generation is
    /// dropped rather than merged.
    private var generation = 0
    private var isExhausted = false

    let kind: MediaHubClient.Kind
    private let pageSize = 60

    init(kind: MediaHubClient.Kind) {
        self.kind = kind
    }

    var isEmpty: Bool { items.isEmpty && !isLoading && failure == nil }

    func reset(_ app: AppModel, query: String?, genre: String?) async {
        generation += 1
        items = []
        total = 0
        isExhausted = false
        failure = nil
        await loadMore(app, query: query, genre: genre)
    }

    func loadMore(_ app: AppModel, query: String?, genre: String?) async {
        guard !isLoading, !isExhausted else { return }

        let mine = generation
        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await app.client.library(
                kind: kind,
                limit: pageSize,
                offset: items.count,
                query: query,
                genre: genre
            )

            // The filter moved while this was in flight; these results belong
            // to a query nobody is looking at any more.
            guard mine == generation else { return }

            total = page.total
            // De-duplicated by id: an item added to the library between two
            // page requests shifts the offset window and repeats a row, and
            // SwiftUI's ForEach over duplicate ids is undefined behaviour on
            // screen — rows vanish and reappear as you scroll.
            var seen = Set(items.map(\.id))
            for card in page.items where seen.insert(card.id).inserted {
                items.append(card)
            }

            if page.items.isEmpty || items.count >= total {
                isExhausted = true
            }
        } catch {
            guard mine == generation else { return }
            await app.handle(error)
            failure = (error as? MediaHubError)?.message ?? "تعذّر تحميل القائمة."
        }
    }
}

struct LibraryView: View {
    @Environment(AppModel.self) private var app

    let title: String
    let kind: MediaHubClient.Kind
    let onSelect: (MediaCard) -> Void

    @State private var model: LibraryModel
    @State private var search = ""
    @State private var genre: String?

    init(title: String, kind: MediaHubClient.Kind, onSelect: @escaping (MediaCard) -> Void) {
        self.title = title
        self.kind = kind
        self.onSelect = onSelect
        _model = State(initialValue: LibraryModel(kind: kind))
    }

    var body: some View {
        Group {
            if let failure = model.failure, model.items.isEmpty {
                FailureState(message: failure) {
                    Task { await model.reset(app, query: trimmedSearch, genre: genre) }
                }
            } else if model.isEmpty {
                EmptyState(
                    symbol: "magnifyingglass",
                    title: trimmedSearch == nil ? "لا يوجد شيء هنا" : "لا نتائج",
                    message: trimmedSearch.map { "لم يُعثر على «\($0)»." }
                )
            } else {
                ScrollView {
                    PosterGrid(items: model.items, onSelect: onSelect) {
                        Task { await model.loadMore(app, query: trimmedSearch, genre: genre) }
                    }

                    if model.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.bottom, Theme.space(8))
                    }
                }
            }
        }
        .pageBackground()
        .navigationTitle(title)
        .searchable(text: $search, placement: .toolbar, prompt: "ابحث في \(title)")
        .task { await model.reset(app, query: trimmedSearch, genre: genre) }
        // Debounced: typing "هيل" is three keystrokes and would otherwise be
        // three full-library queries, the first two of which are thrown away.
        .task(id: search) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await model.reset(app, query: trimmedSearch, genre: genre)
        }
    }

    private var trimmedSearch: String? {
        let value = search.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
