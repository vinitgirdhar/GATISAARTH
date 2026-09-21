#!/usr/bin/env python3
"""Fetch the real IO-VNBD files behind the Git-LFS pointers in `IO-VNBD_DATASET/`.

`IO-VNBD_DATASET/IO-VNBD-master` was cloned without Git LFS, so every csv/jpg/zip in it is a
130-byte pointer (`version ...`, `oid sha256:<hex>`, `size <n>`).  The real objects are public
at `media.githubusercontent.com/media/onyekpeu/IO-VNBD/master/<url-encoded path>`.  This tool

  * reads the pointers (never modifies `IO-VNBD_DATASET/`),
  * downloads the selected files into `ml/data/raw/IO-VNBD_repo/<same relative path>`
    (git-ignored) with parallel connections, retries and resume,
  * verifies EVERY file's size and SHA-256 against its pointer (mismatch -> delete + re-download),
  * skips files that are already present and verified,
  * writes `<dest>/manifest.json` and prints a summary.

Usage (from the repo root):
    python ml/src/dataset/fetch_iovnbd.py                       # default: sync-categorised csv, ~426 MB
    python ml/src/dataset/fetch_iovnbd.py --dry-run
    python ml/src/dataset/fetch_iovnbd.py --subset sync-all     # + Uncategorised copy (another ~429 MB)
    python ml/src/dataset/fetch_iovnbd.py --subset all --include-images

The two `.zip` files are never selected: they only repackage the folders next to them.
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, Iterator

REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_POINTER_ROOT = REPO_ROOT / "IO-VNBD_DATASET" / "IO-VNBD-master"
DEFAULT_DEST = REPO_ROOT / "ml" / "data" / "raw" / "IO-VNBD_repo"
BASE_URL = "https://media.githubusercontent.com/media/onyekpeu/IO-VNBD/master/"

LFS_VERSION = "version https://git-lfs.github.com/spec/v1"
SUBSET_PREFIX = {
    "sync-categorised": "Synchronised V abd S datasets/Categorised IOVNB Dataset/",
    "sync-all": "Synchronised V abd S datasets/",
    "all": "",
}
_OID = re.compile(r"^oid sha256:([0-9a-f]{64})$", re.M)
_SIZE = re.compile(r"^size (\d+)$", re.M)
CHUNK = 1 << 20

Fetch = Callable[[str, int], "tuple[int, Iterable[bytes]]"]


@dataclass(frozen=True)
class Pointer:
    rel: str   # posix path relative to the pointer root
    oid: str   # sha256 hex of the real file
    size: int  # size in bytes of the real file


def parse_pointer(text: str) -> tuple[str, int]:
    """Return (sha256, size) from a Git-LFS pointer; ValueError if `text` is not one."""
    text = text.replace("\r\n", "\n")  # a Windows checkout may have converted the line endings
    if not text.startswith(LFS_VERSION):
        raise ValueError("not a Git-LFS pointer")
    oid, size = _OID.search(text), _SIZE.search(text)
    if not (oid and size):
        raise ValueError("Git-LFS pointer without a valid oid/size")
    return oid.group(1), int(size.group(1))


def discover(pointer_root: Path, subset: str = "sync-categorised", include_images: bool = False) -> list[Pointer]:
    """List the pointer files of `subset` (csv, plus jpg with `include_images`). Zip files are never listed."""
    prefix = SUBSET_PREFIX[subset]
    exts = {".csv"} | ({".jpg", ".jpeg"} if include_images else set())
    found = []
    for dirpath, _, names in os.walk(pointer_root):
        for name in sorted(names):
            path = Path(dirpath) / name
            if path.suffix.lower() not in exts:
                continue
            rel = path.relative_to(pointer_root).as_posix()
            if not rel.startswith(prefix):
                continue
            try:
                with open(path, "rb") as fh:
                    oid, size = parse_pointer(fh.read(512).decode("utf-8", "replace"))
            except ValueError:
                print(f"[skip] {rel}: not a pointer file (already real data?)", file=sys.stderr)
                continue
            found.append(Pointer(rel, oid, size))
    return sorted(found, key=lambda p: p.rel)


def url_for(rel: str) -> str:
    return BASE_URL + urllib.parse.quote(rel, safe="/()")


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(CHUNK), b""):
            h.update(block)
    return h.hexdigest()


def verify(path: Path, ptr: Pointer) -> bool:
    """True when `path` exists with exactly the pointer's size and SHA-256."""
    return path.is_file() and path.stat().st_size == ptr.size and sha256_of(path) == ptr.oid


def http_fetch(url: str, offset: int = 0) -> tuple[int, Iterator[bytes]]:
    """Real network fetch; `offset` > 0 asks for a byte range (status 206 when honoured)."""
    headers = {"User-Agent": "gatisaarth-fetch-iovnbd/1.0"}
    if offset:
        headers["Range"] = f"bytes={offset}-"
    resp = urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=90)

    def chunks() -> Iterator[bytes]:
        with resp:
            for block in iter(lambda: resp.read(CHUNK), b""):
                yield block
    return resp.status, chunks()


def download_one(ptr: Pointer, dest_root: Path, fetch: Fetch = http_fetch, retries: int = 5,
                 sleep: Callable[[float], None] = time.sleep) -> str:
    """Download + verify one file. Returns 'skipped' | 'downloaded' | 'failed: <reason>'."""
    dest = dest_root / ptr.rel
    if verify(dest, ptr):
        return "skipped"
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_name(dest.name + ".part")
    if dest.exists():  # present but wrong -> re-download from scratch
        dest.unlink()
    reason = "no attempt"
    for attempt in range(1, retries + 1):
        try:
            have = part.stat().st_size if part.exists() else 0
            if have > ptr.size:
                part.unlink()
                have = 0
            if have < ptr.size:
                status, chunks = fetch(url_for(ptr.rel), have)
                if have and status != 206:  # server ignored the Range header -> start over
                    have = 0
                with open(part, "ab" if have else "wb") as fh:
                    for block in chunks:
                        fh.write(block)
            if verify(part, ptr):
                os.replace(part, dest)
                return "downloaded"
            part.unlink(missing_ok=True)  # size/sha mismatch: delete, fetch again from byte 0
            reason = "size/sha256 mismatch"
        except (urllib.error.URLError, OSError, TimeoutError) as err:
            reason = f"{type(err).__name__}: {err}"
        if attempt < retries:
            sleep(min(2 ** attempt, 30))
    return f"failed: {reason}"


def _category(rel: str) -> str:
    parts = rel.split("/")
    return "/".join(parts[:3]) if len(parts) > 3 else parts[0]


def fetch_all(pointers: list[Pointer], dest_root: Path, workers: int = 4, retries: int = 5,
              fetch: Fetch = http_fetch, verbose: bool = False) -> dict[str, str]:
    results: dict[str, str] = {}
    done = 0
    with cf.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(download_one, p, dest_root, fetch, retries): p for p in pointers}
        for fut in cf.as_completed(futures):
            p = futures[fut]
            results[p.rel] = fut.result()
            done += 1
            if verbose or results[p.rel].startswith("failed") or done % 12 == 0 or done == len(pointers):
                print(f"[{done:3d}/{len(pointers)}] {results[p.rel]:<11.11} {p.rel} ({p.size / 1e6:.1f} MB)", flush=True)
    return results


def write_manifest(dest_root: Path, pointers: list[Pointer], results: dict[str, str]) -> Path:
    entries = [{"path": p.rel, "size": p.size, "sha256": p.oid, "status": results.get(p.rel, "not attempted")}
               for p in pointers]
    path = dest_root / "manifest.json"
    path.write_text(json.dumps({"base_url": BASE_URL, "files": entries}, indent=1), encoding="utf-8")
    return path


def print_summary(pointers: list[Pointer], results: dict[str, str]) -> None:
    per_cat = defaultdict(lambda: [0, 0])
    for p in pointers:
        per_cat[_category(p.rel)][0] += 1
        per_cat[_category(p.rel)][1] += p.size
    print("\nManifest summary")
    print("-" * 78)
    for cat, (n, size) in sorted(per_cat.items()):
        print(f"  {cat:<70.70} {n:4d} files {size / 1e6:8.1f} MB")
    outcome = defaultdict(int)
    for status in results.values():
        outcome[status.split(":")[0]] += 1
    total = sum(p.size for p in pointers)
    print("-" * 78)
    print(f"  selected {len(pointers)} files, {total / 1e6:.1f} MB | " +
          ", ".join(f"{k}: {v}" for k, v in sorted(outcome.items())))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--pointer-root", type=Path, default=DEFAULT_POINTER_ROOT)
    ap.add_argument("--dest", type=Path, default=DEFAULT_DEST)
    ap.add_argument("--subset", choices=sorted(SUBSET_PREFIX), default="sync-categorised")
    ap.add_argument("--include-images", action="store_true", help="also fetch the .jpg photos")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--retries", type=int, default=5)
    ap.add_argument("--dry-run", action="store_true", help="list what would be downloaded, touch nothing")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args(argv)

    if not args.pointer_root.is_dir():
        print(f"[error] pointer root not found: {args.pointer_root}", file=sys.stderr)
        return 2
    pointers = discover(args.pointer_root, args.subset, args.include_images)
    if not pointers:
        print("[error] no pointer files selected", file=sys.stderr)
        return 2
    print(f"[fetch] {len(pointers)} files ({sum(p.size for p in pointers) / 1e6:.1f} MB) "
          f"subset={args.subset} -> {args.dest}")
    if args.dry_run:
        todo = [p for p in pointers if not verify(args.dest / p.rel, p)]
        print(f"[dry-run] {len(pointers) - len(todo)} already verified, {len(todo)} to download "
              f"({sum(p.size for p in todo) / 1e6:.1f} MB)")
        print_summary(pointers, {p.rel: "would download" for p in todo})
        return 0
    args.dest.mkdir(parents=True, exist_ok=True)
    results = fetch_all(pointers, args.dest, args.workers, args.retries, verbose=args.verbose)
    manifest = write_manifest(args.dest, pointers, results)
    print_summary(pointers, results)
    print(f"  manifest -> {manifest}")
    failed = [rel for rel, s in results.items() if s.startswith("failed")]
    if failed:
        print(f"[error] {len(failed)} files failed verification/download; re-run to resume", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
