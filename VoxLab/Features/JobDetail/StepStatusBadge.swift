import SwiftUI

struct StepStatusBadge: View {
    let status: StepStatus

    var body: some View {
        Label(status.displayName, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption)
            .foregroundStyle(color)
    }

    private var symbol: String {
        switch status {
        case .pending: "circle.dashed"
        case .running: "arrow.trianglehead.2.clockwise"
        case .done: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .cancelled: "stop.circle"
        }
    }

    private var color: Color {
        switch status {
        case .pending, .cancelled: .secondary
        case .running: .blue
        case .done: .green
        case .failed: .red
        }
    }
}
