import Foundation

enum SearchState: Equatable {
    case idle
    case loading(SearchProgress)
    case error(String)
    case noResults
}

@MainActor
final class SearchCoordinator: ObservableObject {
    @Published var query = ""
    @Published var rankedResults: [RankedResult] = []
    @Published var state: SearchState = .idle
    @Published var selectedIndex = 0
    @Published var ollamaHealth = OllamaHealthStatus(
        isRunning: false,
        availableModels: [],
        selectedModelAvailable: false,
        message: nil
    )
    @Published var isUsingFallbackRanking = false
    @Published var statusMessage: String?

    private let settings: UserSettings
    private let spotlightSearch = SpotlightSearch()
    private let metadataEnricher = MetadataEnricher()
    private var searchTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    private let llmInputCap = 30

    init(settings: UserSettings) {
        self.settings = settings
    }

    func refreshOllamaHealth() async {
        let client = makeOllamaClient()
        ollamaHealth = await client.checkHealth()
    }

    func onQueryChanged(_ newValue: String) {
        query = newValue
        debounceTask?.cancel()

        let trimmed = newValue.trimmed
        guard !trimmed.isEmpty else {
            searchTask?.cancel()
            rankedResults = []
            state = .idle
            selectedIndex = 0
            isUsingFallbackRanking = false
            statusMessage = nil
            return
        }

        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(query: trimmed)
        }
    }

    func performSearchImmediately() {
        let trimmed = query.trimmed
        guard !trimmed.isEmpty else { return }
        debounceTask?.cancel()
        Task { await performSearch(query: trimmed) }
    }

    func moveSelection(delta: Int) {
        guard !rankedResults.isEmpty else { return }
        selectedIndex = max(0, min(rankedResults.count - 1, selectedIndex + delta))
    }

    func openSelected(revealInFinder: Bool) {
        guard rankedResults.indices.contains(selectedIndex) else { return }
        let path = rankedResults[selectedIndex].path
        if revealInFinder {
            FileOpener.revealInFinder(path: path)
        } else {
            FileOpener.open(path: path)
        }
    }

    private func performSearch(query: String) async {
        searchTask?.cancel()
        searchTask = Task {
            isUsingFallbackRanking = false
            statusMessage = nil
            rankedResults = []
            selectedIndex = 0

            var progress = SearchProgress.initial
            progress.activate(.spotlight, detail: "Searching…")
            state = .loading(progress)

            do {
                let rawResults = try await spotlightSearch.search(query: query)
                guard !Task.isCancelled else { return }

                progress.complete(.spotlight, detail: Self.fileCountDetail(rawResults.count))
                progress.activate(.filtering, detail: "\(rawResults.count) matches")
                state = .loading(progress)

                let filterSettings = PathFilterSettings(
                    searchScope: settings.searchScope,
                    excludedDirectories: settings.excludedDirectories
                )
                let filteredPaths = PathFilter.filter(rawResults.map(\.path), settings: filterSettings, limit: 100)
                guard !Task.isCancelled else { return }

                if filteredPaths.isEmpty {
                    state = .noResults
                    return
                }

                progress.complete(.filtering, detail: "\(filteredPaths.count) kept")
                let enrichCount = min(filteredPaths.count, llmInputCap)
                progress.activate(.enriching, detail: "0/\(enrichCount)")
                state = .loading(progress)

                let filteredResults = filteredPaths.map { SearchResult(path: $0) }
                let enriched = await metadataEnricher.enrich(Array(filteredResults.prefix(llmInputCap))) { [weak self] current, total in
                    Task { @MainActor in
                        self?.updateEnrichingProgress(current: current, total: total)
                    }
                }
                guard !Task.isCancelled else { return }

                progress.complete(.enriching, detail: Self.fileCountDetail(enriched.count))
                progress.activate(.checkingOllama, detail: nil)
                state = .loading(progress)

                await refreshOllamaHealth()
                guard !Task.isCancelled else { return }

                if ollamaHealth.isRunning, ollamaHealth.selectedModelAvailable {
                    progress.complete(.checkingOllama, detail: "Ready")
                    progress.activate(.ranking, detail: settings.ollamaModel)
                    state = .loading(progress)

                    do {
                        let client = makeOllamaClient()
                        let ranks = try await client.rerank(query: query, items: enriched)
                        guard !Task.isCancelled else { return }
                        rankedResults = mergeRanked(enriched: enriched, ranks: ranks)
                            .prefix(settings.maxResults)
                            .map { $0 }
                        state = rankedResults.isEmpty ? .noResults : .idle
                    } catch {
                        guard !Task.isCancelled else { return }
                        progress.complete(.ranking, detail: "Failed — using fallback order")
                        state = .loading(progress)
                        applyFallbackResults(enriched: enriched, message: error.localizedDescription)
                    }
                } else {
                    let message = ollamaHealth.message ?? OllamaClientError.notRunning.errorDescription
                    progress.complete(.checkingOllama, detail: "Unavailable")
                    progress.complete(.ranking, detail: "Skipped — using fallback order")
                    state = .loading(progress)
                    applyFallbackResults(enriched: enriched, message: message)
                }
            } catch {
                guard !Task.isCancelled else { return }
                state = .error(error.localizedDescription)
            }
        }

        await searchTask?.value
    }

    private func updateEnrichingProgress(current: Int, total: Int) {
        guard case .loading(var progress) = state else { return }
        progress.updateActive(.enriching, detail: "\(current)/\(total)")
        state = .loading(progress)
    }

    private static func fileCountDetail(_ count: Int) -> String {
        count == 1 ? "1 file" : "\(count) files"
    }

    private func applyFallbackResults(enriched: [SearchResult], message: String?) {
        isUsingFallbackRanking = true
        statusMessage = message
        rankedResults = enriched
            .enumerated()
            .map { index, item in
                RankedResult(from: item, rank: index + 1)
            }
            .prefix(settings.maxResults)
            .map { $0 }
        state = rankedResults.isEmpty ? .noResults : .idle
    }

    private func mergeRanked(enriched: [SearchResult], ranks: [OllamaRankEntry]) -> [RankedResult] {
        let lookup = Dictionary(uniqueKeysWithValues: enriched.map { ($0.path, $0) })
        var merged: [RankedResult] = []

        for entry in ranks.sorted(by: { $0.rank < $1.rank }) {
            guard let item = lookup[entry.path] else { continue }
            merged.append(RankedResult(from: item, rank: entry.rank, reason: entry.reason))
        }

        let rankedPaths = Set(merged.map(\.path))
        var nextRank = (merged.map(\.rank).max() ?? 0) + 1
        for item in enriched where !rankedPaths.contains(item.path) {
            merged.append(RankedResult(from: item, rank: nextRank))
            nextRank += 1
        }

        return merged.sorted { $0.rank < $1.rank }
    }

    private func makeOllamaClient() -> OllamaClient {
        OllamaClient(endpoint: settings.ollamaEndpoint, model: settings.ollamaModel)
    }
}
