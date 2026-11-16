import Foundation

/// The text transformations Text Tool offers.
public enum TextCase: String, CaseIterable, Identifiable, Sendable {
    case upper
    case lower
    case title
    case sentence
    case camel
    case snake

    public var id: String { rawValue }

    /// Button label, written in the style it produces.
    public var label: String {
        switch self {
        case .upper: return "UPPERCASE"
        case .lower: return "lowercase"
        case .title: return "Title Case"
        case .sentence: return "Sentence case"
        case .camel: return "camelCase"
        case .snake: return "snake_case"
        }
    }
}

public enum CaseConverter {
    /// Converts `text` to the given case. Conversions are always meant to be
    /// applied to the user's *original* text so that switching between cases is lossless.
    public static func convert(_ text: String, to textCase: TextCase) -> String {
        switch textCase {
        case .upper: return text.uppercased()
        case .lower: return text.lowercased()
        case .title: return titleCase(text)
        case .sentence: return sentenceCase(text)
        case .camel: return perLine(text) { camelCase(words(in: $0)) }
        case .snake: return perLine(text) { words(in: $0).map { $0.lowercased() }.joined(separator: "_") }
        }
    }

    // MARK: - Title & sentence case

    /// Minor words kept lowercase in Title Case unless they start or end a phrase.
    static let minorWords: Set<String> = [
        "a", "an", "the", "and", "but", "or", "nor", "for", "so", "yet",
        "as", "at", "by", "in", "of", "off", "on", "per", "to", "up", "via", "vs", "vs.",
    ]

    static func titleCase(_ text: String) -> String {
        let tokens = tokenize(text)
        let shouting = isShouting(text)
        let wordIndices = tokens.indices.filter { tokens[$0].isWord }
        guard let firstWord = wordIndices.first, let lastWord = wordIndices.last else { return text }

        var result = ""
        var startOfPhrase = true
        for (index, token) in tokens.enumerated() {
            guard token.isWord else {
                result += token.text
                if token.text.contains(where: { ":.!?\n—–".contains($0) }) { startOfPhrase = true }
                continue
            }
            defer { startOfPhrase = false }
            if !shouting, shouldPreserve(token.text) {
                result += token.text
                continue
            }
            let lower = token.text.lowercased()
            let isEdge = index == firstWord || index == lastWord || startOfPhrase
            if !isEdge, minorWords.contains(lower) {
                result += lower
            } else {
                result += capitalizeFirstLetter(lower)
            }
        }
        return result
    }

    static func sentenceCase(_ text: String) -> String {
        let tokens = tokenize(text)
        let shouting = isShouting(text)
        var result = ""
        var capitalizeNext = true
        for token in tokens {
            guard token.isWord else {
                result += token.text
                if endsSentence(token.text) { capitalizeNext = true }
                continue
            }
            defer { capitalizeNext = false }
            if !shouting, shouldPreserve(token.text) {
                result += token.text
                continue
            }
            let lower = token.text.lowercased()
            if capitalizeNext || isPronounI(lower) {
                result += capitalizeFirstLetter(lower)
            } else {
                result += lower
            }
        }
        return result
    }

    /// A separator ends a sentence if it has a terminator followed by whitespace, or a line break.
    private static func endsSentence(_ separator: String) -> Bool {
        if separator.contains(where: \.isNewline) { return true }
        var sawTerminator = false
        for ch in separator {
            if ".!?".contains(ch) { sawTerminator = true }
            else if sawTerminator, ch.isWhitespace { return true }
        }
        return false
    }

    private static func isPronounI(_ lower: String) -> Bool {
        lower == "i" || lower.hasPrefix("i'") || lower.hasPrefix("i’")
    }

    /// Text that is mostly uppercase — acronyms can't be told apart then, so nothing is preserved.
    private static func isShouting(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty else { return false }
        let upper = letters.filter(\.isUppercase).count
        return Double(upper) / Double(letters.count) >= 0.7
    }

    /// Keeps acronyms (NASA) and intentionally mixed-case words (iPhone, macOS, McDonald).
    private static func shouldPreserve(_ word: String) -> Bool {
        let letters = word.filter(\.isLetter)
        guard letters.count > 1 else { return false }
        if letters.allSatisfy(\.isUppercase) { return true }
        let tail = letters.dropFirst()
        return tail.contains(where: \.isUppercase)
    }

    private static func capitalizeFirstLetter(_ word: String) -> String {
        guard let idx = word.firstIndex(where: \.isLetter) else { return word }
        return String(word[..<idx]) + word[idx].uppercased() + String(word[word.index(after: idx)...])
    }

    // MARK: - Developer formats

    private static func camelCase(_ words: [String]) -> String {
        words.enumerated().map { index, word in
            let lower = word.lowercased()
            return index == 0 ? lower : capitalizeFirstLetter(lower)
        }.joined()
    }

    /// Applies a transform to every line, keeping blank lines and leading indentation.
    private static func perLine(_ text: String, _ transform: (String) -> String) -> String {
        text.components(separatedBy: "\n").map { line in
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
            let body = line.dropFirst(indent.count).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? line : String(indent) }
            return indent + transform(body)
        }.joined(separator: "\n")
    }

    /// Splits text into identifier words: on separators, on lower→Upper boundaries
    /// ("fooBar"), and before the last capital of an acronym run ("HTTPServer" → HTTP, Server).
    /// Apostrophes are dropped ("don't" → "dont").
    static func words(in text: String) -> [String] {
        let chars = Array(text)
        var words: [String] = []
        var current = ""

        func flush() {
            if !current.isEmpty { words.append(current); current = "" }
        }

        for (i, ch) in chars.enumerated() {
            if ch == "'" || ch == "’" { continue }
            guard ch.isLetter || ch.isNumber else { flush(); continue }
            if let prev = current.last {
                let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
                if ch.isUppercase, prev.isLowercase || prev.isNumber {
                    flush()
                } else if ch.isUppercase, prev.isUppercase, let next, next.isLowercase {
                    flush()
                }
            }
            current.append(ch)
        }
        flush()
        return words
    }

    // MARK: - Tokenizer

    struct Token {
        var text: String
        var isWord: Bool
    }

    private static func isWordCharacter(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber || ch == "'" || ch == "’"
    }

    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        for ch in text {
            let isWord = isWordCharacter(ch)
            if let last = tokens.last, last.isWord == isWord {
                tokens[tokens.count - 1].text.append(ch)
            } else {
                tokens.append(Token(text: String(ch), isWord: isWord))
            }
        }
        return tokens
    }

    // MARK: - Stats

    public static func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }
}
