#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# graph.sh — bagimlilik grafi.
#
#   graph.sh validate          -> kayit defteri + graf saglik kontrolu
#   graph.sh order             -> topolojik sira (id path)
#   graph.sh next              -> siradaki HAZIR issue ("id path" ya da bos)
#   graph.sh blocked <id>      -> <id> fail ederse transitif bloke olanlar
#   graph.sh deps <id>         -> dogrudan bagimliliklar
#
# Kayit defteri (ISSUES_FILE) sadece "hangi issuelar var" bilgisini tutar;
# bagimliliklar issue kontratlarindaki depends_on alanindan okunur. Tek
# kaynak ilkesi: sira iki yerde tanimlanmaz.
#
# "Siradaki" kararini model degil bu script verir. Boylece ajanin
# "sanirim 7. issuedaydik" gibi bir tahmin yurutmesi gerekmez.
# ---------------------------------------------------------------------------
set -uo pipefail
RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RUNNER_DIR/lib.sh"

cd "$(repo_root)" || exit "$EXIT_INFRA"
[[ -d "$ISSUES_DIR" ]] || { err "issue dizini yok: $ISSUES_DIR"; exit "$EXIT_INFRA"; }

# --- Issue'lari dizinden tara ----------------------------------------------
# Ayri bir kayit defteri (ISSUES.txt) YOK: issue dosyalarinin kendisi tek
# dogruluk kaynagidir. Yeni bir issue eklemek = dizine dosya koymak.
# Bagimliliklar "## Blocked by" bolumunden, tip PRD tablosundan okunur.
# IDS[] ve PATHS[] paralel diziler (bash 3.2 uyumu icin assoc dizi yok).
IDS=(); PATHS=()
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  base="$(basename "$f" .md)"
  [[ "$base" == "PRD" || "$base" == "README" ]] && continue
  IDS+=("$base"); PATHS+=("$f")
done < <(find "$ISSUES_DIR" -maxdepth 1 -name '*.md' 2>/dev/null | sort)

# Bagimlilik jetonlari ("01", "08") id onekine cozulur.
_resolve() {
  local tok="$1" i
  for i in "${!IDS[@]}"; do
    [[ "${IDS[$i]}" == "$tok" || "${IDS[$i]}" == "$tok-"* ]] && { printf '%s' "${IDS[$i]}"; return 0; }
  done
  printf '%s' "$tok"; return 1
}

_path_of() {
  local i
  for i in "${!IDS[@]}"; do
    [[ "${IDS[$i]}" == "$1" ]] && { printf '%s' "${PATHS[$i]}"; return 0; }
  done
  return 1
}

_deps_of() {
  local p; p="$(_path_of "$1")" || return 1
  [[ -f "$p" ]] || return 1
  local C_DEPENDS_ON='' tok out=''
  eval "$("$RUNNER_DIR/contract.sh" parse "$p" 2>/dev/null)" || true
  for tok in $C_DEPENDS_ON; do out="$out $(_resolve "$tok")"; done
  printf '%s' "${out# }"
}

_mode_of() {   # afk | hitl
  local p; p="$(_path_of "$1")" || return 1
  local C_MODE=afk
  eval "$("$RUNNER_DIR/contract.sh" parse "$p" 2>/dev/null)" || true
  printf '%s' "$C_MODE"
}

_status_of() {  # journal.sh'den durum: PASSED|FAILED|BLOCKED|PENDING
  "$RUNNER_DIR/journal.sh" status "$1" 2>/dev/null || echo PENDING
}

case "${1:-}" in

  # --- Saglik kontrolu ------------------------------------------------------
  validate)
    rc=0
    # 1) Path'ler var mi
    for i in "${!IDS[@]}"; do
      [[ -f "${PATHS[$i]}" ]] || { err "issue dosyasi yok: ${IDS[$i]} -> ${PATHS[$i]}"; rc=1; }
    done
    # 2) Id tekrari
    dup="$(printf '%s\n' "${IDS[@]}" | sort | uniq -d)"
    [[ -z "$dup" ]] || { err "tekrarli issue id: $dup"; rc=1; }
    # 3) HITL issue'lari raporla
    for id in "${IDS[@]}"; do
      [[ "$(_mode_of "$id")" == "hitl" ]] && warn "HITL issue (otonom kosuda atlanacak): $id"
    done
    # 4) Cozulemeyen bagimlilik jetonu (ornegin PRD'de var, dosyasi yok)
    for id in "${IDS[@]}"; do
      for tok in $(_deps_of "$id"); do
        _path_of "$tok" >/dev/null || { err "$id -> cozulemeyen bagimlilik: $tok"; rc=1; }
      done
    done
    # 5) Cevrim tespiti (Kahn)
    cycle="$(
      for id in "${IDS[@]}"; do printf '%s\t%s\n' "$id" "$(_deps_of "$id")"; done | awk -F'\t' '
        { node[$1]=1; deps[$1]=$2 }
        END {
          changed = 1
          while (changed) {
            changed = 0
            for (n in node) {
              if (done_[n]) continue
              ready = 1
              split(deps[n], D, " ")
              for (i in D) if (D[i] != "" && !done_[D[i]]) ready = 0
              if (ready) { done_[n] = 1; changed = 1 }
            }
          }
          for (n in node) if (!done_[n]) printf "%s ", n
        }'
    )"
    [[ -z "$cycle" ]] || { err "bagimlilik grafinda cevrim: $cycle"; rc=1; }
    # 6) Kabul kriteri olmayan issue uyarisi — "done" tanimi belirsiz demektir
    for i in "${!IDS[@]}"; do
      [[ -f "${PATHS[$i]}" ]] || continue
      local_out="$("$RUNNER_DIR/contract.sh" parse "${PATHS[$i]}" 2>/dev/null)"
      grep -q "C_NOACCEPTANCE" <<<"$local_out" && warn "kabul kriteri olmayan issue: ${IDS[$i]}"
    done
    (( rc == 0 )) && ok "graf gecerli — ${#IDS[@]} issue"
    exit $rc
    ;;

  # --- Topolojik sira -------------------------------------------------------
  order)
    remaining=("${IDS[@]}"); emitted=""
    while (( ${#remaining[@]} > 0 )); do
      progressed=0; next_remaining=()
      for id in "${remaining[@]}"; do
        ready=1
        for d in $(_deps_of "$id"); do
          [[ " $emitted " == *" $d "* ]] || ready=0
        done
        if (( ready )); then
          printf '%s %s\n' "$id" "$(_path_of "$id")"
          emitted="$emitted $id"; progressed=1
        else
          next_remaining+=("$id")
        fi
      done
      (( progressed )) || { err "cevrim: ${next_remaining[*]}"; exit "$EXIT_INFRA"; }
      remaining=("${next_remaining[@]:-}")
      [[ -z "${remaining[0]:-}" ]] && break
    done
    ;;

  # --- Siradaki hazir issue -------------------------------------------------
  # Hazir = PENDING + tum bagimliliklari PASSED. Cikti bossa yapilacak is yok.
  next)
    while read -r id path; do
      [[ -z "${id:-}" ]] && continue
      st="$(_status_of "$id")"
      # BLOCKED turetilmis bir durumdur: bagimliligi sonradan PASSED olursa
      # issue yeniden uygun hale gelir. SKIPPED (HITL / kriter yok) ve
      # FAILED yapisaldir, kendiliginden acilmaz.
      [[ "$st" == "PENDING" || "$st" == "BLOCKED" ]] || continue
      # HITL issue'lar otonom kosuda calistirilmaz.
      if [[ "${SKIP_HITL:-1}" == "1" && "$(_mode_of "$id")" == "hitl" ]]; then continue; fi
      ready=1
      for d in $(_deps_of "$id"); do
        [[ "$(_status_of "$d")" == "PASSED" ]] || ready=0
      done
      (( ready )) && { printf '%s %s\n' "$id" "$path"; exit 0; }
    done < <("$0" order)
    exit 0
    ;;

  # --- Transitif bloke olanlar ----------------------------------------------
  blocked)
    target="${2:?kullanim: graph.sh blocked <id>}"
    frontier="$target"; blocked=""
    while [[ -n "$frontier" ]]; do
      new=""
      for id in "${IDS[@]}"; do
        [[ " $blocked " == *" $id "* ]] && continue
        [[ "$id" == "$target" ]] && continue
        for d in $(_deps_of "$id"); do
          if [[ " $frontier " == *" $d "* ]]; then
            new="$new $id"; blocked="$blocked $id"; break
          fi
        done
      done
      frontier="$new"
    done
    printf '%s\n' $blocked
    ;;

  deps) _deps_of "${2:?kullanim: graph.sh deps <id>}"; echo ;;

  mode) _mode_of "${2:?kullanim: graph.sh mode <id>}"; echo ;;

  hitl) for id in "${IDS[@]}"; do [[ "$(_mode_of "$id")" == "hitl" ]] && echo "$id"; done ;;

  *) err "kullanim: graph.sh <validate|order|next|blocked|deps|mode|hitl>"; exit "$EXIT_INFRA" ;;
esac
