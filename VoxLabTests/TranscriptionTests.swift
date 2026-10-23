import Foundation
import Synchronization
import Testing
import WhisperKit
@testable import VoxLab

/// Transcripteur factice qui renvoie un texte fixe.
final class StubTranscriber: Transcriber {
    let transcription: Transcription
    let calls = Mutex<[(URL, QualityMode)]>([])

    init(transcription: Transcription) {
        self.transcription = transcription
    }

    func transcribe(audio: URL, quality: QualityMode, onProgress: @escaping @Sendable (Double) -> Void) async throws -> Transcription {
        calls.withLock { $0.append((audio, quality)) }
        onProgress(1)
        return transcription
    }
}

@Suite("Transcription")
struct TranscriptionTests {
    private func result(_ texts: [String], language: String) -> TranscriptionResult {
        TranscriptionResult(
            text: texts.joined(),
            segments: texts.map { TranscriptionSegment(text: $0) },
            language: language,
            timings: TranscriptionTimings()
        )
    }

    @Test("Un segment par ligne, segments vides ignorés")
    func oneSegmentPerLine() {
        let transcription = WhisperKitTranscriber.makeTranscription(from: [
            result([" Je marche seul ", "  ", "dans les rues de Paris"], language: "fr"),
            result([" Je marche seul"], language: "fr"),
        ])
        #expect(transcription.text == "Je marche seul\ndans les rues de Paris\nJe marche seul")
        #expect(transcription.language == "fr")
    }

    @Test("La langue retenue est celle de la majorité des segments")
    func majorityLanguage() {
        let transcription = WhisperKitTranscriber.makeTranscription(from: [
            result(["Yeah"], language: "en"),
            result(["Un", "deux", "trois"], language: "fr"),
            result([], language: "de"),
        ])
        #expect(transcription.language == "fr")
    }

    @Test("Aucun segment : texte vide et langue inconnue")
    func empty() {
        let transcription = WhisperKitTranscriber.makeTranscription(from: [])
        #expect(transcription.text.isEmpty)
        #expect(transcription.language == nil)
    }

    @Test("L'étape écrit transcript_raw.txt et renvoie texte et langue")
    func stepWritesArtifact() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "voxlab-transcribe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let transcriber = StubTranscriber(transcription: Transcription(text: "la la la", language: "it"))
        let context = StepContext(jobID: UUID(), directory: dir, source: .file(URL(filePath: "/tmp/a.mp3")), targetLanguage: "fr", quality: .fast)

        let output = try await TranscribeStep(transcriber: transcriber).run(context) { _ in }

        #expect(output == StepOutput(text: "la la la", detectedLanguage: "it"))
        #expect(try String(contentsOf: dir.appending(path: JobArtifact.rawTranscript), encoding: .utf8) == "la la la")
        let call = try #require(transcriber.calls.withLock { $0.first })
        #expect(call.0.lastPathComponent == JobArtifact.vocals)
        #expect(call.1 == .fast)
    }

    @Test("Piste vocale absente")
    func missingAudio() async {
        await #expect(throws: TranscriptionError.audioMissing("/nope/vocals.wav")) {
            try await WhisperKitTranscriber().transcribe(audio: URL(filePath: "/nope/vocals.wav"), quality: .fast) { _ in }
        }
    }
}

/// Vraie transcription WhisperKit d'une voix de synthèse (`say`). Télécharge le modèle au premier lancement.
/// `TEST_RUNNER_VOXLAB_INTEGRATION=1 xcodebuild test …`.
@Suite("Intégration WhisperKit", .enabled(if: ProcessInfo.processInfo.environment["VOXLAB_INTEGRATION"] == "1"))
struct WhisperKitIntegrationTests {
    @Test("Transcrit une phrase en français et détecte la langue", .timeLimit(.minutes(30)), arguments: [QualityMode.fast, .max])
    func transcribesFrench(quality: QualityMode) async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "voxlab-whisper-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let speech = dir.appending(path: "voix.aiff")
        _ = try await ProcessRunner().run(ProcessRequest(
            executable: URL(filePath: "/usr/bin/say"),
            arguments: ["-v", "Thomas", "-o", speech.path(percentEncoded: false),
                        "Il pleut sur la ville. Je marche sous la pluie et je pense à toi."]
        )).checked()

        let clock = ContinuousClock()
        let start = clock.now
        let progress = Mutex<[Double]>([])
        let transcription = try await WhisperKitTranscriber().transcribe(audio: speech, quality: quality) { value in
            progress.withLock { $0.append(value) }
        }
        print("[\(quality)] \(clock.now - start) : \(transcription.text)")

        #expect(transcription.language == "fr")
        let normalized = transcription.text.lowercased()
        #expect(normalized.contains("pluie"))
        #expect(normalized.contains("ville"))
        #expect(progress.withLock { $0 }.last == 1)
    }
}
