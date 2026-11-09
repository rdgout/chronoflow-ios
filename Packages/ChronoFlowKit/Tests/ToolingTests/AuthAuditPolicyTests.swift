import CoreGraphics
import Testing

struct AuthAuditPolicyTests {
    @Test func onlyAnExplicitlyDisabledElementExemptsContrast() {
        #expect(AuthAuditPolicy.isDisabledContrast(isContrast: true, isEnabled: false))
        for enabled: Bool? in [nil, true] {
            #expect(!AuthAuditPolicy.isDisabledContrast(isContrast: true, isEnabled: enabled))
        }
        for enabled: Bool? in [nil, false, true] {
            #expect(!AuthAuditPolicy.isDisabledContrast(isContrast: false, isEnabled: enabled))
        }
    }

    @Test func auditMustUseTheCurrentScrollFrames() {
        let staleBrand = CGRect(x: 131.3333, y: 14.8333, width: 129, height: 22.3333)
        let auditedBrand = staleBrand.offsetBy(dx: 0, dy: 44.6667)
        let wordmark = CGRect(x: 155.6667, y: 59.5, width: 104.6667, height: 22.3333)
        let footer = CGRect(x: 16, y: 728, width: 358, height: 48)
        let before = ["auth.brand": staleBrand, "sign-up.back": footer]
        let after = ["auth.brand": auditedBrand, "sign-up.back": footer.offsetBy(dx: 0, dy: 44.6667)]
        #expect(!AuthAuditPolicy.sameFrames(before, after))
        #expect(!AuthAuditPolicy.contains(wordmark, in: staleBrand))
        #expect(AuthAuditPolicy.contains(wordmark, in: auditedBrand))
        #expect(AuthAuditPolicy.contains(footer, in: footer))
        #expect(!AuthAuditPolicy.contains(after["sign-up.back"], in: footer))
    }

    @Test func screenshotStabilityAllowsOnlyFloatRoundingAndTheSameControls() {
        let subtitle = CGRect(x: 16, y: 66.4, width: 345.3333, height: 19.3333)
        let frames = ["auth.subtitle": subtitle]
        #expect(AuthAuditPolicy.sameFrames(frames, frames))
        #expect(AuthAuditPolicy.sameFrames(frames, ["auth.subtitle": subtitle.offsetBy(dx: 0, dy: 0.000001)]))
        #expect(!AuthAuditPolicy.sameFrames(frames, ["auth.subtitle": subtitle.offsetBy(dx: 0, dy: 0.011)]))
        #expect(!AuthAuditPolicy.sameFrames(frames, [:]))
        #expect(!AuthAuditPolicy.sameFrames(frames, ["auth.heading": subtitle]))
        for invalid in [CGRect.zero, .null, .infinite] {
            #expect(!AuthAuditPolicy.sameFrames(["auth.subtitle": invalid], ["auth.subtitle": invalid]))
            #expect(!AuthAuditPolicy.contains(invalid, in: subtitle))
            #expect(!AuthAuditPolicy.contains(subtitle, in: invalid))
        }
    }
}
