Status: ready-for-agent
Gates: feature

# 01 — Kisa ve emir kipinde baslik

## Parent

`.scratch/<batch-adi>/PRD.md`

## What to build

Ne yapilacagi. Tek bir dikey dilim (tracer bullet): bir ucundan digerine
calisan, tek basina merge edilebilir bir degisiklik. "Sunu da refactor et"
gibi yan isler ayri issue olmali.

Dosya yollari, tip imzalari, tablo semasi gibi somut ayrintilari buraya yaz.
Uygulayan agent PRD'yi okumak zorunda kalmasin diye issue kendi kendine
yetsin.

## Notes

Tuzaklar, mevcut kodla catisan yerler, kasitli olarak kapsam disi birakilan
seyler.

## Acceptance criteria

Her madde **calistirilabilir** ya da **gozlemlenebilir** olmali. Ajanin
kutuyu isaretlemesi beyandir, kanit degil: kriterde gecen komutlar G14b
tarafindan ayrica gercekten kosulur.

- [ ] `src/foo/bar.ts` disari `parseThing()` veriyor ve gecersiz girdide throw ediyor
- [ ] `npx vitest run src/foo/bar.test.ts` geciyor
- [ ] `npm test` geciyor; `npx tsc --noEmit` sifir hata
- [ ] `npm run lint` temiz

## Blocked by

- `.scratch/<batch-adi>/issues/00-onceki-issue.md` (neden bloke ettigi)
