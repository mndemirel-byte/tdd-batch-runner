# TDD Batch Runner v3

Bir issue setini Claude Code ile **otonom, doğrulanabilir ve kesintiye dayanıklı**
biçimde implement eden koşucu. Her issue kendi git worktree'sinde, kendi taze
`claude -p` oturumunda TDD ile yazılır; sonuç ajanın erişemediği deterministik
kapılardan geçmeden `done` sayılmaz.

Temel ilke: **ajanın "tamamlandı" demesi kanıt değildir.** Karar mercii, ajanın
değiştiremeyeceği bir yerden çalışan doğrulama script'lerinin çıkış kodudur.

---

## Kurulum

Hedef projenin kökünde (Windows'ta **Git Bash** içinde — CMD/PowerShell çalışmaz):

```bash
git clone <bu-repo> /tmp/batch-runner-setup
bash /tmp/batch-runner-setup/install.sh --dry-run   # ne yapacağını göster
bash /tmp/batch-runner-setup/install.sh             # mekanik kurulum
```

`install.sh` sadece mekanik işleri yapar: dosya kopyalama, `chmod +x`,
`.gitignore` girdileri, satır sonu ve araç kontrolü.

Sonra **projeye özel** olan iki adım kalır:

1. `runner/config.sh`'yi doldur — `docs/KURULUM.md` §2'deki prompt'u Claude Code'a ver.
2. `.claude/settings.json` deny kurallarını ekle — `examples/settings-deny-rules.json`.

Doğrula:

```bash
runner/graph.sh validate
./run-issues.sh --dry-run
```

---

## Bu repo ne içeriyor

```
├── install.sh                       Bootstrap: kopyala, chmod, .gitignore, ön kontroller
├── run-one.sh                       Tek issue koş (run-issues.sh --only sarmalayıcısı)
├── BUILD-PROMPT.md                  Benzerini sıfırdan Claude'a kurduracaklar için anayasa + 4 aşama prompt'u
├── run-issues.sh                    Dış koşucu — issue sırası, worktree, retry, merge, devre kesici
├── runner/                          Deterministik kapılar (koşu başında repo DIŞINA kopyalanır)
│   ├── config.sh                    ⚠ PROJEYE ÖZEL — kurulumdan sonra doldurulacak tek dosya
│   ├── lib.sh                       Ortak yardımcılar, çıkış kodu sınıfları
│   ├── preflight.sh                 Koşu öncesi ortam/repo temizlik kontrolleri
│   ├── contract.sh                  Issue dosyası sözleşmesi (Status:, Gates:, kabul kriterleri)
│   ├── graph.sh                     Bağımlılık grafiği: validate / order / next / blocked
│   ├── verify.sh                    G0–G14 kapıları. Çıkış kodu = karar sınıfı (0/1/2/4)
│   ├── status.sh                    Issue `Status:` satırını yazan tek yer (ajan değil, koşucu)
│   ├── journal.sh                   `.tdd-state/journal.jsonl` — kesintiye dayanıklı durum
│   └── final-gate.sh                Koşu sonu: temiz klonda tam suit + build + toplam diff denetimi
├── .claude/
│   ├── agents/tdd-implementer.md    Tek issue'yu TDD ile yazan subagent (kısıtlı tool seti)
│   ├── agents/tdd-reviewer.md       Diff'i kabul kriterlerine karşı okuyan ADVISORY reviewer
│   ├── skills/implement-all/        Orkestratör skill — run-issues.sh her issue için bunu çağırır
│   └── skills/tdd/                  /tdd skill'i (implementer'ın zorunlu bağımlılığı)
├── examples/
│   ├── settings-deny-rules.json     .claude/settings.json'a eklenecek deny kuralları
│   ├── settings-full.json           Gerçek bir projeden tam settings.json örneği
│   ├── settings-local-allow.json    settings.local.json allow listesi örneği
│   ├── config-webapp-project.sh     Web uygulaması ([project-name]) — gerçek koşudan config + saha notları
│   ├── config-content-project.sh    İçerik ağırlıklı örnek proje ([project-name]) config'i
│   ├── config-jest.sh               Jest tabanlı proje config'i
│   └── config-python.sh             Python/pytest projesi config'i
├── templates/
│   └── issue-template.md            Koşucunun okuyabileceği issue formatı
└── docs/
    ├── KURULUM.md                   Adım adım kurulum + kurulum prompt'u + sorun giderme
    ├── TDD-BATCH-RUNNER.md          Tam referans: her kapı, her çıkış kodu, her karar
    ├── tdd-batch-runner-rehberi.md  Dosya dosya "neden böyle" rehberi
    └── agents/
        ├── issue-tracker.md         `.scratch/` altındaki yerel issue tracker sözleşmesi
        └── triage-labels.md         Etiket vokabüleri (ready-for-agent, agent-is-working, done…)
```

---

## Mimari

```
main/master
   └─► batch/run-<tarih>  (integration branch)
          ├─ issue 01: worktree(integration HEAD) → ajan → verify → commit → merge
          ├─ issue 02: worktree(YENİ integration HEAD) → ...   (bağımlılar öncekilerin kodunu görür)
          └─ FINAL: temiz klonda tam suit + build + e2e + toplam diff denetimi
```

İlkeler her harness'a taşınır; sağ sütun onların **bu repodaki** uygulamasıdır — uygulama tartışılabilir, ilke tartışılamaz (bkz. `BUILD-PROMPT.md` anayasası):

| İlke (taşınabilir)                        | Bu repodaki uygulama                                                                        |
| ----------------------------------------- | ------------------------------------------------------------------------------------------- |
| Ajan kendi işini kabul edemez             | `Status:` satırını koşucu yazar; ajan dokunursa G14d hard-fail                               |
| Doğrulama kodu ajan tarafından değişmez    | Koşu başında `runner/` repo **dışına** kopyalanır ve salt-okunur yapılır; içerideki kopyaya dokunulursa G0 hard-fail |
| Karar metin değil çıkış kodu              | `verify.sh` çıkış kodu = karar sınıfı; koşucu metin ayrıştırmaz                               |
| Beyan ≠ kanıt                             | Kabul kriterindeki komutlar ayrıca gerçekten koşulur (G14b)                                   |
| İzolasyon üç boyutta                      | conversation (fresh `claude -p`), workspace (issue başına git worktree), yetki (subagent tool kısıtları) |

---

## Ön koşullar

| Araç                    | Neden                                                       |
| ----------------------- | ----------------------------------------------------------- |
| Git Bash / WSL / Linux  | POSIX bash, `git worktree`, `awk`, `mktemp`, `flock`         |
| `claude` CLI            | Headless `claude -p` koşuları                                |
| `jq`                    | Journal ve `claude -p` JSON çıktısı ayrıştırma               |
| GNU `timeout`           | Issue zaman aşımı. **Windows'taki `System32\timeout.exe` değil** |

`timeout` yoksa koşu çalışır ama zaman aşımı uygulanmaz — takılan bir issue
koşuyu süresiz bloke eder.

---

## Günlük kullanım

```bash
./run-issues.sh --dry-run              # sıra ve plan
./run-issues.sh                        # tüm hazır issue'ları koş
./run-one.sh 03                        # tek issue (= --only 03)
runner/status.sh                       # nerede kalındı
runner/graph.sh validate               # bağımlılık grafiği tutarlı mı
```

Koşu durumu `.tdd-state/` altında tutulur ve `.gitignore`'dadır; kesilen bir
koşu aynı komutla kaldığı yerden devam eder.

Ayrıntı için `docs/KURULUM.md` ve `docs/TDD-BATCH-RUNNER.md`.

---

## Bu klasörü ayrı bir repo yapmak

```bash
cd batch-runner-setup
git init
git add -A
# Windows: exec biti dosya sisteminden okunmuyor, git'e ayrica yazilmali.
# Bu adim atlanirsa klonlayan "Permission denied" alir.
git update-index --chmod=+x install.sh run-issues.sh runner/*.sh
git -c core.autocrlf=input commit -m "feat: TDD batch runner v3 kurulum paketi"
git remote add origin <yeni-repo-url>
git push -u origin main
```

İki not:

- **`core.autocrlf`**: Git for Windows sistem genelinde `true` tanımlar. Paketteki
  `.gitattributes` `*.sh text eol=lf` ile bunu ezer, ama repo ilk kez başka bir
  makinede klonlanmadan önce doğrulamakta fayda var: CRLF'li bir shebang
  `bad interpreter` hatası verir.
- **`.claude/` klasörü**: Bu paket başka bir projenin içinde dururken, Claude Code
  `.claude/skills/` altındaki skill'leri o projenin namespace'ine
  dizin-kapsamlı (`batch-runner-setup:tdd` gibi) olarak da kaydeder. Zararsız,
  ama ayrı repoya taşındıktan sonra bu klasörü ana projeden silmek namespace'i
  temizler.
