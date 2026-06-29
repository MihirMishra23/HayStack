import Foundation

enum RankingPrompt {
    static func build(query: String, items: [SearchResult]) -> String {
        let payload = items.map { item -> [String: Any] in
            var dict: [String: Any] = [
                "path": item.path,
                "filename": item.filename,
                "suffix": (item.path as NSString).pathExtension.lowercased(),
            ]
            if let sizeBytes = item.sizeBytes {
                dict["size_bytes"] = sizeBytes
            }
            if let modifiedDate = item.modifiedDate {
                dict["modified_unix"] = Int(modifiedDate.timeIntervalSince1970)
            }
            if let contentType = item.contentType {
                dict["content_type"] = contentType
            }
            return dict
        }

        let jsonData = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"

        return """
        You are ranking macOS Spotlight search results for a file search app.

        The user searched for: \(query)

        Rank the files from most relevant to least relevant for this search query.

        Strong positive signals:
        - filename or path closely matches the query intent
        - relevant document types (PDF, DOCX, images, code, etc.) for the query
        - files in user folders like Documents, Desktop, Downloads, iCloud Drive, Dropbox, Google Drive
        - recently modified files when recency seems relevant

        Strong negative signals:
        - system, cache, application support, node_modules, virtualenv, git internals
        - templates, logs, binaries, databases, or unrelated files
        - paths that look like dependencies or build artifacts

        Return only valid JSON matching this schema. Do not include markdown fences or commentary.

        JSON format:
        \(RankingResponseSchema.promptExample)

        Include every input path exactly once in results. Use ranks starting at 1.

        Search results:
        \(jsonString)
        """
    }
}
