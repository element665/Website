#!/usr/bin/env python3
"""Append ?v=<content hash> to the local asset URLs in the site's HTML files.

Usage: stamp_assets.py SITE_ROOT

Why: file names such as styles.css or arri_la.jpg never change when their content does, so
browsers (and Cloudflare's edge) keep serving the old copy until their cache entry expires.
A hash in the query string makes the URL change exactly when the file changes, so an edited
stylesheet or a replaced photo reaches returning visitors immediately, while unchanged files
stay cached. nginx ignores the query string when serving static files.

Run inside the Docker build, on the assembled site (after the images were optimized), so the
hash is of the bytes that are actually served. Source files in git are never modified.

Only attributes whose value starts with "./" are touched (src="./..." and href="./..."), so
external URLs (Vimeo, YouTube, IMDb, Instagram) are left alone. The build fails if a local
reference points to a file that does not exist: that would be a broken page in production.
"""
import hashlib
import re
import sys
from pathlib import Path

HASHED_EXTENSIONS = {".css", ".js", ".mjs", ".jpg", ".jpeg", ".png", ".gif", ".webp", ".avif", ".svg", ".ico"}
# src="./path" or href="./path", without an existing query string or fragment
LOCAL_REF = re.compile(r'\b(?P<attr>src|href)="(?P<url>\./[^"?#]+)"')


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    root = Path(argv[1]).resolve()
    pages = sorted(root.rglob("*.html"))
    if not pages:
        print(f"no .html files under {root}")
        return 1

    missing = []
    stamped = 0

    for page in pages:
        text = page.read_text(encoding="utf-8")

        def replace(match):
            nonlocal stamped
            url = match.group("url")
            target = (page.parent / url).resolve()
            if root not in target.parents and target != root:
                missing.append(f"{page.name}: {url} (outside the site folder)")
                return match.group(0)
            if not target.is_file():
                missing.append(f"{page.name}: {url}")
                return match.group(0)
            if target.suffix.lower() not in HASHED_EXTENSIONS:
                return match.group(0)  # e.g. a link to another .html page
            digest = hashlib.sha256(target.read_bytes()).hexdigest()[:10]
            stamped += 1
            return f'{match.group("attr")}="{url}?v={digest}"'

        new_text = LOCAL_REF.sub(replace, text)
        if new_text != text:
            page.write_text(new_text, encoding="utf-8")

    if missing:
        print("ERROR: referenced local files that do not exist:")
        for item in missing:
            print(f"  {item}")
        return 1

    print(f"stamped {stamped} asset URLs in {len(pages)} pages")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
