import Foundation

/// Environnement commun aux binaires externes. Une app lancée depuis le Finder
/// hérite d'un PATH minimal : on y ajoute Homebrew pour les sous-processus (ffmpeg…).
nonisolated enum ToolEnvironment {
    static let path = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        .joined(separator: ":")

    static var base: [String: String] { ["PATH": path] }
}
