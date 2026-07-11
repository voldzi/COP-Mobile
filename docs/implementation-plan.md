# Implementační plán

## Cíl

Dodat iOS/iPadOS 26 thin host, který zobrazuje beze změny existující COP web a
zpřístupňuje bezpečně verzované funkce zařízení. Každá fáze končí samostatně
ověřitelným výsledkem; Android a relay nezačnou dříve, než projdou jejich vstupní
brány.

## Fáze 0 — dokumentace a rozhodnutí

Stav: dokončeno v commitu `f109784`.

Výstupy:

- standardní repository skeleton, assessment, architektura, security/privacy,
  API, provoz, observability, runbook, test strategy a ADR;
- iOS/iPadOS 26 jako minimum;
- samostatný mobilní repo, COP jako vlastník webu, REST a Device API schemas;
- seznam otevřených externích bran bez skrytých domněnek.

Akceptace: skeleton validace projde a repozitář neobsahuje produkční app kód,
secret ani tvrzení o neprovedeném testu.

## Fáze 1 — autoritativní COP Device kontrakt

Stav: dokončeno v COP větvi `codex/cop-mobile-device-contract`, commit
`38db4442fc6aa4d5df0cf788e9e0e9d9aa61e576`.

Vlastník: hlavní COP repozitář.

Výstupy:

- JSON Schema pro handshake, request/response/event, capabilities, location,
  heading, attitude, tracking, asset/share inbox a notification state;
- TypeScript `CopDevice` SDK s browser, native a mock adaptérem;
- fixtures verzované podle SemVer a exportované jako připnutý artifact;
- capability-based web UI bez user-agent větvení;
- ADR a dokumentace v COP, bez změny stávajících REST response shapes.

Akceptace: COP build, lint a testy projdou; browser adapter zachová současné PWA
chování; mock umí deterministicky otestovat denied/unsupported/degraded stavy.

## Fáze 2 — iOS feasibility host

Stav: implementace probíhá; aktuální důkazy a zbývající fyzické/stable gates
jsou v `implementation-report-phase-2.md`.

Vlastník: tento repozitář.

Výstupy:

- XcodeGen projekt, Swift 6, SwiftUI app target a stable-SDK CI;
- `WKWebView` s persistent data store, přesným release/staging/debug allowlistem,
  main-frame bridge a lokálním fresh-install fallbackem;
- protocol handshake a pouze read-only `system.getCapabilities()` spike;
- navigační policy, externí odkazy a debug diagnostika;
- auth spike nad skutečným Keycloak flow bez nativního ukládání webových tokenů.

Akceptace na fyzickém iPhonu/iPadu: online COP a chat fungují, bridge není
dostupný z iframe ani nepovoleného originu, po process kill v airplane mode se
zobrazí cached shell nebo pravdivý lokální fallback, nikoli blank screen.

## Fáze 3 — identita zařízení, push a deep links

Vlastníci: COP, CSM Messaging a tento repozitář.

Výstupy:

- jednorázový, krátkodobý registration-ticket kontrakt, aby APNs token ani
  dlouhodobý bearer nemusely přes nechráněnou hranici;
- native APNs registrace, notification capability snapshot, categories, badge a
  deep links do existujících web routes;
- ordinary a Time Sensitive chování; Critical Alerts pouze při skutečném
  entitlementu a uživatelském souhlasu;
- CSM Messaging delivery audit a idempotentní registrace.

Akceptace: foreground/background/locked/terminated testy na fyzickém zařízení,
token není v COP store ani logu, duplicate push nevytvoří duplicitní akci a
disabled sound/permission je zobrazen jako omezení.

## Fáze 4 — senzory, tracking a sdílené soubory

Vlastník: tento repozitář; webové použití vlastní COP.

Výstupy:

- location s přesností/stářím/reduced-accuracy stavem, heading s kalibrací a
  foreground attitude s quaternionem/reference frame;
- explicitní native-owned tracking session s bounded encrypted sample store;
- iOS Share Extension, App Group inbox, photo/document pickery a opaque asset
  handles;
- permission UX podle `permissions-and-privacy.md`.

Akceptace: revoke za běhu, background/lock/resume, WebView reload, quota,
expirace assetu, škodlivý MIME/oversized soubor, vymazání cache a battery test.

## Fáze 5 — offline report outbox a hardening

Vlastník domény: COP web/API. Nativní host vlastní pouze asset inbox a technické
statusy.

Výstupy:

- webový durable report outbox se stabilním ID a pravdivými sync stavy;
- korelace web draftu s native asset handle a existujícím presigned uploadem;
- real-device cold-start, update/rollback compatibility a storage pressure test;
- App Privacy, accessibility, performance, battery a TestFlight runbook.

Akceptace: po prvním online startu lze v airplane mode otevřít COP, vytvořit
hlášení s lokálním assetem a po reconnectu jej idempotentně odeslat; peer/server
ACK se nikdy nezobrazí jako delivery dříve, než odpovídá skutečnému stavu.

## Fáze 6 — Android parita

Začne až po stabilizaci Device API v1 a iOS MVP. Použije Kotlin/Compose,
AndroidX WebKit secure message listener, `WebViewAssetLoader`, FCM, share intents,
rotation vector a explicitní location foreground service. Web/business hranice
zůstane totožná.

## Fáze 7 — relay laboratoř

Začne pouze po privacy/procurement rozhodnutí o Google Nearby a po schválení
threat modelu. Nejprve mock core, potom foreground iOS/Android testovací build,
nakonec A→B→C store-and-forward. Production flags a sensitive payloads zůstávají
vypnuté, dokud neprojdou identity, key lifecycle, E2E a fyzická interoperabilita.

## Pořadí změn a větví

1. V každém dotčeném repozitáři vytvořit samostatnou `codex/` větev nebo čistý
   worktree; aktuální dirty COP main se nesmí přepisovat.
2. Měnit nejprve autoritativní schema/fixtures, potom web adapter a nakonec
   nativní implementaci stejné verze.
3. Každá fáze má samostatný review, test report a aktualizaci dokumentace.
4. Legacy `04 CSM messenger` zůstane read-only referencí do úspěšné TestFlight
   akceptace nového hostu; následná archivace je samostatné rozhodnutí.
