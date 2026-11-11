#if canImport(UIKit)
    import SwiftUI
    import UIKit

    enum AuthFeedbackTarget: Hashable { case banner }

    private struct AuthFailureFeedback: ViewModifier {
        let form: AuthFormModel
        let focus: FocusState<String?>.Binding?
        let firstInvalidField: String?
        let bannerFocus: AccessibilityFocusState<Bool>.Binding
        let automaticallyFocusesErrors: Bool
        @State private var revision: Int?
        @State private var isActive = false

        func body(content: Content) -> some View {
            ScrollViewReader { scroll in
                content
                    .onAppear { isActive = true }
                    .onDisappear {
                        isActive = false
                        bannerFocus.wrappedValue = false
                    }
                    .onChange(of: form.busy) {
                        if form.busy {
                            focus?.wrappedValue = nil
                            bannerFocus.wrappedValue = false
                        } else {
                            presentFailure()
                        }
                    }
                    .onChange(of: form.announcementRevision) { presentFailure() }
                    .task(id: revision) {
                        guard revision != nil else { return }
                        // Let the inserted banner lay out before resolving its scroll target.
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        revealBanner(in: scroll)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) {
                        _ in
                        // Keyboard dismissal can change the scroll offset after the banner was revealed.
                        revealBanner(in: scroll)
                    }
            }
        }

        private func presentFailure() {
            guard isActive, automaticallyFocusesErrors, !form.busy, form.failure != nil else { return }
            bannerFocus.wrappedValue = false
            focus?.wrappedValue = firstInvalidField
            revision = form.announcementRevision
        }

        private func revealBanner(in scroll: ScrollViewProxy) {
            guard isActive, revision == form.announcementRevision, !form.busy, form.banner != nil,
                firstInvalidField == nil, focus?.wrappedValue == nil
            else { return }
            scroll.scrollTo(AuthFeedbackTarget.banner, anchor: .top)
            bannerFocus.wrappedValue = true
        }
    }

    extension View {
        func authFailureFeedback(
            form: AuthFormModel, focus: FocusState<String?>.Binding? = nil, firstInvalidField: String? = nil,
            bannerFocus: AccessibilityFocusState<Bool>.Binding, automaticallyFocusesErrors: Bool = true
        ) -> some View {
            modifier(
                AuthFailureFeedback(
                    form: form, focus: focus, firstInvalidField: firstInvalidField, bannerFocus: bannerFocus,
                    automaticallyFocusesErrors: automaticallyFocusesErrors))
        }
    }
#endif
