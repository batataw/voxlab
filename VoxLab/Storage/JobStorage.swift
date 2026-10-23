import Foundation

/// Emplacement des artefacts d'un job sur disque :
/// `~/Library/Application Support/VoxLab/jobs/<jobID>/`.
nonisolated struct JobStorage: Sendable {
    let rootDirectory: URL

    init(rootDirectory: URL = JobStorage.defaultRoot) {
        self.rootDirectory = rootDirectory
    }

    static var defaultRoot: URL {
        URL.applicationSupportDirectory
            .appending(path: "VoxLab", directoryHint: .isDirectory)
            .appending(path: "jobs", directoryHint: .isDirectory)
    }

    func directory(for jobID: UUID) -> URL {
        rootDirectory.appending(path: jobID.uuidString, directoryHint: .isDirectory)
    }

    /// Crée le dossier du job s'il n'existe pas encore et le renvoie.
    @discardableResult
    func prepareDirectory(for jobID: UUID) throws -> URL {
        let url = directory(for: jobID)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func removeDirectory(for jobID: UUID) throws {
        let url = directory(for: jobID)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

/// Noms des artefacts produits par chaque étape.
nonisolated enum JobArtifact {
    static let source = "source.wav"
    static let vocals = "vocals.wav"
    static let rawTranscript = "transcript_raw.txt"
    static let correctedTranscript = "transcript_corrected.txt"

    static func translation(language: String) -> String {
        "translation_\(language).txt"
    }
}
