# Icerik-agirlikli ornek proje ([project-name]) icin runner/config.sh farklari

ISSUES_DIR=".scratch/[project-name]/issues"
PRD_FILE=".scratch/[project-name]/PRD.md"
ISSUE_TRACK_RE="^\.scratch/"

TEST_CMD="npm test"
LINT_CMD="npm run lint"
TYPECHECK_CMD="npx tsc --noEmit"
BUILD_CMD="npm run build"
E2E_CMD=""                       # varsa doldur; final kapida G12

# G14b: kriterlerde gecen ve KOSULMASINA IZIN VERILEN ek komutlar.
# Tam eslesme aranir; burada olmayan komut calistirilmaz, WARN dusurulur.
ACCEPTANCE_CMDS_EXTRA="npm run validate-content
npm run content-status"

# content profilinin ZORUNLU dogrulama komutu (issue 08-11)
PROFILE_VERIFY_CONTENT="npm run validate-content"

COVERAGE_CMD=""                  # jest changed-since icin bkz. config-jest.sh
COVERAGE_MIN=80

PERMISSION_MODE="acceptEdits"
ALLOWED_TOOLS="Bash,Read,Edit,Write,Glob,Grep,Task"
SKIP_HITL=1

TEST_FILE_RE="(\.test\.|\.spec\.|/__tests__/)"
NONSRC_RE="\.(md|txt|lock|snap)$"
