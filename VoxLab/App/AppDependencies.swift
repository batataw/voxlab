import Foundation
import SwiftData

/// Seul endroit où les implémentations concrètes des services sont choisies.
struct AppDependencies {
    let processRunner: any ProcessRunning
    let dependencyChecker: any DependencyChecking
    let jobStorage: JobStorage
    let jobController: JobController

    static func live(modelContext: ModelContext) -> AppDependencies {
        let runner = ProcessRunner()
        let storage = JobStorage()
        let toolPaths: @Sendable () -> ToolPaths = { ToolPaths.load() }
        let llmProvider: @Sendable (QualityMode) -> any LLMProvider = { quality in
            switch LLMProviderChoice.load().resolved(for: quality) {
            case .localServer: OpenAICompatibleProvider(settings: { LLMServerSettings.load() })
            case .foundationModels, .automatic: FoundationModelsProvider()
            }
        }

        let store = SwiftDataJobStore(context: modelContext)
        store.recoverInterruptedRuns()

        let pipeline = PipelineRunner(
            steps: [
                ImportStep(fileImporter: FileImporter(runner: runner, toolPaths: toolPaths), urlImporter: nil),
                SeparateStep(separator: DemucsSeparator(runner: runner, toolPaths: toolPaths)),
                TranscribeStep(transcriber: WhisperKitTranscriber()),
                CorrectStep(corrector: LLMCorrector(provider: llmProvider)),
                TranslateStep(translator: RoutingTranslator(
                    apple: AppleTranslator(),
                    llm: LLMTranslator(provider: llmProvider),
                    useLLM: { UserDefaults.standard.bool(forKey: SettingsKey.translateViaLLM) }
                )),
            ],
            store: store,
            storage: storage
        )
        return AppDependencies(
            processRunner: runner,
            dependencyChecker: DependencyChecker(runner: runner),
            jobStorage: storage,
            jobController: JobController(runner: pipeline, storage: storage, context: modelContext)
        )
    }
}
