# TDD Batch Runner v3

**Issue setini Claude Code ile otomatik, doğrulanabilir ve kesintiye dayanıklı biçimde implement etmek**

_v3 — iki bağımsız review turu sonrası. Sürüm geçmişi için bkz. [Bölüm 12](#12-sürüm-geçmişi)._

> **Bu doküman v3 gerçekliğini anlatır.** Issue sözleşmesi (`Status:` başlığı,
> `## Acceptance criteria`, `## Blocked by`) ve dizin taraması v3'te
> gelmiştir; v2'nin `ISSUES.txt` kayıt defteri ve YAML frontmatter kontratı
> **kaldırılmıştır**. `contract.sh` YAML frontmatter'ı hâlâ okur (ek alan
> tanımlamak isteyenler için), ama bağımlılık ve durum bilgisi düz metin
> sözleşmesinden gelir.

---

## İçindekiler

1. [Problem](#1-problem)
2. [Analiz](#2-analiz)
3. [Çözüm mimarisi](#3-çözüm-mimarisi)
4. [Bileşenler](#4-bileşenler)
5. [Kurulum](#5-kurulum)
6. [Kullanım](#6-kullanım)
7. [Sonuçları okuma](#7-sonuçları-okuma)
8. [Doğrulanmış davranışlar](#8-doğrulanmış-davranışlar)
9. [Geliştirme sırasında yakalanan hatalar](#9-geliştirme-sırasında-yakalanan-hatalar)
10. [Neden `/batch` değil](#10-neden-batch-değil)
11. [Sınırlar ve bilinmesi gerekenler](#11-sınırlar-ve-bilinmesi-gerekenler)
12. [Sürüm geçmişi](#12-sürüm-geçmişi)
13. [Örnek proje uyarlaması: [project-name]](#13-örnek-proje-uyarlaması-project-name)

---

## 1. Problem

Bir feature için açılmış klasörde 15 issue var. Her biri `tdd` skill'i ile implement edilmeli. Elle yapılan akış şu:

```
/tdd docs/issues/yeni-feature/01-schema.md
   ...bekle, incele, commit...
/tdd docs/issues/yeni-feature/02-repository.md
   ...bekle, incele, commit...
   (× 15)
```

Bu akışın dört maliyeti var:

- **İnsan bekleme süresi.** Her issue arasında birinin başlatması gerekiyor.
- **Context kirlenmesi.** Aynı oturumda 15 issue işlenirse 6-7. issue'dan sonra bağlam şişer.
- **Kesinti dayanıksızlığı.** Terminal kapanırsa, kota biterse nerede kalındığı kaybolur.
- **Doğrulanmamış "başarı".** Ajanın "tamamlandı" demesi işin doğru yapıldığı anlamına gelmiyor.

**İstenen:** tek tetiklemeyle başlayan, 15 issue bitene kadar çalışan, sonuçları kendi doğrulayan bir döngü.

---

## 2. Analiz

### 2.1 Naif çözüm neden yetmez

"Claude Code'a 15 issue'yu sırayla yapmasını söyle" yaklaşımının üç yapısal sorunu var:

| Sorun                                 | Sonuç                                            |
| ------------------------------------- | ------------------------------------------------ |
| Tek context'te 15 issue               | 6-7. issue'dan sonra bağlam şişer, kalite düşer  |
| Sırayı ve durumu model tutar          | "Sanırım 7. issue'daydık" — tahmin, gerçek değil |
| Model kendi işini kendi değerlendirir | Değerlendiren de aynı olasılıksal süreç          |

Üçüncü maddenin doğru formülasyonu önemli. "Ajan hakem olamaz" fazla mutlak bir ifade: bir modelin kendi diff'ini okuması, ikinci bir subagent'ın bakması değersiz değildir — kapıların ölçemeyeceği tasarım sorunlarını yakalayabilir. Doğrusu şu:

> **Olasılıksal doğrulama, deterministik kabul kapısının yerini tutamaz — ama önüne eklenebilir.**

Model review = advisory sinyal. Deterministik kapı = authoritative karar. Bu ayrım yapılınca katmanlı bir zincir mümkün olur ve her katmanın rolü nettir.

### 2.2 "Sıfır context" tek bir şey değil

"Her issue sıfır bağlamla başlar" ifadesi üç ayrı şeyi karıştırır:

| Boyut                 | Ne izole eder                       | Mekanizma                   |
| --------------------- | ----------------------------------- | --------------------------- |
| **Conversation**      | Önceki issue'ların diyalog geçmişi  | fresh `claude -p`           |
| **Workspace**         | Önceki issue'ların dosya/git durumu | worktree + dal stratejisi   |
| **Proje talimatları** | CLAUDE.md, skills, memory           | bilinçli olarak **korunur** |

Fresh `claude -p` yalnızca birincisini çözer. Üçüncüsü _korunmalıdır_ — `/tdd` skill'inin yüklenmesi buna bağlıdır (bu yüzden `--bare` kullanılmaz). İkincisi ayrı bir karardır ve v3'te açıkça verilmiştir: her issue kendi worktree'sinde, integration HEAD'inden başlar.

Doğru ifade: _"Her issue yeni conversation context ve temiz bir worktree ile başlar; proje talimatları bilinçli olarak taşınır."_

### 2.3 Bir `claude -p` çağrısı kaç farklı şekilde başarısız olur?

Beş. Ve bunlardan sadece biri exit code'a yansır:

| Katman | Ne oldu                                     | Exit code | Kim yakalar          |
| ------ | ------------------------------------------- | --------- | -------------------- |
| **0**  | Process çöktü, ağ gitti, timeout            | ≠ 0       | `$?`                 |
| **1**  | Run _içinde_ hata, process düzgün kapandı   | **0**     | JSON `subtype` alanı |
| **2**  | Kod yazıldı, testler kırmızı                | 0         | G7–G9                |
| **3**  | Testler yeşil ama ajan **testi zayıflattı** | 0         | G4–G6                |
| **4**  | Ajan hiç kod yazmadı, plan anlattı          | 0         | G1–G3                |

Katman 1 için karar alanı `subtype`: `success`, `error_max_turns`, `error_max_budget_usd`, `error_during_execution`. Bunları ayırt etmek retry sınıfını belirler — tur limiti düzeltilebilir, kota hatası düzeltilemez.

### 2.4 Sabotaj tespiti tek tip değil

v1'in en büyük hatası G4/G5/G6'yı aynı kefeye koymaktı. Üçü farklı güven seviyesinde:

| Seviye                                  | Örnek                                                        | Doğru tepki              |
| --------------------------------------- | ------------------------------------------------------------ | ------------------------ |
| **Hard gate** — kesin ihlal             | `.skip` eklendi, test dosyası silindi, verifier değiştirildi | Retry'sız fail           |
| **Yapısal sinyal** — şüphe, kanıt değil | test sayısı artmadı, test satırı değişti                     | Uyarı + inceleme kuyruğu |
| **Semantik review** — makine ölçemez    | testler kabul kriterini gerçekten test ediyor mu             | Reviewer / insan         |

**G6 (`count`) hard gate olamaz.** İki yönde de yanılır: mevcut bir teste assertion eklemek sayıyı artırmaz (yanlış pozitif); iki tautolojik `it("dummy")` eklemek artırır (yanlış negatif). `test.each` tablosuna satır eklemek de sayıyı değiştirmez.

**G5 (`deleted`) fazla kabaydı.** Diff mantığında bir satırı _değiştirmek_ = silmek + eklemek olduğundan meşru rename, taşıma, formatter dokunuşu "sabotaj" damgası yiyordu. v1'in test matrisindeki "assert gevşetildi → FAIL[deleted]" başarısı aslında bunun kanıtıydı: kapı sabotajı değil, her satır değişikliğini yakalıyordu.

Ve daha sofistike gevşetmeler hepsini geçer:

```ts
// önce
expect(result.status).toBe(404);
// sonra — bütün kapılar yeşil
const expectedStatus = result.status;
expect(result.status).toBe(expectedStatus);
```

Bunu test ettim, gerçekten geçiyor. Bu yüzden iddia da düzeltildi: kapılar _"test kümesinin zayıflamadığını kanıtlamaz"_; **yaygın test manipülasyon biçimlerini yakalar ve riski azaltır**.

### 2.5 Sistem "ajanın yaptığını" değil "issue'nun istediğini" test etmeli

Issue "olmayan kullanıcıda 404 dönmeli" diyorsa; ajan kod yazabilir, test ekleyebilir, sayı artabilir, her şey yeşil olabilir — ve eklenen test `expect(true).toBe(true)` olabilir. Kavramsal dönüşüm:

> Issue = serbest metin prompt → Issue = **makine-denetlenebilir yürütme kontratı**

Kontrat olunca kapılar genel hijyeni, kontrat işin özünü doğrular.

### 2.6 "Aynı verifier'ı iki kez koşmak" savunma derinliği değildir

`verify(A); verify(A)` aynı repo durumu üzerinde aynı bug'ı iki kez yapar. Gerçek defense-in-depth **bağımsız başarısızlık mekanizmaları** ister. İkinci koşunun tek meşru rolü, verifier ajanın erişemediği bir yerden koşuluyorsa anlamlıdır — v3'te tam olarak bu yapılır.

### 2.7 Tasarım ilkeleri

1. **Üç izolasyon boyutu ayrı ayrı ele alınır.**
2. **Sıra ve durum dosya sisteminde değil, git gerçekliğiyle mutabakatlı bir journal'da tutulur.**
3. **Doğrulama mekanizması ajanın erişemeyeceği yerde durur.**
4. **Kapılar üç seviyeye ayrılır; sadece kesin ihlaller retry'sız fail eder.**
5. **Karar sınıfı çıkış koduyla taşınır, metinle değil.**

---

## 3. Çözüm mimarisi

```
             ISSUE KONTRATLARI (type, depends_on, acceptance, allowed_paths)
                              │
                              ▼
        run-issues.sh  ── flock ── journal (SHA) ── bütçe tavanı
                              │
              main ──► batch/run-<tarih>   (integration branch)
                              │
        ┌─────────────────────┴──────────────────────┐
        │  her issue:                                 │
        │    worktree(integration HEAD)               │
        │      └─ claude -p "/implement-all --single" │  ← fresh conversation
        │           ├─ Task ─► tdd-implementer  (/tdd)│
        │           └─ Task ─► tdd-reviewer  [advisory]│
        │    verify.sh  ← /tmp/tdd-runner-* (salt-oku) │
        │      G0 anti-tamper      [hard]              │
        │      G0b config          [signal]            │
        │      G0c/G0d kontrat     [hard]              │
        │      G1–G3 diff varlığı  [retry]             │
        │      G4 skip/only        [hard]              │
        │      G5a test silme      [hard]              │
        │      G5b test modif.     [signal]            │
        │      G6 count            [signal]            │
        │      G6' changed-line cov [kapı]             │
        │      G7–G9 test/lint/tip [retry]             │
        │                                              │
        │    PASS → commit (TDD-Issue trailer)         │
        │         → integration HEAD ilerler           │
        │    FAIL → sınıf A/B/C/D → bağımlılar BLOCKED │
        └─────────────────────┬──────────────────────┘
                              ▼
        FINAL: temiz klonda tam suit + build + e2e + toplam diff denetimi
```

### Integration branch modeli

Koşu başında `main`'den `batch/run-<tarih>` açılır. Her PASS eden issue onun üstüne commit'lenir ve bir sonraki issue **yeni HEAD'den** başlar. Böylece bağımlı issue'lar öncekilerin kodunu görür. Sonda tek bir dal merge edilir; "15 bağımsız yeşil dal" yanılsaması yoktur.

### Neden hem bash hem skill hem subagent

Her katmanın **tek ve açık bir gerekçesi** olmalı; yoksa katman silinmeli.

| Katman                   | Gerekçe                                                                   |
| ------------------------ | ------------------------------------------------------------------------- |
| **bash koşucu**          | Deterministik olmalı: sıra, durum, dal, commit, bütçe, kilit              |
| **skill**                | Yorum gerektirir: hata sınıflandırma, retry kararı, prompt zenginleştirme |
| **implementer subagent** | Tool kısıtlaması (Task/WebFetch yok) + ayrı system prompt                 |
| **reviewer subagent**    | Farklı rol, salt-okunur yetki, advisory çıktı                             |

Fresh `claude -p` zaten yeni conversation açtığı için subagent'ın gerekçesi context izolasyonu **değildir** — yetki ayrımı ve ayrı system prompt'tur.

---

## 4. Bileşenler

```
proje-kök/
├── run-issues.sh                    dış koşucu
├── runner/                          DOĞRULAMA ÇEKİRDEĞİ (koşuda repo dışına kopyalanır)
│   ├── config.sh                    TEK düzenlenecek dosya
│   ├── lib.sh                       çıkış kodu sözleşmesi, taşınabilirlik
│   ├── contract.sh                  issue kontratı ayrıştırıcı
│   ├── graph.sh                     DAG: topolojik sıra, çevrim, BLOCKED
│   ├── journal.sh                   SHA'lı journal + git mutabakatı
│   ├── preflight.sh                 baseline, araçlar, graf
│   ├── verify.sh                    kabul kapıları
│   └── final-gate.sh                G10–G13
├── .claude/
│   ├── agents/tdd-implementer.md
│   ├── agents/tdd-reviewer.md
│   └── skills/implement-all/SKILL.md
└── docs/issues/yeni-feature/
    ├── PRD.md                       tip (AFK/HITL) ve genel bağlam
    └── 01-....md ...                issue dosyaları
```

### 4.1 Verifier neden repo dışında

Ajan repo'ya yazabildiği için `verify.sh` repo içinde kalırsa karar mercii ajanın erişimindedir. `"test": "echo success"` yapan bir ajan bütün kapılardan geçer. Koşu başında doğrulama çekirdeği `/tmp/tdd-runner-<id>`'ye kopyalanır, `chmod -R a-w` yapılır ve **yalnızca o kopya çalıştırılır**.

Bu sadece teorik bir risk değil: worktree izolasyonlu subagent'ların `git -C`
veya `GIT_DIR` üzerinden paylaşımlı checkout'a sızabildiği bir sınıf hata
raporlanmış ve bir sürüm notunda düzeltildiği belirtilmiştir — kendi
sürümünüzde durumu changelog'dan doğrulayın. İzolasyon mekanizmasının
kendisi hatalı olabildiği için, doğrulama çekirdeğini repo dışında tutmak
tek katmanlı savunmadan daha güvenlidir.

Fiziksel ayrımın üstüne **G0** gelir ve ilk kapı olması kritiktir: doğrulama mekanizmasına dokunulmuşsa diğer kapıların sonucu zaten anlamsızdır.

### 4.2 Kapı tablosu

| #       | Etiket         | Ne kontrol eder                                       | Seviye   |
| ------- | -------------- | ----------------------------------------------------- | -------- |
| G0      | `anti-tamper`  | `runner/`, `.claude/`, `run-issues.sh`, `.tdd-state/` | **hard** |
| G0b     | `config`       | package.json, jest.config, tsconfig, lock, CI         | signal   |
| G0c     | `scope`        | kontrattaki `allowed_paths` dışı                      | **hard** |
| G0d     | `forbidden`    | kontrattaki `forbidden_paths`                         | **hard** |
| G1      | `nodiff`       | hiç değişiklik var mı                                 | retry    |
| G2      | `notest`       | test dosyasına dokunuldu mu                           | retry    |
| G3      | `nosrc`        | üretim kodu değişti mi                                | retry    |
| G4      | `skip`         | `.skip`/`.only`/`xit` **eklendi** mi                  | **hard** |
| G5a     | `deleted`      | test dosyası silindi / **net** test kaybı             | **hard** |
| G5b     | `modified`     | test satırı değişti                                   | signal   |
| G6      | `count`        | test sayısı arttı mı                                  | signal   |
| G6'     | `coverage`     | değişen satırların coverage'ı                         | kapı     |
| G7      | `tests`        | test suiti (+ flaky re-run)                           | retry    |
| G8/G9   | `lint`/`types` | lint, tip kontrolü                                    | retry    |
| G10–G13 | final          | temiz klonda suit, build, e2e, toplam diff            | kapı     |

### Kapı profilleri (`Gates:` alanı)

| Profil                 | G2 test dosyası | G3 kaynak | G6 test sayısı | G6' coverage | G7p zorunlu komut        |
| ---------------------- | --------------- | --------- | -------------- | ------------ | ------------------------ |
| `feature` (varsayılan) | zorunlu         | zorunlu   | zorunlu        | uygulanır    | —                        |
| `refactor`             | atlanır         | zorunlu   | atlanır        | uygulanır    | —                        |
| `content`              | atlanır         | zorunlu   | atlanır        | **atlanır**  | `PROFILE_VERIFY_CONTENT` |
| `docs`                 | atlanır         | atlanır   | atlanır        | **atlanır**  | `PROFILE_VERIFY_DOCS`    |
| `config`               | atlanır         | atlanır   | atlanır        | **atlanır**  | `PROFILE_VERIFY_CONFIG`  |
| `chore`                | atlanır         | zorunlu   | atlanır        | **atlanır**  | —                        |

Coverage eşiği `COVERAGE_MIN` (varsayılan 80) ile ayarlanır ve yalnızca
`feature`/`refactor` profillerinde uygulanır — test üretmeyen bir issue'da
changed-line coverage anlamsızdır.

Profillerin zorunlu doğrulama komutu (`G7p`) önemli: `content` issue'larında
doğrulama kriter metnine emanet edilmez, profil kendi kapısını getirir.

Atlanan her kapı journal'a `skipped` yazılır — sessiz zayıflama olmaz.

### 4.3 Çıkış kodu sözleşmesi

Karar sınıfı **çıkış koduyla** taşınır; koşucu metin ayrıştırmaz. Böylece mesaj metni değişince davranış değişmez.

| Kod | Sınıf   | Anlam                 | Tepki                                          |
| --- | ------- | --------------------- | ---------------------------------------------- |
| 0   | PASS    | Geçti (WARN olabilir) | commit                                         |
| 1   | B       | Düzeltilebilir        | fresh ajan + hata kanıtı, `MAX_RETRIES`        |
| 2   | C       | Politika ihlali       | kirli workspace atılır, tek temiz-oda denemesi |
| 4   | A/INFRA | Araç/config/ortam     | retry yok, devre kesici sayacı                 |

Sınıf A için ayrıca **devre kesici** var: üst üste iki altyapı hatası, sorunun issue'da değil ortamda olduğunun jenerik göstergesidir; kalan issue'lar yakılmaz. Anahtar kelime listesine güvenmek kırılgan olduğu için hem liste hem sayaç kullanılır.

### 4.4 Issue kontratı

Kontrat, issue dosyasının kendisidir (bkz. §5.2). `contract.sh` şunları çıkarır:

| Alan             | Kaynak                         | Ne yapar                       |
| ---------------- | ------------------------------ | ------------------------------ |
| `Status:`        | başlık satırı                  | yaşam döngüsü; koşucu yazar    |
| `Type:`          | başlık satırı veya PRD tablosu | AFK/HITL; HITL otonom koşulmaz |
| `Gates:`         | başlık satırı                  | kapı profili (§4.2)            |
| bağımlılıklar    | `## Blocked by`                | DAG kenarları                  |
| kabul kriterleri | `## Acceptance criteria`       | G14 ailesinin girdisi          |
| PRD              | `## Parent`                    | ajana bağlam                   |

Ek olarak YAML frontmatter da okunur (`allowed_paths`, `forbidden_paths`,
`verification`). Zorunlu değildir; tanımlıysa G0c/G0d kapıları devreye girer.

**Kabul kriterleri "done" tanımıdır.** Bir issue ancak tüm kriterler
karşılandığında `done` olur. Bu bir söyleyiş değil, dört kapıya bağlanmış
bir kural:

| Kural                                                                  | Kim yapar    | Kapı         |
| ---------------------------------------------------------------------- | ------------ | ------------ |
| Her `- [ ]` → `- [x]`                                                  | implementer  | G14a (retry) |
| Kriterlerde adı geçen komutlar koşulur                                 | verify       | G14b         |
| Kriter metni değiştirilemez — silme, yeniden yazma **ve ekleme** dahil | —            | G14c (hard)  |
| `Status:` satırına ajan dokunamaz                                      | koşucu yazar | G14d (hard)  |

G14c kriterlerin sıralı listesini base ile karşılaştırır; ajanın kendine
kolay bir kriter **eklemesi** de metin değişikliğidir ve hard fail eder.

**G14b'nin komut yüzeyi tam eşleşmedir.** Kriterde geçen bir komut, ancak
`config.sh`'de tanımlı komut kümesiyle (`TEST_CMD`, `LINT_CMD`,
`TYPECHECK_CMD`, `BUILD_CMD`, `ACCEPTANCE_CMDS_EXTRA`) birebir eşleşiyorsa
koşulur. Önek allowlist'i (`npm`, `npx`…) yeterli değildi:

- `npx <paket>` tanımı gereği internetten indirip kod çalıştırır
- `npm run <script>` `package.json`'a bağlıdır, o da yalnızca G0b sinyali

Birleşik saldırı: ajan `package.json`'a masum görünümlü bir script ekler
(koşu durmaz, WARN düşer), kriterde ona atıf yapar, G14b onu _doğrulama
adına_ çalıştırır. Tam eşleşme bu zinciri kırar. Ayrıca shell metakarakteri
(`;`, `|`, `&`, backtick, `$(`) içeren komut hard fail eder — tam eşleşse bile.

Kümede olmayan komutlar **çalıştırılmaz, WARN olarak raporlanır**: insan
görür, sistem koşmaz.

### 4.5 Journal ve mutabakat

Bayrak dosyası (`<id>.done`) commit ile işaretleme arasında crash olursa yalan söyler. Journal her kayıtta `result_sha` tutar ve **her açılışta git ile mutabakata sokulur**:

- journal `PASSED` diyor ama `result_sha` git'te yok → kayıt geçersiz, `PENDING`
- integration dalında `TDD-Issue: <id>` trailer'lı commit var ama journal'da yok → commit'ten geri kazanılır

Yazma sırası **önce commit, sonra journal**. Dosya sistemine değil git'e güvenilir.

> **Dürüst adlandırma:** `.tdd-state/` _yerel kesinti dayanıklılığı_ sağlar, durability değil. Makine/clone kaybında kaybolur.

---

## 5. Kurulum

### 5.1 Dosyalar

```bash
cp -r batch-runner-setup/runner .
cp -r batch-runner-setup/.claude/. .claude/
cp batch-runner-setup/run-issues.sh .
chmod +x run-issues.sh runner/*.sh
printf '.tdd-state/\n.tdd-worktrees/\n' >> .gitignore
$EDITOR runner/config.sh
./run-issues.sh --dry-run
```

**Önkoşul:** `/tdd` skill'i kurulu olmalı. **Araçlar:** `claude`, `jq`, `git`,
`awk`, `timeout` (macOS: `brew install coreutils` → `gtimeout`; yoksa zaman
aşımı uygulanmaz ve preflight uyarır).

Kayıt defteri yazmana gerek yok — `ISSUES_DIR` altındaki `.md` dosyaları
otomatik taranır.

### 5.2 Issue sözleşmesi

```
Status: ready-for-agent
Type:   AFK | HITL          # opsiyonel; yoksa PRD tablosundan okunur
Gates:  feature | content | docs | config | refactor | chore   # opsiyonel

# 01 — Başlık
## Parent               → PRD yolu
## What to build
## Acceptance criteria
- [ ] ...
## Blocked by
01, 02   |   None - can start immediately
```

Kabul kriteri olmayan issue atlanır ve `SKIPPED` yazılır — "done" tanımı
belirsiz bir issue otomatik koşulamaz.

### 5.3 İzin (permission) modeli

Otonom koşuda izin sorusunu cevaplayacak kimse yoktur; bu yüzden mod
açıkça seçilmeli. `config.sh`:

```bash
PERMISSION_MODE="acceptEdits"     # dosya düzenlemeleri otomatik, Bash yine sorar
ALLOWED_TOOLS="Bash,Read,Edit,Write,Glob,Grep,Task"
```

`acceptEdits` çoğu proje için yeterlidir. Bash komutları da sorulmasın
isteniyorsa `bypassPermissions` gerekir — ama bu **yalnızca** izole worktree

- G0 anti-tamper + deny kuralları birlikteyken savunulabilir. İlk kullanımda
  bir kez interaktif onay ister:

```bash
claude --permission-mode bypassPermissions   # onayı ver, çık
```

Deny kuralları `.claude/settings.json` içinde, ajanın erişmemesi gereken
yüzeyleri kapatır:

```json
{
  "permissions": {
    "deny": [
      "Bash(curl:*)",
      "Bash(wget:*)",
      "Bash(npm publish:*)",
      "Bash(git push:*)",
      "Bash(rm -rf /*)",
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./**/*secret*)",
      "Edit(./runner/**)",
      "Edit(./.claude/**)",
      "Edit(./run-issues.sh)"
    ]
  }
}
```

Son üç kural G0'ın ucuz bir kopyasıdır: G0 ihlali _sonradan_ yakalar, deny
kuralı en baştan engeller. İkisi birlikte kullanılır — deny kuralları
`.claude/` içinde durduğu için ajan tarafından değiştirilebilir, G0 ise
repo dışındaki salt-okunur kopyadan çalışır.

**İzin reddi sessiz başarısızlıktır.** Headless modda bir tool reddedilirse
koşu kırılmaz: `subtype` yine `success` döner, ajan hiçbir şey yazamamıştır
ve akış "hiç değişiklik yok" hatasına düşer. Koşucu bu yüzden JSON'daki
`permission_denials` alanını okur ve sıfırdan büyükse issue'yu **sınıf A**
sayar — retry yapmaz, çünkü sorun ajanda değil konfigürasyondadır.

## 6. Kullanım

```bash
./run-issues.sh --dry-run          # topolojik sıra + durumlar, hiçbir şey koşmaz
./run-issues.sh --limit 1          # İLK DENEME İÇİN
./run-issues.sh                    # tam koşu
./run-issues.sh --only 07-api      # tek issue, durumu sıfırlanarak
./run-issues.sh --resume           # pahalı baseline'ı atlayarak devam
./run-issues.sh --accept-hitl 05   # insanın yaptığı HITL işini kapılardan geçir
./run-issues.sh --final-only       # sadece final entegrasyon kapısı
runner/journal.sh report           # durum raporu
```

**İlk koşuda `--limit 1`'i atlama.** Tek issue'nun diff'ini, `.tdd-state/logs/*.json`
içindeki `total_cost_usd`'yi ve `.tdd-state/reviews/*.md` advisory raporunu
okumadan tamamına açmak, kötü bir prompt'un N kez tekrarlanması demektir.

`--resume` yalnızca **pahalı baseline suite'ini** atlar. Araç kontrolü, repo
temizliği, graf doğrulaması, kilit ve journal–git mutabakatı her açılışta
koşar — kesinti sırasında ortam bozulmuş olabilir (silinen `node_modules`,
değişen base) ve bunu gizlemek en kötü seçenektir.

### 6.1 HITL issue'ların yaşam döngüsü

HITL issue'lar otonom koşuda çalıştırılmaz; koşucu bunları `SKIPPED` yazıp
geçer. İnsan işi bitirdiğinde **`done` yazma yetkisi yine ona ait değildir** —
iş aynı kapılardan geçer. Fark, işi ajanın değil insanın yapmasıdır;
doğrulama sözleşmesi aynı kalır.

```bash
git checkout batch/run-<tarih>      # integration dalı
# ... insan işi yapar, kabul kutularını işaretler ...
./run-issues.sh --accept-hitl 05
```

Kapılar geçerse: `Status: done`, `TDD-Issue` trailer'lı commit, integration
HEAD ilerler, journal `PASSED` olur. Kapılar kalırsa `done` yazılmaz ve
komut sıfır dışı kodla çıkar.

Bağımlıları açmak için `./run-issues.sh --resume` yeter: `BLOCKED`
**türetilmiş** bir durumdur, bağımlılığı `PASSED` olunca issue yeniden uygun
hale gelir. `SKIPPED` ve `FAILED` yapısaldır, kendiliğinden açılmaz.

Tüm issue'lar `PASSED` olmadan final entegrasyon kapısı koşmaz — bu yüzden
HITL'ler tamamlanmadan dal "merge'e hazır" ilan edilmez.

## 7. Sonuçları okuma

| Çıktı                                      | Anlamı                                 | Ne yapmalı                                     |
| ------------------------------------------ | -------------------------------------- | ---------------------------------------------- |
| `OK 03-service (f2ce537, $0.42, 1 deneme)` | Kapılardan geçti, commit atıldı        | Diff'i incele                                  |
| `kaldı (sınıf B): GATE G7 fail`            | Testler kırmızı, retry tükendi         | Worktree'de elle bak                           |
| `kaldı (sınıf C): GATE G4 fail`            | Test atlatılmış                        | Issue'yu böl, kapsam geniş olabilir            |
| `kaldı (sınıf C): GATE G0 fail`            | **Doğrulama altyapısına dokunulmuş**   | Ciddi — prompt'u ve issue metnini gözden geçir |
| `WARN GATE G6`                             | Test sayısı artmamış                   | Sinyal; merge öncesi incele                    |
| `bloke edildi: 02-repo`                    | Bağımlılığı fail etti                  | Önce bağımlılığı düzelt                        |
| `üst üste 2 altyapı hatası`                | Ortam sorunu                           | Koşu durdu, ortamı düzelt                      |
| `FINAL KAPI GEÇİLEMEDİ`                    | Issue'lar tek tek yeşil, bütün kırmızı | Entegrasyon regression'ı ara                   |

Başarısız issue'ların **worktree'leri ve dalları silinmez** — inceleme için durur.

Üst üste 3+ issue `WARN G6` veya `FAIL G4` veriyorsa sorun ajanda değil issue'lardadır: kabul kriterleri test edilebilir biçimde yazılmamış demektir.

---

## 8. Doğrulanmış davranışlar

Sahte bir git repo'sunda uçtan uca test edildi.

### Kapılar

| Senaryo                                 | Beklenen                           | Sonuç              |
| --------------------------------------- | ---------------------------------- | ------------------ |
| Normal feature işi                      | exit 0 + commit                    | ✅                 |
| Ajan `runner/verify.sh`'yi değiştiriyor | G0 hard, exit 2                    | ✅                 |
| Ajan `.claude/` değiştiriyor            | G0 hard, exit 2                    | ✅                 |
| `docs` tipi issue, test yok             | G2/G3/G6 skipped, exit 0           | ✅                 |
| `it.skip` eklendi                       | G4 hard, exit 2                    | ✅                 |
| Test dosyası silindi                    | G5a hard, exit 2                   | ✅                 |
| 4 test → 1 test (net kayıp)             | G5a hard, exit 2                   | ✅                 |
| Assertion eklendi, sayı sabit           | G6 signal, exit 0                  | ✅                 |
| Assert gevşetildi (tautoloji)           | **kapılar geçirir** — reviewer işi | ✅ (bilinen sınır) |
| `allowed_paths` dışına çıkıldı          | G0c hard, exit 2                   | ✅                 |
| Testler kırmızı                         | retry, exit 1                      | ✅                 |
| Flaky: ilk kırmızı, ikinci yeşil        | WARN + exit 0                      | ✅                 |
| Coverage %60 < %80                      | retry, exit 1                      | ✅                 |
| Coverage %92 ≥ %80                      | exit 0                             | ✅                 |

### Graf ve durum

| Senaryo                                                   | Sonuç     |
| --------------------------------------------------------- | --------- |
| Topolojik sıra (01→02→03, bağımsız 15)                    | ✅        |
| Çevrim tespiti                                            | ✅ exit 1 |
| Bilinmeyen bağımlılık                                     | ✅ exit 1 |
| Kayıt defterinde olmayan `.md`                            | ✅ WARN   |
| `01` fail → `02`,`03` BLOCKED, `15` devam                 | ✅        |
| Journal: hayali SHA → PENDING                             | ✅        |
| Journal: commit var, kayıt yok → trailer'dan geri kazanım | ✅        |

### Kapılar (v3 eklemeleri)

| Senaryo                                             | Beklenen                                    | Sonuç |
| --------------------------------------------------- | ------------------------------------------- | ----- |
| Ajan kutuları işaretliyor                           | `done`                                      | ✅    |
| Kutuları işaretlemiyor (0/7)                        | G14a retry, `done` yok                      | ✅    |
| Kutuların yarısı işaretli (1/7)                     | G14a retry                                  | ✅    |
| Ajan kriter siliyor                                 | G14c hard                                   | ✅    |
| Ajan kendini `done` ilan ediyor                     | G14d hard                                   | ✅    |
| Kriterdeki tanımlı komutlar koşuluyor               | G14b.1–3 pass                               | ✅    |
| Kriterde **tanımsız** komut (`npm run deploy-prod`) | koşulmaz + WARN                             | ✅    |
| Kriterde shell metakarakteri                        | G14b **hard**                               | ✅    |
| `content` profili                                   | G2/G6/G6cov skip, G7p zorunlu komut koşuyor | ✅    |
| `forbidden_paths` ihlali                            | G0d hard                                    | ✅    |
| `package.json` değişikliği (G0b)                    | signal + WARN                               | ✅    |
| İzin reddi (`permission_denials`)                   | sınıf A, **retry yok**                      | ✅    |

### Koşucu

| Senaryo                                                  | Sonuç                           |
| -------------------------------------------------------- | ------------------------------- | --- |
| HITL issue'lar atlanıyor, `SKIPPED` + `needs-human`      | ✅                              |
| İş yapılmadan `--accept-hitl`                            | reddediliyor, `done` yazılmıyor | ✅  |
| İş yapılıp `--accept-hitl`                               | kapılardan geçip `done`         | ✅  |
| `--resume` ucuz kontrolleri koşuyor, baseline'ı atlıyor  | ✅                              |
| Integration HEAD ilerliyor (her issue öncekinin üstünde) | ✅                              |
| Kesinti sonrası devam                                    | ✅                              |
| `--only` tek issue                                       | ✅                              |
| İkinci koşu engelleniyor (flock)                         | ✅                              |
| Sınıf C → temiz-oda denemesi → yine fail                 | ✅                              |
| API/kimlik hatası → koşu anında duruyor                  | ✅                              |
| Üst üste 2 sınıf A → devre kesici                        | ✅                              |
| Hepsi PASS → final kapı, temiz klonda suit               | ✅                              |
| Eksik issue varsa final kapı **koşulmuyor**              | ✅                              |

---

## 9. Geliştirme sırasında yakalanan hatalar

Hepsi **sessiz** hatalardı — exception fırlatmadılar, sadece yanlış sonuç ürettiler.

### `\b` awk'ta çalışmıyor

Kelime sınırı operatörü GNU grep'te var, awk'ın POSIX motorunda yok — ve sessizce eşleşmiyor. Sabotaj kapıları `it.skip(` eklenmiş diff'lerde bile `PASS` veriyordu.

```bash
SKIP_RE='(^|[^A-Za-z0-9_])(it|test)\.(skip|only)'   # her iki motorda çalışır
```

### `awk -v` kaçış karakterlerini bir kez işliyor

`-v skip="...\(..."` ile geçirilen `\(` awk'a `(` olarak ulaşır ve **grup parantezine** dönüşür. Ters bölüleri ikiye katlayan bir `esc()` gerekiyor.

### `-F'"'` ile JSON alanı saymak kırılgan

Journal'ın awk ayrıştırıcısı alan indekslerini yanlış hesaplıyordu (anahtar `i`, değer `i+2`). Mutabakat ve rapor **hata vermeden boş dönüyordu**. Anahtarı isimle arayan bir `val()` fonksiyonuna geçirildi.

### `--dry-run` sonsuz döngüsü

`next` durumu journal'dan okuyor; dry-run hiçbir şey yazmadığı için aynı issue sonsuza kadar dönüyordu. Dry-run artık döngüye hiç girmiyor; ayrıca gerçek modda da journal yazılamazsa döngüyü kesen bir koruma var.

### Anahtar kelime listesine güvenmek

"Invalid API key" mesajı `authentication|credit balance|rate limit` listesine takılmıyordu ve koşu boşuna devam ediyordu. Liste genişletildi **ve** jenerik bir devre kesici eklendi — liste er geç eksik kalır.

### Test ortamı tuzağı

Sahte repo'da `runner/` ve `run-issues.sh` commit'li olduğu için senaryolar arası `git reset --hard` güncellenen script'leri geri alıyordu; düzeltmeler test edilmemiş görünüyordu. **İki kez** aynı tuzağa düştüm. Test ortamı kurarken doğrulanan kodu versiyon kontrolünün dışında tut.

---

## 10. Neden `/batch` değil

Claude Code bu tasarımın elle kurduğu parçaların bir kısmını yerleşik sunuyor: <cite index="11-1">`/batch`, Claude'un bir büyük değişikliği 5–30 worktree-izole subagent'a bölüp her birinin pull request açtığı bir skill</cite>. Ayrıca `--worktree` bayrağı, subagent frontmatter'ında `isolation: worktree`, `--max-budget-usd`, `--max-turns`, `--json-schema` ve `TaskCompleted` hook'ları var.

Dürüst cevap: **`/batch` bağımsız ve paralellenebilir birimler için tasarlandı.** <cite index="15-1">Mekanik migration'lar, API rename'leri, framework geçişleri, repo geneli tip temizliği için uygundur; muğlak ürün feature'ları ve mimari ağırlıklı işler için önerilmez.</cite> Buradaki problem ise sıralı-bağımlı issue'lar, deterministik TDD kapıları, koşular-arası kalıcı durum ve özel retry politikası gerektiriyor.

Custom runner bu yüzden haklı — ama **yerleşik primitifleri kullanır**: `--max-budget-usd`, `--max-turns`, `--output-format json`, git worktree izolasyonu. Tekerlek yalnızca gerçekten farklı olan yerde icat edilir: sıralı DAG, kabul kapıları, journal.

Karar kuralı: işin birimleri bağımsız ve mekanikse `/batch` kullan. Sıralı bağımlılık, TDD disiplini veya kalıcı durum gerekiyorsa bu runner.

---

## 11. Sınırlar ve bilinmesi gerekenler

**`--bare` kullanma.** Başlangıcı hızlandırır ama hook, skill, plugin, MCP ve CLAUDE.md keşfini atlar — `/implement-all` ve `/tdd` hiç yüklenmez.

**Kapılar kanıt üretmez, risk azaltır.** Tautolojik testler, geriye doğru yazılmış beklentiler ve yanıltıcı mock'lar kapılardan geçer. Semantik doğrulama reviewer + insan işidir.

**Advisory reviewer karar mercii değildir.** Reviewer "kriterleri karşılamıyor" dese de kapılar geçerse issue PASS'tır; notu insan incelemesi için saklanır.

**Sürüm bağımlı davranışlar.** CLI bayrakları ve JSON alan adları sürümle değişebilir; `claude --help` ve resmi CLI referansından doğrula. `--max-budget-usd` yaklaşık bir tavandır — <cite index="7-1">harcama tur bazında toplanıp kontrol edildiği için limit aşıldıktan sonra tespit edilir</cite>, yani biraz üstüne çıkabilir.

**Bütçe kümülatiftir.** Sınıf B retry'ları, temiz-oda denemesi ve reviewer
çağrısı — hepsi issue maliyetine ve dolayısıyla koşu tavanına sayılır.
Tavan gerçek bir tavandır; issue başına `--max-budget-usd`, koşu genelinde
`RUN_BUDGET_USD`.

**Final kapının pratiği.** G10 temiz klon kurar (`npm ci` / `pip install`);
private registry, `.env` veya build secret gerektiren projelerde bu adım
sessizce başarısız olabilir — ilk kez elle `./run-issues.sh --final-only`
koşup süreyi ve gereksinimleri gör. `E2E_CMD` tanımsızsa G12 atlanır ve
uyarı düşer; atlanan kapı raporda görünür.

**Windows'ta bash gerekir.** Runner CMD veya PowerShell'de çalışmaz; Git Bash
ya da WSL2 gerekir. Preflight iki Windows'a özgü tuzağı kontrol eder: PATH'teki
`timeout` GNU coreutils mi (System32'deki bekleme komutu değil) ve script'lerde
CRLF satır sonu var mı. Ayrıntı için `KURULUM.md` §1.0.

**Paralelleştirme.** Bağımsız kolları `git worktree` ile paralel koşabilirsin ama integration branch modeli sıralı akış varsayar; paralel kollar birleşirken final kapı daha da kritikleşir.

**Bu sistem insan incelemesini ortadan kaldırmaz.** Yeşil bir dal, kapılardan geçen bir değişiklik demektir — iyi tasarlanmış bir çözüm olduğu anlamına gelmez. Merge etmeden önce diff'e bak.

---

## 12. Sürüm geçmişi

### v1 → v2

| Konu            | v1                                | v2                                                                      |
| --------------- | --------------------------------- | ----------------------------------------------------------------------- |
| Dal modeli      | Her issue `main`'den bağımsız dal | Integration branch + worktree; bağımlılar öncekini görür                |
| Sıra            | `ORDER.txt` düz liste             | DAG, `depends_on` kontrattan, çevrim tespiti, BLOCKED                   |
| Verifier konumu | Repo içinde (ajan yazabilir)      | Repo dışında salt-okunur kopya + G0 anti-tamper                         |
| G5/G6           | İkisi de hard                     | G5a hard / G5b signal / G6 signal + G6' coverage kapısı                 |
| Issue           | Serbest metin                     | Makine-denetlenebilir kontrat (type, paths, acceptance)                 |
| Retry           | "Sabotajda asla"                  | 4 sınıf: A transient, B düzeltilebilir, C ihlal + temiz-oda, D semantik |
| Durum           | `<id>.done` bayrağı               | SHA'lı journal + git mutabakatı                                         |
| Karar aktarımı  | Metin ayrıştırma (`FAIL[...]`)    | Çıkış kodu sözleşmesi                                                   |
| Bütçe           | Yok                               | Issue + koşu tavanı, `--max-budget-usd`, `--max-turns`                  |
| Baseline        | Yok                               | Preflight; kırmızı base'de koşu başlamaz                                |
| Final kapı      | Yok                               | Temiz klonda suit + build + e2e + toplam diff                           |
| Eşzamanlılık    | Yok                               | flock                                                                   |
| Semantik review | Yok                               | Advisory reviewer subagent                                              |
| Atlanan kapılar | Sessiz                            | Journal'da `skipped`                                                    |

### v2 → v3

| Konu                     | v2                            | v3                                                     |
| ------------------------ | ----------------------------- | ------------------------------------------------------ |
| Issue kaydı              | `ISSUES.txt` kayıt defteri    | Dizin taraması; issue dosyası tek kaynak               |
| Kontrat                  | YAML frontmatter              | `Status:` / `## Blocked by` / `## Acceptance criteria` |
| "Done" tanımı            | Yok                           | G14 ailesi (kutular + komutlar + metin + status)       |
| İnsan katılımı           | Kavram yok                    | HITL tipi, `SKIPPED`, `--accept-hitl` akışı            |
| Kriterdeki komutlar      | Yok                           | Tam eşleşme + metakarakter reddi                       |
| İzin reddi               | Fark edilmiyordu              | `permission_denials` → sınıf A                         |
| Profiller                | `docs`/`config`               | + `content`, profil başına zorunlu komut               |
| Coverage × profil        | Belirsiz                      | `NEED_COV`, test üretmeyen profilde atlanır            |
| `--resume`               | Preflight'ı tamamen atlıyordu | Ucuz kontroller her açılışta                           |
| Reviewer salt-okunurluğu | İddia                         | `tools: Read, Grep, Glob` (Bash/Write yok)             |
| İzin modeli              | Dokümanda yok                 | §5.3: mod, deny kuralları, ilk onay                    |

---

## 13. Örnek proje uyarlaması: [project-name]

Genel sözleşme Bölüm 4–6'da; burada yalnızca bu projeye özgü olanlar var.

### 13.1 Config

```bash
ISSUES_DIR=".scratch/[project-name]/issues"
PRD_FILE=".scratch/[project-name]/PRD.md"
ISSUE_TRACK_RE="^\.scratch/"

TEST_CMD="npm test"
LINT_CMD="npm run lint"
TYPECHECK_CMD="npx tsc --noEmit"
BUILD_CMD="npm run build"
E2E_CMD=""                                   # varsa doldur; final kapıda G12
ACCEPTANCE_CMDS_EXTRA="npm run validate-content
npm run content-status"
PROFILE_VERIFY_CONTENT="npm run validate-content"
COVERAGE_MIN=80
PERMISSION_MODE="acceptEdits"
```

`ACCEPTANCE_CMDS_EXTRA`, issue 01 ve 12'nin kriterlerinde geçen
`npm run validate-content` / `npm run content-status` komutlarının G14b'de
koşulabilmesi için gerekli — kümede olmayan komut çalıştırılmaz.

### 13.2 Yapılması gereken tek elle iş

Issue 08–11'e `Gates: content` satırı ekle. Bunlar 48 ders + 48 quiz + 21
proje stub'ı üretir, birim testi değil; profil olmadan her koşuda haksız
yere `G2 fail` alırlar. Profil, `npm run validate-content`'i zorunlu kapı
olarak getirir.

HITL issue'lara (05, 13) `Type: HITL` eklemek isteğe bağlı — PRD tablosundaki
`**HITL**` işaretinden de okunuyor.

### 13.3 `.scratch/` kod sayılmaz

Issue ve PRD dosyaları `ISSUE_TRACK_RE` ile kod diff'inden ayrıştırılır:
kabul kutusu işaretlemek "üretim kodu yazıldı" ya da "kapsam dışına çıkıldı"
sayılmaz. Aynı filtre final kapının G13 toplam diff denetiminde de
uygulanır — aksi halde başarısızlıkta atılan `chore(<id>): status -> ...`
commit'leri gürültü üretirdi.

### 13.4 Bu proje için doğrulanan akış

13 issue PRD'den üretilip test edildi:

- PRD bağımlılık haritası doğru çözülüyor (09 → 07,08; 13 → 01,07,08,10)
- 11 AFK issue bağımlılık sırasında tamamlanıyor
- 2 HITL issue atlanıyor, `--accept-hitl` ile kapılardan geçirilebiliyor
- HITL tamamlanmadan final entegrasyon kapısı koşmuyor
- Her koşudan sonra çalışma ağacı temiz

### 13.5 Bir tasarım hatası ve düzeltmesi

İlk uygulamada status'u **ana checkout'ta** güncelliyordum. İki sorun: (a)
değişiklik hiçbir commit'e girmiyordu, (b) çalışma ağacı kirli kalıyor ve
sonraki koşunun preflight'ini kırıyordu.

Düzeltme: `agent-is-working` ve `done` **worktree kopyasına** yazılır, issue
commit'ine dahil olur. Başarısızlıkta ana checkout güncellenir ve ayrı bir
`chore(<id>): status -> ...` commit'i atılır — hem insan doğru durumu görür
hem ağaç temiz kalır.
