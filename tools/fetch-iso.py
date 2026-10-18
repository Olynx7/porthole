#!/usr/bin/env python3
"""Parallel ranged downloader for large ISO images, with sha256 verification.

archive.org throttles a single connection hard (we measured 0.5-3 MB/s)
but happily serves many ranges at once (~10 MB/s with three connections),
so this fetch splits the file into N ranges and writes them in place with
os.pwrite(), which is thread-safe for distinct offsets.
"""
import argparse
import hashlib
import os
import sys
import threading
import time
import urllib.request

BLOCK = 1 << 20  # 1 MiB reads
USER_AGENT = "porthole/1.0 (+https://github.com/)"


class Progress:
    def __init__(self, total):
        self.total = total
        self.done = 0
        self.lock = threading.Lock()
        self.started = time.monotonic()
        self._stop = threading.Event()
        self._thread = None

    def add(self, n):
        with self.lock:
            self.done += n

    def _run(self):
        while not self._stop.wait(2):
            self._render()

    def _render(self):
        with self.lock:
            done = self.done
        elapsed = max(time.monotonic() - self.started, 0.001)
        pct = done * 100 / self.total if self.total else 0
        speed = done / elapsed / (1 << 20)
        sys.stderr.write(
            f"\r  {pct:5.1f}%  {done / (1 << 20):7.1f} / {self.total / (1 << 20):.1f} MiB"
            f"  {speed:5.2f} MiB/s   "
        )
        sys.stderr.flush()

    def start(self):
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self):
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=3)
        self._render()
        sys.stderr.write("\n")
        sys.stderr.flush()


def build_opener(proxy):
    if not proxy:
        return urllib.request.build_opener()
    handler = urllib.request.ProxyHandler({"http": proxy, "https": proxy})
    return urllib.request.build_opener(handler)


def fetch_range(opener, url, start, end, fd, progress, retries=5):
    attempt = 0
    while True:
        try:
            req = urllib.request.Request(
                url,
                headers={
                    "Range": f"bytes={start}-{end}",
                    "User-Agent": USER_AGENT,
                    "Accept-Encoding": "identity",
                },
            )
            with opener.open(req, timeout=60) as resp:
                if resp.status != 206:
                    raise RuntimeError(
                        f"server ignored the Range request (status {resp.status}); "
                        "use a single-stream download instead"
                    )
                pos = start
                while True:
                    chunk = resp.read(BLOCK)
                    if not chunk:
                        break
                    os.pwrite(fd, chunk, pos)
                    pos += len(chunk)
                    progress.add(len(chunk))
                if pos != end + 1:
                    raise RuntimeError(
                        f"short read: got {pos - start} of {end - start + 1} bytes"
                    )
                return
        except Exception as exc:  # noqa: BLE001 - retried below
            attempt += 1
            if attempt > retries:
                raise RuntimeError(f"range {start}-{end} failed: {exc}") from exc
            time.sleep(min(2 ** attempt, 10))


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url")
    parser.add_argument("out")
    parser.add_argument("--size", type=int, required=True)
    parser.add_argument("--sha256", default="")
    parser.add_argument("--workers", type=int, default=16)
    parser.add_argument("--proxy", default="")
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args(argv[1:])

    if args.verify_only:
        if not os.path.exists(args.out):
            print(f"missing: {args.out}", file=sys.stderr)
            return 1
        actual = sha256_of(args.out)
        ok = actual == args.sha256
        print(f"{'OK' if ok else 'MISMATCH'}  {args.out}\n  sha256 {actual}")
        return 0 if ok else 1

    if os.path.exists(args.out) and os.path.getsize(args.out) == args.size:
        if not args.sha256 or sha256_of(args.out) == args.sha256:
            print(f"already present and valid: {args.out}")
            return 0

    workers = max(1, min(args.workers, 32))
    part = max(args.size // workers, 1 << 20)

    if os.path.exists(args.out):
        os.unlink(args.out)

    opener = build_opener(args.proxy)
    fd = os.open(args.out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
    try:
        os.ftruncate(fd, args.size)
        progress = Progress(args.size)
        progress.start()
        threads = []
        start = 0
        while start < args.size:
            end = min(start + part - 1, args.size - 1)
            thread = threading.Thread(
                target=fetch_range,
                args=(opener, args.url, start, end, fd, progress),
                daemon=True,
            )
            threads.append(thread)
            thread.start()
            start = end + 1
        errors = []
        for thread in threads:
            thread.join()
        progress.stop()
        if errors:
            raise RuntimeError("; ".join(errors))
    finally:
        os.close(fd)

    actual_size = os.path.getsize(args.out)
    if actual_size != args.size:
        print(f"size mismatch: {actual_size} != {args.size}", file=sys.stderr)
        return 1
    if args.sha256:
        print("  verifying sha256 ...", file=sys.stderr)
        actual = sha256_of(args.out)
        if actual != args.sha256:
            print(f"sha256 mismatch:\n  expected {args.sha256}\n  actual   {actual}",
                  file=sys.stderr)
            return 1
        print(f"sha256 ok: {actual}")
    print(f"saved: {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
