#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# status.sh — issue dosyasindaki `Status:` alanini yonetir.
#
#   status.sh get <issue-path>
#   status.sh set <issue-path> <yeni-durum> [not]
#   status.sh check-acceptance <issue-path>   -> isaretlenmemis kriter var mi
#   status.sh tick-report <issue-path>        -> kriter isaretleme raporu
#
# YASAM DONGUSU
#   ready-for-agent  ──(kosucu)──►  agent-is-working  ──(kapilar PASS)──►  done
#                                          │
#                                          └──(kapilar FAIL)──►  ready-for-agent
#                                                                (ya da needs-human)
#
# NEDEN AJAN DEGIL KOSUCU YAZAR:
# `done` isaretlemek bir KABUL beyanidir. Ajanin kendi isini "done" ilan
# etmesine izin vermek, dogrulama kapilarinin butun amacini ortadan kaldirir.
# Bu yuzden:
#   - `agent-is-working` -> kosucu, ajani baslatmadan once yazar
#   - `done`             -> kosucu, YALNIZCA kapilar PASS verdikten sonra yazar
#   - ajan `Status:` satirina dokunamaz (G0S kapisi bunu zorlar)
#
# Kabul kriteri kutulari (`- [x]`) ise ajanin isidir: her kriteri karsiladigini
# beyan eder. Beyan kanit degildir — kutular isaretli olsa bile kapilar
# kalirsa issue `done` olmaz. Tersi de gecerli: kapilar gecse bile isaretsiz
# kutu varsa issue `done` olmaz (G14).
# ---------------------------------------------------------------------------
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

CMD="${1:-}"; FILE="${2:-}"
[[ -n "$CMD" && -n "$FILE" && -f "$FILE" ]] || { err "kullanim: status.sh <get|set|check-acceptance|tick-report> <issue-path> [deger]"; exit "$EXIT_INFRA"; }

VALID_STATUSES="ready-for-agent agent-is-working done needs-human blocked"

case "$CMD" in

  get)
    sed -n 's/^Status:[[:space:]]*//p' "$FILE" | head -1 \
      | sed -e 's/<!--.*-->//' -e 's/[[:space:]]*$//'
    ;;

  set)
    NEW="${3:?kullanim: status.sh set <path> <durum> [not]}"
    NOTE="${4:-}"
    grep -qw -- "$NEW" <<<"$VALID_STATUSES" || { err "gecersiz durum: $NEW (gecerli: $VALID_STATUSES)"; exit "$EXIT_INFRA"; }

    if grep -qE '^Status:' "$FILE"; then
      # Satiri yerinde degistir. Not varsa yorum olarak eklenir.
      tmp="$(mktemp)"
      if [[ -n "$NOTE" ]]; then
        sed "1,12s|^Status:.*|Status: $NEW  <!-- $(date +%Y-%m-%d\ %H:%M) $NOTE -->|" "$FILE" > "$tmp"
      else
        sed "1,12s|^Status:.*|Status: $NEW|" "$FILE" > "$tmp"
      fi
      cat "$tmp" > "$FILE"; rm -f "$tmp"
    else
      # Status alani yoksa dosyanin basina ekle
      tmp="$(mktemp)"
      { printf 'Status: %s\n\n' "$NEW"; cat "$FILE"; } > "$tmp"
      cat "$tmp" > "$FILE"; rm -f "$tmp"
    fi
    echo "$(basename "$FILE" .md) -> $NEW"
    ;;

  # --- G14'un cekirdegi ------------------------------------------------------
  check-acceptance)
    total="$(grep -cE '^[[:space:]]*- \[[ xX]\]' "$FILE" 2>/dev/null | head -1)"
    done_n="$(grep -cE '^[[:space:]]*- \[[xX]\]' "$FILE" 2>/dev/null | head -1)"
    total="${total:-0}"; done_n="${done_n:-0}"

    if (( total == 0 )); then
      echo "NOACCEPTANCE 0 0"; exit 3      # kriter yok — kosucu uyari uretir
    fi
    if (( done_n < total )); then
      echo "UNCHECKED $done_n $total"; exit 1
    fi
    echo "COMPLETE $done_n $total"; exit 0
    ;;

  tick-report)
    printf 'Kabul kriterleri (%s dosyasi):\n' "$(basename "$FILE")"
    grep -nE '^[[:space:]]*- \[[ xX]\]' "$FILE" | while IFS=: read -r ln rest; do
      if grep -qE '^\s*- \[[xX]\]' <<<"$rest"; then mark="✓"; else mark="✗"; fi
      txt="$(sed -E 's/^[[:space:]]*- \[[ xX]\][[:space:]]*//' <<<"$rest" | cut -c1-70)"
      printf '  %s  satir %-4s %s\n' "$mark" "$ln" "$txt"
    done
    ;;

  *) err "bilinmeyen komut: $CMD"; exit "$EXIT_INFRA" ;;
esac
