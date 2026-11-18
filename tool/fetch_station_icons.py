#!/usr/bin/env python3
"""Downloads a logo for every station the app can list, into assets/station_icons/<uuid>.png.

Run it before a release build (`python3 tool/fetch_station_icons.py`); it is
incremental (existing files and known misses are skipped, `--retry` retries
the misses). Needs Pillow (`pip install pillow`).

Where logos come from, in order:
  1. the station's `favicon` in Radio Browser;
  2. the station's own homepage: apple-touch-icon / icon link / og:image,
     then /favicon.ico. Skipped when the homepage host is shared by several
     stations (a hosting/portal page, whose logo would be the wrong one).
Stations with no usable logo are listed in tool/station_icons_missing.json and
keep the app's old behavior (network favicon, else coloured initials).
"""
import argparse
import hashlib
import io
import json
import ssl
import sys
import urllib.parse
import urllib.request
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from html.parser import HTMLParser
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "station_icons"
MISSING = ROOT / "tool" / "station_icons_missing.json"
MIRRORS = ["de1.api.radio-browser.info", "de2.api.radio-browser.info", "at1.api.radio-browser.info"]
UA = "NiceRadio-IconFetcher/1.0"
SIZE = 160  # px, longest side: covers the 72dp home card at ~2x
MIN_SIDE = 48  # smaller images are blurry placeholders, not logos
STATES = [
    "Acre", "Alagoas", "Amapá", "Amazonas", "Bahia", "Ceará", "Distrito Federal", "Espírito Santo",
    "Goiás", "Maranhão", "Mato Grosso", "Mato Grosso do Sul", "Minas Gerais", "Pará", "Paraíba",
    "Paraná", "Pernambuco", "Piauí", "Rio de Janeiro", "Rio Grande do Norte", "Rio Grande do Sul",
    "Rondônia", "Roraima", "Santa Catarina", "São Paulo", "Sergipe", "Tocantins",
]


def _ssl_context():
    # python.org builds on macOS ship no root certificates; fall back to certifi or the system bundle.
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        system = Path("/etc/ssl/cert.pem")
        return ssl.create_default_context(cafile=str(system) if system.exists() else None)


CTX = _ssl_context()


def get(url, limit=3_000_000, timeout=8):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout, context=CTX) as r:
        return r.read(limit), r.headers.get("content-type", "")


def fetch_state(name):
    qs = urllib.parse.urlencode({"country": "Brazil", "state": name, "limit": 100, "order": "votes",
                                 "reverse": "true", "hidebroken": "true"})
    for host in MIRRORS:
        try:
            data, _ = get(f"https://{host}/json/stations/search?{qs}", limit=20_000_000, timeout=30)
            return json.loads(data)
        except Exception:
            continue
    print(f"  ! could not list {name}", file=sys.stderr)
    return None


def to_png(raw):
    """Raw image bytes -> small PNG bytes, or None when unusable."""
    try:
        img = Image.open(io.BytesIO(raw))
        if min(img.size) < MIN_SIDE:
            return None
        img = img.convert("RGBA")
        img.thumbnail((SIZE, SIZE), Image.LANCZOS)
        out = io.BytesIO()
        img.save(out, "PNG", optimize=True)
        return out.getvalue()
    except Exception:
        return None


def try_url(url):
    if not url or not url.lower().startswith(("http://", "https://")):
        return None
    try:
        raw, _ = get(url)
    except Exception:
        return None
    return to_png(raw)


class IconLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.found = []  # (priority, href)

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "link" and a.get("href"):
            rel = (a.get("rel") or "").lower()
            if "apple-touch-icon" in rel:
                self.found.append((0, a["href"]))
            elif "icon" in rel:
                self.found.append((2, a["href"]))
        elif tag == "meta" and (a.get("property") or "").lower() == "og:image" and a.get("content"):
            self.found.append((1, a["content"]))


def from_homepage(homepage):
    candidates = []
    try:
        raw, _ = get(homepage, limit=400_000)
        parser = IconLinks()
        parser.feed(raw.decode("utf-8", "ignore"))
        candidates = [urllib.parse.urljoin(homepage, h) for _, h in sorted(parser.found)]
    except Exception:
        pass
    candidates.append(urllib.parse.urljoin(homepage, "/favicon.ico"))
    for url in candidates:
        png = try_url(url)
        if png:
            return png
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--retry", action="store_true", help="retry stations recorded as missing")
    args = ap.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    stations = {}
    with ThreadPoolExecutor(6) as ex:
        results = list(ex.map(fetch_state, STATES))
    for result in results:
        for s in result or []:
            stations[s["stationuuid"]] = s
    complete = all(r is not None for r in results)
    print(f"{len(stations)} stations listed")
    if not stations:
        sys.exit("no stations listed (offline?); nothing changed")

    hosts = Counter()
    for s in stations.values():
        host = urllib.parse.urlparse(s.get("homepage") or "").netloc.lower().removeprefix("www.")
        if host:
            hosts[host] += 1

    known_missing = set() if args.retry or not MISSING.exists() else set(json.loads(MISSING.read_text()))

    def work(s):
        uid = s["stationuuid"]
        dest = OUT / f"{uid}.png"
        if dest.exists():
            return uid, "have"
        if uid in known_missing:
            return uid, "miss"
        png = try_url(s.get("favicon"))
        source = "favicon"
        if png is None:
            home = (s.get("homepage") or "").strip()
            host = urllib.parse.urlparse(home).netloc.lower().removeprefix("www.")
            if home.startswith(("http://", "https://")) and hosts[host] <= 2:
                png, source = from_homepage(home), "homepage"
        if png is None:
            return uid, "miss"
        dest.write_bytes(png)
        return uid, source

    stats = Counter()
    missing = set()
    with ThreadPoolExecutor(16) as ex:
        for uid, status in ex.map(work, stations.values()):
            stats[status] += 1
            if status == "miss":
                missing.add(uid)
    # The same image on 3+ stations is a generic/portal logo, not theirs: drop it.
    by_hash = {}
    for f in OUT.glob("*.png"):
        by_hash.setdefault(hashlib.md5(f.read_bytes()).hexdigest(), []).append(f)
    for files in by_hash.values():
        if len(files) > 2:
            for f in files:
                f.unlink()
                missing.add(f.stem)
    # Drop files for stations the app no longer lists, and old misses now solved.
    # Only when every state was listed: a partial listing must not delete good files.
    for f in OUT.glob("*.png") if complete else []:
        if f.stem not in stations:
            f.unlink()
    MISSING.write_text(json.dumps(sorted(missing), indent=0) + "\n")
    print(dict(stats))
    total = sum(f.stat().st_size for f in OUT.glob("*.png"))
    print(f"{len(list(OUT.glob('*.png')))} icons, {total / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
