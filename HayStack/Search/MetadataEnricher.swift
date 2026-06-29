import CoreServices
import Foundation

struct MetadataEnricher: Sendable {
    private let maxConcurrency = 10

    func enrich(
        _ results: [SearchResult],
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> [SearchResult] {
        guard !results.isEmpty else { return [] }

        let total = results.count
        let progress = onProgress

        return await withTaskGroup(of: (Int, SearchResult).self, returning: [SearchResult].self) { group in
            var iterator = results.enumerated().makeIterator()
            var inFlight = 0
            var collected: [(Int, SearchResult)] = []
            collected.reserveCapacity(results.count)

            func addNext() {
                guard inFlight < maxConcurrency, let next = iterator.next() else { return }
                inFlight += 1
                let index = next.offset
                let result = next.element
                group.addTask {
                    (index, Self.enrichSingle(result))
                }
            }

            for _ in 0..<min(maxConcurrency, results.count) {
                addNext()
            }

            var completed = 0
            for await item in group {
                collected.append(item)
                inFlight -= 1
                completed += 1
                progress?(completed, total)
                addNext()
            }

            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static func enrichSingle(_ result: SearchResult) -> SearchResult {
        var enriched = result
        let url = URL(fileURLWithPath: result.path)

        if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) {
            enriched.sizeBytes = values.fileSize
            enriched.modifiedDate = values.contentModificationDate
        }

        if let item = MDItemCreateWithURL(nil, url as CFURL) {
            if let contentType = MDItemCopyAttribute(item, kMDItemContentType) as? String {
                enriched.contentType = contentType
            }
        }

        return enriched
    }
}
