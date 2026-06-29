import SwiftUI

struct ResultsList: View {
    let results: [RankedResult]
    @Binding var selectedIndex: Int
    let state: SearchState
    let statusMessage: String?
    let isUsingFallbackRanking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let statusMessage, isUsingFallbackRanking {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }

            switch state {
            case .loading(let progress):
                SearchProgressView(progress: progress)

            case .error(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

            case .noResults:
                Text("No results found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

            case .idle:
                EmptyView()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                            ResultRow(result: result, isSelected: index == selectedIndex)
                                .id(result.id)
                                .onTapGesture {
                                    selectedIndex = index
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .onChange(of: selectedIndex) { _, newValue in
                    guard results.indices.contains(newValue) else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(results[newValue].id, anchor: .center)
                    }
                }
            }
        }
    }
}
