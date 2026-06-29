import SwiftUI

struct SearchProgressView: View {
    let progress: SearchProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SearchPipelineStep.allCases) { step in
                SearchStepRow(
                    title: step.title,
                    status: progress.status(for: step)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct SearchStepRow: View {
    let title: String
    let status: SearchStepStatus

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            stepIcon
                .frame(width: 14, height: 14)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(labelColor)

                if let detail = detailText {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var stepIcon: some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .font(.caption2)
                .foregroundStyle(.tertiary)

        case .active:
            ProgressView()
                .controlSize(.mini)

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    private var labelColor: some ShapeStyle {
        switch status {
        case .pending:
            return .tertiary
        case .active, .completed:
            return .primary
        }
    }

    private var detailText: String? {
        switch status {
        case .pending:
            return nil
        case .active(let detail), .completed(let detail):
            return detail
        }
    }
}
