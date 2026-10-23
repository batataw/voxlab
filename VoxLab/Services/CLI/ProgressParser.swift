import Foundation

/// Extrait une progression (0…1) des sorties des outils en ligne de commande.
nonisolated enum ProgressParser: Sendable {
    /// Barre tqdm de Demucs : ` 45%|████▌     | 52.6/117.0 [00:10<00:12, …]`.
    case demucs
    /// yt-dlp : `[download]  42.3% of   3.52MiB at  1.20MiB/s ETA 00:01`.
    case ytDlp

    func progress(in line: String) -> Double? {
        switch self {
        case .demucs:
            Self.percentage(in: line, pattern: /(\d{1,3})%\|/)
        case .ytDlp:
            Self.percentage(in: line, pattern: /\[download\]\s+(\d{1,3}(?:\.\d+)?)%/)
        }
    }

    private static func percentage(in line: String, pattern: Regex<(Substring, Substring)>) -> Double? {
        guard let match = line.firstMatch(of: pattern), let value = Double(match.1) else {
            return nil
        }
        return min(max(value / 100, 0), 1)
    }
}
