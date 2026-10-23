import SwiftData
import SwiftUI

/// Historique des jobs en cartes ; une carte ouvre le détail du job.
struct HistoryPage: View {
    @Bindable var navigation: AppNavigation

    var body: some View {
        NavigationStack(path: $navigation.historyPath) {
            HistoryList(navigation: navigation)
                .navigationDestination(for: UUID.self) { id in
                    JobDetailLoader(jobID: id, navigation: navigation)
                }
        }
    }
}

private struct HistoryList: View {
    let navigation: AppNavigation

    @Query(sort: \Job.createdAt, order: .reverse) private var jobs: [Job]
    @Environment(JobController.self) private var controller
    @State private var query = ""

    private var filteredJobs: [Job] { jobs.filter { $0.matches(query) } }

    var body: some View {
        Page {
            PageHeader(title: "Historique", subtitle: subtitle) {
                RoundIconButton(title: "Nouveau job (⌘N)", systemImage: "plus") { navigation.show(.newJob) }
                RoundIconButton(title: "Réglages", systemImage: "gearshape.fill") { navigation.show(.settings) }
            }

            if !jobs.isEmpty {
                SearchField(text: $query)
            }

            if jobs.isEmpty {
                Card {
                    VStack(spacing: 10) {
                        RoundIcon(systemImage: "waveform", tint: .orange, size: 48)
                        Text("Aucun job pour l'instant").font(.headline)
                        Text("Déposez une chanson ou collez un lien YouTube pour lancer le premier traitement.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Nouveau job") { navigation.show(.newJob) }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            } else if filteredJobs.isEmpty {
                Text("Aucun job ne correspond à « \(query) ».")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }

            ForEach(filteredJobs) { job in
                NavigationLink(value: job.id) {
                    JobCard(job: job)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Afficher dans le Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([controller.directory(of: job)])
                    }
                    Divider()
                    Button("Supprimer le job et ses fichiers", systemImage: "trash", role: .destructive) {
                        controller.delete(job)
                    }
                }
            }
        }
    }

    private var subtitle: String {
        switch jobs.count {
        case 0: "Les traitements lancés apparaîtront ici."
        case 1: "1 job"
        default: "\(jobs.count) jobs"
        }
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Rechercher dans les titres et les paroles", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button("Effacer", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.cardBackground, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cardBorder))
    }
}

/// Résout l'identifiant d'un job ; affiche un état vide s'il a été supprimé.
private struct JobDetailLoader: View {
    let jobID: UUID
    let navigation: AppNavigation
    @Query private var jobs: [Job]

    init(jobID: UUID, navigation: AppNavigation) {
        self.jobID = jobID
        self.navigation = navigation
        _jobs = Query(filter: #Predicate<Job> { $0.id == jobID })
    }

    var body: some View {
        if let job = jobs.first {
            JobDetailPage(job: job, navigation: navigation)
        } else {
            ContentUnavailableView("Job introuvable", systemImage: "questionmark.folder")
        }
    }
}
