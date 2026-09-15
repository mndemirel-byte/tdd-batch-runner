#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# TDD Batch Runner v2 — yapilandirma
#
# Bu dosya kosu basinda repo DISINA kopyalanir ve yalnizca kopyasi calistirilir.
# Ajanin repo icindeki kopyayi degistirmesi karari etkilemez (bkz. G0).
#
# PROJENE GORE DUZENLEMEN GEREKEN TEK DOSYA BUDUR.
# ---------------------------------------------------------------------------

# --- Dal modeli -------------------------------------------------------------
BASE_BRANCH="${BASE_BRANCH:-main}"
# Integration branch: kosu basinda BASE_BRANCH'ten acilir, her PASS eden issue
# onun ustune commit'lenir. Bagimli issue'lar oncekilerin kodunu gorur.
INTEGRATION_PREFIX="${INTEGRATION_PREFIX:-batch/run-}"
# Her issue kendi worktree'sinde calisir; ajanin yarim isi ana checkout'u kirletmez.
WORKTREE_ROOT="${WORKTREE_ROOT:-.tdd-worktrees}"


# --- Durum ------------------------------------------------------------------
STATE_DIR="${STATE_DIR:-.tdd-state}"
JOURNAL="${JOURNAL:-$STATE_DIR/journal.jsonl}"

# --- Dogrulama komutlari ----------------------------------------------------
# Karsiligi olmayan komutu bos birak (""); kapi ATLANIR ve journal'a
# "skipped" olarak yazilir (sessiz zayiflamayi onlemek icin).
TEST_CMD="${TEST_CMD:-npm test --silent}"
LINT_CMD="${LINT_CMD:-npm run lint --silent}"
TYPECHECK_CMD="${TYPECHECK_CMD:-npm run typecheck --silent}"
BUILD_CMD="${BUILD_CMD:-npm run build --silent}"      # final kapida kullanilir
E2E_CMD="${E2E_CMD:-}"                                # final kapida kullanilir

# Degisen satir coverage'i (G6'). Stdout'a yuzde sayisi basmali.
# ESIK DEGISKENI: COVERAGE_MIN (asagida). Yalnizca `feature` ve `refactor`
# profillerinde uygulanir; content/docs/config profillerinde ATLANIR ve
# journal'a "skipped" yazilir (test uretmeyen issue'da coverage anlamsizdir).
#   jest    : npx jest --coverage --changedSince=<BASE> --coverageReporters=json-summary
#   python  : diff-cover coverage.xml --compare-branch=<BASE> --fail-under=0
# <BASE> yer tutucusu calisma aninda base SHA ile degistirilir.
COVERAGE_CMD="${COVERAGE_CMD:-}"
COVERAGE_MIN="${COVERAGE_MIN:-80}"

# --- Dil/framework desenleri ------------------------------------------------
TEST_FILE_RE="${TEST_FILE_RE:-(\.test\.|\.spec\.|_test\.|/test_|/tests?/)}"

# DIKKAT: bu desenler hem grep -E hem awk tarafindan kullaniliyor. awk'in POSIX
# regex motoru \b (kelime siniri) DESTEKLEMEZ ve sessizce eslesmez. Onun yerine
# (^|[^A-Za-z0-9_]) kalibi kullaniliyor; her iki motorda da calisir.
TEST_DECL_RE="${TEST_DECL_RE:-(^|[^A-Za-z0-9_])(it|test|describe)\(|(^|[^A-Za-z0-9_])(def test_|func Test)}"
SKIP_RE="${SKIP_RE:-(^|[^A-Za-z0-9_])(it|test|describe)\.(skip|todo|only)|(^|[^A-Za-z0-9_])(xit|xdescribe)\(|@pytest\.mark\.skip|@unittest\.skip|(^|[^A-Za-z0-9_])t\.Skip\(}"
NONSRC_RE="${NONSRC_RE:-\.(md|txt|lock|snap)$}"

# --- G0: korumali yollar ----------------------------------------------------
# HARD: dogrulama mekanizmasinin kendisi. Dokunulursa retry'siz fail.
PROTECTED_HARD="${PROTECTED_HARD:-^\.claude/|^runner/|^run-issues\.sh$|^\.tdd-state/|^\.tdd-worktrees/}"

# SIGNAL: mesru olarak degisebilir ama insan onayi ister (dependency ekleme gibi).
# Kontratta allowed_paths ile acikca izin verilmisse uyari uretilmez.
PROTECTED_CONFIG="${PROTECTED_CONFIG:-^package(-lock)?\.json$|^yarn\.lock$|^pnpm-lock\.yaml$|jest\.config\.|vitest\.config\.|^pytest\.ini$|^pyproject\.toml$|^tsconfig|^\.eslintrc|^\.github/|^\.gitlab-ci\.yml$|^Makefile$}"

# --- Issue sozlesmesi -------------------------------------------------------
# Issue dosyalarinin bulundugu dizin. Kayit defteri yok: issue'lar buradan
# alfabetik taranir, bagimliliklar "## Blocked by" bolumunden okunur.
ISSUES_DIR="${ISSUES_DIR:-.scratch/[project-name]/issues}"
PRD_FILE="${PRD_FILE:-.scratch/[project-name]/PRD.md}"

# Issue/PRD dosyalari "kod" sayilmaz: kabul kutusu isaretlemek ve Status
# guncellemek uretim kodu degildir, kapsam ihlali de degildir.
ISSUE_TRACK_RE="${ISSUE_TRACK_RE:-^\.scratch/}"

# --- G14b: kabul kriterlerindeki komutlar ----------------------------------
# Kriter metni GUVENILMEYEN bir girdi yuzeyidir. Onek allowlist'i yetmez:
#   - `npx <paket>` tanimi geregi internetten indirip kod calistirir
#   - `npm run <script>` package.json'a baglidir, o da yalnizca G0b sinyali
# Kombine saldiri: ajan package.json'a masum bir script ekler (kosu durmaz,
# WARN duser), kriterde ona atif yapar, G14b onu "dogrulama adina" calistirir.
#
# Bu yuzden kural TAM ESLESMEDIR: kriterde gecen bir komut, ancak asagidaki
# kumede birebir varsa kosulur. Kumede olmayan komutlar calistirilmaz,
# WARN olarak raporlanir (insan gorur, sistem kosmaz).
ACCEPTANCE_CMDS_EXTRA="${ACCEPTANCE_CMDS_EXTRA:-npm run validate-content
npm run content-status}"

# Shell metakarakteri iceren hicbir komut kosulmaz (tam eslesse bile).
ACCEPTANCE_METACHAR_RE="${ACCEPTANCE_METACHAR_RE:-[;\&\|\`\$\(\)<>]}"

# --- Kapi profilleri (Gates: alani) ----------------------------------------
# Her profil kendi ZORUNLU dogrulama komutunu getirir. Boylece "content"
# issue'larinda dogrulama kriter metnine emanet edilmez.
PROFILE_VERIFY_CONTENT="${PROFILE_VERIFY_CONTENT:-npm run validate-content}"
PROFILE_VERIFY_DOCS="${PROFILE_VERIFY_DOCS:-}"
PROFILE_VERIFY_CONFIG="${PROFILE_VERIFY_CONFIG:-}"

# HITL (insan katilimi gereken) issue'lar otonom kosuda calistirilmaz.
# Tip issue dosyasindaki `Type:` alanindan ya da PRD tablosundan okunur.
SKIP_HITL="${SKIP_HITL:-1}"

# --- Izin (permission) modeli ----------------------------------------------
# Otonom kosu icin ajanin izin sormadan calisabilmesi gerekir. Iki secenek:
#   acceptEdits        — dosya duzenlemeleri otomatik kabul, Bash yine sorar
#   bypassPermissions  — hepsi kabul; YALNIZCA izole worktree + G0 + deny
#                        kurallari birlikteyken savunulabilir
# Ilk kullanimda bypassPermissions interaktif bir onay ister; bir kez
# `claude --permission-mode bypassPermissions` calistirip kabul et.
# Deny kurallari .claude/settings.json icinde tanimlanir (bkz. dokuman §5.3).
PERMISSION_MODE="${PERMISSION_MODE:-acceptEdits}"

# Ajanin kullanabilecegi araclar. Dar tutmak G0'in tamamlayicisidir.
ALLOWED_TOOLS="${ALLOWED_TOOLS:-Bash,Read,Edit,Write,Glob,Grep,Task}"

# --- Kosu limitleri ---------------------------------------------------------
ISSUE_TIMEOUT="${ISSUE_TIMEOUT:-45m}"
MAX_RETRIES="${MAX_RETRIES:-2}"            # Sinif B (duzeltilebilir) icin
CLEANROOM_RETRY="${CLEANROOM_RETRY:-1}"    # Sinif C icin temiz-oda denemesi (0=kapali)
ISSUE_BUDGET_USD="${ISSUE_BUDGET_USD:-5.00}"
RUN_BUDGET_USD="${RUN_BUDGET_USD:-50.00}"
MAX_TURNS="${MAX_TURNS:-60}"
FLAKY_RERUN="${FLAKY_RERUN:-1}"            # G7 kirmizisinda ajansiz bir kez daha kos
