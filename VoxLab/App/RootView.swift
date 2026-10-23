import SwiftData
import SwiftUI

struct RootView: View {
    let diagnostics: DiagnosticsViewModel
    @Bindable var navigation: AppNavigation

    var body: some View {
        NavigationSplitView {
            Sidebar(navigation: navigation, diagnostics: diagnostics)
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            // L'identité par section force la reconstruction de la colonne : sans elle, SwiftUI
            // peut garder affichée la NavigationStack de l'Historique quand on change de section.
            Group {
                switch navigation.section {
                case .newJob:
                    NewJobPage(navigation: navigation)
                case .history:
                    HistoryPage(navigation: navigation)
                case .diagnostics:
                    DiagnosticsPage(viewModel: diagnostics)
                case .settings:
                    SettingsPage()
                }
            }
            .id(navigation.section)
        }
        .task {
            await diagnostics.refresh()
            if !diagnostics.missingRequired.isEmpty {
                navigation.show(.diagnostics)
            }
        }
    }
}

private struct Sidebar: View {
    @Bindable var navigation: AppNavigation
    let diagnostics: DiagnosticsViewModel

    var body: some View {
        VStack(spacing: 2) {
            ForEach(AppSection.main) { section in
                SidebarRow(section: section, navigation: navigation, badge: badge(for: section))
            }
            Spacer()
            SidebarRow(section: .settings, navigation: navigation, badge: nil)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
    }

    private func badge(for section: AppSection) -> Color? {
        guard section == .diagnostics, diagnostics.hasCheckedOnce, !diagnostics.missingRequired.isEmpty else { return nil }
        return .orange
    }
}

private struct SidebarRow: View {
    let section: AppSection
    @Bindable var navigation: AppNavigation
    let badge: Color?

    private var isSelected: Bool { navigation.section == section }

    var body: some View {
        Button {
            navigation.show(section)
        } label: {
            HStack(spacing: 10) {
                IconTile(systemImage: section.systemImage, color: badge ?? section.color)
                Text(section.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                Spacer()
                if badge != nil {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(isSelected ? .white : .orange)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8).fill(Color.accentColor)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
