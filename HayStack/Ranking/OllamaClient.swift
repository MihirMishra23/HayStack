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
            "format": "json",
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

        print("[HayStack] Raw Ollama response:\n\(accumulated)")
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

        // Format 1: bare array [{"rank":1,"path":"...","reason":"..."}]
        if let array = try? decoder.decode([FlexibleRankEntry].self, from: data) {
            let entries = array.enumerated().compactMap { index, e -> OllamaRankEntry? in
                guard let path = e.path else { return nil }
                return OllamaRankEntry(rank: e.rank ?? (index + 1), path: path, reason: e.reason ?? "")
            }
            if !entries.isEmpty { return entries }
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OllamaClientError.parseError
        }

        // Format 2: object wrapping an array {"results":[...]} or {"rankings":[...]}
        for value in obj.values {
            if let arr = value as? [[String: Any]],
               let arrData = try? JSONSerialization.data(withJSONObject: arr),
               let flexEntries = try? decoder.decode([FlexibleRankEntry].self, from: arrData) {
                let entries = flexEntries.enumerated().compactMap { index, e -> OllamaRankEntry? in
                    guard let path = e.path else { return nil }
                    return OllamaRankEntry(rank: e.rank ?? (index + 1), path: path, reason: e.reason ?? "")
                }
                if !entries.isEmpty { return entries }
            }
        }

        // Format 3: numbered keys {"0":{"path":"...","reason":"..."}, "1":{...}, ...}
        // or single object {"path":"...","reason":"..."}
        var entries: [OllamaRankEntry] = []
        for (key, value) in obj {
            if let dict = value as? [String: Any], let path = dict["path"] as? String {
                let reason = dict["reason"] as? String ?? ""
                let rank = Int(key) ?? (dict["rank"] as? Int) ?? entries.count
                entries.append(OllamaRankEntry(rank: rank + 1, path: path, reason: reason))
            }
        }
        if !entries.isEmpty {
            return entries.sorted { $0.rank < $1.rank }
        }

        // Format 4: single flat object {"path":"...","reason":"..."}
        if let path = obj["path"] as? String {
            let reason = obj["reason"] as? String ?? ""
            let rank = obj["rank"] as? Int ?? 1
            return [OllamaRankEntry(rank: rank, path: path, reason: reason)]
        }

        throw OllamaClientError.parseError
    }
}
