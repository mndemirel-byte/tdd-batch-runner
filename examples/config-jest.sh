# Jest/TypeScript projesi icin coverage kapisi (G6~)
# --changedSince degisen satirlari hedefler; json-summary makine-okur cikti verir.

COVERAGE_CMD="npx jest --coverage --changedSince=<BASE> --coverageReporters=json-summary --silent >/dev/null 2>&1 && node -e \"console.log(require(\\\"./coverage/coverage-summary.json\\\").total.lines.pct)\""
COVERAGE_MIN=80
