# COP Mobile

Tenký nativní host pro existující webovou aplikaci Civil Situation Map (COP/CSM).
Projekt zpřístupní funkce zařízení, které web/PWA nemůže poskytovat dostatečně
spolehlivě: přesnou polohu, kompas a 3D orientaci, uživatelem spuštěné sledování
polohy na pozadí, systémové notifikace, příjem fotografií a dokumentů a později
experimentální device-to-device relay. Vlastníkem produktu je tým COP.

## Stav

Repozitář obsahuje samostatnou iOS aplikaci pro iOS/iPadOS 26, bezpečný
`WKWebView` host mapy a hlášení, nativní komunikační povrch, handshake Device
API `1.0.0`, lokální fallback a unit/contract testy. Komunikační kód je vlastněn
přímo tímto repozitářem v `packages/CSMCommunicationKit`; sestavení nepotřebuje
původní velkou iOS aplikaci ani její Git repozitář.

Závazný baseline:

- minimum iOS/iPadOS 26;
- schválený a přesně připnutý Xcode 27 beta / iOS SDK 27 toolchain;
- existující COP web zůstává zdrojem mapy, hlášení a business logiky;
- nativní vrstva vlastní chat a systémové chování komunikace, ale
  neimplementuje vlastní mapu, report workflow ani AI;
- `CommunicationModel` je komunikační runtime; původní víceúčelový
  `AppModel` a nativní map/relay/watch zdroje nejsou součástí aplikace;
- relay je mimo MVP, v produkci vypnutý a označený jako experiment;
- Android bude používat stejný verzovaný device kontrakt v pozdější fázi.

## Cílové funkce

- bezpečný `WKWebView` host pro povolený HTTPS origin COP;
- verzovaný, capability-based COP Device API a bridge;
- location, heading, foreground attitude a durable background tracking session;
- APNs, lokální notifikace, deep links a pravdivý stav slyšitelnosti;
- iOS Share Extension a chráněný inbox fotografií, videí a dokumentů;
- lokální offline fallback a ověřený start z PWA cache;
- budoucí Android parita a foreground-oriented relay POC.

## Struktura

```text
apps/ios/       samostatný SwiftUI host COP Mobile
apps/android/   rezervovaná hranice pro pozdější Android host
packages/       lokální komunikace a mobilní utility; Device kontrakt zůstává v COP
tests/          contract, integration a real-device testovací podklady
docs/           aktivní dokumentace a ADR
config/         bezpečné, verzované konfigurační šablony
```

## Integrace

- COP web/API: `/Users/voldzi/Developer/18 2026/DELTA_ACR/01 COP`
- historický referenční klient: `04 CSM messenger` (není build ani runtime závislost)
- CSM Messaging/APNs: `/Users/voldzi/Developer/18 2026/DELTA_ACR/05 Messaging`
- autoritativní COP API: `01 COP/openapi/openapi.json`

Projekt neposkytuje vlastní REST API. Popis konzumovaných kontraktů je v
[`docs/api.md`](docs/api.md).

## Lokální ověření

Úplná lokální kontrola:

```bash
bash scripts/check.sh
```

Závazný toolchain je Xcode 27.0 beta build `27A5228h` s iOS SDK 27.0. Kontroluje
jej `scripts/verify-apple-toolchain.sh`; minimum aplikace zůstává iOS/iPadOS
26.0.

## Dokumentace

Rozcestník je v [`docs/README.md`](docs/README.md). Nejdůležitější vstupy:

- [`docs/repository-assessment.md`](docs/repository-assessment.md)
- [`docs/implementation-plan.md`](docs/implementation-plan.md)
- [`docs/architecture.md`](docs/architecture.md)
- [`docs/product-design.md`](docs/product-design.md)
- [`docs/security.md`](docs/security.md)
- [`docs/test-strategy.md`](docs/test-strategy.md)
- [`docs/open-questions.md`](docs/open-questions.md)
- [`docs/implementation-report-phase-2.md`](docs/implementation-report-phase-2.md)

## Retrieval

Po změně dokumentace nebo budoucího zdrojového kódu obnovte lokální Chroma
index:

```bash
"/Users/voldzi/Developer/18 2026/chromadb/tools/chroma-dev.sh" reindex --root .
```
