import Foundation

/// Role: middleware contract. Effects (network, Core Data) live here; they never mutate AppState directly.
@MainActor
protocol MeterMiddleware: AnyObject {
    func enact(_ action: MeterAction, store: MeterStore)
}

/// Role: the single global store. Dispatches run the pure reducer, then middleware.
@MainActor
final class MeterStore {
    private(set) var state: AppState
    private var observers: [UUID: (AppState) -> Void] = [:]
    private var middlewares: [any MeterMiddleware] = []

    init(state: AppState) {
        self.state = state
    }

    func install(_ middlewares: [any MeterMiddleware]) {
        self.middlewares = middlewares
    }

    func dispatch(_ action: MeterAction) {
        state = meterReducer(state: state, action: action)
        notify()
        for middleware in middlewares {
            middleware.enact(action, store: self)
        }
    }

    @discardableResult
    func observe(_ handler: @escaping (AppState) -> Void) -> UUID {
        let token = UUID()
        observers[token] = handler
        handler(state)
        return token
    }

    func drop(_ token: UUID) {
        observers.removeValue(forKey: token)
    }

    private func notify() {
        let snapshot = state
        for handler in observers.values {
            handler(snapshot)
        }
    }
}
