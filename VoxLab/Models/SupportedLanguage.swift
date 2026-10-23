import Foundation

/// Langues européennes proposées en cible de traduction.
nonisolated enum SupportedLanguage: String, CaseIterable, Sendable, Identifiable {
    case fr, en, es, it, de, pt, nl

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fr: "Français"
        case .en: "Anglais"
        case .es: "Espagnol"
        case .it: "Italien"
        case .de: "Allemand"
        case .pt: "Portugais"
        case .nl: "Néerlandais"
        }
    }
}
