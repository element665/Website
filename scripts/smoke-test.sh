#!/usr/bin/env sh
# Smoke test for the built site. Run it from the repo root against a running container:
#
#   docker run -d -p 127.0.0.1:8080:80 website:test
#   sh scripts/smoke-test.sh http://127.0.0.1:8080
#
# It reads site/*.html so it can check that every <iframe> host is allowed by the CSP.
set -eu

BASE="${1:?usage: smoke-test.sh BASE_URL}"
fail=0
ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=1; }
warn() { printf '  warn  %s\n' "$1"; }

headers_of() { curl -sS -D - -o /dev/null "$BASE$1" | tr -d '\r'; }

# wait for the server to come up (up to ~30 s)
i=0
until curl -fsS -o /dev/null "$BASE/" 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -ge 30 ]; then echo "server at $BASE never became ready"; exit 1; fi
  sleep 1
done

echo "Security headers are present on real content (not just on error pages)"
for p in / /gear.html /styles.css /assets/images/logo.png; do
  h=$(headers_of "$p")
  case $(printf '%s\n' "$h" | head -n 1) in
    *" 200 "*) ;;
    *) bad "$p did not return 200"; continue ;;
  esac
  missing=""
  for name in content-security-policy x-content-type-options x-frame-options referrer-policy strict-transport-security; do
    printf '%s\n' "$h" | grep -qi "^$name:" || missing="$missing $name"
  done
  if [ -n "$missing" ]; then bad "$p is missing:$missing"; else ok "$p"; fi
  if printf '%s\n' "$h" | grep -q '^[[:space:]]'; then bad "$p has a folded (multi-line) header"; fi
done

echo "CSP allows every embedded iframe"
csp=$(headers_of / | grep -i '^content-security-policy:' || true)
frame_src=$(printf '%s' "$csp" | tr ';' '\n' | grep -i 'frame-src' || true)
for host in $(grep -ho '<iframe[^>]*src="https\?://[^/"]*' site/*.html | sed 's/.*src="//' | sort -u); do
  case "$frame_src" in
    *"$host"*) ok "frame-src allows $host" ;;
    *) bad "frame-src does not allow $host" ;;
  esac
done

echo "Cache headers"
cc=$(headers_of /index.html | grep -i '^cache-control:' || true)
case "$cc" in *no-cache*) ok "HTML revalidates" ;; *) bad "HTML cache-control is: ${cc:-missing}" ;; esac
n=$(headers_of /styles.css | grep -ci '^cache-control:' || true)
[ "$n" -eq 1 ] && ok "CSS has exactly one Cache-Control header" || bad "CSS has $n Cache-Control headers"
cc=$(headers_of /styles.css | grep -i '^cache-control:' || true)
case "$cc" in *immutable*) bad "CSS is marked immutable but filenames are not hashed" ;; *) ok "CSS is not immutable" ;; esac

echo "Hidden files are not served"
code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/.DS_Store")
case "$code" in 403|404) ok ".DS_Store -> $code" ;; *) bad ".DS_Store -> $code" ;; esac

echo "Image weight (warning only)"
for img in $(grep -ho 'src="\./assets/images/[^"]*"' site/*.html | sed 's/^src="\.//; s/"$//' | sort -u); do
  size=$(curl -sS -o /dev/null -w '%{size_download}' "$BASE$img")
  if [ "$size" -gt 700000 ]; then warn "$img is $((size / 1024)) KB"; fi
done

if [ "$fail" -ne 0 ]; then echo "SMOKE TEST FAILED"; exit 1; fi
echo "smoke test passed"
