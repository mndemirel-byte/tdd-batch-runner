#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# verify.sh — kabul kapisi.
#
#   verify.sh <issue-id> <issue-path> <base-sha>
#
# CIKIS KODU = KARAR SINIFI (kosucu metin ayristirmaz):
#   0  PASS   — gecti (WARN'lar olabilir)
#   1  RETRY  — Sinif B, duzeltilebilir; fresh ajanla tekrar denenebilir
#   2  HARD   — Sinif C, politika ihlali; kirli workspace atilir
#   4  INFRA  — Sinif A, arac/config/repo sorunu; ajanin hatasi degil
#
# TASARIM ILKESI: ajanin raporuna degil, reponun gozlemlenebilir durumuna
# bakar. Olasiliksal dogrulama (model review) bu kapinin YERINI tutamaz,
# ancak ONUNE eklenebilir — reviewer advisory, verify authoritative.
#
# KAPI SEVIYELERI (review §2.3):
#   [hard]   kesin ihlal        -> retry yok
#   [retry]  duzeltilebilir     -> fresh ajanla tekrar
#   [signal] supheli, kanit degil -> WARN + inceleme kuyrugu, kosuyu durdurmaz
#
# NE KANITLAR, NE KANITLAMAZ:
# Bu kapilar "yaygin test manipulasyon bicimlerini yakalar ve riski azaltir".
# "Test kumesinin zayiflamadigini KANITLAMAZ" — ornegin
#   const expected = result.status; expect(result.status).toBe(expected)
# butun kapilardan gecer. Semantik dogrulama icin kontrat + reviewer gerekir.
# ---------------------------------------------------------------------------
set -uo pipefail
RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RUNNER_DIR/lib.sh"

ID="${1:-}"; ISSUE_PATH="${2:-}"; BASE_REF="${3:-}"
[[ -n "$ID" && -n "$BASE_REF" ]] || { err "kullanim: verify.sh <id> <issue-path> <base-sha>"; exit "$EXIT_INFRA"; }

cd "$(repo_root)" || exit "$EXIT_INFRA"
git cat-file -e "$BASE_REF^{commit}" 2>/dev/null || { err "base sha gecersiz: $BASE_REF"; exit "$EXIT_INFRA"; }

GATES=""; WARNS=0
gate()  { GATES="${GATES}${GATES:+,}$1=$2"; }
pass()  { gate "$1" pass; log "GATE $1 pass ${2:-}"; }
skip()  { gate "$1" skipped; log "GATE $1 skipped ${2:-}"; }
sig()   { gate "$1" warn; WARNS=$((WARNS+1)); warn "GATE $1 $2"; }
die()   { gate "$1" fail; log "GATE $1 fail $3"; log "RESULT $2"; log "GATES $GATES"; exit "$( [[ $2 == hard ]] && echo "$EXIT_HARD" || echo "$EXIT_RETRY" )"; }

# --- Kontrati yukle ---------------------------------------------------------
C_TYPE=feature; C_ALLOWED_PATHS=''; C_FORBIDDEN_PATHS=''; C_VERIFICATION=''; C_NOCONTRACT=''
if [[ -n "$ISSUE_PATH" && -f "$ISSUE_PATH" ]]; then
  eval "$("$RUNNER_DIR/contract.sh" parse "$ISSUE_PATH")" || true
fi
[[ -n "$C_NOCONTRACT" ]] && sig contract "kontratsiz issue, feature varsayiliyor"

# Tip -> hangi kapilar uygulanir. docs issuesuna "test eklenmemis" demek
# yanlis pozitiftir; tip alani bu sinifi tamamen bitirir.
NEED_TEST=1; NEED_SRC=1; NEED_GROWTH=1; NEED_COV=1; PROFILE_VERIFY=""
case "$C_TYPE" in
  docs)     NEED_TEST=0; NEED_SRC=0; NEED_GROWTH=0; NEED_COV=0; PROFILE_VERIFY="${PROFILE_VERIFY_DOCS:-}" ;;
  config)   NEED_TEST=0; NEED_SRC=0; NEED_GROWTH=0; NEED_COV=0; PROFILE_VERIFY="${PROFILE_VERIFY_CONFIG:-}" ;;
  # content: uretim dosyasi uretir (stub'lar) ama birim testi uretmez.
  # Coverage anlamsizdir; dogrulama profilin ZORUNLU komutuyla yapilir.
  content)  NEED_TEST=0; NEED_GROWTH=0; NEED_COV=0; PROFILE_VERIFY="${PROFILE_VERIFY_CONTENT:-}" ;;
  refactor) NEED_TEST=0; NEED_GROWTH=0 ;;   # davranis degismemeli, test artmayabilir
  chore)    NEED_TEST=0; NEED_GROWTH=0; NEED_COV=0 ;;
esac

# Calisma agacini indeksle: commit'li ve commit'siz degisiklikler ayni sekilde
# degerlendirilsin (commit'i kosucu atar — tek commit otoritesi).
git add -A >/dev/null 2>&1
CHANGED_ALL="$(git diff --cached --name-only "$BASE_REF")"

# Issue dosyalari kod degildir. Ajan kabul kutularini isaretler, kosucu
# Status alanini gunceller — bunlarin hicbiri "uretim kodu yazildi" ya da
# "kapsam disina cikildi" anlamina gelmemeli. Bu yuzden kod kapilari
# (G0c, G1-G3, G6) issue dosyalarini haric tutan listeyi kullanir.
CHANGED="$(grep -vE "${ISSUE_TRACK_RE:-^$}" <<<"$CHANGED_ALL" || true)"

# =========================================================================
# G0 — ANTI-TAMPER (hard). ILK kapi olmasi kritik: dogrulama mekanizmasina
# dokunulmussa diger kapilarin sonucu zaten anlamsizdir.
# Not: bu script repo DISINDAKI salt-okunur kopyadan calisir; asagidaki
# kontrol repo ici kopyanin degistirilmesini de raporlamak icindir.
# =========================================================================
TAMPERED="$(grep -E "$PROTECTED_HARD" <<<"$CHANGED_ALL" || true)"
[[ -z "$TAMPERED" ]] || die G0 hard "dogrulama altyapisina dokunulmus: $(tr '\n' ' ' <<<"$TAMPERED")"
pass G0

# G0b — config dosyalari (signal). Bazi issuelar mesru olarak dependency
# ekler; bu yuzden kesin yasak degil, insan onayi zorunlulugu.
CFG="$(grep -E "$PROTECTED_CONFIG" <<<"$CHANGED" || true)"
if [[ -n "$CFG" ]]; then
  allowed=1
  for f in $CFG; do
    hit=0
    for pat in $C_ALLOWED_PATHS; do [[ "$f" == $pat ]] && hit=1; done
    (( hit )) || allowed=0
  done
  if (( allowed )); then pass G0b "kontratla izinli"
  else sig G0b "config dosyasi degismis, insan onayi gerekir: $(tr '\n' ' ' <<<"$CFG")"; fi
else pass G0b; fi

# G0c — kontrat kapsami (hard). allowed_paths tanimliysa disina cikilamaz.
if [[ -n "$C_ALLOWED_PATHS" ]]; then
  OUT=""
  for f in $CHANGED; do
    hit=0
    for pat in $C_ALLOWED_PATHS; do [[ "$f" == $pat ]] && hit=1; done
    (( hit )) || OUT="$OUT $f"
  done
  [[ -z "$OUT" ]] || die G0c hard "kontrat kapsami disina cikilmis:$OUT"
  pass G0c
else skip G0c "kontratta allowed_paths yok"; fi

if [[ -n "$C_FORBIDDEN_PATHS" ]]; then
  for f in $CHANGED; do
    for pat in $C_FORBIDDEN_PATHS; do
      [[ "$f" == $pat ]] && die G0d hard "kontratta yasaklanmis dosya degismis: $f"
    done
  done
  pass G0d
fi

# =========================================================================
# G1-G3 — degisiklik varligi (retry)
# =========================================================================
[[ -n "$CHANGED" ]] || die G1 retry "hicbir dosya degismemis"
pass G1

if (( NEED_TEST )); then
  grep -qE "$TEST_FILE_RE" <<<"$CHANGED" || die G2 retry "hicbir test dosyasi eklenmemis/degistirilmemis"
  pass G2
else skip G2 "type=$C_TYPE"; fi

if (( NEED_SRC )); then
  grep -vE "$TEST_FILE_RE" <<<"$CHANGED" | grep -vE "$NONSRC_RE" | grep -q . \
    || die G3 retry "sadece test/dokuman degismis, uretim kodu yok"
  pass G3
else skip G3 "type=$C_TYPE"; fi

# =========================================================================
# G4/G5 — sabotaj izleri. Diff'te dosya bazli tarama.
# =========================================================================
read -r ADDED_SKIP REMOVED_DECL ADDED_DECL <<<"$(
  git diff --cached "$BASE_REF" | awk \
    -v tf="$(esc "$TEST_FILE_RE")" -v skip="$(esc "$SKIP_RE")" -v decl="$(esc "$TEST_DECL_RE")" '
      /^\+\+\+ b\// { f=substr($0,7); istest=(f ~ tf); next }
      /^--- / { next }
      !istest { next }
      /^\+/ && $0 ~ skip { s++ }
      /^-/  && $0 ~ decl { r++ }
      /^\+/ && $0 ~ decl { a++ }
      END { print s+0, r+0, a+0 }'
)"

# G4 — atlatilmis test eklenmis (hard). Kesin ihlal, tartisilmaz.
(( ADDED_SKIP == 0 )) || die G4 hard "atlatilmis test eklenmis (.skip/.only/xit) — adet: $ADDED_SKIP"
pass G4

# G5a — test dosyasi tamamen silinmis ya da NET test kaybi (hard).
DELETED_TEST_FILES="$(git diff --cached --diff-filter=D --name-only "$BASE_REF" | grep -E "$TEST_FILE_RE" || true)"
[[ -z "$DELETED_TEST_FILES" ]] || die G5a hard "test dosyasi silinmis: $(tr '\n' ' ' <<<"$DELETED_TEST_FILES")"
if (( REMOVED_DECL > ADDED_DECL )); then
  die G5a hard "net test kaybi: $REMOVED_DECL silindi, $ADDED_DECL eklendi"
fi
pass G5a

# G5b — test satiri modifiye edilmis (signal). Diff mantiginda bir satiri
# DEGISTIRMEK = silmek + eklemek oldugundan, mesru rename/tasima/refactor da
# buraya duser. Bu yuzden hard degil sinyal: dal inceleme kuyruguna girer.
if (( REMOVED_DECL > 0 )); then
  sig G5b "mevcut test satirlari degismis ($REMOVED_DECL silindi / $ADDED_DECL eklendi) — inceleme gerek"
else pass G5b; fi

# =========================================================================
# G6 — test sayisi (SIGNAL, hard degil).
# Iki yonde de yanilir: mevcut bir teste yeni assertion eklemek sayiyi
# artirmaz (yanlis pozitif); iki tautolojik it("dummy") eklemek artirir
# (yanlis negatif). test.each tablosuna satir eklemek de sayiyi degistirmez.
# Bu yuzden kanit degil sinyaldir. Gercek kanit G6' coverage'dir.
# =========================================================================
count_tests_at_rev() {
  local rev="$1" total=0 n f
  while IFS= read -r f; do
    [[ "$f" =~ $TEST_FILE_RE ]] || continue
    n="$(git show "$rev:$f" 2>/dev/null | grep -cE "$TEST_DECL_RE" || true)"
    total=$(( total + n ))
  done < <(git ls-tree -r --name-only "$rev")
  echo "$total"
}
count_tests_in_worktree() {
  local total=0 n f
  while IFS= read -r f; do
    [[ "$f" =~ $TEST_FILE_RE ]] || continue
    [[ -f "$f" ]] || continue
    n="$(grep -cE "$TEST_DECL_RE" "$f" || true)"
    total=$(( total + n ))
  done < <(git ls-files --cached)
  echo "$total"
}
BEFORE="$(count_tests_at_rev "$BASE_REF")"; AFTER="$(count_tests_in_worktree)"
if (( NEED_GROWTH )); then
  if (( AFTER > BEFORE )); then pass G6 "($BEFORE -> $AFTER)"
  else sig G6 "test sayisi artmamis ($BEFORE -> $AFTER) — inceleme gerek"; fi
else skip G6 "type=$C_TYPE"; fi

# =========================================================================
# G7-G9 — deterministik komutlar (retry)
# =========================================================================
run_gate() {  # run_gate <ad> <komut> [flaky_rerun]
  local label="$1" cmd="$2" flaky="${3:-0}" out
  [[ -z "$cmd" ]] && { skip "$label" "komut tanimsiz"; return 0; }
  if out="$(eval "$cmd" 2>&1)"; then pass "$label"; return 0; fi
  if (( flaky )) && (( FLAKY_RERUN )); then
    # Ajan cagirmadan bir kez daha kos: flaky test icin ucuz sigorta.
    if out="$(eval "$cmd" 2>&1)"; then sig "$label" "ilk kosuda kirmizi, ikincide yesil — FLAKY"; return 0; fi
  fi
  echo "----- $label ciktisi (son 40 satir) -----" >&2
  tail -40 <<<"$out" >&2
  die "$label" retry "komut basarisiz"
}

# Profilin ZORUNLU dogrulama komutu. content issue'larinda dogrulama
# kriter metnine emanet edilmez: profil kendi kapisini getirir.
if [[ -n "$PROFILE_VERIFY" ]]; then run_gate "G7p" "$PROFILE_VERIFY"
else skip G7p "profil=$C_TYPE icin zorunlu komut tanimsiz"; fi

# Kontratta issueya ozel hedefli test varsa once o kosulur (hizli geri bildirim).
[[ -n "$C_VERIFICATION" ]] && run_gate G7a "$C_VERIFICATION" 1
run_gate G7 "$TEST_CMD" 1
run_gate G8 "$LINT_CMD"
run_gate G9 "$TYPECHECK_CMD"

# =========================================================================
# G6' — degisen satir coverage'i (KAPI, G6'nin gercek halefi).
# "Yeni uretim kodunun her satiri en az bir test tarafindan calistirildi mi"
# sorusu, "test sayisi arttir mi"dan katbekat guclu bir kanittir ve
# tautolojik-ama-kodu-calistirmayan testleri dolayli olarak eler.
# =========================================================================
if [[ -n "$COVERAGE_CMD" ]] && (( NEED_COV )); then
  cov_cmd="${COVERAGE_CMD//<BASE>/$BASE_REF}"
  if cov_out="$(eval "$cov_cmd" 2>&1)"; then
    pct="$(grep -oE '[0-9]+(\.[0-9]+)?' <<<"$cov_out" | tail -1)"
    if [[ -z "$pct" ]]; then sig G6cov "coverage ciktisi ayristirilamadi"
    elif awk "BEGIN{exit !($pct < $COVERAGE_MIN)}"; then
      die G6cov retry "degisen satir coverage'i dusuk: %$pct < %$COVERAGE_MIN"
    else pass G6cov "%$pct"; fi
  else sig G6cov "coverage komutu calismadi"; fi
elif (( ! NEED_COV )); then skip G6cov "type=$C_TYPE (coverage bu profilde uygulanmaz)"
else skip G6cov "COVERAGE_CMD tanimsiz"; fi

# =========================================================================
# G14 — KABUL KRITERLERI. Projenin "done" tanimi budur: bir issue ancak
# TUM acceptance criteria karsilandiginda done olabilir.
#
# Uc parcali:
#   G14a  isaretlenmemis kutu kalmamis mi        (ajanin beyani)
#   G14b  kriterlerdeki komutlar gercekten kosuldu mu  (deterministik kanit)
#   G14c  ajan kriter METNINI degistirmemis mi   (hard — kriter silerek
#         "hepsi karsilandi" yapmak en kolay kacamaktir)
#
# Beyan (kutu isareti) kanit degildir: kutular isaretli olsa bile diger
# kapilar kalirsa issue done olmaz. Tersi de gecerli: kapilar gecse bile
# isaretsiz kutu varsa done olmaz.
# =========================================================================
if [[ -n "$ISSUE_PATH" && -f "$ISSUE_PATH" ]]; then

  # --- G14c: kriter metni oynanmis mi (hard) ---
  # Issue dosyasi worktree icinde de olabilir; base'deki haliyle karsilastir.
  ISSUE_REL="$(git ls-files --full-name -- "$ISSUE_PATH" 2>/dev/null | head -1)"
  if [[ -n "$ISSUE_REL" ]] && git cat-file -e "$BASE_REF:$ISSUE_REL" 2>/dev/null; then
    base_crit="$(git show "$BASE_REF:$ISSUE_REL" | sed -nE 's/^[[:space:]]*- \[[ xX]\][[:space:]]*//p' | sort)"
    head_crit="$(sed -nE 's/^[[:space:]]*- \[[ xX]\][[:space:]]*//p' "$ISSUE_PATH" | sort)"
    if [[ "$base_crit" != "$head_crit" ]]; then
      die G14c hard "kabul kriterlerinin METNI degistirilmis — kriter eklemek/silmek/yeniden yazmak yasak"
    fi
    # Status satirini KOSUCU yonetir. Verify aninda degeri tam olarak
    # "agent-is-working" olmali: kosucu ajani baslatmadan once boyle yazdi.
    # Baska bir deger, ajanin kendi kabulunu ilan ettigi anlamina gelir —
    # ki bu butun dogrulama zincirinin amacini ortadan kaldirir.
    cur_status="$("$RUNNER_DIR/status.sh" get "$ISSUE_PATH")"
    exp_status="${TDD_EXPECTED_STATUS:-agent-is-working}"
    if [[ "$cur_status" != "$exp_status" ]]; then
      die G14d hard "Status satiri ajan tarafindan degistirilmis: '$cur_status' (beklenen '$exp_status') — durumu kosucu yonetir"
    fi
    pass G14d
    pass G14c
  else
    skip G14c "issue dosyasi git'te izlenmiyor"
  fi

  # --- G14a: isaretlenmemis kriter (retry) ---
  acc_out="$("$RUNNER_DIR/status.sh" check-acceptance "$ISSUE_PATH")"; acc_code=$?
  case $acc_code in
    0) pass G14a "$(awk '{print $2"/"$3}' <<<"$acc_out") kriter isaretli" ;;
    3) sig G14a "issue'da kabul kriteri yok — done tanimi belirsiz" ;;
    *) die G14a retry "kabul kriterleri eksik: $(awk '{print $2"/"$3}' <<<"$acc_out") isaretli" ;;
  esac

  # --- G14b: kriterlerde adi gecen komutlar (retry) ---
  # "npm test geciyor" yazan bir kriter, komut calistirilmadan karsilanmis
  # sayilamaz. Ajanin kutuyu isaretlemis olmasi yeterli degildir.
  # Kosulmasina IZIN VERILEN komut kumesi: config'te tanimli olanlar.
  # Kriter metninden gelen bir dize, ancak bu kumede BIREBIR varsa kosulur.
  ALLOWED_SET="$(printf '%s\n%s\n%s\n%s\n%s\n' \
      "$TEST_CMD" "$LINT_CMD" "$TYPECHECK_CMD" "$BUILD_CMD" "$ACCEPTANCE_CMDS_EXTRA" \
      | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$' | sort -u)"

  norm() { sed -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//' <<<"$1"; }

  ACC_CMDS="$("$RUNNER_DIR/contract.sh" commands "$ISSUE_PATH" 2>/dev/null || true)"
  if [[ -n "$ACC_CMDS" ]]; then
    n=0; skipped_cmds=""
    while IFS= read -r c; do
      [[ -z "$c" ]] && continue
      cn="$(norm "$c")"

      # (a) Shell metakarakteri iceren hicbir sey kosulmaz.
      if grep -qE "$ACCEPTANCE_METACHAR_RE" <<<"$cn"; then
        die G14b hard "kriterde shell metakarakteri iceren komut var, calistirilmadi: $cn"
      fi

      # (b) Yalnizca config'te tanimli komutlarla TAM ESLESME kosulur.
      matched=0
      while IFS= read -r a; do
        [[ "$(norm "$a")" == "$cn" ]] && { matched=1; break; }
      done <<<"$ALLOWED_SET"

      if (( matched )); then
        n=$((n+1)); run_gate "G14b.$n" "$cn"
      else
        skipped_cmds="$skipped_cmds | $cn"
      fi
    done <<<"$ACC_CMDS"

    [[ -n "$skipped_cmds" ]] && sig G14b "kriterde gecen ama config'te tanimli olmayan komutlar KOSULMADI:$skipped_cmds"
    (( n > 0 )) && pass G14b "$n komut kosuldu" || skip G14b "eslesen komut yok"
  else
    skip G14b "kriterlerde calistirilabilir komut yok"
  fi
else
  skip G14 "issue dosyasi verilmedi"
fi

log "RESULT pass"
log "GATES $GATES"
log "SUMMARY $ID: $(wc -l <<<"$CHANGED") dosya, test $BEFORE -> $AFTER, $WARNS uyari"
exit "$EXIT_PASS"
