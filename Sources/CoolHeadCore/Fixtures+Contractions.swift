import Foundation

/// Checks for GOV.UK's rule on contractions (docs/CARD-TEMPLATE.md, Contractions): a positive one ("it's", "you're",
/// "you'll") is fine; a negative one ("can't", "isn't") or a conditional one ("should've", "it'd") is spelled out
/// ("cannot", "is not"); and "'s" means only "is", never "has". Two checks: the card check (`CardTemplate.problems`,
/// `CardTemplate.clarity`) on made-up sentences, and every string literal in Sources/, read from the source folder this
/// copy was built from, with comments left out.
extension Fixture {
    static func contractionsSamples(_ now: Date) -> [(String, Card)] { [] }

    /// Strings that quote another app's own button or menu name exactly, kept as that app shows it, each by its whole
    /// text. None today: every contraction in Sources/ is Cool Head's own words.
    static let contractionExceptions: Set<String> = []

    /// Made-up words with "^" for a straight apostrophe and "~" for a curly one, so this file's own strings carry no
    /// contraction for the source check to find.
    static func apostrophes(_ s: String) -> String {
        s.replacingOccurrences(of: "^", with: "'").replacingOccurrences(of: "~", with: "\u{2019}")
    }

    static func contractionsChecks(_ now: Date) -> [(String, Bool, String)] {
        [contractionRule(now), contractionSources(), contractionLexer()]
    }

    /// The card check: what the rule spells out is caught, on a card and in Nerdy stuff, and what it allows is not.
    static func contractionRule(_ now: Date) -> (String, Bool, String) {
        var bad: [String] = []
        let caught = ["It can^t be undone.", "Don^t stop it.", "It isn~t responding.", "You should^ve saved it.", "It^d be faster.",
                      "You^d lose nothing.", "It^s been busy for 3 hours.", "That^s had no effect.", "There^s got to be a reason.",
                      "Your Mac^s been busy.", "It^s not been read.", "Let^s stop it.", "You^ve used 5 GB.", "They^ve stopped."]
        let allowed = ["It^s busy.", "It^s 96% done.", "You^re on battery.", "You^ll lose nothing.", "That^s more than usual.",
                       "There^s a newer version.", "I^m sure.", "It cannot be undone.", "It is not responding.", "Do not stop it.",
                       "Google Chrome^s tabs are busy.", "macOS^s own check.", "It^s paused.", "It^s done.", "It^s red.",
                       "It^s connected to Wi-Fi.", "Here^s what^s used."]
        let contraction = { (p: String) in p.contains("contraction") || p.contains("\"'s\" for") || p.contains("\"we\"") || p.contains("present perfect") }
        for raw in caught {
            let s = apostrophes(raw)
            if !CardTemplate.problems(Card(state: .working, headline: s, explanation: "", fixes: [])).contains(where: contraction) { bad.append("card: \"\(s)\" passes") }
            if !CardTemplate.clarity(s).contains(where: contraction) { bad.append("Nerdy stuff: \"\(s)\" passes") }
        }
        for raw in allowed {
            let s = apostrophes(raw)
            for p in CardTemplate.problems(Card(state: .working, headline: s, explanation: "", fixes: [])) where contraction(p) { bad.append("card: \"\(s)\" flagged, \(p)") }
            for p in CardTemplate.clarity(s) where contraction(p) { bad.append("Nerdy stuff: \"\(s)\" flagged, \(p)") }
        }
        let ok = bad.isEmpty
        return ("contractions-rule", ok, ok ? "\(caught.count) negative, conditional, and \"'s\" for \"has\" forms caught on a card and in Nerdy stuff; \(allowed.count) positive contractions, full forms, and possessives allowed" : bad.joined(separator: "; "))
    }

    /// Every negative or conditional contraction, or "'s" before been, had, or got, in a string literal in Sources/,
    /// outside the exceptions, as "File.swift:12: can't".
    static func contractionFindings(in folder: URL) -> [String] {
        let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path } ?? []
        var out: [String] = []
        for f in files {
            guard let src = try? String(contentsOf: f, encoding: .utf8) else { out.append("\(f.lastPathComponent): unreadable"); continue }
            let name = f.path.replacingOccurrences(of: folder.path + "/", with: "")
            out += contractions(src).map { "\(name):\($0.line): \($0.words)" }
        }
        return out
    }

    /// The contractions in one file's string literals, each literal by its first line, the exceptions left out.
    static func contractions(_ src: String, except: Set<String> = contractionExceptions) -> [(line: Int, words: String)] {
        let patterns = [CardTemplate.negativeContraction, CardTemplate.conditionalContraction, #"\b\w+'s\s+(?:been|had|got)\b"#]
        return SwiftStrings.literals(src).filter { !except.contains($0.text) }.compactMap { l in
            let t = l.text.replacingOccurrences(of: "\u{2019}", with: "'")
            let found = patterns.flatMap { p in
                (try? NSRegularExpression(pattern: p, options: .caseInsensitive))?
                    .matches(in: t, range: NSRange(t.startIndex..., in: t)).compactMap { Range($0.range, in: t).map { String(t[$0]) } } ?? []
            }
            return found.isEmpty ? nil : (l.line, found.joined(separator: ", "))
        }
    }

    /// The source check, on the folder this copy was built from; a pass with a note where that folder is not on this
    /// Mac (a copy of the app built elsewhere).
    static func contractionSources() -> (String, Bool, String) {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: sources.appendingPathComponent("CoolHeadCore/CardTemplate.swift").path) else {
            return ("contractions-in-sources", true, "skipped: the source folder this copy was built from is not on this Mac")
        }
        let found = contractionFindings(in: sources)
        return ("contractions-in-sources", found.isEmpty, found.isEmpty
                ? "no negative or conditional contraction, or \"'s\" for \"has\", in a string in Sources/ (\(contractionExceptions.count) exceptions)"
                : "spell out (docs/CARD-TEMPLATE.md, Contractions), or list it in Fixture.contractionExceptions if it quotes another app: " + found.joined(separator: "; "))
    }

    /// The reader of string literals, on made-up source: comments of every kind, regex literals, raw and multi-line
    /// strings, interpolations, escapes, and an exception.
    static func contractionLexer() -> (String, Bool, String) {
        let src = apostrophes(#"""
        // a comment that can^t count
        /// a doc comment that won^t count
        /* a block /* nested */ that isn^t counted */ let url = "https://example.com" // "don^t" in a comment
        let a = "It can^t be undone."
        let b = #"raw: it isn~t "quoted" \(not interpolated) here"#
        let c = """
            Line one.
            Line two doesn^t fit.
            """
        let d = "\(name) didn^t quit, \("inner: won^t") and \(f("x")) \u{2019}s"
        let e = #/["'”]? it^d /#
        let f = "escaped \"quote\" then you^d"
        let g = "Don^t Allow"
        let h = "It^s busy, it^s fine, and Chrome^s been busy."
        """#)
        let texts = SwiftStrings.literals(src).map(\.text)
        // a multi-line string by its first line (6); the inner string of line 10's interpolation, then line 10's own
        let want = [4, 5, 6, 10, 10, 12, 13, 14]
        var bad: [String] = []
        let lines = contractions(src, except: []).map(\.line)
        if lines != want { bad.append("found on lines \(lines), not \(want)") }
        // an exception is left out by its whole text, and only that string
        let excepted = contractions(src, except: [apostrophes("Don^t Allow")]).map(\.line)
        if excepted != want.filter({ $0 != 13 }) { bad.append("with the exception listed, found on lines \(excepted)") }
        if texts.contains(where: { $0.contains("comment") || $0.contains("nested") }) { bad.append("a comment read as a string") }
        if texts.contains(where: { $0.contains(apostrophes("it^d")) }) { bad.append("a regex literal read as a string") }
        if !texts.contains(apostrophes("inner: won^t")) { bad.append("a string inside an interpolation not read") }
        if !texts.contains("https://example.com") { bad.append("a string with // in it cut short") }
        let ok = bad.isEmpty
        return ("contractions-reader", ok, ok ? "comments, regex literals, and an exception left out; raw, multi-line, and interpolated strings read, with their lines" : bad.joined(separator: "; "))
    }
}

/// Reads the string literals in Swift source, outside comments: each with its first line, and its text with escapes
/// read ("\u{2019}" as ’) and every interpolation as one "X", whose own strings are read too. Enough of Swift's
/// grammar for Cool Head's own source: comments (nested ones too), extended regex literals (#/…/#), raw and
/// multi-line strings.
enum SwiftStrings {
    static func literals(_ source: String) -> [(line: Int, text: String)] {
        let r = Reader(Array(source.unicodeScalars))
        r.code(nested: false)
        return r.out
    }

    final class Reader {
        let s: [Unicode.Scalar]
        var i = 0, line = 1
        var out: [(line: Int, text: String)] = []
        init(_ s: [Unicode.Scalar]) { self.s = s }

        func at(_ k: Int) -> Unicode.Scalar? { k < s.count ? s[k] : nil }
        func starts(_ p: String, _ k: Int) -> Bool {
            var k = k
            for c in p.unicodeScalars { guard at(k) == c else { return false }; k += 1 }
            return true
        }
        func hashes(_ k: Int) -> Int { var n = 0; while at(k + n) == "#" { n += 1 }; return n }
        func step() { if s[i] == "\n" { line += 1 }; i += 1 }

        /// Code, to the end or, in an interpolation, to its closing bracket.
        func code(nested: Bool) {
            var depth = 0
            while i < s.count {
                if starts("//", i) { while i < s.count, s[i] != "\n" { i += 1 }; continue }
                if starts("/*", i) {
                    var d = 0
                    while i < s.count {
                        if starts("/*", i) { d += 1; i += 2; continue }
                        if starts("*/", i) { d -= 1; i += 2; if d == 0 { break }; continue }
                        step()
                    }
                    continue
                }
                let h = hashes(i)
                if h > 0, at(i + h) == "/" {
                    // an extended regex literal: to "/" and as many "#"
                    i += h + 1
                    while i < s.count, !(s[i] == "/" && hashes(i + 1) >= h) { step() }
                    i += 1 + h
                    continue
                }
                if at(i + h) == "\"" {
                    let multi = starts("\"\"\"", i + h)
                    i += h + (multi ? 3 : 1)
                    string(hashes: h, multi: multi)
                    continue
                }
                if h > 0 { i += h; continue }
                if nested {
                    if s[i] == "(" { depth += 1 } else if s[i] == ")" { if depth == 0 { i += 1; return }; depth -= 1 }
                }
                step()
            }
        }

        /// A string's text, from just inside its opening quote to just past its closing one.
        func string(hashes h: Int, multi: Bool) {
            let first = line
            var text = String.UnicodeScalarView()
            let close = (multi ? "\"\"\"" : "\"") + String(repeating: "#", count: h)
            let escape = "\\" + String(repeating: "#", count: h)
            while i < s.count {
                if starts(close, i) { i += close.unicodeScalars.count; out.append((first, String(text))); return }
                if starts(escape, i) {
                    let k = i + escape.unicodeScalars.count
                    if at(k) == "(" {
                        text.append("X"); i = k + 1
                        code(nested: true)
                        continue
                    }
                    if at(k) == "u", at(k + 1) == "{", let end = (k + 2..<s.count).first(where: { s[$0] == "}" }),
                       let v = UInt32(String(String.UnicodeScalarView(s[(k + 2)..<end])), radix: 16), let u = Unicode.Scalar(v) {
                        text.append(u); i = end + 1
                        continue
                    }
                    if let e = at(k) {
                        text.append(e == "n" ? "\n" : e == "t" ? "\t" : e)
                        i = k + 1; if e == "\n" { line += 1 }
                        continue
                    }
                }
                text.append(s[i]); step()
            }
            out.append((first, String(text)))
        }
    }
}
