import UIKit

/// Role: swaps onboarding and the instrument shell from store.onboardingComplete.
@MainActor
final class RootSwitchController: UIViewController {
    private let store: MeterStore
    private var token: UUID?
    private var showingOnboarding = false

    init(store: MeterStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { preconditionFailure("Storyboards are not used.") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = InstrumentPalette.background
        token = store.observe { [weak self] state in
            self?.render(state)
        }
    }


    private func render(_ state: AppState) {
        if state.onboardingComplete {
            if children.first is UINavigationController { return }
            swap(to: UINavigationController(rootViewController: RootInstrumentController(store: store)))
            showingOnboarding = false
        } else if !showingOnboarding {
            swap(to: OnboardingInstrumentController(store: store))
            showingOnboarding = true
        }
    }

    private func swap(to child: UIViewController) {
        children.forEach {
            $0.willMove(toParent: nil)
            $0.view.removeFromSuperview()
            $0.removeFromParent()
        }
        addChild(child)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(child.view)
        child.didMove(toParent: self)
    }
}
