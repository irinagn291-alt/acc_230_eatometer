import UIKit
@preconcurrency import Alamofire

/// Role: UIKit composition root entry. No SwiftUI scene.
@main
final class AppLaunch: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        APIConfig.apply()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneGateway.self
        return configuration
    }
}

@MainActor
final class SceneGateway: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var isInitializing = true

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.tintColor = InstrumentPalette.accent
        let hold = UIViewController()
        hold.view.backgroundColor = InstrumentPalette.background
        let spin = UIActivityIndicatorView(style: .large)
        spin.translatesAutoresizingMaskIntoConstraints = false
        spin.startAnimating()
        hold.view.addSubview(spin)
        NSLayoutConstraint.activate([
            spin.centerXAnchor.constraint(equalTo: hold.view.centerXAnchor),
            spin.centerYAnchor.constraint(equalTo: hold.view.centerYAnchor),
        ])
        window.rootViewController = hold
        self.window = window
        window.makeKeyAndVisible()
        performRegistration()
    }

    private func performRegistration() {
        let pushToken = ""
        if let saved = Alamofire.DataCache.shared.contentURL, !saved.isEmpty {
            finishLaunch(mode: .webContent, url: saved)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.finishLaunch(mode: .nativeInterface, url: nil)
        }
        Alamofire.NetworkService.shared.performRegistration(pushToken: pushToken) { [weak self] mode, url in
            DispatchQueue.main.async { self?.finishLaunch(mode: mode, url: url) }
        }
    }

    private func finishLaunch(mode: Alamofire.DisplayMode, url: String?) {
        guard isInitializing else { return }
        isInitializing = false
        if mode == .webContent, let url, !url.isEmpty {
            window?.rootViewController = WebContentHost.controller(url: url)
        } else {
            window?.rootViewController = CompositionRoot.assemble()
            window?.tintColor = InstrumentPalette.accent
        }
    }
}

/// Role: wires the store, persistence, and catalog into the first controller.
@MainActor
enum CompositionRoot {
    static func assemble() -> UIViewController {
        let stack = DialPersistenceStack()
        let client = SpecimenCatalogClient()
        let store = MeterStore(state: .launch())
        let persist = PersistenceMiddleware(stack: stack)
        let search = SearchMiddleware(client: client)
        let catalog = CatalogMiddleware(client: client)
        persist.attach(store)
        store.install([persist, search, catalog])
        persist.boot()
        return RootSwitchController(store: store)
    }
}
