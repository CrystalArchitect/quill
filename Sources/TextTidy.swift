import Foundation
import NaturalLanguage

/// How a dictation fits against the text that is already in the field.
///
/// Speech-to-text treats every utterance as its own sentence: the first word
/// arrives capitalised and the last one usually carries a full stop. Both are
/// wrong the moment the words land mid-sentence — after "…so I was thinking "
/// a capital "So" reads as a typo, and a full stop dropped in front of ", which"
/// breaks the line. This is the logic that looks at the characters on either
/// side of the insertion point and adjusts the payload to match.
///
/// Deliberately free of AppKit and Accessibility. Everything here is a pure
/// function of three strings, which is what lets it be unit-tested without a
/// Mac in the loop (`tests/TextTidyTest.swift`).
enum TextTidy {

    /// The payload to write: case-corrected, terminator-trimmed and padded so it
    /// neither runs into its neighbours nor leaves a double space.
    ///
    /// - existing: the field's current contents, or nil if it could not be read.
    /// - offset:   where the text will land, in UTF-16 units, or nil if unknown.
    ///             When unknown the end of the field is assumed.
    /// - language: the dictation language code ("en", "de", "auto", …). Only
    ///             used to keep German nouns capitalised.
    static func fit(_ text: String, into existing: String?, at offset: Int?, language: String = "en") -> String {
        var out = text
        let boundary = offset ?? existing?.utf16.count

        if isContinuation(before: existing, at: boundary) {
            out = decapitalizeLead(out, language: language)
        }
        if sentenceContinues(after: existing, at: boundary) {
            out = trimTrailingTerminator(out)
        }

        if needsSeparator(before: existing, at: boundary, inserting: out) { out = " " + out }
        if needsTrailingSeparator(in: existing, at: boundary, inserting: out) { out += " " }
        return out
    }

    // MARK: Where are we landing?

    /// Are we landing in the MIDDLE of a sentence, rather than at the start of a
    /// field, a fresh line, a list item, or right after a finished sentence?
    ///
    /// Only the current line matters. Walking back from the caret: trailing
    /// whitespace and closing wrappers (`" ' ) ] }` and their smart forms) are
    /// skipped, so `He said "hello."` and `(done.)` still read as finished. A
    /// terminator (`. ! ? …`) or nothing but a list marker (`-`, `•`, `1.`, `a)`)
    /// means the next word starts fresh and keeps its capital.
    static func isContinuation(before existing: String?, at offset: Int?) -> Bool {
        guard let existing, !existing.isEmpty, let offset, offset > 0 else { return false }
        let line = lineBefore(offset, in: existing)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }                // fresh line
        if isListMarker(trimmed) { return false }          // "- ", "• ", "1) ", "a."

        var index = line.endIndex
        while index > line.startIndex {
            let previous = line.index(before: index)
            let character = line[previous]
            if character.isWhitespace || closingWrappers.contains(character) {
                index = previous
                continue
            }
            return !terminators.contains(character)
        }
        return false                                       // only wrappers and spaces
    }

    /// Does the text after the caret carry on the same sentence? True when the
    /// next thing on the line is a lowercase letter or a joining punctuation
    /// mark — the cases where a full stop from the dictation would be wrong.
    static func sentenceContinues(after existing: String?, at offset: Int?) -> Bool {
        guard let existing, let offset, offset < existing.utf16.count else { return false }
        let line = lineAfter(offset, in: existing)
        guard let next = line.first(where: { !$0.isWhitespace }) else { return false }
        if next.isLetter { return next.isLowercase }
        return ",;:".contains(next)
    }

    // MARK: Adjusting the payload

    /// Lowercases only the first letter, for use when continuing a sentence.
    ///
    /// Words that are capitalised in their own right are left alone: the pronoun
    /// "I" and its contractions, all-caps acronyms (NASA, API), day and month
    /// names, and anything the system's on-device tagger recognises as a
    /// personal, place or organisation name. German is left entirely alone —
    /// every noun is capitalised there, and lowercasing one is a worse error
    /// than leaving a function word capitalised. Brand names the tagger does not
    /// know ("Cursor", "Grok") are the remaining gap; the common case, a
    /// function word the service capitalised because it opened the utterance,
    /// is what this corrects.
    static func decapitalizeLead(_ text: String, language: String = "en") -> String {
        guard let first = text.first, first.isLetter, first.isUppercase else { return text }
        if capitalisesNouns(language: language, text: text) { return text }
        let token = leadingToken(text)
        if shouldPreserveCapital(token, in: text) { return text }
        return text.prefix(1).lowercased() + text.dropFirst()
    }

    /// Drops one trailing sentence terminator, for text landing mid-sentence.
    static func trimTrailingTerminator(_ text: String) -> String {
        guard let last = text.last, terminators.contains(last), last != "\u{2026}" else { return text }
        return String(text.dropLast())
    }

    // MARK: Spacing

    /// Should a space go between what is already there and what we are adding?
    ///
    /// Only when the two would otherwise collide: there is text before the
    /// insertion point, it does not already end in whitespace or an opening
    /// bracket, and the new text does not begin with punctuation that belongs
    /// tight against the previous word.
    static func needsSeparator(before existing: String?, at offset: Int?, inserting text: String) -> Bool {
        guard let existing, !existing.isEmpty, let offset, offset > 0 else { return false }
        guard let boundary = character(in: existing, before: offset) else { return false }

        if boundary.isWhitespace || boundary.isNewline { return false }
        if "([{<\u{201C}\u{2018}\"'-–—/@#".contains(boundary) { return false }

        if let first = text.first {
            if ",.;:!?)]}%\u{201D}\u{2019}".contains(first) { return false }
            // Chinese and Japanese do not put spaces between words.
            if isCJK(first) || isCJK(boundary) { return false }
        }
        return true
    }

    /// Should a space go between what we are adding and what already follows?
    ///
    /// Only relevant when landing mid-text — appending at the end has nothing
    /// after it. Mirrors the leading rule: skip it if the next character is
    /// already whitespace, or is punctuation that belongs tight against a word.
    static func needsTrailingSeparator(in existing: String?, at offset: Int?, inserting text: String) -> Bool {
        guard let existing, let offset, offset >= 0, offset < existing.utf16.count else { return false }
        guard let next = character(in: existing, atOrAfter: offset) else { return false }

        if next.isWhitespace || next.isNewline { return false }
        if ",.;:!?)]}%\u{201D}\u{2019}".contains(next) { return false }

        if let last = text.last {
            if last.isWhitespace { return false }
            if isCJK(last) || isCJK(next) { return false }
        }
        return true
    }

    // MARK: Internals

    private static let terminators: Set<Character> = [".", "!", "?", "\u{2026}", "\u{3002}", "\u{FF01}", "\u{FF1F}"]
    private static let closingWrappers: Set<Character> = ["\"", "'", ")", "]", "}", "\u{2019}", "\u{201D}", "\u{300D}", "\u{300F}"]

    private static let listMarker = try! NSRegularExpression(
        pattern: "^(?:[-–—•*+>#]+|\\d{1,3}[.)]|[a-zA-Z][.)])$")

    private static let dayAndMonthNames: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july", "august",
        "september", "october", "november", "december",
    ]

    /// The current line up to the caret.
    private static func lineBefore(_ utf16Offset: Int, in text: String) -> Substring {
        let units = text.utf16
        let clamped = min(max(utf16Offset, 0), units.count)
        let unit = units.index(units.startIndex, offsetBy: clamped)
        let end = String.Index(unit, within: text) ?? text.endIndex
        var start = end
        while start > text.startIndex {
            let previous = text.index(before: start)
            if text[previous].isNewline { break }
            start = previous
        }
        return text[start..<end]
    }

    /// The current line from the caret onward.
    private static func lineAfter(_ utf16Offset: Int, in text: String) -> Substring {
        let units = text.utf16
        let clamped = min(max(utf16Offset, 0), units.count)
        let unit = units.index(units.startIndex, offsetBy: clamped)
        let start = String.Index(unit, within: text) ?? text.endIndex
        var end = start
        while end < text.endIndex, !text[end].isNewline { end = text.index(after: end) }
        return text[start..<end]
    }

    private static func isListMarker(_ trimmedLine: String) -> Bool {
        let range = NSRange(trimmedLine.startIndex..., in: trimmedLine)
        return listMarker.firstMatch(in: trimmedLine, range: range) != nil
    }

    /// Han, Hiragana, Katakana, and the CJK punctuation and fullwidth blocks.
    private static func isCJK(_ character: Character) -> Bool {
        guard let value = character.unicodeScalars.first?.value else { return false }
        switch value {
        case 0x3000...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xF900...0xFAFF, 0xFF00...0xFFEF, 0x20000...0x2FFFF:
            return true
        default:
            return false
        }
    }

    /// The opening run of letters and internal apostrophes: "I'll," → "I'll".
    private static func leadingToken(_ text: String) -> String {
        var token = ""
        for character in text {
            if character.isLetter || character == "'" || character == "\u{2019}" {
                token.append(character)
            } else {
                break
            }
        }
        return token
    }

    private static func shouldPreserveCapital(_ token: String, in text: String) -> Bool {
        if token == "I" || token.hasPrefix("I'") || token.hasPrefix("I\u{2019}") { return true }
        let letters = token.filter { $0.isLetter }
        if letters.count >= 2, letters.allSatisfy({ $0.isUppercase }) { return true }
        if dayAndMonthNames.contains(token.lowercased()) { return true }
        return isName(leading: token, in: text)
    }

    /// Does the on-device tagger read the first word as a personal, place or
    /// organisation name? Tagged in the context of the whole dictation, which is
    /// what lets it tell "Paris is nice" from "Maybe later".
    private static func isName(leading token: String, in text: String) -> Bool {
        guard token.count >= 2 else { return false }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .word, scheme: .nameType)
        switch tag {
        case .personalName?, .placeName?, .organizationName?: return true
        default: return false
        }
    }

    /// German capitalises every noun, and the on-device tagger cannot tell a
    /// German noun from a function word reliably enough to act on. With
    /// auto-detect on, the language is inferred from the dictation itself.
    private static func capitalisesNouns(language: String, text: String) -> Bool {
        if language == "de" { return true }
        guard language == "auto" || language.isEmpty else { return false }
        return NLLanguageRecognizer.dominantLanguage(for: text) == .german
    }

    private static func character(in text: String, atOrAfter utf16Offset: Int) -> Character? {
        let units = text.utf16
        guard utf16Offset >= 0, utf16Offset < units.count else { return nil }
        let position = units.index(units.startIndex, offsetBy: utf16Offset)
        guard let index = String.Index(position, within: text), index < text.endIndex else { return nil }
        return text[index]
    }

    private static func character(in text: String, before utf16Offset: Int) -> Character? {
        let units = text.utf16
        guard utf16Offset > 0, utf16Offset <= units.count else { return nil }
        let end = units.index(units.startIndex, offsetBy: utf16Offset)
        guard let index = String.Index(end, within: text), index > text.startIndex else { return nil }
        return text[text.index(before: index)]
    }
}
