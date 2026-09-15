# TDD Batch Runner v3 — Kurulum Rehberi

Bu dosya, paketi bir projeye kurmak için Claude Code'a verilecek prompt'u ve
kurulum sonrası yapılması gereken kontrolleri içerir.

Sistemin ne yaptığı ve neden böyle tasarlandığı için: `TDD-BATCH-RUNNER.md`

---

## İçindekiler

1. [Ön koşullar](#1-ön-koşullar)
2. [Kurulum prompt'u](#2-kurulum-promptu)
3. [Kurulum sonrası kontroller](#3-kurulum-sonrası-kontroller)
4. [İlk gerçek koşu](#4-ilk-gerçek-koşu)
5. [Tam koşuya geçiş](#5-tam-koşuya-geçiş)
6. [Günlük kullanım](#6-günlük-kullanım)
7. [Sorun giderme](#7-sorun-giderme)

---

## 1. Ön koşullar

### 1.0 Windows kullanıyorsan önce bunu oku

**Runner CMD'de çalışmaz.** `run-issues.sh` ve `runner/*.sh` bash script'leridir;
`git worktree`, `awk`, `mktemp`, `flock` gibi POSIX araçlarına dayanır. Windows'ta
iki seçenek var:

| Ortam                                    | Durum        | Not                                                |
| ---------------------------------------- | ------------ | -------------------------------------------------- |
| **Git Bash** (Git for Windows ile gelir) | Önerilen     | GNU coreutils dahil; `awk`, `timeout`, `sed` hazır |
| **WSL2**                                 | Çalışır      | Node/npm'i WSL içine de kurmak gerekir             |
| CMD / PowerShell                         | **Çalışmaz** | Yalnızca aşağıdaki ön kontroller için              |

Kurulum prompt'unu Claude Code'a CMD'den de verebilirsin, ama Claude Code'un
çalıştıracağı bash komutları Git Bash gerektirir. En temizi: **Git Bash'te aç.**

#### Windows'a özel üç tuzak

**1. `timeout` yanlış komuta çözülebilir.** Windows'un `C:\Windows\System32\timeout.exe`
dosyası GNU `timeout` DEĞİLDİR — bekleme (sleep) komutudur. PATH sırası yanlışsa
issue zaman aşımı sessizce bozulur. Git Bash'te doğrula:

```bash
timeout --version    # "timeout (GNU coreutils) ..." yazmalı
```

Çıktı bu değilse `config.sh`'de `ISSUE_TIMEOUT` etkisiz kalır; preflight uyarır
ama koşu devam eder.

**2. Satır sonları (CRLF) shebang'i bozar.** Repo `core.autocrlf=true` ile
klonlanmışsa `#!/usr/bin/env bash` satırı `\r` ile biter ve script çalışmaz
(`bad interpreter` hatası). Çözüm:

```bash
git config core.autocrlf input
# Zaten bozulduysa:
sed -i 's/\r$//' run-issues.sh runner/*.sh
```

**3. `chmod +x` git'e yazılmaz.** Windows'ta dosya izinleri git'te takip edilmez.
Script'lerin çalıştırılabilir kalması için:

```bash
git update-index --chmod=+x run-issues.sh
git update-index --chmod=+x runner/*.sh
```

---

### 1.1 Ön kontroller

**Git Bash / macOS / Linux:**

```bash
# Araçlar
command -v claude jq git awk timeout   # macOS'ta timeout yoksa: brew install coreutils
timeout --version                      # GNU coreutils olduğunu doğrula

# /tdd skill'i kurulu mu
ls .claude/skills/tdd/ 2>/dev/null || echo "UYARI: /tdd skill'i yok"

# Base dal YEŞİL mi — bu kritik
npm test && npm run lint && npx tsc --noEmit
```

**Windows CMD** (yalnızca ön kontrol için; kurulum Git Bash'te yapılır):

```bat
REM Araclar — bulunamayan varsa "INFO: Could not find files" yazar
where claude
where jq
where git
where npm

REM DIKKAT: CMD'deki `where timeout` System32	imeout.exe'yi bulur.
REM Bu GNU timeout DEGILDIR. Dogru kontrol Git Bash'te yapilir.
where awk 2>nul || echo UYARI: awk yok - Git Bash gerekli

REM /tdd skill'i kurulu mu
if exist ".claude\skills	dd" (echo OK: tdd skill bulundu) else (echo UYARI: /tdd skill yok)

REM Base dal YESIL mi — bu kritik
npm test && npm run lint && npx tsc --noEmit && echo BASE YESIL
```

**Windows PowerShell:**

```powershell
foreach ($t in 'claude','jq','git','npm','awk') {
  if (Get-Command $t -ErrorAction SilentlyContinue) { "OK   $t" } else { "EKSIK $t" }
}

if (Test-Path '.claude\skills	dd') { 'OK: tdd skill bulundu' } else { 'UYARI: /tdd skill yok' }

npm test; if ($LASTEXITCODE -eq 0) { npm run lint }
if ($LASTEXITCODE -eq 0) { npx tsc --noEmit }
if ($LASTEXITCODE -eq 0) { 'BASE YESIL' } else { 'BASE KIRMIZI - kuruluma baslama' }
```

**Base dal kırmızıysa kurulum yapma.** Preflight zaten koşuyu başlatmaz;
kırmızı bir base'de N issue'nun N'i de haksız yere kalır. Önce base'i düzelt.

Paketi projenin yanına klonla (ya da kopyala):

```bash
git clone <paket-repo-url> ../batch-runner-setup   # Git Bash / macOS / Linux
```

Mekanik kurulumu `install.sh` yapar; aşağıdaki §2 prompt'u ise projeye özel
olan `runner/config.sh` doldurma adımı içindir:

```bash
bash ../batch-runner-setup/install.sh --dry-run
bash ../batch-runner-setup/install.sh
```

---

## 2. Kurulum prompt'u

Claude Code'u **proje kökünde** aç ve şunu yapıştır:

```
batch-runner-setup/ klasöründe TDD Batch Runner v3 paketi var. Bu projeye kur.

## Önce oku
- batch-runner-setup/docs/TDD-BATCH-RUNNER.md — özellikle §5 (Kurulum), §4.2 (kapı profilleri),
  §13 (projeye özel notlar)
- batch-runner-setup/examples/config-content-project.sh
- batch-runner-setup/examples/settings-deny-rules.json

## Yap

1. Dosyaları yerleştir:
   - batch-runner-setup/runner/ → ./runner/
   - batch-runner-setup/.claude/agents/*.md → ./.claude/agents/
   - batch-runner-setup/.claude/skills/implement-all/ → ./.claude/skills/implement-all/
   - batch-runner-setup/.claude/skills/tdd/ → ./.claude/skills/tdd/  (projede yoksa)
   - batch-runner-setup/run-issues.sh → ./run-issues.sh
   - chmod +x run-issues.sh runner/*.sh
   Aynı adlı bir dosya zaten varsa ÜZERİNE YAZMA — bana sor.

2. .gitignore'a ekle (yoksa): .tdd-state/ ve .tdd-worktrees/

3. runner/config.sh'yi bu projeye göre düzenle. Değerleri TAHMİN ETME,
   repodan oku:
   - package.json scripts'ine bak → TEST_CMD, LINT_CMD, TYPECHECK_CMD, BUILD_CMD.
     Karşılığı olmayan komutu "" bırak (kapı atlanır, journal'a skipped yazılır).
   - Issue dizinini ve PRD yolunu doğrula → ISSUES_DIR, PRD_FILE, ISSUE_TRACK_RE
   - validate-content / content-status script'leri varsa
     ACCEPTANCE_CMDS_EXTRA ve PROFILE_VERIFY_CONTENT'e yaz.
     DİKKAT: G14b tam eşleşme arar. Kabul kriterlerinde geçen bir komut bu
     kümede birebir yoksa çalıştırılmaz. Issue'ların "## Acceptance criteria"
     bölümlerindeki backtick'li komutları tara ve hangilerinin kümeye
     girmesi gerektiğini bana listele.
   - TEST_FILE_RE'yi projenin gerçek test dosyası deseniyle eşle
     (repoda arayıp doğrula, varsayma).

4. .claude/settings.json'a deny kurallarını ekle
   (examples/settings-deny-rules.json örnek). Dosya varsa MERGE et, ezme.

5. Issue dosyalarına kapı profili ekle: birim testi değil içerik/stub üreten
   issue'lara başlığa "Gates: content" satırı ekle. Hangilerinin bu profile
   girdiğini PRD ve issue içeriğinden çıkar, bana GEREKÇESİYLE listele ve
   onayımı aldıktan sonra ekle. Issue'ların başka hiçbir satırına dokunma —
   özellikle "## Acceptance criteria" ve "Status:" satırlarına.

## Doğrula (sırayla, çıktılarını göster)
   runner/contract.sh parse <bir issue dosyası>
   runner/graph.sh validate
   runner/graph.sh order
   runner/graph.sh hitl
   ./run-issues.sh --dry-run

## Yapma
- HİÇBİR issue'yu çalıştırma. Kurulum bitince dur.
- Kabul kriterlerini yazma, değiştirme, silme.
- runner/ içindeki script'lerin mantığını değiştirme; sadece config.sh'yi düzenle.

## Bitince raporla
- Hangi config değerlerini neye göre belirledin
- Kaç issue bulundu, kaçı HITL, bağımlılık grafı doğru mu
- Kabul kriterlerinde geçip ACCEPTANCE_CMDS_EXTRA'ya girmeyen komutlar
- Eksik kalan / benim karar vermem gereken şeyler
```

### Prompt'taki kısıtların gerekçesi

| Kısıt                                | Neden                                                              |
| ------------------------------------ | ------------------------------------------------------------------ |
| "Değerleri tahmin etme, repodan oku" | Yanlış `TEST_CMD` her issue'da yanlış kapı sonucu üretir           |
| "Kabul kriterlerini değiştirme"      | G14c bunu hard fail sayar; kurulum ajanı da bu kuraldan muaf değil |
| "Üzerine yazma, sor"                 | Mevcut `.claude/settings.json` veya `runner/` çakışabilir          |
| "Hiçbir issue'yu çalıştırma"         | Kurulum ile ilk koşu ayrı kararlar; kalibrasyon senin işin         |
| "`Gates: content` için onay al"      | Profil seçimi kapıları gevşetir — sessizce yapılmamalı             |

---

## 3. Kurulum sonrası kontroller

Kurulum ajanının raporunu okuduktan sonra bunları **kendin** çalıştır.

### 3.1 Dosya yerleşimi

```bash
ls -l run-issues.sh runner/*.sh          # hepsi çalıştırılabilir mi
ls .claude/agents/tdd-*.md
ls .claude/skills/implement-all/SKILL.md
grep -E '^\.tdd-(state|worktrees)/' .gitignore
```

Beklenen: 9 runner script'i (`config`, `lib`, `contract`, `status`, `graph`,
`journal`, `preflight`, `verify`, `final-gate`), 2 agent, 1 skill.

### 3.2 Config doğruluğu

```bash
grep -E '^(TEST|LINT|TYPECHECK|BUILD|E2E)_CMD|^ISSUES_DIR|^PRD_FILE|^ISSUE_TRACK_RE|^COVERAGE' runner/config.sh
```

Kontrol listesi:

- [ ] `TEST_CMD` gerçekten çalışıyor mu — elle bir kez koş
- [ ] Karşılığı olmayan komut `""` mi (uydurulmuş bir script adı değil)
- [ ] `ISSUES_DIR` ve `PRD_FILE` gerçek yollar mı
- [ ] `ISSUE_TRACK_RE` issue dizinini kapsıyor mu
- [ ] `TEST_FILE_RE` projenin gerçek test dosyalarıyla eşleşiyor mu:

```bash
source runner/config.sh
git ls-files | grep -E "$TEST_FILE_RE" | head
```

Bu komut boş dönüyorsa `TEST_FILE_RE` yanlış — G2 ve G6 her issue'da yanlış
sonuç verir.

### 3.3 Kabul kriteri komutları (G14b)

En kolay gözden kaçan yer burası. Kriterlerde geçen ama `config.sh`'de
tanımlı olmayan komutlar **çalıştırılmaz**, sadece WARN düşer:

```bash
# Kriterlerde geçen tüm komut adayları
for f in "$ISSUES_DIR"/*.md; do runner/contract.sh commands "$f"; done | sort -u

# Config'te tanımlı küme
grep -A3 'ACCEPTANCE_CMDS_EXTRA' runner/config.sh
grep -E '^(TEST|LINT|TYPECHECK|BUILD)_CMD' runner/config.sh
```

İkisini karşılaştır. Kriterlerde geçen her komut kümede **birebir** olmalı —
`npm test` ile `npm run test` farklı sayılır.

### 3.4 Graf ve issue sözleşmesi

```bash
runner/graph.sh validate     # çevrim, eksik dosya, çözülemeyen bağımlılık
runner/graph.sh order        # topolojik sıra
runner/graph.sh hitl         # insan gerektiren issue'lar
runner/contract.sh parse "$ISSUES_DIR"/01-*.md
```

Kontrol listesi:

- [ ] `validate` sıfır hata veriyor (WARN olabilir)
- [ ] `order` çıktısı PRD'deki bağımlılık haritasıyla uyuşuyor
- [ ] `hitl` listesi PRD'de `HITL` işaretli issue'larla aynı
- [ ] `parse` çıktısında `C_STATUS`, `C_DEPENDS_ON`, `C_ACC_TOTAL` doğru
- [ ] `C_ACC_TOTAL` 0 olan issue yok (0 = "done" tanımı belirsiz → `SKIPPED`)

### 3.5 Kapı profilleri

```bash
grep -l '^Gates:' "$ISSUES_DIR"/*.md
```

İçerik/stub üreten issue'ların `Gates: content` aldığını doğrula. Profil
olmadan bu issue'lar her koşuda `G2 fail` (test dosyası yok) alır.

### 3.6 İzin modeli

```bash
grep -E '^PERMISSION_MODE|^ALLOWED_TOOLS' runner/config.sh
cat .claude/settings.json | jq '.permissions.deny'
```

- [ ] `PERMISSION_MODE` bilinçli seçilmiş (`acceptEdits` çoğu proje için yeterli)
- [ ] Deny kuralları `runner/`, `.claude/`, `run-issues.sh` yazımını engelliyor
- [ ] `bypassPermissions` seçildiyse bir kez interaktif onay verilmiş:
      `claude --permission-mode bypassPermissions`

### 3.7 Dry-run

```bash
./run-issues.sh --dry-run
```

Çıktıda görülmesi gerekenler:

- [ ] Integration dalı adı ve runner'ın salt-okunur kopya yolu
- [ ] Her issue için durum, bağımlılıklar, `Status:` değeri
- [ ] HITL issue'larda `[HITL-ATLANIR]` etiketi
- [ ] `OK graf gecerli — N issue`
- [ ] **Hiçbir şey çalıştırılmadı** (dal açılmadı, commit atılmadı)

```bash
git status --porcelain    # boş olmalı
git branch                # batch/ dalı oluşmamış olmalı
```

---

## 4. İlk gerçek koşu

**Tek issue ile başla. Bunu atlama.**

```bash
./run-issues.sh --limit 1
```

Bir issue'nun çıktısını okumadan tamamına açmak, kötü bir prompt'un N kez
tekrarlanması demektir.

### İncelenecekler

```bash
B=$(cat .tdd-state/integration-branch)

# 1. Üretilen diff — asıl kalibrasyon burada
git log --oneline "$B" | head -3
git show "$B" --stat
git show "$B"

# 2. Maliyet — N ile çarp, bütçene sığıyor mu
jq -r '.total_cost_usd' .tdd-state/logs/*.json

# 3. Advisory review — kapıların ölçemediği şeyler
cat .tdd-state/reviews/*.md

# 4. Kapı sonuçları ve atlanan kapılar
runner/journal.sh get <issue-id> | jq -r '.gates'

# 5. Issue dosyası durumu
runner/status.sh get "$ISSUES_DIR"/01-*.md          # done olmalı
runner/status.sh tick-report "$ISSUES_DIR"/01-*.md  # tüm kutular ✓ olmalı
```

### Kalite soruları

| Soru                                                          | Nerede bakılır            |
| ------------------------------------------------------------- | ------------------------- |
| Testler anlamlı mı, tautolojik mi (`expect(true).toBe(true)`) | `git show`                |
| Kabul kriterleri gerçekten karşılanmış mı                     | `.tdd-state/reviews/*.md` |
| Kaç kapı `skipped` — sessizce zayıflama var mı                | journal `gates` alanı     |
| Kaç WARN düştü                                                | koşu çıktısı              |
| Maliyet × issue sayısı bütçeye sığıyor mu                     | `total_cost_usd`          |

Advisory raporda **"işaretli ama kanıt yok"** satırı varsa dikkat: kapılar
bunu yakalayamaz, çünkü kutu işaretlidir ve testler yeşildir.

### Beğenmediysen

```bash
git checkout main
git branch -D "$B"
rm -rf .tdd-state .tdd-worktrees
```

Sonra `config.sh`'yi veya issue'nun kabul kriterlerini düzelt, tekrar dene.
Üst üste birkaç issue `WARN G6` veya `G4 fail` veriyorsa sorun ajanda değil
issue'lardadır: kabul kriterleri test edilebilir biçimde yazılmamış demektir.

---

## 5. Tam koşuya geçiş

İlk issue tatmin ediciyse:

```bash
./run-issues.sh
```

Koşu kesilirse tekrar çalıştır — journal + git mutabakatı kaldığı yerden
devam ettirir. `--resume` yalnızca pahalı baseline suite'ini atlar; araç,
repo, graf, kilit kontrolleri her açılışta koşar.

### HITL issue'lar

Otonom koşu bunları atlar ve `SKIPPED` yazar. Tüm AFK issue'lar bittikten
sonra:

```bash
B=$(cat .tdd-state/integration-branch)
git checkout "$B"

# ... insan işi yapar, kabul kutularını işaretler ...

./run-issues.sh --accept-hitl 05
```

İnsanın yaptığı iş de **aynı kapılardan geçer**; `done` yazma yetkisi insana
da geçmez. Kapılar kalırsa `done` yazılmaz ve komut sıfır dışı kodla çıkar.

Bağımlıları açmak için `./run-issues.sh --resume` yeter — `BLOCKED` türetilmiş
bir durumdur, bağımlılığı `PASSED` olunca issue yeniden uygun hale gelir.

### Final entegrasyon kapısı

Tüm issue'lar `PASSED` olunca otomatik koşar. Elle:

```bash
./run-issues.sh --final-only
```

Bu kapı temiz bir klon kurar (`npm ci`); private registry, `.env` veya build
secret gerektiren projelerde ilk kez elle koşup süreyi ve gereksinimleri gör.

### Merge

```bash
runner/journal.sh report          # hepsi PASSED mi
git diff main.."$B" --stat        # toplam değişiklik
```

Final kapı geçse bile **diff'i oku**. Yeşil bir dal, kapılardan geçen bir
değişiklik demektir — iyi tasarlanmış bir çözüm olduğu anlamına gelmez.

---

## 6. Günlük kullanım

```bash
./run-issues.sh --dry-run           # plan
./run-issues.sh --limit N           # N issue
./run-issues.sh                     # kalan hepsi
./run-issues.sh --only 07-api       # tek issue, sıfırlanarak
./run-issues.sh --resume            # baseline'ı atlayarak devam
./run-issues.sh --accept-hitl 05    # insan işini kapılardan geçir
./run-issues.sh --final-only        # final entegrasyon kapısı

runner/journal.sh report            # durum tablosu
runner/journal.sh get <id>          # tek issue kaydı (JSON)
runner/journal.sh cost              # toplam harcama
runner/journal.sh reset <id>        # durumu sıfırla
runner/status.sh tick-report <path> # kabul kriteri işaretleme durumu
runner/graph.sh order               # topolojik sıra
runner/graph.sh blocked <id>        # bu issue fail ederse kimler bloke olur
```

---

## 7. Sorun giderme

| Belirti                                  | Sebep                                            | Çözüm                                                         |
| ---------------------------------------- | ------------------------------------------------ | ------------------------------------------------------------- |
| `preflight basarisiz` — baseline kırmızı | Base dalda mevcut hata var                       | Önce base'i yeşile getir                                      |
| `calisma agaci kirli`                    | Commit'lenmemiş değişiklik                       | Commit'le veya stash'le                                       |
| `baska bir kosu devam ediyor`            | flock kilidi                                     | Diğer koşu bitene kadar bekle; çökmüşse `rm .tdd-state/.lock` |
| Her issue `G2 fail`                      | `TEST_FILE_RE` yanlış veya profil eksik          | §3.2 ve §3.5'i tekrarla                                       |
| Her issue `G1 fail` (nodiff)             | İzin reddi olabilir                              | `jq '.permission_denials' .tdd-state/logs/*.json`             |
| `sinif A: izin reddi`                    | Permission mode / deny kuralı dar                | §3.6'yı gözden geçir                                          |
| `G14a fail` — kutular işaretsiz          | Ajan işi yaptı ama beyan etmedi                  | Retry zaten deniyor; ısrar ederse issue çok büyük olabilir    |
| `G14b ... KOSULMADI` WARN                | Kriterdeki komut config kümesinde yok            | `ACCEPTANCE_CMDS_EXTRA`'ya ekle                               |
| `G14c fail`                              | Ajan kriter metnini değiştirmiş                  | Worktree'yi incele; kriter muğlaksa sen düzelt                |
| `G14d fail`                              | Ajan `Status:` satırına dokunmuş                 | Politika ihlali; `needs-human`                                |
| `ust uste 2 altyapi hatasi`              | Ortam sorunu (kota, ağ, auth)                    | Devre kesici çalıştı; ortamı düzelt                           |
| `FINAL KAPI GECILEMEDI`                  | Issue'lar tek tek yeşil, bütün kırmızı           | Entegrasyon regression'ı ara                                  |
| Kalan worktree'ler                       | Başarısız issue'ların dalları bilinçli bırakılır | `git worktree list`, inceleyip `git worktree remove`          |
| `bad interpreter: ^M` (Windows)          | CRLF satır sonu                                  | `sed -i 's/\r$//' run-issues.sh runner/*.sh`                  |
| `Permission denied` (Windows)            | `chmod +x` git'e yazılmamış                      | `git update-index --chmod=+x runner/*.sh`                     |
| Zaman aşımı hiç çalışmıyor (Windows)     | System32\timeout.exe kullanılıyor                | Git Bash'te `timeout --version` ile doğrula                   |

### Durumu tamamen sıfırlama

```bash
git checkout main
git worktree list --porcelain | awk '/^worktree /{print $2}' \
  | grep -v "^$(pwd)$" | xargs -r -n1 git worktree remove --force
git branch | sed 's/^[* ]*//' | grep -E '^(batch|issue)/' | xargs -r git branch -D
rm -rf .tdd-state .tdd-worktrees
```

Issue dosyalarındaki `Status:` alanları bundan etkilenmez; gerekiyorsa elle
`ready-for-agent` yap.
