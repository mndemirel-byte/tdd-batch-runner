#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# journal.sh — durum defteri (append-only JSONL) + git mutabakati.
#
#   journal.sh record <id> <status> <attempt> <base_sha> <result_sha> <cost> <gates> <note>
#   journal.sh status <id>            -> PASSED|FAILED|BLOCKED|PENDING
#   journal.sh get <id>               -> son kaydin JSON'u
#   journal.sh cost                   -> toplam harcama (USD)
#   journal.sh reconcile <integration-branch>
#   journal.sh report
#   journal.sh reset <id>
#
# NEDEN JOURNAL, NEDEN BAYRAK DOSYASI DEGIL:
# Bayrak dosyasi ("<id>.done") commit ile isaretleme arasinda crash olursa
# yalan soyler. Journal her kayitta result_sha tutar; restart'ta durum git
# gercekligiyle MUTABAKATA sokulur. Dosya sistemine degil git'e guveniriz.
#
# DURABILITY UYARISI: .tdd-state/ yerel kesinti dayanikliligi saglar,
# durability degil. Makine/clone kaybinda kaybolur. Kalici olmasi isteniyorsa
# git notes / CI artifact gibi bir tasiyici gerekir.
# ---------------------------------------------------------------------------
set -uo pipefail
RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RUNNER_DIR/lib.sh"
cd "$(repo_root)" || exit "$EXIT_INFRA"
mkdir -p "$(dirname "$JOURNAL")"
touch "$JOURNAL"

_last() {  # <id> -> son kayit satiri
  grep -F "\"issue\":\"$1\"" "$JOURNAL" 2>/dev/null | tail -1
}

# awk icin ortak alan cikarici. -F'"' ile alan saymak KIRILGANDIR (anahtar i,
# deger i+2 gelir ve bir alan eklenince tum indeksler kayar); bu yuzden
# anahtari isimle arayan bir fonksiyon kullaniyoruz.
_AWK_VAL='
function val(s, k,   re, p, rest, q) {
  re = "\"" k "\":\""
  p = index(s, re)
  if (p == 0) return ""
  rest = substr(s, p + length(re))
  q = index(rest, "\"")
  return substr(rest, 1, q - 1)
}'

case "${1:-}" in

  record)
    id="${2:?}"; status="${3:?}"; attempt="${4:-1}"; base="${5:-}"
    result="${6:-}"; cost="${7:-0}"; gates="${8:-}"; note="${9:-}"
    printf '{"ts":%s,"issue":%s,"status":%s,"attempt":%s,"base_sha":%s,"result_sha":%s,"cost_usd":%s,"gates":%s,"note":%s}\n' \
      "$(json_str "$(date -Iseconds)")" "$(json_str "$id")" "$(json_str "$status")" \
      "$attempt" "$(json_str "$base")" "$(json_str "$result")" "${cost:-0}" \
      "$(json_str "$gates")" "$(json_str "$note")" >> "$JOURNAL"
    ;;

  status)
    line="$(_last "${2:?}")"
    if [[ -z "$line" ]]; then echo PENDING; exit 0; fi
    sed -n 's/.*"status":"\([A-Z]*\)".*/\1/p' <<<"$line"
    ;;

  get) _last "${2:?}" ;;

  cost)
    awk -F'"cost_usd":' 'NF>1 { split($2, a, ","); s += a[1] } END { printf "%.4f\n", s+0 }' "$JOURNAL"
    ;;

  attempts)
    grep -cF "\"issue\":\"${2:?}\"" "$JOURNAL" 2>/dev/null || echo 0
    ;;

  # --- Git ile mutabakat ----------------------------------------------------
  # Iki yonlu tutarsizlik duzeltilir:
  #   a) journal PASSED diyor ama result_sha git'te yok -> kayit gecersiz
  #   b) integration dalinda "TDD-Issue: <id>" trailer'li commit var ama
  #      journal'da PASSED yok -> commit'ten geri kazan
  reconcile)
    branch="${2:?kullanim: journal.sh reconcile <integration-branch>}"
    fixed=0
    # (a) hayali SHA'lar
    while read -r id sha; do
      [[ -z "${sha:-}" ]] && continue
      if ! git cat-file -e "$sha^{commit}" 2>/dev/null; then
        warn "journal'daki commit git'te yok: $id ($sha) -> PENDING'e dusuruldu"
        "$0" record "$id" PENDING 0 "" "" 0 "" "reconcile: kayip commit"
        fixed=$((fixed+1))
      fi
    done < <(awk "$_AWK_VAL"'
               { id = val($0, "issue"); st = val($0, "status"); sha = val($0, "result_sha")
                 last_st[id] = st; last_sha[id] = sha }
               END { for (k in last_st) if (last_st[k] == "PASSED" && last_sha[k] != "") print k, last_sha[k] }
             ' "$JOURNAL")
    # (b) commit var, journal yok
    if git rev-parse --verify "$branch" >/dev/null 2>&1; then
      while read -r sha id; do
        [[ -z "${id:-}" ]] && continue
        if [[ "$("$0" status "$id")" != "PASSED" ]]; then
          warn "commit var ama journal'da yok: $id ($sha) -> PASSED olarak geri kazanildi"
          "$0" record "$id" PASSED 1 "" "$sha" 0 "" "reconcile: commit'ten geri kazanildi"
          fixed=$((fixed+1))
        fi
      done < <(git log "$branch" --format='%H%x09%(trailers:key=TDD-Issue,valueonly)' 2>/dev/null \
                 | awk -F'\t' '$2 != "" { gsub(/[[:space:]]+$/, "", $2); print $1, $2 }')
    fi
    (( fixed == 0 )) && ok "journal git ile tutarli" || ok "mutabakat: $fixed kayit duzeltildi"
    ;;

  report)
    printf '%s\n' "=================================================="
    awk "$_AWK_VAL"'
      { id = val($0, "issue"); if (id != "") last[id] = val($0, "status") }
      END { for (k in last) print last[k] "\t" k }
    ' "$JOURNAL" | sort | awk -F'\t' '
      { cnt[$1]++; list[$1] = list[$1] " " $2 }
      END {
        order[1]="PASSED"; order[2]="FAILED"; order[3]="SKIPPED"; order[4]="BLOCKED"; order[5]="PENDING"
        for (i=1;i<=5;i++) { s=order[i]; if (cnt[s]) printf " %-8s %2d :%s\n", s, cnt[s], list[s] }
      }'
    printf ' %-8s $%s\n' "MALIYET" "$("$0" cost)"
    printf '%s\n' "=================================================="
    ;;

  reset)
    "$0" record "${2:?}" PENDING 0 "" "" 0 "" "elle sifirlandi"
    ok "sifirlandi: $2"
    ;;

  *) err "kullanim: journal.sh <record|status|get|cost|attempts|reconcile|report|reset>"; exit "$EXIT_INFRA" ;;
esac
