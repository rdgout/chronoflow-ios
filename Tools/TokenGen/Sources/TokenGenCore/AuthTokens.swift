import Foundation

public func authTokens(root: URL) throws -> Data {
    func read(_ path: String) throws -> String {
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }
    let json =
        try JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appending(path: "_design/canvas/ds/chronoflow/tokens.json"))) as! [String: Any]
    return try authTokens(
        root: root, board: read("_design/canvas/AuthSignIn.dc.html"),
        bundle: read("_design/canvas/ds/chronoflow/components/bundle.js"),
        css: read("_design/canvas/ds/chronoflow/components/bundle.css"), json: json)
}

func authTokens(root: URL, board: String, bundle: String, css: String, json: [String: Any]) throws -> Data {
    func one(_ pattern: String, _ source: String) throws -> String {
        let values = try captures(pattern, in: source)
        guard values.count == 1 else { throw GenerationError.invalid("Auth source must uniquely match: \(pattern)") }
        return values[0]
    }
    func style(_ pattern: String) throws -> [String: String] {
        let text = try one(pattern, board)
        return Dictionary(
            uniqueKeysWithValues: text.split(separator: ";").compactMap { declaration in
                let parts = declaration.split(separator: ":", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                return parts.count == 2 ? (parts[0], parts[1]) : nil
            })
    }
    func value(_ text: String?, suffix: String = "px") throws -> Double {
        guard let text, text.hasSuffix(suffix), let number = Double(text.dropLast(suffix.count)) else {
            throw GenerationError.invalid("Invalid auth metric: \(text ?? "missing")")
        }
        return number
    }
    func pixels(_ style: [String: String], _ key: String) throws -> Double { try value(style[key]) }
    func padding(_ style: [String: String]) throws -> [Double] {
        guard let text = style["padding"] else { throw GenerationError.invalid("Missing auth padding") }
        return try text.split(separator: " ").map { try $0 == "0" ? 0 : value(String($0)) }
    }
    func token(_ group: String, _ name: String) throws -> Double {
        let rows = (json[group] as! [String: Any])["tokens"] as! [[String: Any]]
        return try value(rows.first { $0["name"] as? String == name }?["value"] as? String)
    }
    func same(_ values: [Double], _ context: String) throws -> Double {
        guard let first = values.first, values.allSatisfy({ $0 == first }) else {
            throw GenerationError.invalid("Auth sources disagree: \(context) \(values)")
        }
        return first
    }
    func component(_ name: String) throws -> String {
        try one("function \(name)\\((.*?)\\}(?=function |var )", bundle)
    }
    func classes(_ pattern: String, _ component: String) throws -> String { try one(pattern, component) }
    func utility(_ prefix: String, _ classes: String) throws -> Double {
        guard let number = Double(try one("(?:^| )\(prefix)([0-9.]+)(?= |$)", classes)) else {
            throw GenerationError.invalid("Invalid auth utility: \(prefix)")
        }
        return number
    }
    func require(_ classes: String, _ required: [String]) throws {
        let words = Set(classes.split(separator: " ").map(String.init))
        guard Set(required).isSubset(of: words) else { throw GenerationError.invalid("Auth component classes changed") }
    }
    let shell = try style(#"<div class="cf-sky"[^>]*style="([^"]+)""#)
    let header = try style(#"<div style="([^"]*justify-content: space-between; height: [^"]+)""#)
    let back = try style(#"<a href="Main.dc.html"[^>]*style="([^"]+)""#)
    let brand = try style(#"<span style="(display: inline-flex;[^"]+)""#)
    let headingGroup = try style(#"<div style="([^"]*flex-direction: column;[^"]*margin-top:[^"]+)""#)
    let heading = try style(#"<h1 style="([^"]+)""#)
    let body = try style(#"<p style="([^"]+)">Sign in to see your trips and plans\.</p>"#)
    let card = try style(#"<section aria-label="Sign in" style="([^"]+)""#)
    let banner = try style(#"<div role="alert" style="([^"]+)""#)
    let bannerIcon = try style(#"<svg[^>]*style="(flex-shrink: 0;[^"]+)""#)
    let footer = try style(#"<a href="GuestFlight.dc.html" style="([^"]+)""#)
    let links = try style(#"<div style="(display: flex; justify-content: space-between;[^"]+)""#)
    let forgot = try style(#"<a href="AuthForgot.dc.html"[^>]*style="([^"]+)""#)
    let signup = try style(#"<a href="AuthSignUp.dc.html"[^>]*style="([^"]+)""#)
    let divider = try style(#"<div aria-hidden="true" style="([^"]+)""#)
    let button = try classes(#"className:c\("([^"]+)""#, component("ue"))
    let field = try classes(#"className:"([^"]*focus-visible:border-ring[^"]+)""#, component("Da"))
    let fieldGroup = try classes(#"className:c\("([^"]+)""#, component("Da"))
    let notice = try one(
        #"function \w+\(\{[^}]*\}\)\{[^}]*className:c\("(flex items-start gap-3 rounded-2xl border p-3 text-sm)""#,
        bundle)
    let noticeIcon = try one(#"className:c\("(mt-[0-9.]+ size-[0-9.]+ shrink-0)""#, bundle)
    let buttonLarge = try one(#"lg:"([^"]+)"#, one(#"Ba=\{([^}]+)\}"#, bundle))
    try require(field, ["rounded-md", "border", "bg-transparent", "text-base", "focus-visible:ring-ring"])
    try require(button, ["text-sm", "font-medium"])
    try require(
        try classes(#"className:"(flex items-center gap-1.5 text-sm text-destructive)""#, component("Da")),
        ["items-center"])
    let spacing = try token("spacing", "space-1")
    let shellPadding = try padding(shell)
    let bannerPadding = try padding(banner)
    let forgotPadding = try padding(forgot)
    let signupPadding = try padding(signup)
    guard shellPadding.count == 3, bannerPadding.count == 2, forgotPadding.count == 2, signupPadding.count == 2 else {
        throw GenerationError.invalid("Auth padding arity")
    }
    let border = try value(one(#"^([0-9.]+px) solid "#, banner["border"] ?? ""))
    let cssBorder = try value(one(#"\.border\{[^}]*border-width:([0-9.]+px)"#, css))
    let metrics: [(String, Double)] = try [
        ("gutter", same([shellPadding[0], shellPadding[1]], "shell gutters")), ("bottom", shellPadding[2]),
        (
            "touch",
            same(
                [
                    pixels(header, "height"), pixels(back, "height"), pixels(back, "width"),
                    pixels(forgot, "min-height"), pixels(signup, "min-height"),
                ], "touch")
        ),
        ("backGlyph", value(one(#"<a href="Main.dc.html"[^>]*>\s*<svg[^>]*\swidth="([0-9.]+)""#, board), suffix: "")),
        ("brandGap", pixels(brand, "gap")),
        (
            "moon",
            value(one(#"<span style="display: inline-flex;[^>]*><svg[^>]*\swidth="([0-9.]+)""#, board), suffix: "")
        ),
        ("headingMargin", pixels(headingGroup, "margin-top")),
        (
            "fieldGap",
            same(
                [
                    pixels(headingGroup, "gap"), pixels(links, "gap"), utility("gap-", fieldGroup) * spacing,
                    utility("gap-", button) * spacing, forgotPadding[1], signupPadding[1],
                ], "field gap")
        ),
        ("cardPadding", pixels(card, "padding")), ("cardRadius", pixels(card, "border-radius")),
        ("cardGap", pixels(card, "gap")), ("footerGap", pixels(footer, "margin-top")),
        ("footerHeight", pixels(footer, "min-height")), ("bannerGap", pixels(banner, "gap")),
        ("bannerVertical", bannerPadding[0]), ("bannerHorizontal", bannerPadding[1]),
        ("bannerRadius", pixels(banner, "border-radius")),
        ("bannerGlyph", value(one(#"<div role="alert"[^>]*><svg[^>]*\swidth="([0-9.]+)""#, board), suffix: "")),
        ("bannerIconTop", pixels(bannerIcon, "margin-top")),
        (
            "icon",
            same(
                [
                    value(
                        one(
                            #"<x-import component-from-global-scope="ChronoFlow.Button"[^>]*>\s*<svg[^>]*\swidth="([0-9.]+)""#,
                            board), suffix: ""), utility("size-", noticeIcon) * spacing,
                ], "icon")
        ),
        ("spacer", utility("px-", buttonLarge) * spacing),
        (
            "inset",
            same([utility("px-", field) * spacing, utility("p-", notice) * spacing, pixels(divider, "gap")], "inset")
        ),
        ("fieldRadius", token("radius", "radius-md")), ("noticeRadius", token("radius", "radius-2xl")),
        ("noticeIconTop", utility("mt-", noticeIcon) * spacing),
        ("borderWidth", same([border, cssBorder], "border")), ("focusWidth", utility("focus-visible:ring-", field)),
    ]
    var code =
        "// Generated by Tools/TokenGen from auth boards, tokens.json and components. Do not edit.\nimport Foundation\nnonisolated public enum AuthTokens {\n"
    func literal(_ number: Double) -> String { number.rounded() == number ? String(Int(number)) : String(number) }
    for (name, number) in metrics { code += "public static var \(name): CGFloat { \(literal(number)) }\n" }
    let opacity =
        try same([utility("disabled:opacity-", button), utility("disabled:opacity-", field)], "disabled opacity") / 100
    code += "public static var disabledOpacity: Double { \(opacity) }\n"
    for appearance in ["light", "dark"] {
        let shadow =
            ((json["shadow"] as! [String: Any])["tokens"] as! [[String: Any]]).first {
                $0["name"] as? String == "shadow-soft"
            }!["value"] as! [String: String]
        let values = shadow[appearance]!.split(separator: " ").map(String.init)
        for (suffix, number) in [
            ("Y", try value(values[1])), ("Radius", try value(values[2]) / 2), ("Spread", try value(values[3])),
        ] {
            code += "public static var \(appearance)Shadow\(suffix): CGFloat { \(literal(number)) }\n"
        }
    }
    code += "}\nextension Typography {\n"
    let type = json["type"] as! [String: Any]
    let families = type["families"] as! [String: String]
    let styles = (type["groups"] as! [[String: Any]]).flatMap { $0["styles"] as! [[String: Any]] }
    let hintToken = styles.first { $0["name"] as? String == "body" }!
    let hint = [
        "font-size": hintToken["fontSize"] as! String, "line-height": hintToken["lineHeight"] as! String,
        "font-weight": String(hintToken["fontWeight"] as! Int),
    ]
    guard shell["font-family"] == "var(--font-sans)" else { throw GenerationError.invalid("Auth root font changed") }
    for (name, declaration, defaultFamily, optical, relative) in [
        ("authBrand", brand, "display", 20, "title3"), ("authHeading", heading, "display", 32, "largeTitle"),
        ("authBody", body, "sans", 0, "body"), ("authLabel", forgot, "sans", 0, "subheadline"),
        ("authStrong", signup, "sans", 0, "subheadline"), ("authHint", hint, "sans", 0, "subheadline"),
        ("authMeta", divider, "sans", 0, "caption"),
    ] {
        let family = declaration["font-family"] ?? "var(--font-\(defaultFamily))"
        let face: String
        let weight = try declaration["font-weight"] ?? one(#"--font-weight-normal:([0-9]+)(?:;|\})"#, css)
        switch family {
        case "var(--font-display)"
        where families["display"]?.hasPrefix("'Fraunces',") == true && ["400", "500"].contains(weight):
            face = "fraunces\(weight)Opsz\(optical)"
        case "var(--font-sans)"
        where families["sans"]?.hasPrefix("'Figtree',") == true && ["400", "500", "600", "700"].contains(weight):
            face = "figtree\(weight)"
        default: throw GenerationError.invalid("Unsupported auth typeface: \(name)")
        }
        let size = try pixels(declaration, "font-size")
        let line = try pixels(declaration, "line-height")
        let tracking: Double
        if let letterSpacing = declaration["letter-spacing"] {
            tracking =
                try letterSpacing.hasSuffix("em") ? value(letterSpacing, suffix: "em") * size : value(letterSpacing)
        } else {
            tracking = 0
        }
        code +=
            "public static var \(name): Style { Style(face: .\(face), size: \(literal(size)), lineHeight: \(literal(line)), tracking: \(tracking), relativeTo: .\(relative)) }\n"
    }
    code += "}\n"
    return try formattedSwift(code, root: root)
}
