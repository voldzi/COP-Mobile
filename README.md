# COP Mobile

Tenký nativní host pro existující webovou aplikaci Civil Situation Map (COP/CSM).
Projekt zpřístupní funkce zařízení, které web/PWA nemůže poskytovat dostatečně
spolehlivě: přesnou polohu, kompas a 3D orientaci, uživatelem spuštěné sledování
polohy na pozadí, systémové notifikace, příjem fotografií a dokumentů a později
experimentální device-to-device relay. Vlastníkem produktu je tým COP.

## Stav

Repozitář je ve fázi 0 — analýza, architektonická rozhodnutí a dokumentační
skeleton. Neobsahuje produkční Swift ani Kotlin kód.

Závazný baseline:

- minimum iOS/iPadOS 26;
- stabilní Xcode a stabilní Apple SDK, nikoli beta-only produkční závislosti;
- existující COP web zůstává jediným UI a zdrojem business logiky;
- nativní vrstva neimplementuje vlastní chat, mapu, report workflow ani AI;
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
apps/ios/       budoucí SwiftUI host a Share Extension
apps/android/   rezervovaná hranice pro pozdější Android host
packages/       pouze mobilní utility; autoritativní device kontrakt zůstává v COP
tests/          contract, integration a real-device testovací podklady
docs/           aktivní dokumentace a ADR
config/         bezpečné, verzované konfigurační šablony
```

## Integrace

- COP web/API: `/Users/voldzi/Documents/Development/18 2026/DELTA_ACR/01 COP`
- referenční starý nativní klient: `/Users/voldzi/Documents/Development/18 2026/DELTA_ACR/04 CSM messenger`
- CSM Messaging/APNs: `/Users/voldzi/Documents/Development/18 2026/DELTA_ACR/05 Messaging`
- autoritativní COP API: `01 COP/openapi/openapi.json`

Projekt neposkytuje vlastní REST API. Popis konzumovaných kontraktů je v
[`docs/api.md`](docs/api.md).

## Lokální ověření

V dokumentační fázi je jediným build-independent checkem:

```bash
bash scripts/validate-skeleton.sh
```

Swift/Xcode a Android příkazy budou přidány společně s prvními build targety;
dokumentace je nesmí předstírat dříve, než existují.

## Dokumentace

Rozcestník je v [`docs/README.md`](docs/README.md). Nejdůležitější vstupy:

- [`docs/repository-assessment.md`](docs/repository-assessment.md)
- [`docs/implementation-plan.md`](docs/implementation-plan.md)
- [`docs/architecture.md`](docs/architecture.md)
- [`docs/product-design.md`](docs/product-design.md)
- [`docs/security.md`](docs/security.md)
- [`docs/test-strategy.md`](docs/test-strategy.md)
- [`docs/open-questions.md`](docs/open-questions.md)

## Retrieval

Po změně dokumentace nebo budoucího zdrojového kódu obnovte lokální Chroma
index:

```bash
"/Users/voldzi/Documents/Development/18 2026/chromadb/tools/chroma-dev.sh" reindex --root .
```
