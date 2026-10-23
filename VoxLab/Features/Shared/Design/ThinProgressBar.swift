import SwiftUI

/// Barre de progression fine et arrondie, aux couleurs de l'étape en cours.
struct ThinProgressBar: View {
    let value: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
                    .animation(.easeOut(duration: 0.3), value: value)
            }
        }
        .frame(height: 5)
        .accessibilityElement()
        .accessibilityValue("\(Int((value * 100).rounded())) %")
    }
}

#Preview {
    ThinProgressBar(value: 0.42, tint: .pink).padding().frame(width: 300)
}
