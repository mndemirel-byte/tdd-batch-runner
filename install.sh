#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# install.sh — TDD Batch Runner v3 bootstrap.
#
# Paketin mekanik kurulum adimlarini deterministik olarak yapar:
#   dosya kopyalama, chmod, .gitignore, satir sonu kontrolu, arac kontrolu.
#
# YAPMADIGI SEY: config.sh'yi doldurmak. O adim projeye ozeldir ve
# KURULUM.md §2'deki prompt ile Claude Code'a yaptirilir.
#
# Kullanim (proje kokunden):
#   bash <paket-yolu>/install.sh
#   bash <paket-yolu>/install.sh --dry-run
#
# Windows: Git Bash icinde calistir. CMD/PowerShell desteklenmez.
# ---------------------------------------------------------------------------
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

c_ok()   { printf '\033[32mOK  \033[0m %s\n' "$*"; }
c_warn() { printf '\033[33mUYARI\033[0m %s\n' "$*"; }
c_err()  { printf '\033[31mHATA\033[0m %s\n' "$*" >&2; }
run()    { if (( DRY )); then echo "  [dry-run] $*"; else eval "$@"; fi; }

rc=0

# --- 0. Proje koku mu? ------------------------------------------------------
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  c_err "git deposu degil. Proje kokunde calistir."; exit 1; }
cd "$ROOT" || exit 1
echo "Proje koku : $ROOT"
echo "Paket      : $SRC"
(( DRY )) && echo "MOD        : dry-run (hicbir sey degistirilmeyecek)"
echo

# --- 1. Ortam ---------------------------------------------------------------
echo "── Ortam ───────────────────────────────────────────"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) c_ok "Git Bash / MSYS ortami" ;;
  Linux|Darwin)         c_ok "$(uname -s)" ;;
  *)                    c_warn "bilinmeyen ortam: $(uname -s)" ;;
esac

for t in claude jq git awk; do
  command -v "$t" >/dev/null 2>&1 && c_ok "$t" || { c_err "$t bulunamadi"; rc=1; }
done

# GNU timeout mu? (Windows System32\timeout.exe bir BEKLEME komutudur)
if command -v gtimeout >/dev/null 2>&1 && gtimeout --version 2>/dev/null | grep -qi coreutils; then
  c_ok "gtimeout (GNU coreutils)"
elif command -v timeout >/dev/null 2>&1 && timeout --version 2>/dev/null | grep -qi coreutils; then
  c_ok "timeout (GNU coreutils)"
else
  c_warn "GNU timeout yok — issue zaman asimi UYGULANMAYACAK"
  command -v timeout >/dev/null 2>&1 && \
    c_warn "  PATH'teki 'timeout' GNU degil (Windows System32 olabilir)"
  c_warn "  macOS: brew install coreutils"
fi

if [[ -d .claude/skills/tdd ]]; then
  c_ok "/tdd skill'i projede zaten var"
elif [[ -d "$SRC/.claude/skills/tdd" ]]; then
  c_ok "/tdd skill'i pakette var — asagida kurulacak"
else
  c_warn "/tdd skill'i yok — implementer '/tdd' komutunu genisletemez"
fi
echo

# --- 2. Satir sonlari -------------------------------------------------------
echo "── Satir sonlari ───────────────────────────────────"
crlf=0
for f in "$SRC"/run-issues.sh "$SRC"/runner/*.sh; do
  if grep -qU $'\r' "$f" 2>/dev/null; then crlf=1; c_err "CRLF: $(basename "$f")"; fi
done
if (( crlf )); then
  c_err "Paket dosyalarinda CRLF var. Duzelt:"
  c_err "  git config core.autocrlf input"
  c_err "  sed -i 's/\\r\$//' $SRC/run-issues.sh $SRC/runner/*.sh"
  rc=1
else
  c_ok "hepsi LF"
fi
echo

# --- 3. Dosya yerlesimi -----------------------------------------------------
echo "── Dosyalar ────────────────────────────────────────"
copy_guard() {  # copy_guard <kaynak> <hedef>
  local s="$1" d="$2"
  if [[ -e "$d" ]]; then
    if diff -q "$s" "$d" >/dev/null 2>&1; then c_ok "$d (zaten ayni)"
    else c_warn "$d ZATEN VAR ve FARKLI — atlandi, elle karsilastir"; fi
    return
  fi
  run "mkdir -p '$(dirname "$d")'"
  run "cp '$s' '$d'"
  c_ok "$d"
}

run "mkdir -p runner .claude/agents .claude/skills/implement-all"
for f in "$SRC"/runner/*.sh; do copy_guard "$f" "runner/$(basename "$f")"; done
for f in "$SRC"/.claude/agents/*.md; do copy_guard "$f" ".claude/agents/$(basename "$f")"; done
copy_guard "$SRC/.claude/skills/implement-all/SKILL.md" ".claude/skills/implement-all/SKILL.md"
copy_guard "$SRC/run-issues.sh" "run-issues.sh"

# /tdd skill'i: implementer'in sert bagimliligi. Projede zaten varsa
# copy_guard dokunmaz, farkliysa uyarir.
if [[ -d "$SRC/.claude/skills/tdd" ]]; then
  run "mkdir -p .claude/skills/tdd"
  for f in "$SRC"/.claude/skills/tdd/*.md; do
    copy_guard "$f" ".claude/skills/tdd/$(basename "$f")"
  done
fi
echo

# --- 4. Calistirma izinleri -------------------------------------------------
# Indirilen paketlerde exec biti korunmaz; bu adim atlanirsa "Permission
# denied" alinir. Windows'ta ayrica git'e de yazmak gerekir.
echo "── Izinler ─────────────────────────────────────────"
run "chmod +x run-issues.sh runner/*.sh"
if (( ! DRY )); then
  ok_x=1
  for f in run-issues.sh runner/*.sh; do [[ -x "$f" ]] || { ok_x=0; c_err "calistirilamiyor: $f"; }; done
  (( ok_x )) && c_ok "run-issues.sh + $(ls runner/*.sh | wc -l) runner script'i calistirilabilir"
fi
if git config --get core.fileMode 2>/dev/null | grep -q false || [[ "$(uname -s)" == MINGW* ]]; then
  c_warn "Windows: exec biti git'te takip edilmiyor. Commit'lemek icin:"
  c_warn "  git update-index --chmod=+x run-issues.sh runner/*.sh"
fi
echo

# --- 5. .gitignore ----------------------------------------------------------
echo "── .gitignore ──────────────────────────────────────"
for entry in ".tdd-state/" ".tdd-worktrees/"; do
  if grep -qxF "$entry" .gitignore 2>/dev/null; then c_ok "$entry (zaten var)"
  else run "printf '%s\n' '$entry' >> .gitignore"; c_ok "$entry eklendi"; fi
done
echo

# --- 6. Sonraki adim --------------------------------------------------------
echo "════════════════════════════════════════════════════"
if (( rc == 0 )); then
  c_ok "Mekanik kurulum tamam."
  echo
  echo "SIRADAKI ADIM — bunlar projeye ozeldir, elle/Claude ile yapilir:"
  echo "  1. runner/config.sh'yi doldur       ($SRC/docs/KURULUM.md §2 prompt'u)"
  echo "  2. .claude/settings.json deny kurallari ($SRC/examples/settings-deny-rules.json)"
  echo "  3. Icerik ureten issue'lara 'Gates: content' satiri"
  echo "     Issue formati: $SRC/templates/issue-template.md"
  echo
  echo "Sonra dogrula:"
  echo "  runner/graph.sh validate"
  echo "  ./run-issues.sh --dry-run"
else
  c_err "Eksikler var — yukaridaki HATA satirlarini gider."
fi
exit $rc
