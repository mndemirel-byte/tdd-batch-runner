# BUILD-PROMPT — bu repoyu (benzerini) sifirdan Claude'a kurdurma prompt'lari

Bu repo hazir bir uygulamadir; kurmak icin `install.sh` + `docs/KURULUM.md` yeter.
Bu dosya farkli bir ihtiyac icindir: **ayni mekanizmayi kendi zevkinize gore
sifirdan Claude'a insa ettirmek.** Asagidaki prompt'lar bu reponun insa
surecinin damitilmis halidir; her asamanin bu repodaki karsiligi sonda tabloda.

Kritik risk baştan: insa eden ajan degismezleri bilmezse kapilari "pratiklik"
gerekcesiyle gevsetir — kendi odevine not veremeyen ajan, not sistemini
kurarken de kendine kolaylik tanir. Care: her insa oturumunun basina konan
ve pazarliga kapali olan ANAYASA blogu.

## Anayasa (her insa oturumunun ilk mesaji)

```text
Bu projede bir batch runner kuruyoruz. Asagidaki ILKELER anayasadir,
hicbir asamada gevsetilemez. Her ilkenin altindaki satir bu projedeki
UYGULAMASIDIR: uygulama tartisilabilir, ilke tartisilamaz.
1. Kabul durumunu uretici degistiremez.
   -> Status'u yalnizca kosucu yazar (agent-is-working damgasi dahil);
      ajan Status satirina dokunamaz, verify beklenen degeri denetler.
2. Uretici, kabul mekanizmasini ve verifier'lari degistiremez.
   -> repo disi salt-okunur kopya + deny kurallari + anti-tamper kapi
      (+ mumkunse sandbox yazma engeli).
3. Authoritative kabul sonucu model prose'undan turetilmez;
   deterministik ve makine-okur bir verifier sonucudur.
   -> bu runner'da sozlesme dort cikis kodudur: 0 PASS, 1 RETRY,
      2 HARD, 4 INFRA.
4. Beyan kanit degildir.
   -> kriter kutusu isaretlemek yetmez; kriterdeki komutlar yalnizca
      config'te TAM eslesenler olmak uzere ayrica kosulur.
5. Kapi EKLEYEBILIRSIN; kapi cikaramaz, kosulunu gevsetemezsin.
Her asamada: once yazili plan, onayimdan sonra kod.
Her asama sonunda: degisikligi nasil dogrulayacagimi soyle.
```

## Asama 1 — Ciplak kosu (Katman 0–1: process + exit-0 yalani)

```text
GOAL: Tek issue path'i alan run-one akisini planla: integration HEAD'den
  gecici worktree ac, icinde claude -p cagir, sonucu raporla.
CONSTRAINTS: JSON cikti; butce ve tur siniri bayraklari; izin modu
  config'ten okunur; ANAYASA madde 2 ve 3 bu script icin de gecerli.
EXPECTED ARTIFACT: script plani + JSON'dan okunacak alanlarin listesi
  (subtype, permission_denials + reddedilen tool adlari, total_cost_usd)
  + config alanlari.
ACCEPTANCE CHECK: izinsiz bir kosuda izin reddi raporda GORUNUR olmali;
  butce siniri kosuyu kesmeli. Ikisini nasil test edecegini yaz.
```

## Asama 2 — Verifier (Katman 2–4: kirmizi test, sabotaj, bos diff)

```text
GOAL: verify.sh'yi planla — sira: anti-tamper -> kontrat kapsami ->
  diff varligi -> skip/silme taramasi -> test/lint/typecheck ->
  changed-line coverage -> kriterlerde gecen komutlarin icrasi.
CONSTRAINTS: cikis kodu sozlesmesi 0/1/2/4; her kapi hard/sinyal olarak
  etiketlenir; verifier kosuda repo DISI salt-okunur kopyadan calisir;
  ajanin raporu hicbir kapida girdi degildir; kriter komutlarinda shell
  metakarakteri = hard fail, tam-eslesme disinda kosulmaz.
EXPECTED ARTIFACT: kapi listesi + her kapinin sinifi ve gerekcesi + plan.
ACCEPTANCE CHECK: dort tatbikat — kasitli .skip, kasitli test silme,
  verify'a dokunus (ucu HARD); assert gevsetme (sinyale duser).
```

## Asama 3 — Dongu (olcek: sira, hafiza, devam)

```text
GOAL: Donguyu kur — issue sozlesmesi (Status yasam dongusu, kabul
  kutulari, Blocked by), bagimlilik grafi, integration branch akisi,
  append-only journal.
CONSTRAINTS: uc kayit, uc otorite — issue dosyasi=workflow durumu,
  git=gerceklesmis kod (TDD-Issue trailer'lari), journal=kosu kaniti;
  celiskide git kazanir, mutabakat IKI yonlu (hayali SHA dusurulur,
  trailer'li commit geri kazanilir); done'i yalnizca kosucu yazar;
  PASS commit'i integration'a ancak ata-dogrulamasiyla
  (merge-base --is-ancestor) katilmis sayilir; fail bagimlilarini bloklar.
EXPECTED ARTIFACT: durum makinesi + mutabakat algoritmasi plani.
ACCEPTANCE CHECK: kesinti tatbikati — kosunun ortasinda process'i oldur,
  yeniden baslat; kaldigi yerden dogru devam ettigini journal+git ile goster.
```

## Asama 4 — Akis kontrolu (dayaniklilik)

```text
GOAL: Akis kontrolunu kur — dort retry sinifi, iki butce katmani,
  ardisik altyapi hatasinda devre kesici, kosu sonunda final kapi.
CONSTRAINTS: ihlalde workspace ATILIR, ayni workspace'te retry yok;
  temiz-oda denemesi en fazla bir ve guclendirilmis uyariyla; final kapi
  temiz klonda kosar; G7 kirmizisinda ajansiz bir flaky re-run serbest.
EXPECTED ARTIFACT: basarisizlik->sinif->tepki tablosu + final kapi adimlari.
ACCEPTANCE CHECK: sinif basina bir simulasyon; butce tavani kosuyu TEMIZ
  durdurmali — yarim commit yok, journal tutarli, rapor eksiksiz.
```

## Asamalarin bu repodaki karsiliklari

| Asama | Bu repoda |
|---|---|
| 1 Ciplak kosu | `run-one.sh`, `run-issues.sh` (claude cagrisi + Katman 0/1 blogu), `runner/config.sh` |
| 2 Verifier | `runner/verify.sh`, `runner/lib.sh` (EXIT_*), `examples/settings-deny-rules.json` |
| 3 Dongu | `runner/graph.sh`, `runner/journal.sh`, `runner/contract.sh`, `runner/status.sh`, `run-issues.sh` (integration + merge dogrulamasi) |
| 4 Akis kontrolu | `run-issues.sh` (retry siniflari, devre kesici, butce), `runner/final-gate.sh`, `runner/preflight.sh` |

Uyari: insa ajaninin kodu sahiplenilmemis koddur — verifier'in verifier'i
sizsiniz. Her asamanin kabul kontrolu okumayi ODAKLAR; yerine gecmez.
