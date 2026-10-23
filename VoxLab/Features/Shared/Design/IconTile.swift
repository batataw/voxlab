import SwiftUI

/// Symbole blanc sur pastille colorée arrondie (barre latérale, en-têtes de carte).
struct IconTile: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom),
                in: .rect(cornerRadius: size * 0.3)
            )
    }
}

/// Pastille ronde neutre, comme l'icône d'une carte de mode.
struct RoundIcon: View {
    let systemImage: String
    var tint: Color = .primary
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Color.primary.opacity(0.06), in: .circle)
    }
}

#Preview {
    HStack {
        IconTile(systemImage: "plus", color: .orange)
        IconTile(systemImage: "list.bullet", color: .red)
        RoundIcon(systemImage: "music.note")
    }
    .padding()
}
