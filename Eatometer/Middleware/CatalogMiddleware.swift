import Foundation

/// Role: barcode resolution. Tries every candidate before reporting a miss; caches on success.
@MainActor
final class CatalogMiddleware: MeterMiddleware {
    private let client: SpecimenCatalogClient
    private var task: Task<Void, Never>?

    init(client: SpecimenCatalogClient) {
        self.client = client
    }

    func enact(_ action: MeterAction, store: MeterStore) {
        guard case .catalog(.resolveBarcode(let raw)) = action else { return }
        task?.cancel()
        let candidates = DialBarcode.candidates(from: raw)
        task = Task { [weak store, client] in
            guard let store else { return }
            if candidates.isEmpty {
                store.dispatch(.catalog(.resolveMiss))
                return
            }
            store.dispatch(.catalog(.resolving))
            var sawTransport = false
            for code in candidates {
                if Task.isCancelled { return }
                if let cached = store.state.specimens[code], !cached.name.isEmpty {
                    store.dispatch(.catalog(.resolved(cached)))
                    return
                }
                if let shelf = SpecimenShelf.specimen(barcode: code) {
                    store.dispatch(.catalog(.resolved(shelf)))
                    return
                }
                do {
                    let record = try await client.product(code: code)
                    if Task.isCancelled { return }
                    store.dispatch(.catalog(.resolved(record)))
                    return
                } catch let fault as CatalogFault {
                    if fault == .cancelled { return }
                    if fault == .transport { sawTransport = true }
                    continue
                } catch {
                    sawTransport = true
                    continue
                }
            }
            if Task.isCancelled { return }
            store.dispatch(sawTransport ? .catalog(.resolveOffline) : .catalog(.resolveMiss))
        }
    }
}
