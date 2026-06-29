# HayStack — Smart macOS File Search

**Build from source** — clone this repo and run in Xcode. There is no pre-built download.

## What This Is

A macOS menu bar app that replaces Finder search with AI-reranked results. The user presses a global hotkey, a floating search panel appears, they type a natural language query, and results appear ranked by actual relevance using a local LLM via Ollama.

## Core User Flow

1. User presses global hotkey (default: `⌥ Space`)
2. A floating search panel appears centered on screen (similar to Spotlight/Raycast)
3. User types a query like "my resume" or "that lease PDF from March"
4. App queries macOS Spotlight index via `mdfind`
5. Results are pre-filtered to remove junk (caches, node_modules, Library internals, etc.)
6. Remaining results are enriched with metadata via `mdls`
7. Results are sent to Ollama's local REST API for reranking
8. Ranked results stream into the UI as they're ready
9. User navigates with arrow keys, hits Enter to open the file in its default app, or `⌘ Enter` to reveal in Finder

The menu bar icon provides access to settings: hotkey customization, excluded directories, Ollama model selection, and max results count.

---

## Build from Source

### Prerequisites

- macOS 14+
- Xcode 15+
- [Ollama](https://ollama.com) installed and running
- At least one model pulled (default: `llama3.2:1b`)

### Steps

1. Clone the repo:

```bash
git clone https://github.com/YOUR_USERNAME/HayStack.git
cd HayStack
```

2. Install and start Ollama:

```bash
brew install ollama
ollama serve          # keep running in a terminal
ollama pull llama3.2:1b
```

3. Open `HayStack.xcodeproj` in Xcode and press `⌘R` to build and run.

4. If the global hotkey (`⌥ Space` by default) does not work, grant **Accessibility** permission:
   **System Settings → Privacy & Security → Accessibility** → add Xcode (while developing) or HayStack (if running a built `.app`).

### Unsigned app note

HayStack is distributed as source only. If you build a standalone `.app` (see [Build & Distribution](#build--distribution) below), macOS may block it on first launch because it is not signed or notarized. Right-click the app and choose **Open**, or allow it under **System Settings → Privacy & Security**.

---

## Tech Stack

| Layer | Technology | Reason |
|-------|-----------|--------|
| Language | Swift | Native macOS access, small binary, easy notarization |
| UI Framework | SwiftUI | Modern, declarative, good for lightweight UI |
| Spotlight Access | `NSMetadataQuery` or shelling out to `mdfind` | Built-in macOS file indexing |
| Metadata Enrichment | `mdls` via Process or `MDItemCopyAttributes` | Get content type, authors, page count, text snippets |
| LLM Reranking | Ollama REST API (`http://localhost:11434/api/generate`) | Local, private, no API key needed |
| Distribution | Source-only (build in Xcode) | No paid Apple Developer account required |

---

## Project Structure

```
HayStack/
├── HayStack.xcodeproj
├── HayStack/
│   ├── HayStackApp.swift              # App entry point, menu bar setup
│   ├── AppDelegate.swift              # Menu bar icon, global hotkey registration
│   ├── Views/
│   │   ├── SearchPanel.swift          # The floating search window
│   │   ├── SearchField.swift          # Text input with live filtering
│   │   ├── ResultRow.swift            # Single result row (icon, name, path, rank reason)
│   │   ├── ResultsList.swift          # Scrollable ranked results
│   │   └── SettingsView.swift         # Preferences window
│   ├── Search/
│   │   ├── SpotlightSearch.swift      # Wraps mdfind
│   │   ├── MetadataEnricher.swift     # Pulls extended metadata per file
│   │   ├── PathFilter.swift           # Pre-filters junk paths before LLM
│   │   ├── SearchCoordinator.swift    # Search pipeline orchestration
│   │   └── SearchResult.swift         # Data model for a single result
│   ├── Ranking/
│   │   ├── OllamaClient.swift         # HTTP client for Ollama REST API
│   │   ├── RankingPrompt.swift        # Prompt construction for reranking
│   │   └── RankedResult.swift         # Result + rank + reason from LLM
│   ├── Settings/
│   │   ├── UserSettings.swift         # UserDefaults-backed preferences
│   │   └── HotkeyManager.swift        # Global keyboard shortcut registration
│   └── Utilities/
│       ├── FileOpener.swift           # NSWorkspace open / reveal in Finder
│       └── Extensions.swift           # Helpers
├── scripts/
│   └── release.sh                     # Archive, notarize, and package DMG
├── system_search.py                   # Python CLI prototype (reference)
└── README.md
```

---

## Component Details

### 1. Global Hotkey & Menu Bar (`AppDelegate.swift`)

- Register a global hotkey using `CGEvent.tapCreate` or the `HotKey` Swift package (https://github.com/soffes/HotKey)
- Menu bar uses `MenuBarExtra` (macOS 13+) or `NSStatusItem` for older support
- Menu items: "Search" (triggers panel), "Settings", "Quit"

### 2. Search Panel (`SearchPanel.swift`)

- A borderless, floating `NSPanel` (not a regular window)
- Appears centered on the active screen
- Dismisses on `Escape` or clicking outside
- No title bar, rounded corners, slight shadow — visually similar to Spotlight
- Width: ~680pt, max height: ~500pt
- SwiftUI content hosted inside via `NSHostingView`

### 3. Spotlight Search (`SpotlightSearch.swift`)

```swift
func search(query: String) async throws -> [SearchResult] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
    process.arguments = ["-name", query]  // filename search
    // For content search: process.arguments = [query]
    // For raw query: process.arguments = [rawMDQuery]

    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return output.split(separator: "\n").map { SearchResult(path: String($0)) }
}
```


### 4. Pre-Filtering (`PathFilter.swift`)

Filter results BEFORE sending to the LLM. This is critical for speed and quality.

```swift
struct PathFilter {
    static let blockedPrefixes: [String] = [
        "/Library/",
        "/System/",
        "/Applications/",
        "/usr/",
        "/private/",
        "/.Trash/",
        "/node_modules/",
        "/.git/",
        "/venv/",
        "/.venv/",
        "/env/",
        "/__pycache__/",
        "/.cache/",
        "/Cache/",
        "/Caches/",
        "/Application Support/",
        "/BrowserProfiles/",
        "/DerivedData/",
    ]

    static let blockedExtensions: Set<String> = [
        ".dylib", ".so", ".o", ".a",
        ".app", ".framework",
        ".log", ".pid", ".lock",
        ".DS_Store",
        ".plist",         // usually system config
        ".sqlite", ".db", // usually app databases
    ]

    // Only paths under home directory by default
    static let allowedRoots: [String] = [
        "~/Documents", "~/Desktop", "~/Downloads",
        "~/Library/Mobile Documents", // iCloud Drive
        "~/Dropbox", "~/Google Drive",
    ]

    static func shouldInclude(_ path: String) -> Bool {
        // Implement: check against blocked prefixes/extensions,
        // optionally restrict to allowed roots
    }
}
```

### 5. Metadata Enrichment (`MetadataEnricher.swift`)

After filtering, enrich each surviving result with useful metadata for the LLM:

```swift
struct EnrichedResult {
    let path: String
    let filename: String
    let suffix: String
    let sizeBytes: Int?
    let modifiedDate: Date?
    let contentType: String?       // from kMDItemContentType
    let numberOfPages: Int?        // from kMDItemNumberOfPages
    let authors: [String]?         // from kMDItemAuthors
    let textSnippet: String?       // first ~200 chars of kMDItemTextContent
}
```

Use `MDItemCreateWithURL` + `MDItemCopyAttribute` for direct API access, or shell out to `mdls -name kMDItemContentType -name kMDItemNumberOfPages ...` per file.

### 6. Ollama Client (`OllamaClient.swift`)

Communicate with Ollama's REST API. It runs at `http://localhost:11434`.

**Generate endpoint (for reranking):**
```
POST http://localhost:11434/api/generate
{
    "model": "llama3.2:1b",
    "prompt": "<ranking prompt with enriched results>",
    "stream": true,
    "format": "json"
}
```

- Use `stream: true` to show results as they arrive
- Parse the streamed JSON tokens incrementally
- Handle connection errors gracefully (Ollama not running → show a helpful message)
- Add a timeout (e.g., 15 seconds) so the UI never hangs

**Check Ollama is running:**
```
GET http://localhost:11434/api/tags
```
Returns available models. Use this at app launch to verify Ollama is available and the selected model is pulled.

### 7. Ranking Prompt (`RankingPrompt.swift`)

Build a prompt that tells the LLM to rank results as a JSON array. Key design choices:

- Include the user's original natural language query so the LLM understands intent
- Send enriched metadata (not just paths) so the LLM has real signal
- Ask for JSON output: `[{"rank": 1, "path": "...", "reason": "..."}]`
- Cap the number of results sent to the LLM at ~30 (after pre-filtering)
- Use `format: "json"` in the Ollama API call to enforce valid JSON output

### 8. Settings (`UserSettings.swift`)

Persist with `UserDefaults`:

```swift
struct UserSettings {
    var hotkey: String = "⌥Space"
    var ollamaModel: String = "llama3.2:1b"
    var ollamaEndpoint: String = "http://localhost:11434"
    var maxResults: Int = 25
    var excludedDirectories: [String] = []
    var searchScope: SearchScope = .homeDirectory  // or .allVolumes
}
```

---

## v1 Scope (Ship This)

Focus exclusively on these features for the first release:

- Menu bar icon + global hotkey to open search panel
- Text input that queries Spotlight via mdfind
- Pre-filtering of junk paths
- Basic metadata enrichment (filename, size, modified date, content type)
- Ollama reranking with streamed results
- Arrow key navigation + Enter to open + ⌘Enter to reveal in Finder
- Settings: hotkey, model name, excluded folders
- Graceful handling when Ollama is not running
- Build-from-source distribution via GitHub

### Explicitly NOT in v1

- Natural language → mdfind query translation (v2)
- File content previews / Quick Look integration (v2)
- Background file indexing or embedding cache (v2)
- Cloud LLM fallback (v2)
- Homebrew cask (v2)
- File watching / live index updates (v2)
- Multiple LLM provider support (v2)

---

## Build & Distribution

### Development

Open `HayStack.xcodeproj` in Xcode 15+, build and run (`⌘R`). See [Build from Source](#build-from-source) above for full setup.

HayStack uses the [HotKey](https://github.com/soffes/HotKey) Swift package for global shortcuts. App Sandbox is disabled so Spotlight, localhost Ollama, and file open/reveal work outside the App Store.

### Optional: local `.app` build

To produce a standalone `.app` and `.dmg` locally (unsigned):

```bash
SKIP_NOTARIZE=1 ./scripts/release.sh Debug
```

Output lands in `build/HayStack.dmg`. Expect macOS Gatekeeper warnings on first launch — right-click → **Open**.

### Optional: signed release (requires Apple Developer account)

If you have a Developer ID certificate, `scripts/release.sh` can archive, sign, notarize, and package a DMG:

```bash
export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="your-notary-profile"   # or APPLE_ID / APPLE_ID_PASSWORD / APPLE_TEAM_ID
./scripts/release.sh Release
```

### Prerequisites for Users

- macOS 14+
- Ollama installed and running (`brew install ollama && ollama serve`)
- At least one model pulled (app suggests `llama3.2:1b` on first launch if none found)

---

## Future Directions (v2+)

- **Natural language query translation**: User types "lease agreement from last month" → LLM generates the right mdfind query with date constraints
- **Embedding-based search**: Pre-compute embeddings for file metadata using a local model, do vector similarity at query time instead of LLM reranking (faster)
- **Quick Look preview**: Show file previews inline in the results panel
- **Frecency scoring**: Track which files the user actually opens and boost them in future rankings
- **Multiple backends**: Support Claude API, OpenAI API, or local llama.cpp as alternatives to Ollama
- **Homebrew Cask**: `brew install --cask haystack`
- **File watching**: Use FSEvents to detect new/moved/deleted files and update any local index