#!/usr/bin/env python3

import json
import subprocess
import sys
from pathlib import Path


OLLAMA_MODEL = "llama3.2:1b"


def log(msg: str) -> None:
    print(f"[progress] {msg}", file=sys.stderr, flush=True)


def run_mdfind(query: str) -> list[str]:
    log(f"running mdfind query: {query!r}")

    result = subprocess.run(
        ["mdfind", query],
        text=True,
        capture_output=True,
        check=False,
    )

    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        sys.exit(result.returncode)

    paths = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    log(f"mdfind returned {len(paths)} result(s)")
    return paths


def describe_path(path: str) -> dict:
    p = Path(path)

    try:
        stat = p.stat()
        size = stat.st_size
        modified_unix = int(stat.st_mtime)
    except OSError:
        size = None
        modified_unix = None

    return {
        "path": path,
        "filename": p.name,
        "parent_dir": str(p.parent),
        "suffix": p.suffix.lower(),
        "size_bytes": size,
        "modified_unix": modified_unix,
    }


def build_prompt(items: list[dict]) -> str:
    return f"""
You are ranking macOS Spotlight search results for the user's actual resume.

The user wants to find their real resume file.

Rank the paths from most likely to least likely to be the user's real resume.

Strong positive signals:
- filename contains resume, cv, curriculum vitae, mihir, mishra, swe, software, engineer, final, latest, updated
- file type is PDF, DOCX, DOC, RTF, TXT, or Markdown
- path is in Documents, Desktop, Downloads, iCloud Drive, Google Drive, Dropbox, or career/job/application folders
- file looks like a personally authored resume rather than a template

Strong negative signals:
- path is inside Library, cache folders, application support, browser profiles, node_modules, virtualenvs, git internals, system folders
- file looks like a template, sample, attachment, log, package file, app resource, or unrelated document
- file extension is clearly not a document

Return only valid JSON. Do not include markdown.

JSON format:

[
  {{
    "rank": 1,
    "path": "/full/path",
    "reason": "brief reason"
  }}
]

Search results:
{json.dumps(items, indent=2)}
""".strip()


def rank_with_ollama(items: list[dict]) -> str:
    prompt = build_prompt(items)

    log(f"sending all {len(items)} result(s) to Ollama model: {OLLAMA_MODEL}")
    log("Ollama is generating the ranking...")

    process = subprocess.Popen(
        ["ollama", "run", OLLAMA_MODEL],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )

    assert process.stdin is not None
    assert process.stdout is not None
    assert process.stderr is not None

    process.stdin.write(prompt)
    process.stdin.close()

    output_chunks: list[str] = []

    for line in process.stdout:
        print(line, end="", flush=True)
        output_chunks.append(line)

    stderr = process.stderr.read()
    returncode = process.wait()

    if returncode != 0:
        print(stderr, file=sys.stderr)
        sys.exit(returncode)

    log("ranking complete")
    return "".join(output_chunks)


def main() -> None:
    # More specific than raw `mdfind resume`.
    # This searches for files whose *filename* contains resume/cv/curriculum vitae,
    # rather than files whose contents merely mention those words.
    default_query = (
        'kMDItemFSName == "*resume*"c || '
        'kMDItemFSName == "*cv*"c || '
        'kMDItemFSName == "*curriculum vitae*"c'
    )

    query = sys.argv[1] if len(sys.argv) > 1 else default_query

    paths = run_mdfind(query)

    if not paths:
        print("No results found.")
        return

    log(f"using all {len(paths)} result(s)")
    log("collecting basic file metadata")

    items = [describe_path(path) for path in paths]

    rank_with_ollama(items)


if __name__ == "__main__":
    main()
