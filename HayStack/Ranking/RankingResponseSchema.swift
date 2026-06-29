import Foundation

enum RankingResponseSchema {
    /// JSON schema passed to Ollama's `format` parameter for constrained ranking output.
    static let ollamaFormat: [String: Any] = [
        "type": "object",
        "properties": [
            "results": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "rank": ["type": "integer"],
                        "path": ["type": "string"],
                        "reason": ["type": "string"],
                    ],
                    "required": ["rank", "path", "reason"],
                ],
            ],
        ],
        "required": ["results"],
    ]

    static let promptExample = """
    {
      "results": [
        {
          "rank": 1,
          "path": "/full/path",
          "reason": "brief reason"
        }
      ]
    }
    """
}
