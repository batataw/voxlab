import SwiftUI

/// Couleurs et mesures communes à toutes les pages.
enum Theme {
    static let cardRadius: CGFloat = 14
    static let tileRadius: CGFloat = 7
    static let pagePadding: CGFloat = 24
    static let cardSpacing: CGFloat = 12

    /// Fond de page : gris clair légèrement dégradé, pour faire ressortir les cartes.
    static var pageBackground: some View {
        Color(nsColor: .windowBackgroundColor)
            .overlay(
                LinearGradient(colors: [.clear, Color.primary.opacity(0.04)], startPoint: .top, endPoint: .bottom)
            )
            .ignoresSafeArea()
    }

    static let cardBackground = Color(nsColor: .controlBackgroundColor).opacity(0.85)
    static let cardFooterBackground = Color.primary.opacity(0.05)
    static let cardBorder = Color.primary.opacity(0.08)
    static let chipBackground = Color(nsColor: .controlBackgroundColor)
}

extension Step {
    /// Couleur de pastille de l'étape, la même partout dans l'app.
    var tint: Color {
        switch self {
        case .import: .blue
        case .separate: .purple
        case .transcribe: .pink
        case .correct: .teal
        case .translate: .indigo
        }
    }
}

extension StepStatus {
    var tint: Color {
        switch self {
        case .pending, .cancelled: .secondary
        case .running: .blue
        case .done: .green
        case .failed: .red
        }
    }

    var systemImage: String {
        switch self {
        case .pending: "circle.dashed"
        case .running: "arrow.trianglehead.2.clockwise"
        case .done: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .cancelled: "stop.circle"
        }
    }
}
