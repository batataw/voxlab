import SwiftUI

/// Étiquette en pilule : icône et court texte.
struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(tint == .secondary ? Color.primary.opacity(0.75) : tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.chipBackground, in: .capsule)
        .overlay(Capsule().strokeBorder(Theme.cardBorder))
    }
}

/// Statut coloré d'un job ou d'une étape.
struct StatusPill: View {
    let status: StepStatus
    /// Remplace le libellé du statut (par ex. « Transcription 42 % »).
    var label: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(label ?? status.displayName)
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
        .foregroundStyle(status.tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(status.tint.opacity(0.12), in: .capsule)
    }
}

#Preview {
    VStack(alignment: .leading) {
        HStack { Chip(text: "en → fr", systemImage: "globe"); Chip(text: "Obsolète", systemImage: "exclamationmark.triangle", tint: .orange) }
        HStack { ForEach(StepStatus.allCases, id: \.self) { StatusPill(status: $0) } }
    }
    .padding()
}
