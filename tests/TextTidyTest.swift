// How a dictation fits against the text already in the field.
//   swiftc -o /tmp/quill-texttidy-test Sources/TextTidy.swift tests/TextTidyTest.swift && /tmp/quill-texttidy-test
// Or simply: tests/run.sh
import Foundation

@main
enum TextTidyTest {
    static func main() {
        var failed = 0

        func expect(_ name: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("ok   \(name)")
            } else {
                print("FAIL \(name)")
                failed += 1
            }
        }

        func expectEqual(_ name: String, _ got: String, _ want: String) {
            if got == want {
                print("ok   \(name)")
            } else {
                print("FAIL \(name)\n     got:  \(got.debugDescription)\n     want: \(want.debugDescription)")
                failed += 1
            }
        }

        func end(_ s: String) -> Int { s.utf16.count }

        // MARK: isContinuation — are we landing mid-sentence?

        expect("continuation after a word", TextTidy.isContinuation(before: "so I was thinking ", at: end("so I was thinking ")))
        expect("continuation after a word, no trailing space", TextTidy.isContinuation(before: "so I was thinking", at: end("so I was thinking")))
        expect("continuation after a comma", TextTidy.isContinuation(before: "first, ", at: end("first, ")))
        expect("continuation after a colon", TextTidy.isContinuation(before: "note: ", at: end("note: ")))
        expect("continuation after a dash", TextTidy.isContinuation(before: "one thing — ", at: end("one thing — ")))
        expect("continuation after a digit", TextTidy.isContinuation(before: "step 1 ", at: end("step 1 ")))
        expect("continuation after a closing bracket", TextTidy.isContinuation(before: "(see above) ", at: end("(see above) ")))
        expect("continuation mid-text at caret", TextTidy.isContinuation(before: "abcdef", at: 3))

        expect("not continuation at empty field", !TextTidy.isContinuation(before: "", at: 0))
        expect("not continuation at nil field", !TextTidy.isContinuation(before: nil, at: nil))
        expect("not continuation at offset 0", !TextTidy.isContinuation(before: "hello", at: 0))
        expect("not continuation after a full stop", !TextTidy.isContinuation(before: "Done. ", at: end("Done. ")))
        expect("not continuation after question mark", !TextTidy.isContinuation(before: "Really? ", at: end("Really? ")))
        expect("not continuation after exclamation", !TextTidy.isContinuation(before: "Wow! ", at: end("Wow! ")))
        expect("not continuation after ellipsis", !TextTidy.isContinuation(before: "and then… ", at: end("and then… ")))
        expect("not continuation after Chinese full stop", !TextTidy.isContinuation(before: "好的。", at: end("好的。")))
        expect("not continuation after newline", !TextTidy.isContinuation(before: "line one\n", at: end("line one\n")))
        expect("not continuation after blank line", !TextTidy.isContinuation(before: "para one\n\n", at: end("para one\n\n")))
        expect("not continuation on a fresh indented line", !TextTidy.isContinuation(before: "para one\n    ", at: end("para one\n    ")))
        expect("not continuation after quoted sentence end",
               !TextTidy.isContinuation(before: "He said \"hello.\" ", at: end("He said \"hello.\" ")))
        expect("not continuation after parenthesised sentence end",
               !TextTidy.isContinuation(before: "(done.) ", at: end("(done.) ")))
        expect("not continuation after only whitespace", !TextTidy.isContinuation(before: "   ", at: 3))

        // Only the current line counts. A previous unfinished line does not make
        // the next one a continuation.
        expect("earlier line without a stop, fresh line now",
               !TextTidy.isContinuation(before: "no stop here\n", at: end("no stop here\n")))
        expect("mid-line in a later line", TextTidy.isContinuation(before: "Done.\nand then ", at: end("Done.\nand then ")))

        // List items start fresh.
        expect("not continuation after a dash bullet", !TextTidy.isContinuation(before: "- ", at: end("- ")))
        expect("not continuation after a dot bullet", !TextTidy.isContinuation(before: "• ", at: end("• ")))
        expect("not continuation after a star bullet", !TextTidy.isContinuation(before: "* ", at: end("* ")))
        expect("not continuation after a numbered item", !TextTidy.isContinuation(before: "1. ", at: end("1. ")))
        expect("not continuation after a bracketed number", !TextTidy.isContinuation(before: "12) ", at: end("12) ")))
        expect("not continuation after a lettered item", !TextTidy.isContinuation(before: "a) ", at: end("a) ")))
        expect("not continuation after an indented bullet", !TextTidy.isContinuation(before: "text\n  - ", at: end("text\n  - ")))
        expect("not continuation after a markdown heading marker", !TextTidy.isContinuation(before: "## ", at: end("## ")))
        expect("not continuation after a quote marker", !TextTidy.isContinuation(before: "> ", at: end("> ")))
        expect("a dash inside a sentence is still a continuation",
               TextTidy.isContinuation(before: "so - ", at: end("so - ")))

        // MARK: sentenceContinues — does what follows the caret carry on?

        expect("continues before a lowercase word", TextTidy.sentenceContinues(after: "I think  we should go", at: end("I think ")))
        expect("continues before a comma", TextTidy.sentenceContinues(after: "I think, we should", at: end("I think")))
        expect("does not continue at end of field", !TextTidy.sentenceContinues(after: "I think", at: end("I think")))
        expect("does not continue before a capital", !TextTidy.sentenceContinues(after: "one. Two", at: end("one. ")))
        expect("does not continue before a newline", !TextTidy.sentenceContinues(after: "one\nnext line", at: end("one")))
        expect("does not continue on nil field", !TextTidy.sentenceContinues(after: nil, at: nil))

        // MARK: decapitalizeLead — lower the opener, keep the exceptions

        expectEqual("lower a plain opener", TextTidy.decapitalizeLead("So we could ship"), "so we could ship")
        expectEqual("lower The", TextTidy.decapitalizeLead("The cat"), "the cat")
        expectEqual("lower single A", TextTidy.decapitalizeLead("A thing"), "a thing")
        expectEqual("lower And", TextTidy.decapitalizeLead("And then it works"), "and then it works")
        expectEqual("lower Because", TextTidy.decapitalizeLead("Because of that"), "because of that")
        expectEqual("lower Which", TextTidy.decapitalizeLead("Which means"), "which means")
        expectEqual("keep pronoun I", TextTidy.decapitalizeLead("I think"), "I think")
        expectEqual("keep I'm", TextTidy.decapitalizeLead("I'm sure"), "I'm sure")
        expectEqual("keep I'll", TextTidy.decapitalizeLead("I'll go"), "I'll go")
        expectEqual("keep I’ve (smart quote)", TextTidy.decapitalizeLead("I’ve seen it"), "I’ve seen it")
        expectEqual("keep acronym NASA", TextTidy.decapitalizeLead("NASA rocks"), "NASA rocks")
        expectEqual("keep acronym API", TextTidy.decapitalizeLead("API keys"), "API keys")
        expectEqual("keep OK", TextTidy.decapitalizeLead("OK then"), "OK then")
        expectEqual("keep a day name", TextTidy.decapitalizeLead("Monday we ship"), "Monday we ship")
        expectEqual("keep a month name", TextTidy.decapitalizeLead("December is cold"), "December is cold")
        expectEqual("keep a personal name", TextTidy.decapitalizeLead("John said hi"), "John said hi")
        expectEqual("keep a place name", TextTidy.decapitalizeLead("Paris is nice"), "Paris is nice")
        expectEqual("keep an organisation", TextTidy.decapitalizeLead("Google it"), "Google it")
        expectEqual("keep Elon", TextTidy.decapitalizeLead("Elon said"), "Elon said")
        expectEqual("already lowercase unchanged", TextTidy.decapitalizeLead("hello there"), "hello there")
        expectEqual("non-letter lead unchanged", TextTidy.decapitalizeLead("123 go"), "123 go")
        expectEqual("empty unchanged", TextTidy.decapitalizeLead(""), "")
        expectEqual("Chinese unchanged", TextTidy.decapitalizeLead("我们可以"), "我们可以")
        expectEqual("German is left alone (nouns are capitalised)", TextTidy.decapitalizeLead("Hunde sind toll", language: "de"), "Hunde sind toll")
        expectEqual("German detected under auto is left alone too", TextTidy.decapitalizeLead("Dann gehen wir nach Hause", language: "auto"), "Dann gehen wir nach Hause")
        expectEqual("English under auto is still lowered", TextTidy.decapitalizeLead("So we could ship it", language: "auto"), "so we could ship it")

        // MARK: trimTrailingTerminator

        expectEqual("drop trailing full stop", TextTidy.trimTrailingTerminator("maybe later."), "maybe later")
        expectEqual("drop trailing question mark", TextTidy.trimTrailingTerminator("maybe later?"), "maybe later")
        expectEqual("keep ellipsis", TextTidy.trimTrailingTerminator("maybe later…"), "maybe later…")
        expectEqual("nothing to drop", TextTidy.trimTrailingTerminator("maybe later"), "maybe later")
        expectEqual("only one dropped", TextTidy.trimTrailingTerminator("what?!"), "what?")

        // MARK: Spacing (unchanged behaviour, now testable)

        expect("space after a word", TextTidy.needsSeparator(before: "hello", at: 5, inserting: "world"))
        expect("no space after whitespace", !TextTidy.needsSeparator(before: "hello ", at: 6, inserting: "world"))
        expect("no space after an opening bracket", !TextTidy.needsSeparator(before: "(", at: 1, inserting: "world"))
        expect("no space before a comma", !TextTidy.needsSeparator(before: "hello", at: 5, inserting: ", world"))
        expect("no space in an empty field", !TextTidy.needsSeparator(before: "", at: 0, inserting: "world"))
        expect("trailing space before a following word", TextTidy.needsTrailingSeparator(in: "hello world", at: 6, inserting: "there"))
        expect("no trailing space before whitespace", !TextTidy.needsTrailingSeparator(in: "hello world", at: 5, inserting: "there"))
        expect("no space between Chinese characters", !TextTidy.needsSeparator(before: "我在想", at: 3, inserting: "我们"))
        expect("no trailing space before Chinese", !TextTidy.needsTrailingSeparator(in: "我在想", at: 1, inserting: "们"))
        expect("no trailing space before a comma", !TextTidy.needsTrailingSeparator(in: "hello, world", at: 5, inserting: "there"))
        expect("no trailing space at the end", !TextTidy.needsTrailingSeparator(in: "hello", at: 5, inserting: "there"))

        // MARK: fit — the whole thing, as the inserter uses it

        expectEqual("the reported bug: append mid-sentence",
                    TextTidy.fit("So we could ship on Friday.", into: "so I was thinking ", at: end("so I was thinking ")),
                    "so we could ship on Friday.")
        expectEqual("append mid-sentence without a trailing space adds one",
                    TextTidy.fit("So we could", into: "so I was thinking", at: end("so I was thinking")),
                    " so we could")
        expectEqual("append after a full stop keeps the capital",
                    TextTidy.fit("Great idea.", into: "Done. ", at: end("Done. ")),
                    "Great idea.")
        expectEqual("append after a full stop with no space adds one and keeps the capital",
                    TextTidy.fit("Great idea.", into: "Done.", at: end("Done.")),
                    " Great idea.")
        expectEqual("empty field untouched",
                    TextTidy.fit("Hello world.", into: "", at: 0),
                    "Hello world.")
        expectEqual("unreadable field untouched",
                    TextTidy.fit("Hello world.", into: nil, at: nil),
                    "Hello world.")
        expectEqual("nil offset means the end of the field",
                    TextTidy.fit("So we could", into: "I was thinking ", at: nil),
                    "so we could")
        expectEqual("mid-sentence I stays capital",
                    TextTidy.fit("I think so.", into: "you know ", at: end("you know ")),
                    "I think so.")
        expectEqual("insert into the middle of a sentence: case and full stop, one space",
                    TextTidy.fit("Maybe.", into: "I think we should go", at: end("I think")),
                    " maybe")
        expectEqual("insert between two words with no gap: both spaces",
                    TextTidy.fit("Maybe.", into: "I thinkwe should go", at: end("I think")),
                    " maybe ")
        expectEqual("insert before a comma drops the full stop and the trailing space",
                    TextTidy.fit("Maybe.", into: "I think, we should go", at: end("I think")),
                    " maybe")
        expectEqual("insert before a new sentence keeps the full stop",
                    TextTidy.fit("Maybe.", into: "I think. We should go", at: end("I think. ")),
                    "Maybe. ")
        expectEqual("new list item keeps its capital",
                    TextTidy.fit("Buy milk.", into: "Shopping:\n- ", at: end("Shopping:\n- ")),
                    "Buy milk.")
        expectEqual("numbered item keeps its capital",
                    TextTidy.fit("Buy milk.", into: "1. ", at: end("1. ")),
                    "Buy milk.")
        expectEqual("fresh line keeps its capital",
                    TextTidy.fit("Buy milk.", into: "Shopping list\n", at: end("Shopping list\n")),
                    "Buy milk.")
        expectEqual("terminal prompt line is treated as a continuation (commands are lowercase)",
                    TextTidy.fit("Git status.", into: "~/code ❯ ", at: end("~/code ❯ ")),
                    "git status.")
        expectEqual("name mid-sentence keeps its capital",
                    TextTidy.fit("John will know.", into: "ask ", at: end("ask ")),
                    "John will know.")
        expectEqual("Chinese passes straight through",
                    TextTidy.fit("我们可以明天再说。", into: "我在想", at: end("我在想")),
                    "我们可以明天再说。")

        if failed > 0 {
            print("\n\(failed) failed")
            exit(1)
        }
        print("\nall passed")
    }
}
