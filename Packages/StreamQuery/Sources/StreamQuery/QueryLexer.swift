//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// A piece of query text.
enum QueryToken: Equatable {

    case word(String)

    /// A word that arrived in quotes.
    ///
    /// Kept distinct from `word` because quoting is what says "this is a search
    /// term, not a keyword": `unread` is the flag, `"unread"` is the word.
    case quotedWord(String)

    /// `field:value`. The value keeps whatever quoting it arrived with removed.
    case pair(field: String, value: String)

    case or
    case not
    case openParen
    case closeParen
}

/// Splits query text into tokens.
///
/// Quoting exists so that a value can contain spaces — `title:"swift concurrency"`
/// — and so that a bare phrase can be searched as a phrase.
enum QueryLexer {

    static func tokenize(_ input: String) -> [QueryToken] {

        var tokens: [QueryToken] = []
        var characters = Array(input)
        var index = 0

        func skipWhitespace() {
            while index < characters.count, characters[index].isWhitespace {
                index += 1
            }
        }

        /// Reads a run of characters, honouring quotes.
        ///
        /// - Parameter stopAtColon: True while reading a possible field name, so
        ///   that `title:swift` splits but `https://example.com` does not get
        ///   mangled once we are past the field position.
        func readValue(stopAtColon: Bool) -> (text: String, wasQuoted: Bool) {
            if index < characters.count, characters[index] == "\"" {
                index += 1
                var value = ""
                while index < characters.count, characters[index] != "\"" {
                    // A backslash escapes the next character, so a value can
                    // contain the quote that delimits it.
                    if characters[index] == "\\", index + 1 < characters.count {
                        index += 1
                    }
                    value.append(characters[index])
                    index += 1
                }
                if index < characters.count { index += 1 }  // closing quote
                return (value, true)
            }

            var value = ""
            while index < characters.count {
                let character = characters[index]
                if character.isWhitespace || character == "(" || character == ")" {
                    break
                }
                if stopAtColon, character == ":" {
                    break
                }
                value.append(character)
                index += 1
            }
            return (value, false)
        }

        while index < characters.count {
            skipWhitespace()
            guard index < characters.count else { break }

            let character = characters[index]

            if character == "(" {
                tokens.append(.openParen)
                index += 1
                continue
            }

            if character == ")" {
                tokens.append(.closeParen)
                index += 1
                continue
            }

            // A leading minus negates the term that follows.
            if character == "-", index + 1 < characters.count,
               !characters[index + 1].isWhitespace {
                tokens.append(.not)
                index += 1
                continue
            }

            let (head, wasQuoted) = readValue(stopAtColon: true)

            // `field:value`
            if !wasQuoted, index < characters.count, characters[index] == ":" {
                index += 1
                let (value, _) = readValue(stopAtColon: false)
                tokens.append(.pair(field: head, value: value))
                continue
            }

            guard !head.isEmpty || wasQuoted else {
                index += 1
                continue
            }

            // Keywords are only keywords unquoted, so `"or"` searches for the
            // word rather than combining terms.
            if !wasQuoted {
                switch head.uppercased() {
                case "OR": tokens.append(.or); continue
                case "AND": continue  // implicit; juxtaposition already means AND
                case "NOT": tokens.append(.not); continue
                default: break
                }
            }

            tokens.append(wasQuoted ? .quotedWord(head) : .word(head))
        }

        return tokens
    }
}
