import CoreText
import Foundation

nonisolated struct ExactLineTextLayout {
    let text: NSAttributedString
    let ranges: [NSRange]
    let lineHeight: CGFloat

    init(text: NSAttributedString, width: CGFloat, lineHeight: CGFloat) {
        self.text = text
        self.lineHeight = lineHeight
        let typesetter = CTTypesetterCreateWithAttributedString(text)
        var ranges: [NSRange] = []
        var location = 0
        while location < text.length {
            let count = max(1, CTTypesetterSuggestLineBreak(typesetter, location, max(0, width)))
            ranges.append(NSRange(location: location, length: count))
            location += count
        }
        if let last = text.string.unicodeScalars.last, CharacterSet.newlines.contains(last) {
            ranges.append(NSRange(location: text.length, length: 0))
        }
        self.ranges = ranges
    }

    var height: CGFloat { CGFloat(ranges.count) * lineHeight }

    func frame(for index: Int, width: CGFloat, naturalHeight: CGFloat) -> CGRect {
        CGRect(
            x: 0, y: CGFloat(index) * lineHeight + (lineHeight - naturalHeight) / 2,
            width: width, height: naturalHeight)
    }

    func line(at index: Int) -> NSAttributedString {
        let range = ranges[index]
        let string = text.string as NSString
        var end = NSMaxRange(range)
        while end > range.location,
            let scalar = UnicodeScalar(string.character(at: end - 1)),
            CharacterSet.whitespacesAndNewlines.contains(scalar)
        {
            end -= 1
        }
        return text.attributedSubstring(from: NSRange(location: range.location, length: end - range.location))
    }
}
