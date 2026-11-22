#!/usr/bin/env python3
"""Builds the station lists and logos the app downloads from Cloudflare Pages.

Run by .github/workflows/stations.yml (weekly, on demand, and on every push that
touches stations/overrides.json or stations/custom_logos/). Locally:
`python3 tool/build_stations.py --site build/stations-site`. Needs Pillow.

Steps:
  1. validate stations/overrides.json (fails before any network call);
  2. list each state's stations from Radio Browser (same query the app used),
     dropping the ones its substring search pulls in from other states;
  3. apply the overrides (hide / rename / stream / add);
  4. find a logo for every station, into stations/logos/<id>.png (incremental;
     stations/custom_logos/<id>.png always wins);
  5. write stations/lists/<UF>.json (committed: the weekly diff) and, with
     --site, the folder that gets deployed: v1/<UF>.json + v1/logos/<id>-<hash>.png,
     plus robots.txt (blocks search engines) and favicon.ico (the app icon).

Safety: a state whose listing failed, or shrank below half of what is
published, keeps its published stations (overrides still apply), so one bad
Radio Browser day never empties the app. Logos are only deleted after a
complete listing.

Published JSON keeps Radio Browser's field names so the app's existing parser
(`RadioStation.fromJson`, with its URL validation) reads it unchanged.

Where logos come from, in order:
  1. stations/custom_logos/<id>.png (added by hand);
  2. the station's `favicon` in Radio Browser;
  3. the station's own homepage: apple-touch-icon / icon link / og:image,
     then /favicon.ico. Skipped when the homepage host is shared by several
     stations (a hosting/portal page, whose logo would be the wrong one).
Stations with no usable logo are listed in stations/logos_missing.json and
get the app's coloured initials.
"""
import argparse
import hashlib
import io
import ipaddress
import json
import os
import shutil
import socket
import ssl
import sys
import unicodedata
import urllib.parse
import urllib.request
import warnings
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATIONS = ROOT / "stations"
OVERRIDES = STATIONS / "overrides.json"
LOGOS = STATIONS / "logos"
CUSTOM_LOGOS = STATIONS / "custom_logos"
LISTS = STATIONS / "lists"
MISSING = STATIONS / "logos_missing.json"
DEFAULT_BASE_URL = "https://nice-radio-stations.pages.dev"
MIRRORS = ["de1.api.radio-browser.info", "de2.api.radio-browser.info", "at1.api.radio-browser.info"]
UA = "NiceRadio-StationBuilder/1.0"
SIZE = 160  # px, longest side: covers the 72dp home card at ~2x
MIN_SIDE = 48  # smaller images are blurry placeholders, not logos
MAX_PIXELS = 4096 * 4096  # bigger is no logo; refusing it stops decompression bombs
MIN_KEEP = 0.5  # a fresh list below half the published one is treated as a bad fetch
MANUAL_PREFIX = "manual-"
# Fields the app reads (`RadioStation.fromJson`); order is Radio Browser's votes ranking,
# which the app's dedupe relies on ("keep the first = most voted").
FIELDS = ("stationuuid", "name", "url", "url_resolved", "favicon", "tags", "state", "bitrate")
# Same names and UFs as lib/utils/brazilian_states.dart.
STATES = {
    "Acre": "AC", "Alagoas": "AL", "Amapá": "AP", "Amazonas": "AM", "Bahia": "BA", "Ceará": "CE",
    "Distrito Federal": "DF", "Espírito Santo": "ES", "Goiás": "GO", "Maranhão": "MA",
    "Mato Grosso": "MT", "Mato Grosso do Sul": "MS", "Minas Gerais": "MG", "Pará": "PA",
    "Paraíba": "PB", "Paraná": "PR", "Pernambuco": "PE", "Piauí": "PI", "Rio de Janeiro": "RJ",
    "Rio Grande do Norte": "RN", "Rio Grande do Sul": "RS", "Rondônia": "RO", "Roraima": "RR",
    "Santa Catarina": "SC", "São Paulo": "SP", "Sergipe": "SE", "Tocantins": "TO",
}
APP_ICON = ROOT / "assets" / "icon" / "icon.png"
# The data is for the app, not for search engines.
ROBOTS = "User-agent: *\nDisallow: /\n"
HEADERS = """\
/v1/*
  Access-Control-Allow-Origin: *
/v1/*.json
  Cache-Control: public, max-age=3600
/v1/logos/*
  Cache-Control: public, max-age=31536000, immutable
"""


def is_http(url):
    return isinstance(url, str) and url.lower().startswith(("http://", "https://"))


# ------------------------------------------------------------------ overrides

def validate_overrides(o):
    """Problems with the hand-edited overrides file, as readable strings."""
    errors = []
    allowed = {"hide", "rename", "stream", "add"}
    if not isinstance(o, dict):
        return ["the file must be a JSON object"]
    errors += [f"unknown key '{k}' (use {sorted(allowed)})" for k in o if k not in allowed]
    if not isinstance(o.get("hide", []), list) or not all(isinstance(i, str) for i in o.get("hide", [])):
        errors.append("'hide' must be a list of station ids")
    for key in ("rename", "stream"):
        value = o.get(key, {})
        if not isinstance(value, dict) or not all(isinstance(v, str) and v.strip() for v in value.values()):
            errors.append(f"'{key}' must map station ids to non-empty text")
    stream = o.get("stream", {})
    errors += [f"stream for {i} is not an http(s) URL: {u}" for i, u in (stream if isinstance(stream, dict) else {}).items()
               if isinstance(u, str) and not is_http(u)]
    added = o.get("add", [])
    if not isinstance(added, list):
        return errors + ["'add' must be a list"]
    seen = set()
    for n, entry in enumerate(added):
        where = f"add[{n}]"
        if not isinstance(entry, dict):
            errors.append(f"{where} must be an object")
            continue
        sid = entry.get("id", "")
        if not isinstance(sid, str) or not sid.startswith(MANUAL_PREFIX) or len(sid) <= len(MANUAL_PREFIX):
            errors.append(f"{where}: 'id' must start with '{MANUAL_PREFIX}' (e.g. manual-sp-radio-x)")
        elif sid in seen:
            errors.append(f"{where}: id '{sid}' is repeated")
        seen.add(sid)
        if entry.get("state") not in STATES:
            errors.append(f"{where}: 'state' must be one of the state names, e.g. 'São Paulo'")
        if not isinstance(entry.get("name"), str) or not entry["name"].strip():
            errors.append(f"{where}: 'name' is required")
        if not is_http(entry.get("stream")):
            errors.append(f"{where}: 'stream' must be an http(s) URL")
        for opt in ("favicon", "homepage"):
            if opt in entry and not is_http(entry[opt]):
                errors.append(f"{where}: '{opt}' must be an http(s) URL")
    return errors


def apply_overrides(state, stations, o):
    """One state's station list with the overrides applied (input untouched)."""
    hide = set(o.get("hide", []))
    out = []
    for s in stations:
        sid = s["stationuuid"]
        if sid in hide or sid.startswith(MANUAL_PREFIX):  # manual ones are re-added below
            continue
        s = dict(s)
        if sid in o.get("rename", {}):
            s["name"] = o["rename"][sid]
        if sid in o.get("stream", {}):
            s["url"] = s["url_resolved"] = o["stream"][sid]
        out.append(s)
    for e in o.get("add", []):
        if e["state"] == state and e["id"] not in hide:
            out.append({"stationuuid": e["id"], "name": e["name"].strip(), "url": e["stream"],
                        "url_resolved": e["stream"], "favicon": e.get("favicon", ""),
                        "homepage": e.get("homepage", ""), "tags": e.get("tags", ""),
                        "state": state, "bitrate": e.get("bitrate", 0)})
    return out


def unknown_ids(o, known):
    ids = set(o.get("hide", [])) | set(o.get("rename", {})) | set(o.get("stream", {}))
    return sorted(i for i in ids if i not in known and not i.startswith(MANUAL_PREFIX))


def _words(text):
    plain = unicodedata.normalize("NFKD", text or "").encode("ascii", "ignore").decode().lower()
    return " " + " ".join("".join(c if c.isalnum() else " " for c in plain).split()) + " "


def state_of(label):
    """The state a free-text Radio Browser label names ("Curitiba Paraná" -> Paraná), longest
    name winning ("Mato Grosso do Sul" over "Mato Grosso"), or None when it names none."""
    found = [name for name in STATES if _words(name) in _words(label)]
    return max(found, key=len) if found else None


def keep_in_state(stations, state):
    """Drops stations that belong to another state. Radio Browser's `state` search matches any
    substring, so "Pará" also returns Paraná and Paraíba, "Mato Grosso" Mato Grosso do Sul."""
    return [s for s in stations if state_of(s.get("state")) in (None, state)]


def choose_base(fresh, published):
    """Fresh Radio Browser list, or the published one when the fetch failed or shrank a lot."""
    published = [s for s in published if not s["stationuuid"].startswith(MANUAL_PREFIX)]
    if fresh is None or len(fresh) < MIN_KEEP * len(published):
        return published, False
    return fresh, True


# ---------------------------------------------------------------- network

def _ssl_context():
    # python.org builds on macOS ship no root certificates; fall back to certifi or the system bundle.
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        system = Path("/etc/ssl/cert.pem")
        return ssl.create_default_context(cafile=str(system) if system.exists() else None)


CTX = _ssl_context()


def _check_public(url):
    """Refuses URLs whose host resolves to a private/loopback/link-local address: logo and
    homepage URLs come from crowdsourced data, and the runner must not fetch its own network."""
    host = urllib.parse.urlparse(url).hostname
    if not host:
        raise ValueError(f"no host in {url}")
    for info in socket.getaddrinfo(host, None):
        if not ipaddress.ip_address(info[4][0].split("%")[0]).is_global:
            raise ValueError(f"non-public address for {host}")


class _PublicRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        _check_public(newurl)  # every hop, not just the first URL
        return super().redirect_request(req, fp, code, msg, headers, newurl)


_OPENER = urllib.request.build_opener(urllib.request.HTTPSHandler(context=CTX), _PublicRedirects)


def get(url, limit=3_000_000, timeout=8):
    # shortcut: the address is checked, then resolved again by urllib (DNS rebinding window);
    # fine for a throwaway CI runner, pin the IP if this ever runs somewhere with secrets nearby.
    _check_public(url)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with _OPENER.open(req, timeout=timeout) as r:
        return r.read(limit), r.headers.get("content-type", "")


def fetch_state(name):
    qs = urllib.parse.urlencode({"country": "Brazil", "state": name, "limit": 100, "order": "votes",
                                 "reverse": "true", "hidebroken": "true"})
    for host in MIRRORS:
        try:
            data, _ = get(f"https://{host}/json/stations/search?{qs}", limit=20_000_000, timeout=30)
            return keep_in_state([s for s in json.loads(data) if s.get("stationuuid")], name)
        except Exception:
            continue
    print(f"::warning::could not list {name}; keeping its published stations", file=sys.stderr)
    return None


def to_png(raw):
    """Raw image bytes -> small PNG bytes, or None when unusable."""
    from PIL import Image  # only the logo step needs Pillow (tests don't)
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            img = Image.open(io.BytesIO(raw))
            # The size comes from the header, before decoding: refuse decompression bombs.
            if min(img.size) < MIN_SIDE or img.size[0] * img.size[1] > MAX_PIXELS:
                return None
            img.draft("RGB", (SIZE, SIZE))  # JPEG: decode straight at a reduced scale
            img = img.convert("RGBA")
            img.thumbnail((SIZE, SIZE), Image.LANCZOS)
        out = io.BytesIO()
        img.save(out, "PNG", optimize=True)
        return out.getvalue()
    except Exception:
        return None


def try_url(url):
    if not is_http(url):
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


# ------------------------------------------------------------------ logos

def _host(url):
    return urllib.parse.urlparse(url or "").netloc.lower().removeprefix("www.")


def update_logos(stations, complete, retry):
    """Fills stations/logos/ for [stations]; returns the set of ids without a logo."""
    LOGOS.mkdir(parents=True, exist_ok=True)
    hosts = Counter(h for h in (_host(s.get("homepage")) for s in stations) if h)
    known_missing = set() if retry or not MISSING.exists() else set(json.loads(MISSING.read_text(encoding="utf-8")))

    def work(s):
        uid = s["stationuuid"]
        if (CUSTOM_LOGOS / f"{uid}.png").exists():
            return uid, "custom"
        dest = LOGOS / f"{uid}.png"
        if dest.exists():
            return uid, "have"
        if uid in known_missing:
            return uid, "miss"
        png = try_url(s.get("favicon"))
        source = "favicon"
        if png is None:
            home = (s.get("homepage") or "").strip()
            if is_http(home) and hosts[_host(home)] <= 2:
                png, source = from_homepage(home), "homepage"
        if png is None:
            return uid, "miss"
        dest.write_bytes(png)
        return uid, source

    stats = Counter()
    missing = set()
    with ThreadPoolExecutor(16) as ex:
        for uid, status in ex.map(work, stations):
            stats[status] += 1
            if status == "miss":
                missing.add(uid)
    # The same image on 3+ stations is a generic/portal logo, not theirs: drop it.
    by_hash = {}
    for f in LOGOS.glob("*.png"):
        by_hash.setdefault(hashlib.md5(f.read_bytes()).hexdigest(), []).append(f)
    for files in by_hash.values():
        if len(files) > 2:
            for f in files:
                f.unlink()
                missing.add(f.stem)
    # Drop logos of stations no longer listed. Only after a complete listing:
    # a partial one must not delete good files.
    listed = {s["stationuuid"] for s in stations}
    for f in LOGOS.glob("*.png") if complete else []:
        if f.stem not in listed:
            f.unlink()
    MISSING.write_text(json.dumps(sorted(missing & listed), indent=0) + "\n", encoding="utf-8")
    print(f"logos: {dict(stats)}")
    return missing


def logo_file(uid):
    custom = CUSTOM_LOGOS / f"{uid}.png"
    if custom.exists():
        return custom
    fetched = LOGOS / f"{uid}.png"
    return fetched if fetched.exists() else None


def hashed_name(uid, path):
    # Content hash in the name: a changed logo gets a new URL, so the app's
    # per-URL disk cache and the CDN's immutable cache both stay correct.
    return f"{uid}-{hashlib.sha256(path.read_bytes()).hexdigest()[:10]}.png"


def write_favicon(dest):
    """The app icon as a multi-size favicon.ico (browsers ask for it when someone opens a list)."""
    from PIL import Image
    Image.open(APP_ICON).convert("RGBA").save(dest, sizes=[(16, 16), (32, 32), (48, 48)])


# ------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--retry", action="store_true", help="retry stations recorded as missing a logo")
    ap.add_argument("--site", type=Path, help="also assemble the deployable folder here")
    ap.add_argument("--base-url", default=os.environ.get("STATIONS_BASE_URL", DEFAULT_BASE_URL))
    args = ap.parse_args()
    base_url = args.base_url.rstrip("/")

    overrides = json.loads(OVERRIDES.read_text(encoding="utf-8")) if OVERRIDES.exists() else {}
    errors = validate_overrides(overrides)
    if errors:
        sys.exit("stations/overrides.json is invalid:\n  - " + "\n  - ".join(errors))

    with ThreadPoolExecutor(6) as ex:
        fresh = dict(zip(STATES, ex.map(fetch_state, STATES)))

    lists = {}
    complete = True
    for state, uf in STATES.items():
        path = LISTS / f"{uf}.json"
        published = json.loads(path.read_text(encoding="utf-8")) if path.exists() else []
        base, ok = choose_base(fresh[state], published)
        if not ok and fresh[state] is not None:
            print(f"::warning::{state}: Radio Browser returned {len(fresh[state])} stations, "
                  f"published has {len(published)}; keeping the published ones")
        complete &= ok
        lists[state] = apply_overrides(state, base, overrides)

    every = [s for stations in lists.values() for s in stations]
    if not every:
        sys.exit("no stations at all (offline?); nothing changed")
    for sid in unknown_ids(overrides, {s["stationuuid"] for s in every}
                           | {s["stationuuid"] for stations in fresh.values() for s in stations or []}):
        print(f"::warning::overrides.json mentions {sid}, which no longer exists in Radio Browser")

    update_logos(every, complete, args.retry)

    LISTS.mkdir(parents=True, exist_ok=True)
    site_logos = None
    if args.site:
        shutil.rmtree(args.site, ignore_errors=True)
        site_logos = args.site / "v1" / "logos"
        site_logos.mkdir(parents=True)
        (args.site / "_headers").write_text(HEADERS, encoding="utf-8")
        (args.site / "robots.txt").write_text(ROBOTS, encoding="utf-8")
        write_favicon(args.site / "favicon.ico")
    for state, uf in STATES.items():
        published = []
        for s in lists[state]:
            entry = {k: s.get(k, "") for k in FIELDS}
            logo = logo_file(s["stationuuid"])
            entry["favicon"] = ""
            if logo:
                name = hashed_name(s["stationuuid"], logo)
                entry["favicon"] = f"{base_url}/v1/logos/{name}"
                if site_logos:
                    shutil.copyfile(logo, site_logos / name)
            published.append(entry)
        text = json.dumps(published, ensure_ascii=False, indent=1) + "\n"
        (LISTS / f"{uf}.json").write_text(text, encoding="utf-8")
        if args.site:
            (args.site / "v1" / f"{uf}.json").write_text(text, encoding="utf-8")
    print(f"{len(every)} stations in {len(STATES)} states")


if __name__ == "__main__":
    main()
