import SwiftUI

/// Conteneur arrondi des pages, avec une bande inférieure optionnelle pour les étiquettes.
struct Card<Content: View, Footer: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            if Footer.self != EmptyView.self {
                Divider().opacity(0.5)
                footer
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardFooterBackground)
            }
        }
        .background(Theme.cardBackground)
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.cardBorder)
        }
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}

extension Card where Footer == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
        self.footer = EmptyView()
    }
}

/// Carte avec un titre de section (« Pipeline », « Audio »…) et des accessoires à droite.
struct SectionCard<Accessory: View, Content: View>: View {
    let title: String
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    accessory
                }
                content
            }
        }
    }
}

extension SectionCard where Accessory == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = EmptyView()
        self.content = content()
    }
}

#Preview {
    VStack {
        Card {
            Text("Contenu")
        } footer: {
            HStack { Chip(text: "Auto", systemImage: "globe"); Chip(text: "Max", systemImage: "bolt") }
        }
        SectionCard(title: "Pipeline") { Text("Étapes") }
    }
    .padding()
    .frame(width: 480)
}
