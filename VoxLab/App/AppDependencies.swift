import Foundation

/// Seul endroit où les implémentations concrètes des services sont choisies.
struct AppDependencies {
    let processRunner: any ProcessRunning
    let dependencyChecker: any DependencyChecking
    let jobStorage: JobStorage

    static func live() -> AppDependencies {
        let runner = ProcessRunner()
        return AppDependencies(
            processRunner: runner,
            dependencyChecker: DependencyChecker(runner: runner),
            jobStorage: JobStorage()
        )
    }
}
