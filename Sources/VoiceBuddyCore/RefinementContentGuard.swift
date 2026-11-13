import Foundation
import NaturalLanguage

/// Moderate editing preserves vocabulary; missing multi-character nouns indicate lost content.
public enum RefinementContentGuard {
    public static func missingNouns(in output: String, original: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = original
        let range = original.startIndex..<original.endIndex
        if original.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
            tagger.setLanguage(.simplifiedChinese, range: range)
        }
        var missing = Set<String>()
        let folded = output.lowercased()
        tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, token in
            let word = String(original[token])
            if tag == .noun, word.count >= 2, !folded.contains(word.lowercased()) { missing.insert(word) }
            return true
        }
        return missing.sorted()
    }
}
