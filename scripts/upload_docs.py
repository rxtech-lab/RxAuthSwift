#!/usr/bin/env python3
"""Upload markdown docs under docs/ to the autopilot docs service.

Stdlib-only. Walks docs/, parses YAML-ish frontmatter, keeps files that
declare a `slug`, errors on duplicate slugs, and POSTs the documents in
batches to the docs service.

Env config:
  DOCS_ENDPOINT        default https://autopilot.rxlab.app
  DOCS_REPOSITORY_ID   e.g. owner/repo (required unless --dry-run)
  DOCS_UPLOAD_TOKEN    bearer token (required unless --dry-run)

Usage:
  python scripts/upload_docs.py [--dry-run] [--docs-dir docs]
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

BATCH_SIZE = 50
DEFAULT_ENDPOINT = "https://autopilot.rxlab.app"


def find_repo_root() -> str:
    # scripts/ lives at the repo root; docs are resolved relative to it.
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def parse_frontmatter(text: str):
    """Return (metadata: dict, body: str).

    Supports a leading `---` fenced YAML block with simple `key: value`
    pairs (no nested structures, which the doc frontmatter never uses).
    Returns ({}, text) when no frontmatter is present.
    """
    if not text.startswith("---"):
        return {}, text

    lines = text.splitlines(keepends=True)
    # lines[0] is the opening fence.
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return {}, text

    meta = {}
    for raw in lines[1:end]:
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        value = value.strip()
        if (value.startswith('"') and value.endswith('"')) or (
            value.startswith("'") and value.endswith("'")
        ):
            value = value[1:-1]
        meta[key.strip()] = value

    body = "".join(lines[end + 1 :]).lstrip("\n")
    return meta, body


def collect_documents(docs_dir: str):
    documents = []
    slug_sources: dict[str, str] = {}

    for root, _dirs, files in os.walk(docs_dir):
        for name in sorted(files):
            if not name.endswith((".md", ".markdown")):
                continue
            path = os.path.join(root, name)
            with open(path, "r", encoding="utf-8") as fh:
                text = fh.read()
            meta, body = parse_frontmatter(text)
            slug = meta.get("slug")
            if not slug:
                rel = os.path.relpath(path, docs_dir)
                print(f"  skip (no slug): {rel}", file=sys.stderr)
                continue
            if slug in slug_sources:
                raise SystemExit(
                    f"Duplicate slug '{slug}' in {os.path.relpath(path, docs_dir)} "
                    f"and {os.path.relpath(slug_sources[slug], docs_dir)}"
                )
            slug_sources[slug] = path
            documents.append({"docId": slug, "content": body})

    return documents


def batched(items, size):
    for i in range(0, len(items), size):
        yield items[i : i + size]


def post_batch(endpoint: str, repo_id: str, token: str, batch):
    url = (
        f"{endpoint.rstrip('/')}/api/v1/docs/repositories/"
        f"{urllib.parse.quote(repo_id, safe='')}/documents"
    )
    payload = json.dumps({"documents": batch}).encode("utf-8")
    request = urllib.request.Request(url, data=payload, method="POST")
    request.add_header("Content-Type", "application/json")
    request.add_header("Authorization", f"Bearer {token}")

    with urllib.request.urlopen(request) as response:
        status = response.getcode()
        body = response.read().decode("utf-8", errors="replace")
    return status, body


def main() -> int:
    parser = argparse.ArgumentParser(description="Upload docs to autopilot")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Parse and batch without making any network call",
    )
    parser.add_argument(
        "--docs-dir",
        default=os.path.join(find_repo_root(), "docs"),
        help="Directory to scan for markdown docs (default: docs/)",
    )
    args = parser.parse_args()

    endpoint = os.environ.get("DOCS_ENDPOINT", DEFAULT_ENDPOINT)
    repo_id = os.environ.get("DOCS_REPOSITORY_ID")
    token = os.environ.get("DOCS_UPLOAD_TOKEN")

    if not os.path.isdir(args.docs_dir):
        raise SystemExit(f"Docs directory not found: {args.docs_dir}")

    documents = collect_documents(args.docs_dir)
    if not documents:
        raise SystemExit("No documents with a `slug` frontmatter were found.")

    batches = list(batched(documents, BATCH_SIZE))
    print(
        f"Collected {len(documents)} document(s) in {len(batches)} batch(es) "
        f"of up to {BATCH_SIZE}."
    )
    for doc in documents:
        print(f"  - {doc['docId']} ({len(doc['content'])} chars)")

    if args.dry_run:
        print("Dry run: no network call made.")
        return 0

    if not repo_id:
        raise SystemExit("DOCS_REPOSITORY_ID is required (e.g. owner/repo).")
    if not token:
        raise SystemExit("DOCS_UPLOAD_TOKEN is required.")

    for index, batch in enumerate(batches, start=1):
        try:
            status, body = post_batch(endpoint, repo_id, token, batch)
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise SystemExit(
                f"Batch {index}/{len(batches)} failed: HTTP {error.code} {detail}"
            )
        except urllib.error.URLError as error:
            raise SystemExit(f"Batch {index}/{len(batches)} failed: {error.reason}")
        print(f"Batch {index}/{len(batches)} -> HTTP {status} {body}".rstrip())

    print("Upload complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
