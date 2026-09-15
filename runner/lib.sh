#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# lib.sh — ortak yardimcilar. Tum runner script'leri bunu source eder.
# ---------------------------------------------------------------------------

RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$RUNNER_DIR/config.sh"

# --- Cikis kodu sozlesmesi --------------------------------------------------
# Dogrulama script'leri karar sinifini CIKIS KODUYLA bildirir; kosucu metin
# ayristirmaz. Boylece mesaj metni degisince davranis degismez.
EXIT_PASS=0     # gecti (WARN'lar olabilir)
EXIT_RETRY=1    # Sinif B — duzeltilebilir, fresh ajanla tekrar denenebilir
EXIT_HARD=2     # Sinif C — politika ihlali, kirli workspace atilir
EXIT_INFRA=4    # Sinif A/altyapi — config/arac/repo sorunu, ajan hatasi degil

# --- Loglama ----------------------------------------------------------------
_c() { [[ -t 1 ]] && printf '\033[%sm' "$1" || true; }
log()  { printf '%s\n' "$*"; }
warn() { _c 33; printf 'WARN %s\n' "$*"; _c 0; }
err()  { _c 31; printf 'HATA %s\n' "$*" >&2; _c 0; }
ok()   { _c 32; printf 'OK   %s\n' "$*"; _c 0; }

# --- Tasinabilirlik ---------------------------------------------------------
# macOS'ta GNU timeout yoktur; coreutils kuruluysa gtimeout gelir.
# DIKKAT (Windows): C:\Windows\System32\timeout.exe GNU timeout DEGILDIR,
# bekleme (sleep) komutudur. PATH sirasi yanlissa zaman asimi sessizce
# bozulur. Bu yuzden yalnizca --version ciktisi GNU coreutils diyen ikili
# kabul edilir.
_is_gnu_timeout() { "$1" --version 2>/dev/null | grep -qi 'coreutils'; }

TIMEOUT_BIN=""
if command -v gtimeout >/dev/null 2>&1 && _is_gnu_timeout gtimeout; then
  TIMEOUT_BIN="gtimeout"
elif command -v timeout >/dev/null 2>&1 && _is_gnu_timeout timeout; then
  TIMEOUT_BIN="timeout"
fi
run_with_timeout() {  # run_with_timeout <sure> <komut...>
  local t="$1"; shift
  if [[ -n "$TIMEOUT_BIN" ]]; then "$TIMEOUT_BIN" "$t" "$@"; else "$@"; fi
}

# awk, -v ile gelen degerde kacis dizilerini BIR KEZ isler: "\(" awk'a "("
# olarak ulasir ve regex'te grup parantezine donusur, desen sessizce bozulur.
# Ters bolulari ikiye katlayarak bunu onleriz.
esc() { printf '%s' "${1//\\/\\\\}"; }

# --- JSON kacisi (jq'suz, journal yazimi icin) ------------------------------
json_str() {
  local s="${1//\\/\\\\}"
  s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}

# --- Git yardimcilari -------------------------------------------------------
repo_root() { git rev-parse --show-toplevel 2>/dev/null; }
sha_short() { git rev-parse --short "${1:-HEAD}" 2>/dev/null; }
