#if canImport(UIKit)
    import DesignSystem
    import SwiftUI
    import UIKit

    public enum AuthElement: String, CaseIterable {
        case brand, heading, card, footer, email, password, submit, forgot, signup, forgotLabel, signupLabel
        case code, modeToggle
    }

    public struct AuthScreen<Card: View, Footer: View>: View {
        @Environment(\.colorScheme) private var scheme
        let title: String
        let description: String
        let back: () -> Void
        let card: Card
        let footer: Footer
        let measure: (AuthElement, CGRect) -> Void
        public init(
            title: String, description: String, back: @escaping () -> Void,
            measure: @escaping (AuthElement, CGRect) -> Void = { _, _ in },
            @ViewBuilder card: () -> Card, @ViewBuilder footer: () -> Footer
        ) {
            self.title = title
            self.description = description
            self.back = back
            self.measure = measure
            self.card = card()
            self.footer = footer()
        }
        public var body: some View {
            GeometryReader { viewport in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        AuthBrand(back: back).authMeasure(.brand, measure)
                        VStack(alignment: .leading, spacing: AuthTokens.fieldGap) {
                            WelcomeText(title, style: Typography.authHeading, color: .skyTitle).accessibilityAddTraits(
                                .isHeader
                            )
                            .accessibilityIdentifier("auth.heading")
                            WelcomeText(description, style: Typography.authBody, color: .skyTitle)
                        }.padding(.top, AuthTokens.headingMargin).authMeasure(.heading, measure)
                        Spacer(minLength: AuthTokens.spacer)
                        VStack(alignment: .leading, spacing: AuthTokens.cardGap) { card }
                            .padding(AuthTokens.cardPadding)
                            .background {
                                AuthCardShadow(appearance: scheme == .dark ? .dark : .light)
                                RoundedRectangle(cornerRadius: AuthTokens.cardRadius).fill(ColorToken.card.color)
                            }
                            .authMeasure(.card, measure)
                        if Footer.self != EmptyView.self {
                            footer.padding(.top, AuthTokens.footerGap).authMeasure(.footer, measure)
                        }
                    }
                    .padding(.horizontal, AuthTokens.gutter).padding(.top, AuthTokens.gutter).padding(
                        .bottom, AuthTokens.bottom
                    )
                    .frame(minHeight: viewport.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.always, axes: .vertical)
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("auth.scroll")
            }.background { CfSky().ignoresSafeArea() }
        }
    }

    private struct AuthCardShadow: UIViewRepresentable {
        let appearance: TokenAppearance
        func makeUIView(context: Context) -> AuthCardShadowView {
            let view = AuthCardShadowView()
            view.isOpaque = false
            view.isUserInteractionEnabled = false
            return view
        }
        func updateUIView(_ view: AuthCardShadowView, context: Context) {
            (view.layer as! AuthCardShadowLayer).appearance = appearance
            if view.layer.contentsScale != context.environment.displayScale {
                view.layer.contentsScale = context.environment.displayScale
                view.layer.setNeedsLayout()
            }
        }
    }

    private final class AuthCardShadowView: UIView {
        override class var layerClass: AnyClass { AuthCardShadowLayer.self }
    }

    extension View {
        func authMeasure(_ element: AuthElement, _ measure: @escaping (AuthElement, CGRect) -> Void) -> some View {
            onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                measure(element, $0)
            }
        }
    }
#endif
