# Testovací strategie

## Stav a účel

Repozitář je ve fázi 2 a obsahuje první buildovatelný iOS host. Aktuální unit a
contract testy pokrývají origin policy, handshake a capability baseline;
`implementation-report-phase-2.md` pravdivě odděluje simulátor, beta toolchain,
stable CI a dosud neprovedené fyzické/backendové scénáře.

Minimální platforma je **iOS 26**. Úspěšný build nebo simulátor sám o sobě není
důkaz funkčního kompasu, motion, APNs, background location, Share Extension ani
budoucího rádiového transportu.

## Principy kvality

- Testuje se hranice „COP web = UI/business“ a „native = capability/transport“,
  nikoli jen jednotlivé metody.
- Jediným veřejným kontraktem webu je verzovaný `CopDevice`; Swift a TypeScript
  používají stejné JSON Schema a fixtures.
- Každá citlivá capability má happy path, denied/restricted/revoked variantu a
  pravdivý fallback.
- Bezpečnost bridge se testuje jako nepřátelská hranice i při trusted originu.
- Offline, background a notifikační chování se testuje změnou skutečného stavu
  zařízení, ne pouze mockem.
- Test nesmí do příloh, screenshotů ani logů vložit produkční token, reálnou
  polohu osoby, obsah občanského hlášení nebo soukromé fotografie.
- Flaky real-device test se neignoruje; přesune se do karantény s vlastníkem,
  důvodem a termínem opravy. Release gate zůstává explicitní.

## Vrstvy testů

| Vrstva | Účel | Prostředí | Gate |
| --- | --- | --- | --- |
| Dokumentace a konfigurace | Povinné soubory, žádná tajemství, sladěné targety/entitlements | CI / shell | Každý commit |
| Contract fixtures | Stejná interpretace bridge requestů, response, eventů a dat | TypeScript + Swift | Každá změna schématu |
| Swift unit | Routing, validace, state machines, filtry, retence, privacy redaction | macOS CI bez WebView/radia | Pull request |
| Web unit/component | Native/browser adapter, capability UI, timeouts, denied UX | COP CI | Pull request v COP |
| Integration | `WKWebView` ↔ bridge ↔ fake native services, origin a lifecycle | iOS 26 simulator + lokální test origin | Pull request / nightly |
| UI automation | Start, fallback, permission copy, deep link, tracking state, accessibility | iOS 26 simulator; vybrané testy device | Release candidate |
| Backend contract | OIDC, device ticket, APNs registration, upload/outbox a deep links | Staging | Release candidate |
| Real device | Senzory, background, APNs, Share Extension, offline, výkon a baterie | Podepsaný build na iOS 26 | Povinný release gate |
| Security/privacy | Nepovolený origin, fuzz, log/entitlement/privacy audit | CI + manual artifact review | Release candidate |

## Sdílené kontraktní testy

Autoritativní fixtures žijí se schématy `CopDevice` v COP repozitáři. Mobilní
repozitář je konzumuje v připnuté verzi; nesmí udržovat ručně odlišnou kopii.
Každá fixture obsahuje očekávaný výsledek a podle potřeby stabilní error code.

Minimální společná sada:

- platný a nekompatibilní handshake;
- chybějící/nesprávný `sessionId`, opakovaný request ID a zneplatněná session;
- validní current location, stale/reduced/simulated/invalid location;
- validní a nevalidní heading, calibration required a změna orientace;
- validní foreground attitude a nedostupná/odmítnutá motion capability;
- permission `notDetermined`, `granted`, `denied`, `restricted` a změna za běhu;
- start/read/stop background tracking session a obnovení po reloadu WebView;
- validní `NativeAssetRef`, expirovaný/missing asset a nepovolený media type;
- validní push deep link a route s nepovoleným originem;
- malformed JSON, neznámá metoda, neznámé pole, příliš velký request a timeout;
- event sequence v pořadí, mezera v sequence, duplicita a event staré session;
- až v relay laboratoři: TTL, hop limit, deduplikace, quota a poškozený hash.

Stejná validní fixture musí projít TypeScript a Swift dekódováním. Stejná
nevalidní fixture musí být odmítnuta ekvivalentní kategorií chyby. Snapshoty
nesmějí nahradit sémantické assertions.

## Web a bridge

### Web adapter a capability UI

V COP repozitáři se ověří:

- `BrowserCopDeviceAdapter` funguje bez nativního bridge a nesimuluje
  unsupported capability;
- `NativeCopDeviceAdapter` nepovolí request před `bridge.ready`;
- UI se rozhoduje podle capability, nikoli podle user-agentu nebo názvu iOS;
- timeout, cancellation a reload nezanechají pending Promise/subscription;
- denied/restricted/reduced stav má srozumitelný fallback;
- chybná native response, neznámá major verze a event mimo sequence neselžou
  nekontrolovaně;
- webový outbox nepovažuje nativní převzetí assetu za serverový ACK;
- route z push/share vstupu projde stejnou autentizací a autorizací jako běžná
  navigace;
- žádný webový kód nedostane APNs token ani filesystem cestu.

### Bezpečnost bridge

Automatizované integrační testy a ruční penetrační scénáře musí ověřit:

- bridge je dostupný jen přes přesný release/staging/debug allowlist;
- HTTP, wildcard, podobně vypadající doména, jiný port, subdoména a user-info URL
  jsou odmítnuty;
- iframe, popup a subresource nemohou volat native metody;
- cross-origin redirect a navigace zneplatní session ještě před dalším requestem;
- návrat na povolený origin vyžaduje nový handshake;
- request staré session, duplicitní ID a replay se nevykonají podruhé;
- schema, method allowlist, payload limit, rate limit a timeout jsou vynuceny
  před I/O nebo permission promptem;
- eventy se předávají přes argumenty bezpečného JavaScript API, nikoli
  interpolací neověřeného textu do source;
- externí link se otevře systémově a nezíská bridge;
- Web Inspector, debug originy a citlivá diagnostika nejsou v release artifactu;
- fuzz/malformed vstupy nezpůsobí crash, deadlock ani logování payloadu.

## iOS unit a integrační testy

### Unit testy bez WebView

- dekódování/validace envelope a mapování stabilních error codes;
- výběr kompatibilní protocol version a session lifecycle;
- origin canonicalization a navigation policy;
- method routing, cancellation, timeout a idempotence request ID;
- permission state machine včetně revokace za běhu;
- filtrace location podle accuracy/age, reduced/simulated stav a throttling;
- filtrace heading accuracy, calibration a správné rozlišení heading/course;
- attitude reference frame, normalizace quaternionu a foreground-only pravidlo;
- tracking session state machine, durable cursor, stop a recovery metadat;
- asset allowlist, skutečná velikost, SHA-256, quota, TTL a cleanup;
- APNs/deep-link parsing bez vystavení tokenu nebo nepovolené route;
- OSLog privacy redaction a diagnostický export bez zakázaných hodnot.

Nativní služby musí být testovatelné přes protokoly/fakes bez spuštění WebView.
Čas, UUID, filesystem, notification center, location/motion source a síť musí
být injektovatelné, aby byly expiry a lifecycle scénáře deterministické.

### Integration a UI testy

- trusted WebView start, handshake a capability refresh;
- nepovolený origin, externí link, redirect a reload session;
- lokální fallback a přechod zpět na COP po obnovení sítě;
- permission pre-prompt, systémový dialog, denied a Settings round-trip;
- tracking status po reloadu WebView a dostupné Stop;
- příjem pending Share Extension položky a otevření správného webového importu;
- tap na lokální/push notifikaci za foreground, background a terminated stavu;
- nepřihlášený deep link projde loginem a až poté otevře autorizovanou route;
- VoiceOver label/order, Dynamic Type, dark mode, Reduce Motion a rotace zařízení.

Systémový permission stav se mezi UI testy nesmí nepozorovaně dědit. Test setup
musí uvést, zda používá čistou instalaci, reset privacy databáze simulátoru nebo
ručně připravený fyzický telefon.

## Povinná real-device matice pro iOS MVP

| Zařízení | OS | Povinné scénáře |
| --- | --- | --- |
| iPhone A podporovaný aplikací | Nejnižší dostupný iOS 26 runtime; pro přesný `26.0` baseline navíc simulator runtime, pokud fyzické zařízení nelze bezpečně downgradeovat | Online/offline start, WebView/OIDC, permission flow, senzory, Share Extension |
| iPhone B jiné hardwarové generace | Aktuální stabilní iOS 26.x | APNs, Focus/mute, background tracking, baterie, process/restart scénáře |
| iPad | iPadOS 26.x, pouze pokud má být release univerzální | Layout, multiwindow, rotace, WebView login, share a deep link |

Pro pilot nestačí jedno zařízení použité vývojářem. Minimálně dva iPhony musí
mít odlišnou hardwarovou generaci a testovací Apple IDs / push registrace.
Modely, OS buildy a fyzická dostupnost se evidují v implementačním reportu.

### Senzory a tracking na fyzickém zařízení

Každý kandidát na release projde:

1. jednorázovou fresh location venku i uvnitř, včetně accuracy a stáří;
2. reduced/precise stavem a vypnutými Location Services;
3. heading ve všech podporovaných orientacích, kalibračním stavem a magnetickým
   rušením; course se porovná pouze jako odlišná veličina;
4. foreground attitude, změnou orientace a ukončením při backgroundu;
5. explicitním Start background trackingu ve foregroundu;
6. 30 minutami pohybu se zhasnutou obrazovkou, přechodem Wi-Fi/cellular/offline,
   Low Power Mode a omezenou baterií;
7. návratem do aplikace, reloadem WebView, kontrolou continuity/cursor a Stop;
8. odebráním oprávnění během session a ověřením bezpečného ukončení;
9. běžným ukončením procesu, restartem telefonu a force-quit. Výsledek musí
   pravdivě ukázat systémové omezení, ne tvrdit nepřerušenou kontinuitu.

Záznam trasy používá syntetickou testovací identitu a schválený testovací
prostor. Export důkazů obsahuje pouze agregované metriky nebo redigovanou trasu.

### Share Extension a soubory na fyzickém zařízení

- share jedné fotografie z Photos, jednoho PDF a podporovaného dokumentu z Files;
- HEIC/JPEG/PNG, velký soubor těsně pod a nad limitem, nulový/poškozený soubor;
- více položek, nepodporovaný UTType, cloudová položka čekající na stažení a
  zrušení extension uprostřed kopie;
- zamčené zařízení/Data Protection, nedostatek místa, zaplněná quota a cleanup;
- hash, opaque handle, zákaz absolutní cesty/base64 a EXIF location policy;
- kill host aplikace před claimem, následný start, expirace a ruční Clear;
- potvrzení, že Share Extension neobsahuje mapu, report formulář ani business
  validaci COP.

### APNs a notifikace na fyzickém zařízení

- první request, denied, později změněný stav v Nastavení a zrušená registrace;
- běžná, Time Sensitive a lokální notifikace při foreground, background,
  terminated a zamčeném telefonu;
- Focus, mute, vypnutý zvuk, vypnuté Time Sensitive a Scheduled Summary;
- validní, expirovaný, duplicitní a neautorizovaný deep link;
- payload inspection potvrzující absenci citlivého textu a tokenu;
- token rotation/reinstall a backend unregister při logout/revokaci;
- Critical Alert pouze po doloženém entitlementu; bez něj musí být capability a
  produktové copy vypnuté;
- PushKit/CallKit se v MVP nesmí objevit v podepsaných entitlements/background
  modes ani v testovaném chování.

## Offline, lifecycle a chaos scénáře

### Cold-start akceptace

1. **Po dřívějším online startu:** COP se jednou úspěšně načte a přihlásí,
   proces se ukončí, zapne se airplane mode a aplikace se znovu spustí. Do 3 s
   se zobrazí cached web shell nebo jasně zdokumentovaný bezpečný degraded stav.
2. **Čerstvá instalace offline:** před prvním startem se zapne airplane mode.
   Zobrazí se lokální fallback s konektivitou, Retry a verzí; nikdy prázdný
   WebView, nekonečný spinner ani nativní napodobenina reportu.
3. **Poškozená/nekompatibilní cache:** aplikace cache nepovažuje za úspěšný
   obsah, přejde na fallback a po návratu sítě bezpečně obnoví web artifact.
4. **Síť během akce:** výpadek při uploadu/share importu zachová korelační ID a
   pravdivý stav. Native ACK, web outbox ACK a server ACK se nesmějí zaměnit.

### Negativní a chaos sada

- WebView reload nebo crash během requestu a tracking session;
- app background, systémové memory pressure, process kill a restart zařízení;
- captive portal, DNS failure, TLS chyba, dostupná Wi-Fi bez COP backendu a
  přechod mezi sítěmi;
- storage téměř plné/plné, read-only chyba, poškozený spool a ztráta Keychain
  reference;
- čas zařízení posunutý dopředu/dozadu a monotónní timeouty;
- permission revoke, rodičovské/MDM restriction a vypnutá systémová služba;
- dva tapy/start requesty, duplicate callback, out-of-order event a stale event;
- logout/login jiného uživatele s pending assetem nebo tracking daty;
- starý web build proti novému hostu a nový web build proti staršímu
  podporovanému hostu v rámci deklarovaného compatibility okna.

## Výkon, baterie a stabilita

Výchozí cíle se změří na referenčních fyzických zařízeních a poté se potvrdí
nebo upraví v ADR; nesmějí být vykázány bez měření.

| Metrika | Počáteční cíl MVP | Metoda |
| --- | --- | --- |
| Cached shell interactive | p95 do 3 s | 20 cold startů v airplane mode po validním online seed |
| Bridge request bez I/O | p95 do 100 ms | Signpost od validovaného requestu po response, min. 1 000 opakování |
| Heading event → web UI | p95 do 250 ms | Signpost s aktivní foreground subscription |
| Crash-free pilot sessions | Bez známého reprodukovatelného crash v kritické cestě | TestFlight/crash report + interní evidence |
| Background tracking baterie | Změřená spotřeba za 30 min pro každý režim | Stejná trasa, jas, síť a battery baseline; výsledek bez marketingové interpretace |
| Native spool/share quota | Limit je vždy vynucen bez pádu a bez překročení disku | Boundary a disk-full test |

Na MainActor nesmí běžet blokující souborové, databázové, hashovací ani schema
I/O. Instruments kontroluje hangs, memory growth, energy a file activity. Test
zahrnuje alespoň 30 reloadů WebView, 100 start/stop subscription cyklů a cleanup
po simulované dlouhé offline periodě.

## Security, privacy a artifact review

Před release se kontroluje výsledný podepsaný `.app`, nikoli jen projektové
soubory:

- deployment target je iOS 26 a release používá schválený stabilní Xcode/SDK;
- entitlements obsahují jen Push, App Groups, Associated Domains, schválený
  background mode a případně Time Sensitive; žádný nevyužitý relay/VoIP gate;
- Info.plist obsahuje pouze používané a lokalizované purpose strings;
- App Transport Security, App-Bound/allowlist politika a production originy jsou
  přesné; debug originy a Web Inspector chybějí;
- privacy manifest a App Store privacy answers odpovídají binárce a všem SDK;
- strings/binary scan nenajde secret, privátní certifikát, produkční access token
  ani interní filesystem cestu;
- kontrolovaný log capture z každé kritické cesty neobsahuje souřadnice,
  payload, soubor, APNs token, cookie ani raw user/device ID;
- diagnostický export je redigovaný a stabilním kódem korelovatelný bez PII.

## MVP akceptační matice

| Oblast | Povinný důkaz | Release gate |
| --- | --- | --- |
| Architektura | Code review ukáže nulovou nativní mapu/chat/report business logiku a jediný `CopDevice` kontrakt | Ano |
| iOS 26 host | Podepsaný build, online OIDC a stabilní WebView na fyzickém iPhonu | Ano |
| Bridge security | Negativní origin/frame/session/fuzz sada bez bypassu | Ano |
| Poloha/heading/attitude | Přesnost, stáří, validity, reduced/denied a foreground omezení na zařízení | Ano |
| Background tracking | Explicitní Start/Stop, reload continuity, screen-off test, revoke/force-quit pravdivý stav | Ano |
| Share Extension | Photos + Files, quota/hash/TTL/Data Protection a import přes opaque handle | Ano |
| Notifikace | APNs/lokální/Time Sensitive, Focus/mute a deep link na fyzickém zařízení | Ano |
| Offline | Cached cold start a fresh-install fallback bez prázdného WebView | Ano |
| Privacy | Permission flow, redigované logy, manifest, entitlements a retence | Ano |
| Critical Alerts | Apple entitlement + samostatná device sada | Ne pro MVP; capability musí být vypnutá |
| Android | Sdílené contract fixtures po zahájení Android fáze | Ne pro iOS MVP |
| Relay | Oddělený laboratorní protokol; žádná citlivá data | Ne pro MVP; release flag musí být off |

## Relay laboratoř — budoucí samostatný gate

Po schválení relay fáze se přidá minimálně 2× iPhone, 2× Android, cross-platform
iPhone↔Android a třízařízení A→B→C. Na fyzických telefonech se ověří opt-in,
peer authentication, foreground/background přechod, TTL, hop limit, dedup,
durable queue, quota, checksum, peer ACK versus backend ACK, přerušení transferu,
clock skew a kill switch. Úspěch laboratoře není oprávnění označit funkci za
produkční mesh; produkční gate vyžaduje samostatný threat model a E2E návrh.

## Evidence a řízení výsledků

Každý real-device test run zaznamená:

- datum, tester, scénář a ID testovacího případu;
- model zařízení, OS build, app build/commit, web build a backend environment;
- stav sítě, Focus/Low Power a relevantních oprávnění před testem;
- očekávaný a skutečný výsledek, Pass/Fail/Blocked;
- redigovaný screenshot/video/log a issue odkaz při neúspěchu;
- potvrzení cleanup testovacích assetů, registrací a lokálních dat.

Release report nesmí použít „not tested“ jako Pass. `Blocked` musí mít vlastníka,
bezpečný fallback a rozhodnutí, zda blokuje release. Všechny položky označené
„Ano“ v MVP akceptační matici musí mít fyzický důkaz nebo release nevznikne.

## Ověření v aktuální dokumentační fázi

Do založení Xcode projektu je jediný spustitelný baseline:

```bash
bash scripts/validate-skeleton.sh
```

Po vzniku kódu se do `AGENTS.md`, `README.md` a CI doplní přesné, neinteraktivní
příkazy pro build, unit testy, UI testy, lint/static analysis a contract
fixtures. Neurčené názvy schémat nebo příkazy se nesmějí v dokumentaci vydávat
za již existující implementaci.
