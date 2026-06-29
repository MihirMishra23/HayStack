import Foundation

enum OllamaClientError: LocalizedError {
    case notRunning
    case modelNotFound(String)
    case timeout
    case parseError
    case requestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return "Ollama is not running. Start it with: ollama serve"
        case .modelNotFound(let model):
            return "Model \"\(model)\" not found. Run: ollama pull \(model)"
        case .timeout:
            return "Ollama ranking timed out."
        case .parseError:
            return "Failed to parse Ollama ranking response."
        case .requestFailed(let message):
            return message
        case .invalidResponse:
            return "Received an invalid response from Ollama."
        }
    }
}

struct OllamaHealthStatus: Equatable, Sendable {
    let isRunning: Bool
    let availableModels: [String]
    let selectedModelAvailable: Bool
    let message: String?
}

struct OllamaRankEntry: Sendable {
    let rank: Int
    let path: String
    let reason: String
}

private struct FlexibleRankEntry: Decodable {
    let rank: Int?
    let path: String?
    let reason: String?
}

private struct StructuredRankingResponse: Decodable {
    let results: [FlexibleRankEntry]
}

struct OllamaClient: Sendable {
    let endpoint: String
    let model: String
    let timeout: TimeInterval

    init(endpoint: String, model: String, timeout: TimeInterval = 15) {
        var e = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if e.hasSuffix("/") { e = String(e.dropLast()) }
        self.endpoint = e
        self.model = model
        self.timeout = timeout
    }

    func checkHealth() async -> OllamaHealthStatus {
        guard let url = URL(string: "\(endpoint)/api/tags") else {
            return OllamaHealthStatus(
                isRunning: false,
                availableModels: [],
                selectedModelAvailable: false,
                message: "Invalid Ollama endpoint."
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return OllamaHealthStatus(
                    isRunning: false,
                    availableModels: [],
                    selectedModelAvailable: false,
                    message: OllamaClientError.notRunning.errorDescription
                )
            }

            let models = parseModels(from: data)
            let modelAvailable = models.contains { $0 == model || $0.hasPrefix("\(model):") || model.hasPrefix("\($0):") }

            var message: String?
            if !modelAvailable {
                message = OllamaClientError.modelNotFound(model).errorDescription
            }

            return OllamaHealthStatus(
                isRunning: true,
                availableModels: models,
                selectedModelAvailable: modelAvailable,
                message: message
            )
        } catch {
            return OllamaHealthStatus(
                isRunning: false,
                availableModels: [],
                selectedModelAvailable: false,
                message: OllamaClientError.notRunning.errorDescription
            )
        }
    }

    func rerank(query: String, items: [SearchResult]) async throws -> [OllamaRankEntry] {
        guard !items.isEmpty else { return [] }
        guard let url = URL(string: "\(endpoint)/api/generate") else {
            throw OllamaClientError.invalidResponse
        }

        let prompt = RankingPrompt.build(query: query, items: items)
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": true,
            "format": RankingResponseSchema.ollamaFormat,
            "options": [
                "temperature": 0,
            ],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = timeout

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OllamaClientError.invalidResponse
        }

        if http.statusCode == 404 {
            throw OllamaClientError.modelNotFound(model)
        }

        guard http.statusCode == 200 else {
            throw OllamaClientError.requestFailed("Ollama returned status \(http.statusCode).")
        }

        var accumulated = ""
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let chunk = json["response"] as? String {
                accumulated += chunk
            }

            if json["done"] as? Bool == true {
                break
            }
        }

        return try parseRankEntries(from: accumulated)
    }

    private func parseModels(from data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return []
        }

        return models.compactMap { $0["name"] as? String }
    }

    private func parseRankEntries(from text: String) throws -> [OllamaRankEntry] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw OllamaClientError.parseError
        }

        let decoder = JSONDecoder()

        if let response = try? decoder.decode(StructuredRankingResponse.self, from: data) {
            let entries = response.results.enumerated().compactMap { index, entry -> OllamaRankEntry? in
                guard let path = entry.path else { return nil }
                return OllamaRankEntry(
                    rank: entry.rank ?? (index + 1),
                    path: path,
                    reason: entry.reason ?? ""
                )
            }
            if !entries.isEmpty { return entries }
        }

        // Fallback for bare array responses from older Ollama versions.
        if let array = try? decoder.decode([FlexibleRankEntry].self, from: data) {
            let entries = array.enumerated().compactMap { index, entry -> OllamaRankEntry? in
                guard let path = entry.path else { return nil }
                return OllamaRankEntry(
                    rank: entry.rank ?? (index + 1),
                    path: path,
                    reason: entry.reason ?? ""
                )
            }
            if !entries.isEmpty { return entries }
        }

        throw OllamaClientError.parseError
    }
}
