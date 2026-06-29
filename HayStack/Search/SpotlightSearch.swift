import Foundation

enum SpotlightSearchError: LocalizedError {
    case launchFailed
    case nonZeroExit(Int32)

    var errorDescription: String? {
        switch self {
        case .launchFailed:
            return "Failed to launch mdfind."
        case .nonZeroExit(let code):
            return "mdfind exited with code \(code)."
        }
    }
}

struct SpotlightSearch: Sendable {
    func search(query: String) async throws -> [SearchResult] {
        let trimmed = query.trimmed
        guard !trimmed.isEmpty else { return [] }

        return try await Task.detached(priority: .userInitiated) {
            try Self.runMdfind(query: trimmed)
        }.value
    }

    private static func runMdfind(query: String) throws -> [SearchResult] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [query]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            throw SpotlightSearchError.launchFailed
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SpotlightSearchError.nonZeroExit(process.terminationStatus)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { SearchResult(path: String($0)) }
    }
}
