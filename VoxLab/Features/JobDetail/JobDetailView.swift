import SwiftUI

struct JobDetailView: View {
    let job: Job

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title)
                        .font(.title2.bold())
                    Text(job.sourceReference)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(job.orderedStepRuns) { run in
                        StepTimelineRow(run: run)
                        if run.step != Step.allCases.last {
                            Divider()
                        }
                    }
                }
                .padding(12)
                .background(.background.secondary, in: .rect(cornerRadius: 10))
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(job.title)
    }
}

private struct StepTimelineRow: View {
    let run: StepRun

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: run.step.systemImage)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(run.step.displayName).bold()
                    Spacer()
                    if let duration = run.duration {
                        Text(Duration.seconds(duration), format: .units(allowed: [.hours, .minutes, .seconds], width: .narrow))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    StepStatusBadge(status: run.status)
                }
                if run.status == .running {
                    ProgressView(value: run.progress)
                }
                if let message = run.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
