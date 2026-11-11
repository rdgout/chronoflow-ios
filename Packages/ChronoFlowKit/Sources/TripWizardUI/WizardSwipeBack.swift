#if canImport(UIKit)
    import SwiftUI
    import UIKit

    // SwiftUI disables the system edge gesture when the Checking chevron is hidden.
    struct WizardSwipeBack: UIViewControllerRepresentable {
        func makeUIViewController(context: Context) -> Controller { Controller() }
        func updateUIViewController(_ controller: Controller, context: Context) {}
        final class Controller: UIViewController, UIGestureRecognizerDelegate {
            private weak var previous: (any UIGestureRecognizerDelegate)?
            override func viewDidAppear(_ animated: Bool) {
                super.viewDidAppear(animated)
                guard let gesture = navigationController?.interactivePopGestureRecognizer else { return }
                previous = gesture.delegate
                gesture.delegate = self
                gesture.isEnabled = true
            }
            override func viewWillDisappear(_ animated: Bool) {
                if let gesture = navigationController?.interactivePopGestureRecognizer, gesture.delegate === self {
                    gesture.delegate = previous
                }
                super.viewWillDisappear(animated)
            }
            func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
                (navigationController?.viewControllers.count ?? 0) > 1
            }
        }
    }
#endif
