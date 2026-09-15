#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# preflight.sh — dongoye girmeden once, bir kez.
#
#   preflight.sh <integration-branch>
#
# En onemli kontrol BASELINE'dir: base dal zaten kirmiziysa 15 issue'nun
# 15'i de haksiz yere FAIL[tests] yer ve saatler + bütce bosa gider.
# ---------------------------------------------------------------------------
set -uo pipefail
RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RUNNER_DIR/lib.sh"
cd "$(repo_root)" || exit "$EXIT_INFRA"

QUICK=0
if [[ "${1:-}" == "--quick" ]]; then QUICK=1; shift; fi
BRANCH="${1:-}"
rc=0

log "── Araclar ─────────────────────────────────────────"
for t in claude git jq awk; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t"; else err "$t bulunamadi"; rc=1; fi
done
if [[ -n "$TIMEOUT_BIN" ]]; then ok "$TIMEOUT_BIN (GNU coreutils)"
else
  warn "GNU timeout bulunamadi — issue zaman asimi UYGULANMAYACAK."
  if command -v timeout >/dev/null 2>&1; then
    warn "  PATH'te bir 'timeout' var ama GNU degil (muhtemelen"
    warn "  Windows System32\\timeout.exe — o bir bekleme komutudur)."
    warn "  Git Bash kullan ya da PATH sirasini duzelt."
  fi
  warn "  macOS: brew install coreutils (gtimeout saglar)"
fi

# CRLF kontrolu: Windows'ta core.autocrlf=true ile klonlanmis repo'da
# shebang satiri \r ile biter ve script hic calismaz.
if grep -qU $'\r' "$RUNNER_DIR/verify.sh" 2>/dev/null; then
  err "runner script'lerinde CRLF satir sonu var — bash bunlari calistiramaz."
  err "  git config core.autocrlf input"
  err "  sed -i 's/\\r\$//' run-issues.sh runner/*.sh"
  rc=1
else
  ok "satir sonlari (LF)"
fi

log ""
log "── Repo ────────────────────────────────────────────"
if [[ -n "$(git status --porcelain)" ]]; then
  err "calisma agaci kirli. Once commit'le ya da stash'le."; rc=1
else ok "calisma agaci temiz"; fi
git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1 \
  && ok "base dal: $BASE_BRANCH ($(sha_short "$BASE_BRANCH"))" \
  || { err "base dal yok: $BASE_BRANCH"; rc=1; }

log ""
log "── Graf ────────────────────────────────────────────"
"$RUNNER_DIR/graph.sh" validate || rc=1

if (( QUICK )); then
  log ""
  log "── Baseline ────────────────────────────────────────"
  warn "--resume: pahali baseline suite'i atlandi (araç/repo/graf kontrolleri kosuldu)"
  log ""
  if (( rc == 0 )); then ok "hizli preflight temiz"; else err "hizli preflight basarisiz"; fi
  exit $rc
fi

log ""
log "── Baseline (base dal zaten yesil mi?) ─────────────"
# Bu kontrol atlanirsa, kirmizi bir base uzerinde 15 issue haksiz yere fail eder.
baseline_gate() {
  local label="$1" cmd="$2"
  [[ -z "$cmd" ]] && { warn "$label ATLANDI (komut tanimsiz — kapi kalici olarak kapali)"; return 0; }
  if eval "$cmd" >/dev/null 2>&1; then ok "$label yesil"; return 0; fi
  err "$label KIRMIZI — base dalda mevcut hata var, kosu baslatilmamali"
  return 1
}
baseline_gate "test"      "$TEST_CMD"      || rc=1
baseline_gate "lint"      "$LINT_CMD"      || rc=1
baseline_gate "typecheck" "$TYPECHECK_CMD" || rc=1

log ""
log "── Bütce ───────────────────────────────────────────"
spent="$("$RUNNER_DIR/journal.sh" cost)"
ok "issue tavani \$$ISSUE_BUDGET_USD · kosu tavani \$$RUN_BUDGET_USD · simdiye kadar \$$spent"

log ""
if (( rc == 0 )); then ok "preflight temiz — kosu baslatilabilir"
else err "preflight basarisiz — yukaridaki maddeleri duzelt"; fi
exit $rc
