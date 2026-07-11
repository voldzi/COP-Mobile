# Repository Assessment

## Stav a rozsah

- Datum průzkumu: 2026-07-11
- Cílový repozitář: `06 COP Mobile`
- Zdrojový web/backend: `01 COP`
- Referenční nativní prototyp: `04 CSM messenger`
- Rozhodnutí vlastníka produktu: thin native host, iOS/iPadOS minimum 26.0,
  Android později

Tento dokument uzavírá fázi 0. V cílovém repozitáři zatím nevzniká Swift,
Kotlin ani jiný produkční kód.

## Shrnutí

Záměr je proveditelný bez přepsání COP. Stávající COP už poskytuje produkční
React/Vite web, Fastify API, OIDC, PWA cache, IndexedDB, Matrix E2EE storage,
Web Push, community report attachments a mobilní pairing/device/mesh endpointy.
Chybí však verzovaný Device API/bridge, Share Extension, nativně vlastněný
background tracking a zapisovatelný webový offline outbox.

`04 CSM messenger` je rozsáhlá plně nativní aplikace, nikoli základ thin
hostu. Duplikuje mapu, chat, report workflow, Matrix klienta a doménové modely,
cílí na iOS/watchOS 27 a neobsahuje `WKWebView` bridge ani Share Extension.
Má užitečné technické prototypy, ale musí zůstat referencí a zdrojem
auditovatelných testovacích nápadů, ne výchozím codebase.

Doporučený výsledek:

```text
01 COP        = web + business logika + REST + autorita Device kontraktu
06 COP Mobile = iOS 26 thin host + native služby + generované modely
04 Messenger  = zmrazená referenční/prototypová implementace
```

## Prozkoumané zdroje

### Relevantní strom 01 COP

```text
01 COP/
├── apps/
│   ├── cop-api/src/             Fastify backend a mobile routes
│   ├── cop-web/src/             React/Vite web, auth a offline runtime
│   ├── cop-web/public/
│   │   └── cop-service-worker.js
│   └── cop-chat/                samostatný webový chat
├── packages/
│   ├── core/src/                sdílený auth/API základ
│   └── messaging/src/           Matrix E2EE, Web Push, IndexedDB
├── openapi/openapi.json         binding REST kontrakt
├── docs/architecture/
│   └── 09_OFFLINE_AND_EDGE_ARCHITECTURE.md
├── docs/integration/
│   ├── 09_CSM_MESSAGING_INTEGRATION.md
│   └── 12_COP_NOTIFICATION_DECISION_AND_PUSH.md
└── .github/workflows/ci.yml
```

### Relevantní strom 04 CSM messenger

```text
04 CSM messenger/
├── Apps/CSMMobile/              plně nativní SwiftUI UI
├── Sources/CSMCore/             COP/Matrix/report/relay doménové služby
├── Sources/CSMDesignSystem/
├── Apps/CSMMobileWatch/
├── project.yml                  XcodeGen, iOS/watchOS 27
└── docs/                        produkt, integrace, ADR a release
```

### Cílový strom ve fázi 0

```text
06 COP Mobile/
├── README.md
├── AGENTS.md
├── CLAUDE.md
├── .env.example
├── apps/
│   ├── ios/README.md            hranice budoucího iOS 26 targetu
│   └── android/README.md        hranice pozdějšího Android targetu
├── packages/README.md           budoucí generated/support utility hranice
├── tests/README.md              test harness a evidence
├── docs/
│   ├── README.md
│   ├── architecture.md
│   ├── api.md
│   ├── product-design.md
│   ├── security.md
│   ├── operations.md
│   ├── observability.md
│   ├── runbook.md
│   ├── repository-assessment.md
│   ├── implementation-plan.md
│   ├── permissions-and-privacy.md
│   ├── test-strategy.md
│   ├── open-questions.md
│   ├── adr/
│   └── archive/
└── scripts/validate-skeleton.sh
```

Složky `apps/ios` a `apps/android` jsou ve fázi 0 pouze dokumentované hranice;
build targety vzniknou až v implementační fázi. Contract packages nevzniknou
zde, ale v `01 COP/packages`.

## Skutečný stav 01 COP

| Oblast | Nález | Dopad na COP Mobile |
| --- | --- | --- |
| Stack | pnpm 10 monorepo, Node 24, React 19/Vite 8 web, Fastify 5 API, TypeScript | web se nepřesouvá; iOS pouze načte publikovaný artifact |
| UI | mapa a chat jsou webové, včetně samostatného `/chat/` | žádná SwiftUI mapa ani Matrix UI |
| API contract | JSON-first `openapi/openapi.json` | každá serverová změna začíná v COP OpenAPI |
| Produkční origin | `https://cop.zeleznalady.cz`; API a chat jsou publikované same-origin cestami | release allowlist může být přesný; staging origin stále chybí |
| Auth | Keycloak/OIDC; browser session a refresh lifecycle vlastní COP web, session se ukládá v origin storage | native nesmí kopírovat access/refresh token do Keychain |
| Offline shell | service worker cachuje hlavní a chatový shell, asset manifesty a použité mapové tiles | lze zkusit remote-HTTPS cached start v persistentním WebKit store |
| Offline data | IndexedDB snapshot + kompatibilní localStorage fallback; UI přejde do degraded/offline | aktuální fallback je read-only |
| Chat offline/E2EE | Matrix sync/crypto state a sealed recovery data v IndexedDB | zachovat stejný WebKit origin a persistentní data store |
| Community reports | draft/create/update/attachments/upload/complete/submit REST workflow | upload z `NativeAssetRef` musí navázat na stávající slot, ne nový endpoint |
| Push | COP web má Web Push; APNs registry a delivery vlastní CSM Messaging | APNs token nesmí skončit v COP ani JavaScriptu |
| Mobile | bootstrap, offline snapshot, pairing, COP device audit, revoke, mesh ingest/ACK | využít kompatibilní pairing/deep links; nepovažovat device audit za push registry |
| Statický artifact | `vite build` vytváří `dist`, který obsluhuje `server.mjs` | celý shell lze technicky balit, ale až po samostatném auth/CORS/SW rozhodnutí |
| Kvalita | TypeScript, ESLint, Vitest, build a contract checks; skeleton a OpenAPI validace v CI | Device contract fixtures se mají připojit do stávajícího COP CI |

### Důležitý rozpor se zadáním

Původní zadání předpokládá existující offline outbox pro manuální hlášení.
Aktuální `docs/architecture/09_OFFLINE_AND_EDGE_ARCHITECTURE.md` ale výslovně
říká, že PWA offline fallback je pouze informační a nepovoluje manuální hlášení
ani akční workflow. Offline report je tedy změna webu COP, ne funkce tenkého
nativního hostu.

### Aktuální REST kontrakty použitelné pro mobil

- `GET /api/v1/mobile/bootstrap`
- `GET /api/v1/mobile/offline-snapshot`
- `GET|POST /api/v1/mobile/devices`
- `DELETE /api/v1/mobile/devices/{deviceId}`
- pairing session create/read/claim/confirm
- `POST /api/v1/mobile/mesh/ingest`
- `GET /api/v1/mobile/mesh/acks`
- community report draft/attachment/upload/submit workflow
- AASA a `/mobile/pair/{code}` fallback

Wire formát se nesmí opisovat z tohoto dokumentu; autoritou je COP OpenAPI.

## Vyhodnocení 04 CSM messenger

### Co projekt skutečně implementuje

- SwiftUI messenger a nativní Matrix Rust E2EE klient;
- nativní MapKit mapu, mapové vrstvy, report workflow a offline map packs;
- nativní OIDC/PKCE a Keychain token store;
- APNs registraci a deep links;
- watchOS target a lokální AI;
- šifrované snapshot/outbox stores;
- relay/mesh prototyp s TTL, hop limit, podpisy, replay ochranou a gateway
  endpointy.

### Proč není vhodný jako základ

- deployment target je iOS/watchOS 27.0, zatímco nový produkt závazně cílí od
  iOS/iPadOS 26.0;
- cílem projektu je messenger-first plně nativní klient, tedy jiná systémová
  hranice;
- cílené hledání nenašlo `WKWebView`, `WKScriptMessageHandler` ani Share
  Extension target;
- poloha pro report používá jednorázové `requestLocation()`; není zde
  požadovaný kompas, 3D attitude ani durable background tracking API;
- mapové, reportové, chatové a auth modely by vytvořily druhý zdroj pravdy.

### Co lze po auditu využít

| Kandidát | Zacházení |
| --- | --- |
| AES-GCM file store, Keychain a complete file protection pattern | koncept/test převzít po threat-model a API review, ne kopírovat celý core |
| APNs/deep-link fixtures | přizpůsobit thin-host route allowlistu |
| relay TTL/dedup/replay a gateway test cases | použít jako negativní fixtures v pozdější laboratoři |
| device posture a diagnostics scénáře | převést na capability/diagnostics požadavky |

### Co se nesmí převzít

- SwiftUI chat/map/report UI;
- Matrix klient a E2EE business lifecycle;
- native OIDC jako paralelní login;
- doménové COP modely, offline map katalog, Watch target a lokální AI;
- relay obálka jako produkční kontrakt bez nového auditu.

Konkrétní relay výstraha: `CrisisRelayEnvelopeSigningPayload` nezahrnuje
`hopCount`, i když se tato hodnota při forwardu mění. Prototyp proto nelze
označit za hotový podepsaný multi-hop kontrakt. Queue a byte/quota politika
rovněž musí být navržena znovu pro thin host.

## Mezera mezi současným a cílovým stavem

| Požadavek | Stav | Minimální změna |
| --- | --- | --- |
| stejný COP web v aplikaci | chybí host | iOS 26 SwiftUI + `WKWebView` |
| jednotný Device API | chybí | JSON Schema + TS SDK v `01 COP`, Swift consumer zde |
| secure bridge | chybí | ADR 0002, exact origin, main-frame, session a schema |
| offline cold start | PWA cache existuje, WebKit není fyzicky ověřeno | persistentní data store + real-device cache test + native fallback |
| fresh-install offline | chybí | lokální SwiftUI fallback, bez business workflow |
| kompas/attitude | chybí thin contract | foreground native služby |
| background tracking | chybí | durable native session oddělená od WebView subscription |
| příjem fotek/dokumentů | pickery existují jen ve starém klientu | Share Extension + protected App Group inbox |
| APNs bez native OIDC tokenu | chybí delegace | jednorázový COP -> CSM registration ticket |
| hlasité/critical upozornění | standardní push existuje | Time Sensitive baseline; Critical Alerts až s entitlementem |
| offline report | web je read-only | COP web outbox, bez nativní kopie formuláře |
| Android | neexistuje | pozdější host nad stejným contract package |
| cross-platform relay | starý Apple prototyp, bez Android důkazu | samostatná default-off laboratoř |

## Doporučené minimální změny

### 0. Dokumentační baseline — tento repozitář

- udržet repo bez produkčního kódu;
- přijmout ADR 0001–0006;
- uzamknout iOS/iPadOS 26.0, thin-host boundary, remote HTTPS baseline a
  bezpečný bridge;
- zapsat blokující gates před jednotlivými funkcemi.

### 1. Contract práce — pouze 01 COP

- založit `packages/cop-device-contract` s JSON Schema a fixtures;
- založit `packages/cop-device-sdk` s browser, native a mock adaptérem;
- rozšířit web UI capability-based, bez platform checks;
- přidat registration-ticket endpoint do binding OpenAPI;
- přidat contract test CSM Messaging redeem flow.

### 2. iOS host — 06 COP Mobile

- stabilní Swift 6/Xcode toolchain, minimum iOS/iPadOS 26.0;
- SwiftUI shell, `WKWebView`, persistentní website store, exact-origin
  navigation policy a secure bridge;
- lokální fallback a diagnostika;
- bez nativní mapy, chatu, report formuláře a OIDC klienta.

### 3. Nativní capabilities

- location, heading a foreground attitude;
- explicitní durable background tracking;
- kamera, photo/document picker a Share Extension;
- lokální/APNs notifikace a route-limited deep links.

### 4. Offline workflow a hardening

- real-device cold-start/cache matrix;
- webový report outbox v `01 COP`;
- binary asset upload handoff;
- TestFlight, privacy, battery a permission testy;
- Critical Alerts jen po udělení entitlementu.

### 5. Android a relay

- Android host až po stabilizaci contract v1;
- relay POC až po cross-platform transport, privacy/procurement a E2E security
  gate; v produkci defaultně vypnutý.

## Rizika a mitigace

| Riziko | Dopad | Mitigace / gate |
| --- | --- | --- |
| kompromitovaný nebo XSS web na povoleném originu | zneužití native capability | přesná method/capability policy, user action, schema, rate/size limit; origin není jediná důvěra |
| remote web se nasadí dříve než host | protocol mismatch | semver handshake, capability negotiation a řízený `BLOCKED` stav |
| WebKit cache se po kill/reboot nechová jako Safari PWA | nefunkční offline start | fyzický iPhone/iPad test před tvrzením offline podpory |
| OIDC redirect/storage ve WebView | přihlášení nebo obnova selže | persistentní store, App-Bound Domains/OIDC spike, žádný paralelní native login |
| native dostane dlouhodobý web token | rozšíření attack surface | jednorázový registrační ticket; žádné čtení WebKit token storage |
| Share Extension přinese škodlivý/velký soubor | storage exhaustion/parser risk | typ/size/quota/hash, protected inbox, expiry, žádné automatické parsování |
| background tracking vybije baterii | provozní a privacy incident | explicitní session, viditelný stav, adaptive policy, battery test |
| požadavek na „neztišitelné“ vyzvánění | falešná bezpečnostní garance | pravdivé Time Sensitive/Critical capability a serverová multichannel eskalace |
| relay je zaměněn za always-on mesh | falešná dostupnost | foreground-oriented, experimental flag, fyzické testy, žádný produkční payload |
| reuse starého relay prototypu | kryptografická/queue chyba | pouze fixtures/koncepty, nový threat model a externí review |

## Uzamčené předpoklady

- nový repozitář zůstává sibling projektu `01 COP`;
- produktové jméno je COP Mobile/CSM host; kompatibilní bundle ID a deep-link
  rozhodnutí se zachová, pokud signing audit neodhalí konflikt;
- minimum je iOS/iPadOS 26.0, nikoli 18 ani 27;
- production web je `https://cop.zeleznalady.cz`;
- první distribuce je TestFlight/interní pilot;
- web vlastní OIDC, doménový outbox a upload workflow;
- 3D attitude je foreground-only;
- background tracking začíná pouze explicitní uživatelskou akcí;
- relay není MVP a je defaultně vypnutý;
- `04 CSM messenger` se nemaže, ale dále se nerozšiřuje jako paralelní COP
  klient.

## Blokující otázky podle milníku

Pro založení dokumentačního skeletonu není otevřený blocker. Před konkrétními
milníky musí být uzavřeno:

| Milník | Blokující rozhodnutí / důkaz |
| --- | --- |
| WebView release | potvrdit staging originy, Keycloak redirect/WebAuthn flow a App-Bound Domains na reálném zařízení |
| Remote push | schválit a implementovat COP/CSM jednorázový registration-ticket contract |
| Media upload | definovat serverem vydaný binary upload descriptor, MIME/byte kvóty a retenci |
| Offline report | dodat webový outbox a idempotentní reconnect test v `01 COP` |
| Background tracking | schválit privacy texty, retenční dobu, přesnost/battery profily a App Store deklaraci |
| Critical Alerts | získat Apple entitlement; bez něj capability zůstane nedostupná |
| Relay POC | rozhodnout transport/procurement, trust anchor, identity/revokaci, E2E key management a testovací zařízení iOS + Android |

Tyto položky neblokují vytvoření iOS host shellu, browser/mock kontraktu,
lokálního fallbacku ani foreground sensor spike.

## Akceptační důkaz pro ukončení fáze 0

- dokumentace jasně říká, že COP web je jediný business source of truth;
- iOS/iPadOS 26.0 je ve všech cílových dokumentech;
- Device contract authority je v `01 COP`;
- bridge a offline boot mají samostatné přijaté ADR;
- současný read-only offline stav není prezentován jako hotový outbox;
- starý full-native projekt je klasifikován jako reference, ne základ;
- žádný Swift/Kotlin/produkční projekt nebyl v této fázi vytvořen.
