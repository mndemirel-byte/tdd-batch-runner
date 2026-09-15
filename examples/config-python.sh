# Python projesi icin config.sh farklari (config.sh uzerine uygula)

TEST_CMD="pytest -q"
LINT_CMD="ruff check ."
TYPECHECK_CMD="mypy ."
BUILD_CMD=""
COVERAGE_CMD="diff-cover coverage.xml --compare-branch=<BASE> --fail-under=0"
COVERAGE_MIN=80

TEST_FILE_RE="(/test_|_test\.py$|/tests?/)"
TEST_DECL_RE="(^|[^A-Za-z0-9_])def test_"
SKIP_RE="(@pytest\.mark\.skip|@unittest\.skip|(^|[^A-Za-z0-9_])pytest\.skip\()"
NONSRC_RE="\.(md|txt|cfg|ini)$"
PROTECTED_CONFIG="^pyproject\.toml$|^setup\.(py|cfg)$|^pytest\.ini$|^requirements.*\.txt$|^tox\.ini$|^\.github/"
