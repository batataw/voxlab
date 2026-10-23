import Foundation

/// Découpe un texte ligne à ligne en blocs d'une taille maximale, sans jamais couper une ligne.
/// Les blocs s'arrêtent de préférence à une fin de couplet (ligne vide).
nonisolated enum TextChunker {
    static func chunks(of text: String, maxCharacters: Int) -> [[String]] {
        var chunks: [[String]] = []
        var current: [String] = []
        var currentSize = 0
        var lastStanzaBreak: Int?

        func flush(upTo end: Int) {
            chunks.append(Array(current[..<end]))
            current.removeFirst(end)
            currentSize = current.reduce(0) { $0 + $1.count + 1 }
            lastStanzaBreak = nil
        }

        for line in text.components(separatedBy: "\n") {
            let size = line.count + 1
            if currentSize + size > maxCharacters, !current.isEmpty {
                flush(upTo: lastStanzaBreak.map { $0 + 1 } ?? current.count)
            }
            current.append(line)
            currentSize += size
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                lastStanzaBreak = current.count - 1
            }
        }
        if !current.isEmpty {
            flush(upTo: current.count)
        }
        return chunks
    }
}
