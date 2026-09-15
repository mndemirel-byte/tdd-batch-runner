#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# contract.sh — issue dosyasindan yurutme kontratini cikarir.
#
#   contract.sh parse <issue-path>       -> eval edilebilir KEY="VALUE"
#   contract.sh acceptance <issue-path>  -> kabul kriterleri (metin)
#   contract.sh acceptance-raw <path>    -> ham checkbox satirlari (satir no ile)
#   contract.sh commands <issue-path>    -> kriterlerden cikarilan komutlar
#
# DESTEKLENEN FORMAT (projenin gercek issue sozlesmesi):
#
#   Status: ready-for-agent | agent-is-working | done | needs-human
#   Gates:  feature | content | docs | config | refactor | chore   (opsiyonel)
#   Type:   AFK | HITL                                             (opsiyonel)
#
#   # 01 — Baslik
#   ## Parent            -> PRD yolu
#   ## What to build
#   ## Acceptance criteria
#   - [ ] ...
#   ## Blocked by
#   01, 02   |   None - can start immediately
#
# YAML frontmatter (--- blogu) da desteklenir; varsa onun alanlari da basilir.
#
# AFK/HITL: issue dosyasinda `Type:` yoksa PRD tablosundan okunur
# (satir: | 05 | ... | 03, 04 | **HITL** |). HITL issue'lar otonom kosuda
# CALISTIRILMAZ — tanimi geregi insan katilimi gerektirirler.
# ---------------------------------------------------------------------------
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

CMD="${1:-}"; FILE="${2:-}"
[[ -n "$CMD" && -n "$FILE" ]] || { err "kullanim: contract.sh <parse|acceptance|acceptance-raw|commands> <issue-path>"; exit "$EXIT_INFRA"; }
[[ -f "$FILE" ]] || { err "issue dosyasi yok: $FILE"; exit "$EXIT_INFRA"; }

ID_FROM_FILE="$(basename "$FILE" .md)"
NUM="$(sed -n 's/^\([0-9][0-9]*\)-.*/\1/p' <<<"$ID_FROM_FILE")"

_section() {  # <dosya> <bolum-basligi-regex> — basliktan sonraki govde
  awk -v pat="$2" '
    $0 ~ "^##+[[:space:]]*" pat { inside=1; next }
    inside && /^##+[[:space:]]/ { exit }
    inside { print }
  ' "$1"
}

_header_field() { head -12 "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1 | sed -e 's/<!--.*-->//' -e 's/[[:space:]]*$//'; }

_frontmatter() { awk 'NR==1 && /^---[[:space:]]*$/ {i=1; next} i && /^---[[:space:]]*$/ {exit} i {print}' "$1"; }

# --- PRD tablosu -----------------------------------------------------------
_prd_row() {
  [[ -n "${PRD_FILE:-}" && -f "${PRD_FILE:-}" && -n "$NUM" ]] || return 1
  grep -E "^\|[[:space:]]*${NUM}[[:space:]]*\|" "$PRD_FILE" | head -1
}
_prd_mode() {
  local row; row="$(_prd_row)" || return 1
  grep -qi 'HITL' <<<"$row" && echo hitl || echo afk
}
_prd_deps() {
  local row; row="$(_prd_row)" || return 1
  awk -F'|' '{ print $4 }' <<<"$row" | grep -oE '[0-9]{2}' | tr '\n' ' '
}

case "$CMD" in

  parse)
    FM="$(_frontmatter "$FILE")"
    if grep -q '[a-zA-Z_]*:' <<<"$FM" 2>/dev/null; then
      printf '%s\n' "$FM" | awk '
        function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/,"",s); return s }
        /^[[:space:]]*#/ { next }
        /^[a-zA-Z_]+[[:space:]]*:/ {
          k=$0; sub(/[[:space:]]*:.*$/,"",k)
          v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); v=trim(v)
          gsub(/^\[|\]$/,"",v); gsub(/,/," ",v); gsub(/"/,"",v)
          if (k=="acceptance") next
          printf "C_%s=\"%s\"\n", toupper(k), v
        }'
    fi

    STATUS="$(_header_field "$FILE" 'Status')"
    GATES="$(_header_field "$FILE" 'Gates')"
    TYPEH="$(_header_field "$FILE" 'Type')"

    BLOCKED="$(_section "$FILE" 'Blocked by' | tr -d '\r')"
    if grep -qiE '(none|yok)' <<<"$BLOCKED"; then
      DEPS=""
    else
      DEPS="$(grep -oE '[0-9]{2}' <<<"$BLOCKED" | sort -u | tr '\n' ' ')"
      # Bolum bos/eksikse PRD tablosuna dus
      [[ -z "${DEPS// /}" ]] && DEPS="$(_prd_deps 2>/dev/null || true)"
    fi

    MODE="$(tr '[:upper:]' '[:lower:]' <<<"${TYPEH}")"
    [[ -z "$MODE" ]] && MODE="$(_prd_mode 2>/dev/null || echo afk)"
    [[ "$MODE" == "hitl" ]] || MODE=afk

    ACC_TOTAL="$(grep -cE '^[[:space:]]*- \[[ xX]\]' "$FILE" 2>/dev/null | head -1)"
    ACC_DONE="$(grep -cE '^[[:space:]]*- \[[xX]\]' "$FILE" 2>/dev/null | head -1)"
    ACC_TOTAL="${ACC_TOTAL:-0}"; ACC_DONE="${ACC_DONE:-0}"
    PARENT="$(_section "$FILE" 'Parent' | grep -oE '[^ `]+\.md' | head -1)"

    printf 'C_ID="%s"\n'         "$ID_FROM_FILE"
    printf 'C_NUM="%s"\n'        "$NUM"
    printf 'C_STATUS="%s"\n'     "${STATUS:-unknown}"
    printf 'C_MODE="%s"\n'       "$MODE"
    printf 'C_TYPE="%s"\n'       "${GATES:-feature}"
    printf 'C_PARENT="%s"\n'     "${PARENT}"
    printf 'C_DEPENDS_ON="%s"\n' "$(sed 's/[[:space:]]*$//' <<<"${DEPS}")"
    printf 'C_ACC_TOTAL="%s"\n'  "${ACC_TOTAL:-0}"
    printf 'C_ACC_DONE="%s"\n'   "${ACC_DONE:-0}"
    [[ "${ACC_TOTAL:-0}" -eq 0 ]] && printf 'C_NOACCEPTANCE="1"\n'
    printf 'C_ALLOWED_PATHS="%s"\n'   "${C_ALLOWED_PATHS:-}"
    printf 'C_FORBIDDEN_PATHS="%s"\n' "${C_FORBIDDEN_PATHS:-}"
    printf 'C_VERIFICATION="%s"\n'    "${C_VERIFICATION:-}"
    ;;

  acceptance)
    _section "$FILE" 'Acceptance criteria' | sed -nE 's/^[[:space:]]*- \[[ xX]\][[:space:]]*//p'
    ;;

  acceptance-raw)
    grep -nE '^[[:space:]]*- \[[ xX]\]' "$FILE" 2>/dev/null || true
    ;;

  commands)
    # Kabul kriterlerindeki backtick'li komut ADAYLARINI cikarir.
    # DIKKAT: burada hicbir guvenlik karari verilmez — bu yalnizca ayristirma.
    # Hangi adayin gercekten kosulacagina verify.sh karar verir (G14b),
    # config.sh'deki komut kumesiyle TAM ESLESME arayarak.
    _section "$FILE" 'Acceptance criteria' \
      | grep -oE '`[^`]+`' | tr -d '`' \
      | grep -E '^(npm|npx|pnpm|yarn|make|pytest|go|cargo|\./)' \
      | sed 's/[[:space:]]*$//' | sort -u
    ;;

  *) err "bilinmeyen komut: $CMD"; exit "$EXIT_INFRA" ;;
esac
