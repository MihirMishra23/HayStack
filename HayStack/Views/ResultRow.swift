import AppKit
import SwiftUI

struct ResultRow: View {
    let result: RankedResult
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: result.path))
                .resizable()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.filename)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(result.parentPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !result.reason.isEmpty {
                    Text(result.reason)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if let contentType = result.contentType {
                        Text(contentType)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let modifiedDate = result.modifiedDate {
                        Text(modifiedDate.shortDisplay)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let sizeBytes = result.sizeBytes {
                        Text(sizeBytes.formattedFileSize)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
