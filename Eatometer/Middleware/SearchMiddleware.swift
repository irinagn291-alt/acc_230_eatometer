import Foundation

/// Role: debounced catalog search. Cancels the previous flight; falls back to the local shelf.
@MainActor
final class SearchMiddleware: MeterMiddleware {
    private let client: SpecimenCatalogClient
    private var task: Task<Void, Never>?

    init(client: SpecimenCatalogClient) {
        self.client = client
    }

    func enact(_ action: MeterAction, store: MeterStore) {
        switch action {
        case .catalog(.searchTextChanged), .catalog(.searchRetry):
            let query = store.state.search.query
            task?.cancel()
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            task = Task { [weak store, client] in
                guard let store else { return }
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    if Task.isCancelled { return }
                    let spinner = Task { @MainActor in
                        try await Task.sleep(for: .milliseconds(150))
                        if !Task.isCancelled {
                            store.dispatch(.catalog(.searchSpinner))
                        }
                    }
                    let remote: [SpecimenRecord]
                    var notice: String?
                    do {
                        remote = try await client.search(terms: trimmed)
                    } catch is CancellationError {
                        spinner.cancel()
                        return
                    } catch {
                        remote = []
                        notice = "The wire to Open Food Facts did not hold. Showing the local drum."
                    }
                    spinner.cancel()
                    if Task.isCancelled { return }
                    let local = SpecimenShelf.matches(trimmed)
                    let merged = CatalogSelector.merge(remote: remote, local: local)
                    if merged.isEmpty && notice != nil {
                        store.dispatch(.catalog(.searchFailed))
                    } else {
                        store.dispatch(.catalog(.searchFinished(merged, notice: notice)))
                    }
                } catch {
                    return
                }
            }
        default:
            break
        }
    }

}
