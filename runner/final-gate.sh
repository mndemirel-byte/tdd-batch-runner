#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# final-gate.sh — kosu sonu zorunlu entegrasyon kapisi.
#
#   final-gate.sh <integration-branch> <base-sha>
#
# NEDEN GEREKLI: issuelar tek tek yesilken birlesimleri regression uretebilir
# (04 ✓ + 07 ✓ ≠ 04+07 ✓). Integration branch modeli bunu AZALTIR — her issue
# oncekilerin ustunde dogrulanir — ama ortadan kaldirmaz: son issue'dan sonra
# tam suit hic kosulmamis olabilir ve her issue kendi hedefli testine gore
# gecmis olabilir.
#
# G10  tam test suiti  — TEMIZ KLONDA
# G11  build / package — TEMIZ KLONDA
# G12  e2e (tanimliysa) — TEMIZ KLONDA
#      (klon sarti ucu icin de ayni gerekceyle gecerlidir: yerel artiklar
#       testi de build'i de yanlis yere yesil gosterebilir)
# G13  toplam diff denetimi: korumali dosyalar tum kosu boyunca temiz mi
# ---------------------------------------------------------------------------
set -uo pipefail
RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RUNNER_DIR/lib.sh"
REPO="$(repo_root)"; cd "$REPO" || exit "$EXIT_INFRA"

BRANCH="${1:?kullanim: final-gate.sh <integration-branch> <base-sha>}"
BASE_SHA="${2:?}"
rc=0

log "══ FINAL ENTEGRASYON KAPISI ══════════════════════"

# --- G13: toplam diff denetimi (once, ucuz) --------------------------------
# Issue/PRD dosyalari ve durum-only commit'leri kod degisikligi sayilmaz.
ALL_CHANGED="$(git diff --name-only "$BASE_SHA".."$BRANCH" | grep -vE "${ISSUE_TRACK_RE:-^$}" || true)"
TAMPERED="$(grep -E "$PROTECTED_HARD" <<<"$ALL_CHANGED" || true)"
if [[ -n "$TAMPERED" ]]; then
  err "G13 dogrulama altyapisi kosu boyunca degismis: $(tr '\n' ' ' <<<"$TAMPERED")"; rc=1
else ok "G13 korumali dosyalar temiz"; fi

CFG="$(grep -E "$PROTECTED_CONFIG" <<<"$ALL_CHANGED" || true)"
[[ -n "$CFG" ]] && warn "G13 config dosyalari degismis, merge oncesi incele: $(tr '\n' ' ' <<<"$CFG")"

# --- G10-G12: temiz klonda dogrulama ---------------------------------------
# Temiz klon sarttir ve UC KAPI icin de gecerlidir: yerel node_modules
# artiklari, cache'ler ve .gitignore'lanmis dosyalar testi de build'i de
# yanlis yere yesil gosterebilir.
if [[ -n "$TEST_CMD$BUILD_CMD$E2E_CMD" ]]; then
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  log "G10-G12 temiz klon hazirlaniyor: $TMP"
  if git clone -q --no-hardlinks --branch "$BRANCH" "$REPO" "$TMP/repo" 2>/dev/null; then
    pushd "$TMP/repo" >/dev/null || exit "$EXIT_INFRA"
    [[ -f package-lock.json ]] && npm ci --silent >/dev/null 2>&1
    [[ -f requirements.txt  ]] && pip install -q -r requirements.txt >/dev/null 2>&1
    if [[ -n "$TEST_CMD" ]]; then
      eval "$TEST_CMD" && ok "G10 tam test suiti (temiz klon) yesil" || { err "G10 temiz klonda KIRMIZI"; rc=1; }
    else warn "G10 ATLANDI (TEST_CMD tanimsiz)"; fi
    if [[ -n "$BUILD_CMD" ]]; then
      eval "$BUILD_CMD" >/dev/null 2>&1 && ok "G11 build (temiz klon)" || { err "G11 build basarisiz (temiz klon)"; rc=1; }
    else warn "G11 ATLANDI (BUILD_CMD tanimsiz)"; fi
    if [[ -n "$E2E_CMD" ]]; then
      eval "$E2E_CMD" >/dev/null 2>&1 && ok "G12 e2e (temiz klon)" || { err "G12 e2e basarisiz (temiz klon)"; rc=1; }
    else warn "G12 ATLANDI (E2E_CMD tanimsiz)"; fi
    popd >/dev/null
  else err "G10-G12 klon basarisiz"; rc=1; fi
else warn "G10-G12 ATLANDI (hicbir dogrulama komutu tanimsiz)"; fi

log ""
if (( rc == 0 )); then
  ok "FINAL KAPI GECILDI — '$BRANCH' merge incelemesine hazir"
else
  err "FINAL KAPI GECILEMEDI — '$BRANCH' merge'e hazir DEGIL"
fi
exit $rc
