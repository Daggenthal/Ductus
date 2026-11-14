// Prints the lines from stdin that the macOS spell checker accepts in any of
// the given languages. Used by build_corpus.py to drop old spellings
// ("fôrça", "daß", "eenigszins") and typos from the book text.
//
// Usage: swift scripts/spellcheck.swift pt_BR,pt_PT < words.txt
import AppKit

let languages = CommandLine.arguments.dropFirst().first?.split(separator: ",").map(String.init) ?? []
let checker = NSSpellChecker.shared
for language in languages where !checker.availableLanguages.contains(language) {
    FileHandle.standardError.write("spell checker has no \(language) dictionary\n".data(using: .utf8)!)
    exit(1)
}
while let word = readLine() {
    let accepted = languages.contains { language in
        checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false,
                              inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
    }
    if accepted { print(word) }
}
