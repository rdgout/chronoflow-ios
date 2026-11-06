import Auth
import CoreGraphics
import Testing

struct AuthLayoutTests {
    @Test func zeroInsetBoardAndEveryDeviceRespectFourInsets() {
        #expect(
            AuthLayout.content(
                size: CGSize(width: 375, height: 812), insets: .init(top: 0, left: 0, bottom: 0, right: 0))
                == CGRect(x: 16, y: 16, width: 343, height: 772))
        let devices: [(String, CGSize, AuthLayout.Insets)] = [
            ("se", CGSize(width: 375, height: 667), .init(top: 20, left: 0, bottom: 0, right: 0)),
            ("17e", CGSize(width: 390, height: 844), .init(top: 47, left: 0, bottom: 34, right: 0)),
            ("17", CGSize(width: 402, height: 874), .init(top: 62, left: 0, bottom: 34, right: 0)),
            ("air", CGSize(width: 420, height: 912), .init(top: 68, left: 0, bottom: 34, right: 0)),
            ("18pro", CGSize(width: 402, height: 874), .init(top: 62, left: 0, bottom: 34, right: 0)),
            ("18promax", CGSize(width: 440, height: 956), .init(top: 62, left: 0, bottom: 34, right: 0)),
            ("duo", CGSize(width: 466, height: 678), .init(top: 0, left: 0, bottom: 0, right: 19)),
        ]
        for (_, size, fixture) in devices {
            for insets in [fixture, .init(top: 0, left: 24, bottom: 20, right: 62)] {
                let rect = AuthLayout.content(size: size, insets: insets)
                #expect(rect.minX == insets.left + 16 && rect.maxX == size.width - insets.right - 16)
                #expect(rect.minY == insets.top + 16 && rect.maxY == size.height - insets.bottom - 24)
            }
        }
    }
    @Test func measuredKeyboardViewportRevealsPairOrReportsOverflow() {
        let field = CGRect(x: 20, y: 300, width: 300, height: 100)
        let submit = CGRect(x: 20, y: 500, width: 300, height: 44)
        let viewport = CGRect(x: 0, y: 0, width: 375, height: 330)
        let result = AuthLayout.reveal(field: field, submit: submit, viewport: viewport)
        #expect(result.fits)
        #expect(viewport.contains(field.offsetBy(dx: 0, dy: -result.offset)))
        #expect(viewport.contains(submit.offsetBy(dx: 0, dy: -result.offset)))
        #expect(
            !AuthLayout.reveal(field: field, submit: submit, viewport: CGRect(x: 0, y: 0, width: 375, height: 150)).fits
        )
    }
}
