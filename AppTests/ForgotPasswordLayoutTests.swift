import Auth
import DesignSystem
import SwiftUI
import UIKit
import XCTest

nonisolated final class ForgotPasswordLayoutTests: XCTestCase {
    @MainActor func testFormAndSentElementFramesMatchAtAX5AndXXLarge() async throws {
        try await AuthTestHost.registerFonts()
        let fixture = try XCTUnwrap(AuthDeviceFixture.all().first { $0.name == "se" })
        let host = try AuthTestHost(EmptyView(), size: fixture.size, insets: fixture.insets, scale: fixture.scale)
        defer { host.close() }
        for sent in [false, true] {
            var expectedFrames: [AuthElement: CGRect] = [:]
            var expectedInput: CGRect?
            var expectedText: CGRect?
            var expectedFont: CGFloat?
            for category in [UIContentSizeCategory.extraExtraLarge, .accessibilityExtraExtraExtraLarge] {
                var frames: [AuthElement: CGRect] = [:]
                host.configure(
                    ForgotPasswordView(model: await forgotPasswordSnapshotModel(sent: sent, state: .fieldError)) {
                        frames[$0] = $1
                    }, category: category)
                try await host.settleLayout { Array(frames.values) }
                let field = forgotPasswordNativeField(in: host.window)
                let native =
                    field.map {
                        "nativeCategory=\($0.traitCollection.preferredContentSizeCategory.rawValue), resolvedFont=\(String(describing: $0.font))"
                    } ?? "no native field"
                let context = "requested=\(category.rawValue), sent=\(sent), \(native)"
                if category == .extraExtraLarge {
                    expectedFrames = frames
                } else {
                    XCTAssertEqual(Set(frames.keys), Set(expectedFrames.keys), context)
                    for element in expectedFrames.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                        XCTAssertEqual(
                            frames[element], expectedFrames[element], "AX5 grows/moves \(element): \(context)")
                    }
                }
                if !sent {
                    let field = try XCTUnwrap(field, context)
                    let input = field.convert(field.bounds, to: host.window)
                    let text = field.convert(field.textRect(forBounds: field.bounds), to: host.window)
                    let font = try XCTUnwrap(field.font, context).pointSize
                    XCTAssertEqual(field.traitCollection.preferredContentSizeCategory, .extraExtraLarge, context)
                    let expected = Typography.authBody.uiFont(compatibleWith: field.traitCollection)
                    XCTAssertEqual(field.font?.fontName, expected.fontName, context)
                    XCTAssertEqual(
                        font, expected.pointSize, "Native email must use its capped trait metrics: \(context)")
                    XCTAssertEqual(field.font?.lineHeight, expected.lineHeight, context)
                    if category == .extraExtraLarge {
                        XCTAssertEqual(
                            input, CGRect(x: 48, y: 473.5, width: 279, height: 25),
                            "Preserve the recorded SE xxLarge native email geometry: \(context)")
                        expectedInput = input
                        expectedText = text
                        expectedFont = font
                    } else {
                        for (name, actual, expected) in [
                            ("input", input, try XCTUnwrap(expectedInput)),
                            ("text rect", text, try XCTUnwrap(expectedText)),
                        ] {
                            XCTAssertTrue(
                                AuthSnapshotCapture.nativeInputRectsMatch(actual, expected, scale: host.scale),
                                "AX5 native email \(name) differs by more than one device pixel: \(actual) vs \(expected), \(context)"
                            )
                        }
                        XCTAssertEqual(font, expectedFont, "AX5 grows native email font: \(context)")
                    }
                }
            }
        }
    }

    @MainActor func testLastControlCanScrollAboveKeyboardInsetsOnDuoAndSE() async throws {
        try await AuthTestHost.registerFonts()
        // Duo's saved visible keyboard begins at 414 of 678 points; SE's keyboard is 218 points tall.
        for (alias, keyboardInset) in [("duo", CGFloat(264)), ("se", CGFloat(218))] {
            let fixture = try XCTUnwrap(AuthDeviceFixture.all().first { $0.name == alias })
            for language in ["en", "nl"] {
                for category in [UIContentSizeCategory.large, .extraExtraLarge] {
                    for sent in [false, true] {
                        var frames: [AuthElement: CGRect] = [:]
                        var insets = fixture.insets
                        insets.bottom = max(insets.bottom, keyboardInset)
                        let host = try AuthTestHost(
                            ForgotPasswordView(model: await forgotPasswordSnapshotModel(sent: sent)) {
                                frames[$0] = $1
                            },
                            size: fixture.size, insets: insets, language: language, category: category,
                            scale: fixture.scale)
                        defer { host.close() }
                        try await host.settleLayout { Array(frames.values) }
                        let scroll = try XCTUnwrap(authScrollViews(host.controller.view).first)
                        let viewport = scroll.convert(scroll.bounds, to: host.window).intersection(
                            host.window.bounds.inset(by: insets))
                        let toggle = try XCTUnwrap(frames[sent ? .backToSignIn : .submit])
                        let maximum = max(
                            -scroll.adjustedContentInset.top,
                            scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                        let needed = max(0, toggle.maxY - viewport.maxY + AuthTokens.fieldGap)
                        let context =
                            "\(alias), \(language), \(category), sent=\(sent), viewport=\(viewport), maximumOffset=\(maximum)"
                        XCTAssertGreaterThanOrEqual(maximum, scroll.contentOffset.y + needed, context)
                        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: maximum), animated: false)
                        try await host.settleLayout { Array(frames.values) }
                        let revealed = try XCTUnwrap(frames[sent ? .backToSignIn : .submit])
                        XCTAssertTrue(viewport.contains(revealed), "Last control \(revealed) outside \(context)")
                        XCTAssertLessThanOrEqual(revealed.maxY + AuthTokens.fieldGap, viewport.maxY, context)
                    }
                }
            }
        }
    }

    @MainActor func testFormAndSentStatesRespectEveryProfilesSafeInsetsAndTouchTargets() async throws {
        try await AuthTestHost.registerFonts()
        for fixture in try AuthDeviceFixture.all() {
            for language in ["en", "nl"] {
                for category in [UIContentSizeCategory.large, .extraExtraLarge] {
                    for sent in [false, true] {
                        for state in sent ? [.none] : ForgotPasswordSnapshotState.allCases {
                            var frames: [AuthElement: CGRect] = [:]
                            let host = try AuthTestHost(
                                ForgotPasswordView(model: await forgotPasswordSnapshotModel(sent: sent, state: state)) {
                                    frames[$0] = $1
                                }, size: fixture.size, insets: fixture.insets, language: language, category: category,
                                scale: fixture.scale)
                            defer { host.close() }
                            try await host.settleLayout { Array(frames.values) }
                            XCTAssertEqual(
                                Set(frames.keys),
                                Set([AuthElement.brand, .heading, .subtitle, .card]).union(
                                    sent ? [.notice, .openEmail, .backToSignIn] : [.email, .submit]))
                            let brand = try XCTUnwrap(frames[.brand])
                            XCTAssertEqual(brand.minY, fixture.insets.top + AuthTokens.gutter, accuracy: 0.5)
                            for frame in frames.values {
                                XCTAssertGreaterThan(frame.height, 0)
                                XCTAssertGreaterThanOrEqual(frame.minX, fixture.insets.left + AuthTokens.gutter - 0.5)
                                XCTAssertLessThanOrEqual(
                                    frame.maxX, fixture.size.width - fixture.insets.right - AuthTokens.gutter + 0.5)
                            }
                            for element in sent ? [AuthElement.openEmail, .backToSignIn] : [.email, .submit] {
                                XCTAssertGreaterThanOrEqual(try XCTUnwrap(frames[element]).height, AuthTokens.touch)
                            }
                            XCTAssertLessThan(try XCTUnwrap(frames[.heading]).maxY, try XCTUnwrap(frames[.card]).minY)
                            let first = try XCTUnwrap(frames[sent ? .notice : .email])
                            let second = try XCTUnwrap(frames[sent ? .openEmail : .submit])
                            XCTAssertLessThanOrEqual(first.maxY, second.minY)

                        }
                    }
                }
            }
        }
    }
}

@MainActor func forgotPasswordNativeField(in view: UIView) -> UITextField? {
    if let field = view as? UITextField { return field }
    return view.subviews.lazy.compactMap { forgotPasswordNativeField(in: $0) }.first
}
