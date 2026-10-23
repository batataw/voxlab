import Foundation

/// Source audio d'un job, telle que fournie par l'utilisateur.
nonisolated enum JobSource: Sendable, Equatable {
    case file(URL)
    case youtube(URL)
}

extension Job {
    var source: JobSource {
        switch sourceKind {
        case .file: .file(URL(filePath: sourceReference))
        case .youtube: .youtube(URL(string: sourceReference) ?? URL(filePath: "/"))
        }
    }
}
