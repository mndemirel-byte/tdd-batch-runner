#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run-issues.sh — TDD Batch Runner v2
#
#   ./run-issues.sh                  bekleyen tum issuelari isle
#   ./run-issues.sh --limit 2        ilk 2 tanesi (ILK DENEME ICIN)
#   ./run-issues.sh --only 07-api    tek issue (durumu sifirlanarak)
#   ./run-issues.sh --dry-run        plani yazdir, calistirma
#   ./run-issues.sh --resume         mevcut integration dalina devam et
#   ./run-issues.sh --final-only     sadece final entegrasyon kapisini kos
#
# MIMARI
#   main ──> batch/run-<tarih>  (integration branch)
#              │
#              ├─ issue 01: worktree(integration HEAD) -> ajan -> verify -> commit
#              ├─ issue 02: worktree(YENI integration HEAD) -> ...
#              └─ FINAL: temiz klonda tam suit + build + e2e + diff denetimi
#
# Integration branch modeli sayesinde bagimli issuelar oncekilerin kodunu
# gorur. "15 bagimsiz yesil dal" yanilsamasi yoktur; sonda tek dal merge edilir.
#
# UC IZOLASYON BOYUTU (karistirilmamali):
#   conversation  -> her issue icin fresh `claude -p`          [bu script]
#   workspace     -> her issue icin ayri git worktree          [bu script]
#   proje talimatlari -> CLAUDE.md/skills bilincli olarak KORUNUR (--bare YOK)
# ---------------------------------------------------------------------------
set -uo pipefail   # -e YOK: tek issue patlayinca dongu olmesin

REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "git repo degil" >&2; exit 1; }
cd "$REPO"

# --- Dogrulama cekirdegini repo DISINA kopyala ------------------------------
# Ajan repo'ya yazabildigi icin verify.sh/config.sh repo icinde kalirsa
# karar mercii ajanin erisimindedir. Kosu basinda salt-okunur bir kopya
# alinir ve YALNIZCA o calistirilir. (Claude Code v2.1.218'de worktree
# izolasyonlu subagentlarin `git -C`/`GIT_DIR` ile paylasimli checkout'a
# sizabildigi bir hata duzeltildi — fiziksel ayrim bu tur sizintilara karsi
# da tek saglam savunmadir.)
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
export TDD_RUNNER="${TDD_RUNNER:-/tmp/tdd-runner-$RUN_ID}"
if [[ ! -d "$TDD_RUNNER" ]]; then
  mkdir -p "$TDD_RUNNER"
  cp "$REPO/runner"/*.sh "$TDD_RUNNER/" 2>/dev/null || { echo "runner/ bulunamadi" >&2; exit 1; }
  chmod -R a-w "$TDD_RUNNER"
fi
source "$TDD_RUNNER/lib.sh"

# --- Argumanlar -------------------------------------------------------------
LIMIT=0; ONLY=""; DRY=0; RESUME=0; FINAL_ONLY=0; ACCEPT_HITL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit)       LIMIT="$2"; shift 2 ;;
    --only)        ONLY="$2";  shift 2 ;;
    --dry-run)     DRY=1;      shift   ;;
    --resume)      RESUME=1;   shift   ;;
    --final-only)  FINAL_ONLY=1; shift ;;
    --accept-hitl) ACCEPT_HITL="$2"; shift 2 ;;
    -h|--help)    sed -n '3,12p' "$0"; exit 0 ;;
    *) err "bilinmeyen arguman: $1"; exit 2 ;;
  esac
done

mkdir -p "$STATE_DIR/logs" "$STATE_DIR/reviews"

# --- Tek orneklik kilidi ----------------------------------------------------
# Iki kosu ayni journal ve ayni integration dali uzerinde calisirsa durum bozulur.
LOCK="$STATE_DIR/.lock"
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK"
  flock -n 9 || { err "baska bir kosu devam ediyor (kilit: $LOCK)"; exit 1; }
else
  if [[ -f "$LOCK" ]] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
    err "baska bir kosu devam ediyor (pid $(cat "$LOCK"))"; exit 1
  fi
  echo $$ > "$LOCK"; trap 'rm -f "$LOCK"' EXIT
fi

# --- Integration dali -------------------------------------------------------
INTEGRATION_FILE="$STATE_DIR/integration-branch"
if (( RESUME || FINAL_ONLY )) && [[ -f "$INTEGRATION_FILE" ]]; then
  INTEGRATION="$(cat "$INTEGRATION_FILE")"
elif [[ -f "$INTEGRATION_FILE" ]] && (( ! DRY )); then
  INTEGRATION="$(cat "$INTEGRATION_FILE")"
  log "Mevcut integration dali kullaniliyor: $INTEGRATION (yenisi icin .tdd-state/ temizle)"
else
  INTEGRATION="${INTEGRATION_PREFIX}$(date +%Y%m%d-%H%M)"
fi
BASE_SHA="$(git rev-parse "$BASE_BRANCH" 2>/dev/null || echo "")"

# --- Final-only kisayolu ----------------------------------------------------
if (( FINAL_ONLY )); then
  "$TDD_RUNNER/final-gate.sh" "$INTEGRATION" "$BASE_SHA"; exit $?
fi

# --- HITL kabul akisi -------------------------------------------------------
# Insan bir HITL issue'yu bitirdiginde `done` yazma yetkisi yine ona ait
# DEGILDIR: is ayni kapilardan gecer. Fark, isi ajanin degil insanin
# yapmasidir — dogrulama sozlesmesi ayni kalir.
#
#   1. Insan `issue/<id>` dalinda (ya da integration ustunde) isi yapar
#   2. ./run-issues.sh --accept-hitl <id>
#   3. Kapilar PASS -> status done, commit, integration ilerler,
#      bagimlilari otomatik acilir (BLOCKED -> tekrar uygun)
if [[ -n "$ACCEPT_HITL" ]]; then
  read -r HID HPATH <<<"$("$TDD_RUNNER/graph.sh" order | grep -E "^${ACCEPT_HITL}[[:space:]]|^${ACCEPT_HITL}-" | head -1)"
  [[ -n "${HID:-}" ]] || { err "issue bulunamadi: $ACCEPT_HITL"; exit 1; }
  HBASE="$(git rev-parse "$INTEGRATION")"
  log "HITL kabul: $HID"
  log "  kapilar insan isini de ayni sekilde denetler."

  # Insanin biraktigi durum ne olursa olsun beklenen degeri esitle.
  HSTAT="$("$TDD_RUNNER/status.sh" get "$HPATH")"
  TDD_EXPECTED_STATUS="$HSTAT" \
    "$TDD_RUNNER/verify.sh" "$HID" "$HPATH" "$HBASE"; hv=$?
  if (( hv != 0 )); then
    err "HITL isi kapilardan gecemedi (kod $hv) — done yazilmadi"
    exit "$hv"
  fi
  "$TDD_RUNNER/status.sh" set "$HPATH" done "insan tarafindan yapildi, kapilar dogruladi" >/dev/null
  TITLE="$(grep -m1 '^# ' "$HPATH" 2>/dev/null | sed 's/^# *//')"
  git add -A && git commit -q -m "feat($HID): ${TITLE:-$HID}" -m "TDD-Issue: $HID" -m "HITL: insan tarafindan uygulandi"
  RSHA="$(git rev-parse HEAD)"
  "$TDD_RUNNER/journal.sh" record "$HID" PASSED 1 "$HBASE" "$RSHA" 0 "hitl" "insan + kapilar"
  ok "$HID kabul edildi ($(sha_short "$RSHA"))"
  log "Bagimlilari acmak icin: ./run-issues.sh --resume"
  exit 0
fi

# --- Dry-run ----------------------------------------------------------------
# next-issue durumu journal'dan okur; dry-run'da hicbir sey yazilmadigi icin
# dongoye girersek ayni issue sonsuza kadar doner. Bu yuzden ayri yol.
if (( DRY )); then
  log "Integration dali : $INTEGRATION"
  log "Runner kopyasi   : $TDD_RUNNER (salt-okunur)"
  log ""
  log "Topolojik sira ve durumlar:"
  "$TDD_RUNNER/graph.sh" order | while read -r id path; do
    st="$("$TDD_RUNNER/journal.sh" status "$id")"
    deps="$("$TDD_RUNNER/graph.sh" deps "$id")"
    mode="$("$TDD_RUNNER/graph.sh" mode "$id")"
    istat="$("$TDD_RUNNER/status.sh" get "$path" 2>/dev/null)"
    tag=""; [[ "$mode" == "hitl" ]] && tag=" [HITL-ATLANIR]"
    printf '  %-8s %-36s %-16s deps:[%s]%s\n' "$st" "$id" "$istat" "$deps" "$tag"
  done
  log ""
  "$TDD_RUNNER/graph.sh" validate
  exit $?
fi

# --- Preflight --------------------------------------------------------------
# Ucuz kontroller (arac, repo temizligi, graf) HER acilista kosar; yalnizca
# pahali baseline suite'i --resume ile atlanir. Kesinti sirasinda ortam
# bozulmus olabilir (silinen node_modules, degisen base) — araclari hic
# dogrulamadan devam etmek bunu gizler.
if (( RESUME )); then
  "$TDD_RUNNER/preflight.sh" --quick "$INTEGRATION" || { err "preflight (hizli) basarisiz"; exit 1; }
else
  "$TDD_RUNNER/preflight.sh" "$INTEGRATION" || { err "preflight basarisiz, kosu baslatilmadi"; exit 1; }
fi

# --- Integration dalini hazirla --------------------------------------------
if git rev-parse --verify "$INTEGRATION" >/dev/null 2>&1; then
  log "integration dali mevcut: $INTEGRATION"
else
  git checkout -q "$BASE_BRANCH" && git checkout -q -b "$INTEGRATION" || { err "integration dali acilamadi"; exit 1; }
  ok "integration dali acildi: $INTEGRATION ($(sha_short))"
fi
echo "$INTEGRATION" > "$INTEGRATION_FILE"
git checkout -q "$INTEGRATION"

# --- Journal <-> git mutabakati --------------------------------------------
"$TDD_RUNNER/journal.sh" reconcile "$INTEGRATION"

[[ -n "$ONLY" ]] && "$TDD_RUNNER/journal.sh" reset "$ONLY" >/dev/null

processed=0; LAST_ID=""; CONSEC_A=0

# ===========================================================================
# ANA DONGU
# ===========================================================================
while :; do
  read -r ID ISSUE_PATH <<<"$("$TDD_RUNNER/graph.sh" next)"
  if [[ -z "${ID:-}" ]]; then log ""; log "Hazir issue kalmadi."; break; fi

  # Sonsuz dongu korumasi: bir issue islendikten sonra hala PENDING donuyorsa
  # journal yazamamis demektir (izin/disk sorunu).
  if [[ "$ID" == "$LAST_ID" ]]; then
    err "'$ID' journal'a yazilamadi, dongu duruyor. $STATE_DIR yazilabilir mi?"; exit 1
  fi
  LAST_ID="$ID"

  [[ -n "$ONLY" && "$ID" != "$ONLY" ]] && { log "--only $ONLY: sirada once '$ID' var, duruluyor."; break; }
  (( LIMIT > 0 && processed >= LIMIT )) && { log "Limit ($LIMIT) doldu."; break; }

  # --- Kosu butcesi ---------------------------------------------------------
  SPENT="$("$TDD_RUNNER/journal.sh" cost)"
  if awk "BEGIN{exit !($SPENT >= $RUN_BUDGET_USD)}"; then
    err "kosu butcesi doldu (\$$SPENT / \$$RUN_BUDGET_USD) — temiz duruluyor"; break
  fi

  eval "$("$TDD_RUNNER/contract.sh" parse "$ISSUE_PATH" 2>/dev/null)" || true
  ISSUE_BASE="$(git rev-parse "$INTEGRATION")"

  # --- HITL guvenlik kapisi -------------------------------------------------
  # HITL issue'lar tanimi geregi insan katilimi gerektirir; otonom kosuda
  # calistirilmalari kararin insan tarafindan verilmedigi anlamina gelir.
  if [[ "${SKIP_HITL:-1}" == "1" && "${C_MODE:-afk}" == "hitl" ]]; then
    warn "$ID HITL — otonom kosuda atlaniyor, insan calistirmali"
    "$TDD_RUNNER/status.sh" set "$ISSUE_PATH" needs-human "otonom kosuda atlandi" >/dev/null
    "$TDD_RUNNER/journal.sh" record "$ID" SKIPPED 0 "$ISSUE_BASE" "" 0 "" "HITL — insan gerekli (bkz. --accept-hitl)"
    processed=$((processed+1))
    continue
  fi

  # --- Kabul kriteri var mi -------------------------------------------------
  if [[ -n "${C_NOACCEPTANCE:-}" ]]; then
    warn "$ID kabul kriteri icermiyor — 'done' tanimi belirsiz, atlaniyor"
    "$TDD_RUNNER/journal.sh" record "$ID" SKIPPED 0 "$ISSUE_BASE" "" 0 "" "kabul kriteri yok"
    processed=$((processed+1))
    continue
  fi

  log ""
  log "═══════════════════════════════════════════════════════════════"
  log " ISSUE   : $ID   (gates=${C_TYPE:-feature}, mod=${C_MODE:-afk})"
  log " STATUS  : ${C_STATUS:-unknown}  ·  kriter: ${C_ACC_DONE:-0}/${C_ACC_TOTAL:-0}"
  log " DOSYA   : $ISSUE_PATH"
  log " BASE    : $(sha_short "$ISSUE_BASE") ($INTEGRATION)"
  log " DEPS    : $("$TDD_RUNNER/graph.sh" deps "$ID")"
  log " HARCAMA : \$$SPENT / \$$RUN_BUDGET_USD"
  log "═══════════════════════════════════════════════════════════════"

  # --- Worktree izolasyonu --------------------------------------------------
  WT="$REPO/$WORKTREE_ROOT/$ID"
  BRANCH="issue/$ID"
  git worktree remove --force "$WT" >/dev/null 2>&1 || true
  git branch -D "$BRANCH" >/dev/null 2>&1 || true
  if ! git worktree add -q -b "$BRANCH" "$WT" "$ISSUE_BASE" 2>/dev/null; then
    err "worktree acilamadi: $WT"
    "$TDD_RUNNER/journal.sh" record "$ID" FAILED 0 "$ISSUE_BASE" "" 0 "" "worktree acilamadi"
    continue
  fi

  attempt=0; verdict=""; issue_cost=0; gates=""; note=""

  while :; do
    attempt=$((attempt+1))
    log "── deneme $attempt ──"

    # Status gecisi: ajan calismaya basliyor. Bu satiri KOSUCU yazar, ajan
    # degil — `done` bir kabul beyanidir ve ajanin kendini kabul etmesine
    # izin vermek dogrulama kapilarinin amacini ortadan kaldirir.
    # Worktree kopyasina yazilir: commit'e dahil olur ve ana calisma agaci
    # temiz kalir (kirli agac bir sonraki kosunun preflight'ini kirardi).
    #
    # DONGUNUN ICINDE: retry yollari worktree'yi `git reset --hard $ISSUE_BASE`
    # ile sifirliyor, bu da issue dosyasini commit'li haline (ready-for-agent)
    # dondurup damgayi siliyordu. Damga disarida bir kez basildiginda, reset'ten
    # gecen her deneme ajan ne yaparsa yapsin G14d'de kesin olarak kaliyordu.
    "$TDD_RUNNER/status.sh" set "$WT/$ISSUE_PATH" agent-is-working "run $RUN_ID" >/dev/null

    # --- Ajan kosusu --------------------------------------------------------
    LOG="$STATE_DIR/logs/$ID-$attempt.json"
    PROMPT="/implement-all --single $ID $ISSUE_PATH --base $ISSUE_BASE"
    [[ -n "$note" ]] && PROMPT="$PROMPT --retry-context $STATE_DIR/logs/$ID-last-failure.txt"

    ( cd "$WT" && run_with_timeout "$ISSUE_TIMEOUT" claude -p "$PROMPT" \
        --permission-mode "$PERMISSION_MODE" \
        --allowedTools "$ALLOWED_TOOLS" \
        --max-budget-usd "$ISSUE_BUDGET_USD" \
        --max-turns "$MAX_TURNS" \
        --output-format json ) > "$LOG" 2>"$STATE_DIR/logs/$ID-$attempt.stderr"
    code=$?

    # --- Katman 0: process seviyesi ----------------------------------------
    if (( code == 124 )); then verdict=A; note="timeout ($ISSUE_TIMEOUT)"; break; fi
    if (( code != 0 )) && [[ ! -s "$LOG" ]]; then verdict=A; note="process exit=$code, cikti yok"; break; fi

    # --- Katman 1: exit 0 ama run icinde hata ------------------------------
    # Claude Code basarida 0 doner; ancak kosunun ICINDE olusan hata sonuc
    # olarak stdout'a yazilir. Karar alani `subtype`:
    #   success | error_max_turns | error_max_budget_usd | error_during_execution
    # --- Izin reddi kontrolu (Katman 1'in gorunmez kolu) ------------------
    # Headless modda bir izin reddi kosuyu KIRMAZ: subtype "success" doner,
    # ajan hicbir sey yazamamistir ve akis G1 "nodiff"e duserek sinif B
    # retry olarak YANLIS siniflanir — ajan iki kez daha ayni izin duvarina
    # carpar. Reddler `permission_denials` alaninda kayitlidir; bu bir
    # ortam/config sorunudur, sinif A'dir.
    denials="$(jq -r '(.permission_denials // []) | length' "$LOG" 2>/dev/null || echo 0)"
    if [[ "${denials:-0}" =~ ^[0-9]+$ ]] && (( denials > 0 )); then
      dtools="$(jq -r '[(.permission_denials // [])[].tool_name] | unique | join(",")' "$LOG" 2>/dev/null || echo "?")"
      verdict=A; note="izin reddi ($denials adet: $dtools) — PERMISSION_MODE / deny kurallarini gozden gecir"
      break
    fi

    subtype="$(jq -r '.subtype // "unknown"' "$LOG" 2>/dev/null)"
    is_err="$(jq -r '.is_error // false' "$LOG" 2>/dev/null)"
    cost="$(jq -r '.total_cost_usd // 0' "$LOG" 2>/dev/null)"
    issue_cost="$(awk "BEGIN{printf \"%.4f\", $issue_cost + ${cost:-0}}")"

    case "$subtype" in
      success) ;;
      error_max_turns)      verdict=B; note="tur limiti ($MAX_TURNS) asildi"; ;;
      error_max_budget_usd|error_budget)
                            verdict=A; note="issue butcesi (\$$ISSUE_BUDGET_USD) doldu"; break ;;
      *)
        if [[ "$is_err" == "true" ]]; then
          msg="$(jq -r '.result // ""' "$LOG" | head -c 200)"
          if grep -qiE 'authenticat|invalid api key|api key|/login|unauthorized|oauth|credit balance|rate.?limit|usage limit|quota|overloaded' <<<"$msg"; then
            err "API/kimlik/kota hatasi — kosu durduruluyor: $msg"
            "$TDD_RUNNER/journal.sh" record "$ID" PENDING "$attempt" "$ISSUE_BASE" "" "$issue_cost" "" "API/kota"
            git worktree remove --force "$WT" >/dev/null 2>&1
            exit 1
          fi
          verdict=A; note="run hatasi ($subtype): $msg"; break
        fi
        ;;
    esac

    # --- Kapilar ------------------------------------------------------------
    # Kapilar worktree icinde kosar; issue dosyasi worktree'deki kopyadir
    # (ajan kabul kutularini orada isaretler).
    VOUT="$( cd "$WT" && "$TDD_RUNNER/verify.sh" "$ID" "$WT/$ISSUE_PATH" "$ISSUE_BASE" 2>&1 )"
    vcode=$?
    printf '%s\n' "$VOUT"
    gates="$(sed -n 's/^GATES //p' <<<"$VOUT" | tail -1)"

    case $vcode in
      0) verdict=PASS; break ;;
      1) verdict=B ;;   # duzeltilebilir
      2) verdict=C ;;   # politika ihlali
      *) verdict=A; note="verify altyapi hatasi"; break ;;
    esac

    printf '%s\n' "$VOUT" | tail -30 > "$STATE_DIR/logs/$ID-last-failure.txt"
    note="$(grep -m1 '^GATE .* fail' <<<"$VOUT" || echo "dogrulama basarisiz")"

    # --- Retry politikasi ---------------------------------------------------
    # Sinif B: fresh ajan + hata kaniti, MAX_RETRIES dahilinde.
    # Sinif C: kirli workspace ATILIR. Ayni workspace uzerinde ajani ikna
    #          etmeye calismak yasak; ama SIFIRDAN temiz bir deneme farkli
    #          bir seydir ve bir kez denenebilir (temiz-oda).
    if [[ "$verdict" == B ]] && (( attempt < MAX_RETRIES )); then
      ( cd "$WT" && git reset -q --hard "$ISSUE_BASE" && git clean -qfd )
      continue
    fi
    if [[ "$verdict" == C ]] && (( CLEANROOM_RETRY )) && (( attempt <= CLEANROOM_RETRY )); then
      warn "politika ihlali — kirli workspace atiliyor, temiz-oda denemesi"
      ( cd "$WT" && git reset -q --hard "$ISSUE_BASE" && git clean -qfd )
      echo "ONCEKI DENEME POLITIKA IHLALI ILE REDDEDILDI: $note
Testleri zayiflatmak (skip/silme/assert gevsetme) kesinlikle yasaktir.
Sikisirsan testi degistirme; dur ve neden sikistigini raporla." \
        > "$STATE_DIR/logs/$ID-last-failure.txt"
      continue
    fi
    break
  done

  # --- Sonucu isle ----------------------------------------------------------
  # Devre kesici: anahtar kelime listesine guvenmek kirilgandir (yeni bir hata
  # metni listede olmayabilir). Ust uste iki Sinif A hatasi, sorunun issue'da
  # degil ortamda oldugunun jenerik gostergesidir; kalan issue'lari yakmayiz.
  if [[ "$verdict" == A ]]; then
    CONSEC_A=$((CONSEC_A+1))
  else
    CONSEC_A=0
  fi

  if [[ "$verdict" == PASS ]]; then
    # Butun kapilar gecti VE tum kabul kriterleri isaretli (G14). Ancak
    # simdi `done` yazilabilir.
    "$TDD_RUNNER/status.sh" set "$WT/$ISSUE_PATH" done "run $RUN_ID" >/dev/null
    TITLE="$(grep -m1 '^# ' "$ISSUE_PATH" 2>/dev/null | sed 's/^# *//')"
    ( cd "$WT" && git add -A && git commit -q \
        -m "feat($ID): ${TITLE:-$ID}" -m "TDD-Issue: $ID" )
    RESULT_SHA="$(cd "$WT" && git rev-parse HEAD)"
    # Integration HEAD ilerler: bir sonraki issue bu kodun uzerinde calisir.
    git merge -q --ff-only "$BRANCH" 2>/dev/null || git merge -q --no-edit "$BRANCH"

    # MERGE DOGRULAMASI. Merge'in cikis kodu tek basina yeterli degil ve
    # gormezden gelinmesi sessiz veri kaybi uretiyordu: ana checkout kirliyse
    # merge "local changes would be overwritten" ile iptal olur, script devam
    # eder, journal'a PASSED yazilir, worktree ve DAL SILINIR -- commit boylece
    # hicbir ref'ten erisilemez hale gelir. Kapilar dogru, is dogru, ama is
    # kaybolur. Tek guvenilir kontrol: sonuc gercekten HEAD'in atasi mi?
    if ! git merge-base --is-ancestor "$RESULT_SHA" HEAD 2>/dev/null; then
      err "$ID kapilardan gecti AMA integration dalina katilamadi"
      err "  commit KORUNUYOR : $RESULT_SHA"
      err "  dal KORUNUYOR    : $BRANCH"
      err "  worktree KORUNUYOR: $WT"
      err "  olasi sebep: ana checkout kirli. 'git status' ile bak, temizle,"
      err "  sonra: git merge --ff-only $BRANCH"
      "$TDD_RUNNER/journal.sh" record "$ID" FAILED "$attempt" "$ISSUE_BASE" "" "$issue_cost" "$gates" "merge basarisiz (kapilar gecti)"
      # Ortam kaynakli bir hata: devre kesici sayacina dahil edilir.
      CONSEC_A=$((CONSEC_A+1))
      for b in $("$TDD_RUNNER/graph.sh" blocked "$ID"); do
        [[ -z "$b" ]] && continue
        "$TDD_RUNNER/journal.sh" record "$b" BLOCKED 0 "" "" 0 "" "bagimlilik merge edilemedi: $ID" >/dev/null
        warn "     bloke edildi: $b"
      done
    else
      # ONEMLI: once commit, sonra journal. Arada crash olursa reconcile
      # commit'teki TDD-Issue trailer'indan durumu geri kazanir.
      "$TDD_RUNNER/journal.sh" record "$ID" PASSED "$attempt" "$ISSUE_BASE" "$RESULT_SHA" "$issue_cost" "$gates" "ok"
      ok "$ID  ($(sha_short "$RESULT_SHA"), \$$issue_cost, $attempt deneme)"
      git worktree remove --force "$WT" >/dev/null 2>&1
      git branch -D "$BRANCH" >/dev/null 2>&1
    fi
  else
    # Sinif C (politika ihlali) insan bakisi ister; digerleri tekrar
    # denenebilir durumda birakilir.
    if [[ "$verdict" == C ]]; then
      NEWSTAT=needs-human; STATNOTE="politika ihlali: $note"
    else
      NEWSTAT=ready-for-agent; STATNOTE="kapi kaldi: $note"
    fi
    # Basarisizlikta issue dosyasi ana checkout'ta guncellenir ve durum-only
    # commit atilir: hem insan issue'da dogru durumu gorur hem calisma agaci
    # temiz kalir (kirli agac sonraki kosunun preflight'ini kirar).
    "$TDD_RUNNER/status.sh" set "$ISSUE_PATH" "$NEWSTAT" "$STATNOTE" >/dev/null
    if [[ -n "$(git status --porcelain -- "$ISSUE_PATH")" ]]; then
      git add "$ISSUE_PATH" && git commit -q -m "chore($ID): status -> $NEWSTAT" -m "TDD-Status: $ID"
    fi
    "$TDD_RUNNER/journal.sh" record "$ID" FAILED "$attempt" "$ISSUE_BASE" "" "$issue_cost" "$gates" "sinif=$verdict $note"
    err "$ID kaldi (sinif $verdict): $note"
    [[ -f "$WT/$ISSUE_PATH" ]] && "$TDD_RUNNER/status.sh" tick-report "$WT/$ISSUE_PATH" | head -12
    log "     worktree inceleme icin duruyor: $WT  (dal: $BRANCH)"
    # Bagimlilari BLOKE et — bagimsizlar calismaya devam eder.
    for b in $("$TDD_RUNNER/graph.sh" blocked "$ID"); do
      [[ -z "$b" ]] && continue
      "$TDD_RUNNER/journal.sh" record "$b" BLOCKED 0 "" "" 0 "" "bagimlilik basarisiz: $ID" >/dev/null
      warn "     bloke edildi: $b"
    done
  fi

  processed=$((processed+1))
  [[ -n "$ONLY" ]] && break

  if (( CONSEC_A >= 2 )); then
    err "ust uste $CONSEC_A altyapi hatasi (Sinif A) — sorun ortamda, kosu durduruluyor."
    err "Son sebep: $note"
    break
  fi
done

# ===========================================================================
# FINAL
# ===========================================================================
log ""
"$TDD_RUNNER/journal.sh" report

PASSED_N="$("$TDD_RUNNER/graph.sh" order | while read -r id _; do "$TDD_RUNNER/journal.sh" status "$id"; done | grep -c PASSED || true)"
TOTAL_N="$("$TDD_RUNNER/graph.sh" order | wc -l)"

if (( PASSED_N > 0 )) && (( PASSED_N == TOTAL_N )); then
  log ""
  "$TDD_RUNNER/final-gate.sh" "$INTEGRATION" "$BASE_SHA"
elif (( PASSED_N > 0 )); then
  log ""
  warn "Bazi issuelar tamamlanmadi — final entegrasyon kapisi KOSULMADI."
  warn "'$INTEGRATION' merge'e hazir DEGIL. Kalanlari bitirdikten sonra:"
  warn "  ./run-issues.sh --final-only"
fi
