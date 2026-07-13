# Testovací strategie

## Stav a účel

Repozitář obsahuje buildovatelný hybridní iOS host, Location + Heading slice,
nativní chat přes `CSMCommunicationKit` a nativní call presentation podle
ADR 0009. Dokument pravdivě odděluje existující SwiftUI/CallKit povrch od
přechodného webového Matrix/WebRTC media enginu a od budoucího plně nativního
WebRTC gate.

Minimální platforma je **iOS 26**. Úspěšný build nebo simulátor sám o sobě není
důkaz funkčního kompasu, motion, APNs, E2EE interoperability, CallKit audio,
proximity, background location, Share Extension ani budoucího rádiového
transportu.

## Principy kvality

- Testuje se hranice „COP web = mapa/report/business“,
  „CSMCommunicationKit = native E2EE chat“ a „host = capability/call
  presentation“, nikoli jen jednotlivé metody.
- Jediným veřejným kontraktem webu je verzovaný `CopDevice`; Swift a TypeScript
  používají stejné JSON Schema a fixtures.
- Každá citlivá capability má happy path, denied/restricted/revoked variantu a
  pravdivý fallback.
- Bezpečnost bridge se testuje jako nepřátelská hranice i při trusted originu.
- Offline, background a notifikační chování se testuje změnou skutečného stavu
  zařízení, ne pouze mockem.
- Nativní call UI se nesmí použít jako důkaz nativního media enginu. Každý call
  test zaznamená zvlášť PushKit, CallKit presentation, web signaling, ICE/TURN a
  media-connected outcome.
- Test nesmí do příloh, screenshotů ani logů vložit produkční token, reálnou
  polohu osoby, obsah občanského hlášení nebo soukromé fotografie.
- Flaky real-device test se neignoruje; přesune se do karantény s vlastníkem,
  důvodem a termínem opravy. Release gate zůstává explicitní.

## Vrstvy testů

Aktuální automatizované pokrytí ověřuje, že handshake pravdivě hlásí foreground
location/heading bez background supportu, `location.getCurrent` nevyvolá
permission request, location event nese monotónní sequence a invalidace session
zastaví senzorové updates. Konfigurační validátor vyžaduje When In Use purpose
string a současně zakazuje Always/background deklarace.

WebView smoke test na fyzickém zařízení navíc ověřuje, že selection haptika
nastane po tapnutí, ale nevzniká při scrollu a neblokuje aktivaci webového
ovládacího prvku.

Fyzický smoke test musí navíc potvrdit systémový dialog až po explicitní akci,
Full/Reduced Accuracy stav, GPS accuracy a reakci headingu při rotaci zařízení.

| Vrstva | Účel | Prostředí | Gate |
| --- | --- | --- | --- |
| Dokumentace a konfigurace | Povinné soubory, žádná tajemství, sladěné targety/entitlements | CI / shell | Každý commit |
| Contract fixtures | Stejná interpretace bridge requestů, response, eventů a dat | TypeScript + Swift | Každá změna schématu |
| Swift unit | Routing, bridge a call state machines, OIDC/Matrix store boundaries, filtry, retence, privacy redaction | macOS CI bez WebView/radia | Pull request |
| Web unit/component | Native/browser adapter, capability UI, timeouts, denied UX | COP CI | Pull request v COP |
| Integration | `WKWebView` ↔ bridge ↔ native chat/call presentation, origin a lifecycle; Matrix adapter proti test double | iOS 26 simulator + lokální test origin | Pull request / nightly |
| UI automation | Start, native login/chat, call view, fallback, permission copy, deep link, tracking state, accessibility | iOS 26 simulator; vybrané testy device | Release candidate |
| Backend contract | Web/native OIDC, Matrix bootstrap/E2EE, device ticket, APNs registration, upload/outbox a deep links | Staging | Release candidate |
| Real device | Native OIDC/E2EE chat, VoIP/CallKit/proximity/audio, senzory, background, APNs, Share Extension, offline, výkon a baterie | Podepsaný build na iOS 26 | Povinný release gate |
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
- `communications.openChat` pouze s prázdným payloadem;
- `calls.updatePresentation` pro všechny direction/phase hodnoty, bounded ID a
  title, direct/group kind, bounded participant/eligible seznam, foreground a
  povolené state transitions, plus odmítnutí SDP/ICE,
  tokenu, druhé aktivní identity, překročení procesní kvóty a neznámého pole;
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
- hlasový hovor v hlavním rámci přesného COP originu vyžádá systémové oprávnění
  mikrofonu a lze jej přijmout; iframe, jiný origin a kamera jsou odmítnuty.
- otevření nativního chatu nepřenáší room content, user token ani auth stav;
- webový call engine posílá nativní prezentaci `connected` až po skutečném media
  spojení a po `ended`/`failed` call overlay i proximity stav zaniknou;
- APNs callbacky mají jediného host delegate, Matrix facade obdrží token i
  foreground/background/action události a cold-start call action přežije do
  prvního platného bridge handshake; push před mountem se claimne právě jednou
  a otevře vybranou konverzaci;
- malformed/stale call update nemůže vytvořit CallKit transakci nebo aktivovat
  audio session.
- CallKit answer/reject/end/mute zůstane pending do ACK Matrix commandu,
  opakuje stejné `actionId`, deduplikuje command i ACK a při 12s timeoutu nebo
  záporném ACK failuje. Cold-start command doručený před Matrix call snapshotem
  se provede po jeho vzniku, nejpozději v 9s webovém pending okně;
- JavaScript delivery error invaliduje bridge, zachová jediný pending event se
  stejným `actionId` a po novém handshake jej doručí znovu. `CXProvider` reset
  vyvolá webový hangup a opožděný `CXStartCallAction` nesníží `connected` na
  `connecting`.
- záporný ACK, 12s nativní timeout a CallKit `timedOutPerforming` vyvolají reload
  web media enginu, report/remove call a deaktivaci audia; `end`/`reject` se po
  forced close fulfillne, `answer`/`mute` failne a remote ended odstraní pending
  akce stejného call UUID;

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
- nativní OIDC state/issuer/redirect/PKCE validace, cancel, refresh, logout a
  změna subjectu;
- Matrix bootstrap/session restore, oddělené web/native device ID, encrypted
  timeline/outbox reducer, idempotentní retry a cross-user store isolation;
- call presentation state machine, incoming/outgoing CallKit action mapping,
  audio activate/deactivate, mute/speaker route a proximity enable/cleanup;
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
- otevření/zavření `CSMCommunicationHost` nezruší WebView route ani aktivní
  webový call engine;
- fresh nativní OIDC login, návrat přes `csm` redirect, obnovení Keychain session,
  nativní logout a nezávislá webová session;
- E2EE send/receive mezi webem a nativním Matrix zařízením, offline outbox a
  reconnect bez duplicitního eventu;
- call overlay nad COP i chatem, ringing/connecting/connected/failed/ended,
  mute, speaker a accessibility controls;
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

### Nativní komunikace a hovory na fyzickém zařízení

- OIDC/PKCE fresh login, cancel, přerušení callbacku, refresh po restartu,
  logout, revoked refresh token a přihlášení jiného subjectu;
- potvrzení, že WebKit a native mají oddělené session/device ID a že bridge ani
  log neobsahuje žádný access/refresh token nebo recovery material;
- web → native a native → web E2EE zpráva, reakce/reply/příloha podle
  podporovaného povrchu, history pagination a recovery warning;
- úplné stránkování dostupné timeline, avatary v seznamu/hlavičce/zprávě,
  bubliny s ocasem a reakce připnuté k původní zprávě;
- nativní otázka v `COP AI Assistant`, odpověď přes kanonický COP AI endpoint a
  její následné zobrazení ve stejné E2EE Matrix room na webu i v iOS;
- airplane mode s cached timeline a encrypted outboxem, reconnect, retry,
  idempotence a serverové potvrzení bez dvojité zprávy;
- incoming i outgoing hovor přes Wi-Fi a mobilní síť, TURN relay, změna sítě,
  Bluetooth připojení/odpojení, audio interruption a zamčená obrazovka;
- skupinový start z nativního detailu, postupné přizvání alespoň dvou dalších
  členů, obousměrný zvuk mezi všemi účastníky, serverové odmítnutí identity mimo
  místnost a UI/server limit šesti osob;
- PushKit → CallKit při foreground, background a system-terminated procesu;
- pokračování obousměrného zvuku po lock/background pouze během aktivní
  CallKit session a jeho zastavení po end/failure;
  force-quit se vykazuje jako omezení platformy, ne Pass;
- ringing, connecting, connected, failed, remote ended a lokální end; duration
  začíná až po potvrzeném `connected`;
- přiložení connected handset hovoru k uchu zčerná obrazovku a blokuje dotyk,
  oddálení ji obnoví, speaker/Bluetooth se chovají podle route policy a cleanup
  po skončení vždy vypne proximity monitoring;
- oddělené důkazy pro CallKit presentation, web Matrix signaling, ICE/TURN a
  obousměrný audio stream. Nativní call UI samo o sobě není Pass pro média;
- plně nativní WebRTC není součástí tohoto gate a nesmí být označen jako
  implementovaný bez nového ADR, dependency auditu a interoperability sady.

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
- shoda podepsaného `aps-environment` se serverovým endpointem: Debug proti
  sandboxu, Staging/Release proti production; před TestFlight ověřit řízený
  cutover a vyloučit smíšení tokenů obou prostředí;
- Critical Alert pouze po doloženém entitlementu; bez něj musí být capability a
  produktové copy vypnuté;
- PushKit/CallKit podle ADR 0008 a 0009: příchozí a ended VoIP push, CallKit
  answer/reject/end, native call overlay, audio route a proximity cleanup, cold
  start, suspended/system-terminated stav, zámek obrazovky, expirovaný call a
  potvrzení, že safety ani běžné notifikace nepoužijí VoIP topic.

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
5. **Nativní chat offline:** po dřívější E2EE synchronizaci je dostupná pouze
   subject-bound cached timeline; nový text zůstane v encrypted communication
   outboxu a po reconnectu se odešle právě jednou.

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
- logout/login jiného uživatele s Matrix crypto storem, cached timeline a
  pending message; data předchozího subjectu se nikdy nezobrazí;
- WebView crash/reload během prezentovaného hovoru, stale call snapshot,
  duplicitní PushKit invite, audio interruption a proximity notification po end;
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
| Native cached chat interactive | Počáteční cíl p95 do 1 s po odemčení dostupného store | 20 cold startů s dříve synchronizovanou testovací identitou |
| Call invite → CallKit report | Vždy uvnitř systémového PushKit deadline | Signpost bez obsahu payloadu na fyzickém zařízení |
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
- entitlements obsahují jen Push, App Groups, Associated Domains a schválené
  background modes `remote-notification`, skutečný `voip` a `audio` výhradně
  pro aktivní CallKit hovor; žádný nevyužitý relay, location nebo obecný audio
  keepalive gate;
- Info.plist obsahuje pouze používané a lokalizované purpose strings;
- App Transport Security, App-Bound/allowlist politika a production originy jsou
  přesné; debug originy a Web Inspector chybějí;
- privacy manifest a App Store privacy answers odpovídají binárce a všem SDK;
- `CSMCommunicationKit` a Matrix Rust dependency jsou reprodukovatelně
  připnuté, povolené pro iOS 26 a archive neobsahuje nepoužitý legacy target;
- foreground, background a notification-action callback awaitují headless
  zpracování `CSMCommunicationKit` před completion; reply/mark-read fungují i
  bez připojeného chat view, zatímco signed-out/loading payload zůstává v
  bounded claim-once queue;
- strings/binary scan nenajde secret, privátní certifikát, produkční access token
  ani interní filesystem cestu;
- kontrolovaný log capture z každé kritické cesty neobsahuje souřadnice,
  payload, soubor, APNs token, cookie ani raw user/device ID;
- diagnostický export je redigovaný a stabilním kódem korelovatelný bez PII.

## MVP akceptační matice

| Oblast | Povinný důkaz | Release gate |
| --- | --- | --- |
| Architektura | Code review ukáže nulovou nativní mapu/report business logiku, uzavřený `CSMCommunicationKit` a jediný `CopDevice` bridge kontrakt | Ano |
| iOS 26 host | Podepsaný build, webová i nativní OIDC session a stabilní WebView na fyzickém iPhonu | Ano |
| Nativní E2EE chat | Matrix Rust send/receive, offline timeline/outbox, recovery stav, logout a cross-user isolation | Ano |
| Nativní call presentation | PushKit/CallKit, pravdivý state, audio routes, proximity a web-media interoperability | Ano |
| Plně nativní WebRTC | Nové ADR, audit dependency, Matrix signaling a ICE/TURN/audio physical suite | Ne pro tuto etapu; nesmí se tvrdit jako hotové |
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

## Ověření v aktuální implementační fázi

Aktuální lokální baseline je:

```bash
bash scripts/check.sh
python3 scripts/validate-device-contract.py
python3 scripts/validate-ios-project.py
```

Tyto kontroly nenahrazují staging OIDC/Matrix/E2EE ani fyzické PushKit,
CallKit, proximity, audio-route a WebRTC/TURN důkazy. Každý neprovedený gate se
vykáže jako `Blocked` nebo `Not run`, nikdy jako Pass.
