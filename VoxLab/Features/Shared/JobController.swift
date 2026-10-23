import Foundation
import Observation
import os
import SwiftData

/// Actions sur les jobs exposées aux vues : création, lancement, annulation, suppression.
@MainActor
@Observable
final class JobController {
    private static let logger = Logger(subsystem: "com.voxlab", category: "JobController")

    private let runner: PipelineRunner
    private let storage: JobStorage
    private let context: ModelContext

    init(runner: PipelineRunner, storage: JobStorage, context: ModelContext) {
        self.runner = runner
        self.storage = storage
        self.context = context
    }

    /// Crée un job à partir d'un fichier local et lance le pipeline.
    @discardableResult
    func createJob(fileURL: URL, targetLanguage: SupportedLanguage) -> Job {
        let job = Job(
            title: fileURL.deletingPathExtension().lastPathComponent,
            sourceKind: .file,
            sourceReference: fileURL.path(percentEncoded: false),
            targetLanguage: targetLanguage.rawValue,
            quality: QualityMode.load()
        )
        context.insert(job)
        save()
        start(job, scope: .resume)
        return job
    }

    /// Crée un job à partir d'une URL YouTube ; le titre définitif vient de yt-dlp à l'import.
    @discardableResult
    func createJob(youtubeURL: URL, targetLanguage: SupportedLanguage) -> Job {
        let job = Job(
            title: "YouTube – \(youtubeURL.absoluteString)",
            sourceKind: .youtube,
            sourceReference: youtubeURL.absoluteString,
            targetLanguage: targetLanguage.rawValue,
            quality: QualityMode.load()
        )
        context.insert(job)
        save()
        start(job, scope: .resume)
        return job
    }

    func resume(_ job: Job) {
        start(job, scope: .resume)
    }

    func rerun(_ step: Step, of job: Job) {
        start(job, scope: .only(step))
    }

    func cancel(_ job: Job) {
        let id = job.id
        Task { await runner.cancel(jobID: id) }
    }

    /// Supprime le job, ses étapes et ses fichiers sur disque.
    func delete(_ job: Job) {
        let id = job.id
        Task { await runner.cancel(jobID: id) }
        do {
            try storage.removeDirectory(for: id)
        } catch {
            Self.logger.error("Suppression des fichiers du job impossible : \(error.localizedDescription, privacy: .public)")
        }
        context.delete(job)
        save()
    }

    /// Édition manuelle d'un texte : mise à jour en base et dans le fichier.
    /// Modifier le texte corrigé rend la traduction obsolète.
    func updateText(_ text: String, kind: TranscriptKind, of job: Job) {
        guard job.text(kind) != text else { return }
        switch kind {
        case .raw: job.rawTranscript = text
        case .corrected:
            job.correctedTranscript = text
            if job.translation != nil { job.isTranslationStale = true }
        case .translated: job.translation = text
        }
        do {
            let directory = try storage.prepareDirectory(for: job.id)
            try text.write(to: directory.appending(path: job.artifactName(for: kind)), atomically: true, encoding: .utf8)
        } catch {
            Self.logger.error("Écriture du texte impossible : \(error.localizedDescription, privacy: .public)")
        }
        save()
    }

    /// Change la langue cible ; une traduction existante devient obsolète.
    func setTargetLanguage(_ language: SupportedLanguage, of job: Job) {
        guard job.targetLanguage != language.rawValue else { return }
        job.targetLanguage = language.rawValue
        if job.translation != nil { job.isTranslationStale = true }
        save()
    }

    var translatesViaLLM: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.translateViaLLM)
    }

    /// URL d'un artefact du job s'il existe sur disque.
    func existingArtifact(_ name: String, of job: Job) -> URL? {
        let url = storage.directory(for: job.id).appending(path: name)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    func directory(of job: Job) -> URL {
        storage.directory(for: job.id)
    }

    private func start(_ job: Job, scope: PipelineScope) {
        let id = job.id
        Task { await runner.start(jobID: id, scope: scope) }
    }

    private func save() {
        do {
            try context.save()
        } catch {
            Self.logger.error("Sauvegarde SwiftData impossible : \(error.localizedDescription, privacy: .public)")
        }
    }
}
