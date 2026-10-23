import SwiftData
import SwiftUI

struct HistoryView: View {
    @Binding var selection: PersistentIdentifier?
    @Query(sort: \Job.createdAt, order: .reverse) private var jobs: [Job]

    var body: some View {
        List(selection: $selection) {
            ForEach(jobs) { job in
                HistoryRow(job: job)
                    .tag(job.persistentModelID)
            }
        }
        .overlay {
            if jobs.isEmpty {
                ContentUnavailableView(
                    "Aucun job",
                    systemImage: "tray",
                    description: Text("Les traitements lancés apparaîtront ici.")
                )
            }
        }
        .navigationTitle("Historique")
    }
}

private struct HistoryRow: View {
    let job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(job.title)
                .lineLimit(1)
            HStack(spacing: 6) {
                StepStatusBadge(status: job.overallStatus)
                Text(job.createdAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
