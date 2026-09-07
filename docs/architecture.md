# Architecture

## Stav dokumentu

Tento dokument popisuje schválenou cílovou architekturu po ADR 0009. Repozitář
obsahuje hybridní iOS host: bezpečný COP WebView a Device bridge, nativní E2EE
chat přes `CSMCommunicationKit` a nativní prezentaci skutečných VoIP hovorů.
Plně nativní WebRTC, další senzory, tracking, Share Extension, relay a Android
mají vlastní implementační a akceptační gates.

První podporovanou platformou bude iOS/iPadOS 26.0. Android bude následovat nad
stejným kontraktem; nesmí kvůli němu vzniknout druhá webová nebo doménová
implementace.

## Účel a hranice produktu

COP Mobile je hybridní host existující aplikace COP. Uživatelům v terénu
zpřístupní stejné webové rozhraní mapy a hlášení jako browser/PWA, nativní E2EE
komunikační povrch a funkce, které webová platforma neposkytuje dostatečně
spolehlivě:

- přesnou polohu, kompas a 3D natočení zařízení;
- explicitně spuštěné sledování polohy na pozadí;
- fotografování, výběr a příjem fotografií a dokumentů;
- lokální a vzdálené notifikace a návrat na správnou webovou trasu;
- nativní chat, offline timeline/outbox a Matrix E2EE lifecycle;
- systémovou prezentaci hovoru, CallKit, audio routing a proximity blackout;
- chráněné technické úložiště a diagnostiku;
- v pozdější laboratorní fázi device-to-device relay.

COP web zůstává jediným vlastníkem mapy, hlášení, vrstev, doménových modelů,
autorizace a ostatních business workflow. Nativní komunikaci vlastní
`CSMCommunicationKit`; host ani bridge neinterpretují Matrix credentials nebo
decrypted chat payload.

### Mimo rozsah

- nativní mapa, report formuláře nebo AI orchestrace;
- nový mobilní backend či proxy COP API;
- plně nativní WebRTC/media engine před samostatným ADR a interoperability gate;
- garantované vyzvánění navzdory nastavení operačního systému;
- trvale běžící background mesh na iOS;
- produkční relay citlivých dat bez schváleného threat modelu, identity zařízení
  a end-to-end správy klíčů;
- Android implementace a plný lokální web bundle v první iOS etapě.

## Kontext systému

```mermaid
flowchart LR
  user([Uživatel]) --> host["COP Mobile<br/>iOS/iPadOS 26+"]
  share["iOS Share Sheet"] --> extension["Share Extension"]
  extension --> host
  sensors["Core Location / Motion<br/>kamera / soubory"] <--> host
  apns["Apple Push Notification service"] --> host

  subgraph cop["01 COP — zdroj pravdy"]
    web["COP web/PWA<br/>UI + business logika"]
    api["COP API<br/>openapi/openapi.json"]
    contracts["COP Device contract + SDK<br/>(plánované balíčky)"]
  end

  host <--> web
  web <--> api
  contracts --> web
  contracts --> host
  web <--> oidc["Keycloak / OIDC"]
  host <--> nativechat["CSMCommunicationKit<br/>SwiftUI + Matrix Rust E2EE"]
  nativechat <--> oidc
  nativechat <--> messaging
  host --> messaging["CSM Messaging<br/>registrace APNs zařízení"]

  android["Budoucí Android host"] -. stejný kontrakt .-> contracts
  relay["Budoucí relay laboratoř"] -. feature flag .-> host
```

COP Mobile poskytuje nativní capability webu, ale neobchází COP API. Doménová
data mapy a hlášení jdou z webu přímo do existujících serverových kontraktů.
Komunikační modul volá COP, CSM Messaging a Matrix pouze přes jejich existující
autentizované kontrakty a vlastní svůj oddělený nativní OIDC/Matrix lifecycle.

## Architektonické principy

1. **Web je business source of truth.** Nativní vrstva neinterpretuje hlášení,
   incidenty ani mapové vrstvy. Komunikační zprávy interpretuje pouze uzavřený
   `CSMCommunicationKit` podle Matrix/CSM kontraktů.
2. **Contract authority je v 01 COP.** JSON Schema, TypeScript typy, webový
   `CopDevice` SDK a společné fixtures vzniknou v COP repozitáři. Mobilní
   repozitář spotřebuje připnutou verzi a validuje proti stejným fixtures.
3. **Capability-based chování.** Web se rozhoduje podle vyjednaných capabilities
   a omezení, nikoli podle user-agentu nebo názvu platformy.
4. **Nativní služba vlastní OS lifecycle.** WebView může požádat o operaci a
   číst stav, ale durable background tracking, share inbox a push lifecycle
   vlastní nativní proces.
5. **Bridge je nedůvěryhodná hranice.** Kontrola originu sama nestačí; každá
   zpráva má verzi, session, schema, limit, timeout a autorizaci metody.
6. **Velká data nejsou JSON bridge payload.** Fotografie a dokumenty se
   předávají opaque handlem `NativeAssetRef`, nikdy base64 nebo cestou k
   souboru.
7. **Pravdivé degraded stavy.** Aplikace rozlišuje online, cached offline a
   fresh-install fallback. Neprohlašuje read-only snapshot za zapisovatelný
   offline režim.
8. **Oddělené identity a secrets.** Webová a nativní OIDC/Matrix session jsou
   samostatné; žádný token, recovery material, decrypted event, SDP ani ICE
   candidate nepřechází Device bridgem.
9. **Jedno vlastnictví hovoru.** COP API vlastní autoritativní stav přímého
   hovoru. Native vlastní CallKit, PushKit, SwiftUI prezentaci, proximity,
   audio routing a LiveKit média. Hovor není závislý na WebView.
10. **Pouze přímé hovory.** Telefon je dostupný jen v direct chatu s jediným
    protějškem. Skupinové a AI hovory nejsou součástí kontraktu.

## Hlavní komponenty

| Komponenta | Odpovědnost | Nevlastní |
| --- | --- | --- |
| App shell | SwiftUI lifecycle, volbu COP/chat povrchu, deep link routing, call overlay, globální fallback a diagnostika | mapovou a report business logiku |
| Web container | `WKWebView`, persistentní website data store, navigation policy a načtení COP HTTPS originu | doménová cache a autorizaci |
| `CSMCommunicationKit` | nativní SwiftUI chat, OIDC/PKCE, Keychain, Matrix Rust E2EE, timeline a offline outbox | mapu, hlášení a COP business workflow |
| Native voice call | CallKit/PushKit, SwiftUI call view, COP API lifecycle, LiveKit room, `AVAudioSession`, mute/route a proximity | Matrix call signaling, skupinové hovory a WebView média |
| Bridge coordinator | handshake, vyjednání verze, session, dispatch, timeout, cancel a event sequencing | schema authority |
| Origin policy a validator | přesný allowlist, main-frame kontrola, JSON Schema a limity | důvěru v obsah povolené stránky |
| Native services | `system`, `permissions`, `location`, `heading`, `attitude`, `tracking`, `connectivity`, `media`, `shares`, `notifications` | mapu a reporty |
| Protected stores | nativní OIDC/Matrix credentials, Matrix crypto/timeline/outbox, tracking, asset a share data podle oddělených policies | webové cookies nebo kopii COP mapové databáze |
| Share Extension | import `NSItemProvider` položek do chráněného App Group inboxu | upload a report workflow |
| Relay adapter | pozdější foreground-oriented experiment s opaque obálkou | význam payloadu, vlastní kryptografický protokol |

Tabulka popisuje vlastnické hranice. Základ hostu, nativního chatu a direct-call
cesty je implementovaný; senzory, Share Extension a relay zůstávají vázané na
své samostatné fáze a release gates.

### Vnitřní architektura nativního chatu

`CSMCommunicationHost` je jediný veřejný vstup. Uvnitř používá výhradně
komunikační `CommunicationModel`; původní víceúčelový `AppModel` byl odstraněn.
Balíček nekompiluje mapu, hlášení, relay, radio plánování ani watch
synchronizaci. `CommunicationModel` koordinuje pouze nativní přihlášení,
Matrix/E2EE, chat, push a hovory a deleguje obrazovkový stav do menších částí:

| Část | Vlastnictví |
| --- | --- |
| `ChatSessionStore` | nativní přihlášení, aktivní actor, device ID a bezpečnostní zámek |
| `ConversationListStore` | immutable snapshot seznamu, výběr a revision |
| `TimelineStore` | právě jedna otevřená místnost a omezené okno zpráv |
| `TimelineReducer` | jediná deterministická cesta pro replace/upsert/reaction/edit/delete a deduplikaci |
| `TimelineSynchronizationController` | právě jeden live stream; polling jen po nedostupném/ukončeném streamu |
| `OutboxActor` | serializovaná šifrovaná offline fronta se stabilním `transactionId` |
| `MediaPipelineActor` | file-backed příprava přílohy, thumbnail a upload mimo hlavní actor |
| `SearchIndex` | inkrementální lokální index načteného okna |
| `ChatTimelinePresentationStore` | obrazovková cache prezentačních řádků podle timeline revision a dotazu |

Nativní senzory a oprávnění jsou služby hostitelské aplikace. Přes verzovaný
Device bridge je používá COP web, který zůstává vlastníkem mapy, hlášení,
vrstev, workflow a doménových dat. Chat může vyvolat akci „Otevřít COP“, ale
nevytváří paralelní nativní formulář ani mapový stav.

Lokální historie je šifrovaná po stránkách. V paměti se drží nejvýše 500
zpráv otevřené místnosti; výchozí stránka má 200 zpráv a starší stránka se
načte explicitně se zachováním scroll anchoru. Celková délka místnosti proto
nezvětšuje observable SwiftUI stav.

Timeline reducer je jediný deduplikační bod. Serverové potvrzení, lokální echo,
reakce, editace a smazání nesmí modifikovat pole zpráv jinou cestou. Odeslání
nejprve uloží stable transaction do šifrovaného outboxu a zobrazí lokální echo;
restart nebo reconnect používá stejný identifikátor a nesmí vytvořit druhý
event.

SwiftUI používá standardní `NavigationStack`, toolbary, sheets a systémová
context menu. iOS 26 Liquid Glass patří navigaci a ovládacím prvkům, nikoli
obsahovým bublinám. Celá bublina je jedna VoiceOver skupina a reply/reaction
jsou accessibility actions. Prezentační seskupení a hledání se připraví mimo
hlavní actor pouze při změně revision nebo dotazu.

Při startu hovoru z nativního chatu zůstává `CSMCommunicationKit` SwiftUI
povrch namountovaný pod nativním call overlayem. `VoiceCallService` vytvoří
nebo načte serverový hovor přímo přes COP API a připojí se do krátkodobě
autorizovaného LiveKit roomu. WebView se hovoru neúčastní a jeho reload ani
nedostupnost nesmí call lifecycle změnit. Vložený webový chat dostává režim
`voiceMedia=native`, nepožaduje mikrofon a nepřipojuje se do LiveKit roomu;
jinak by stejná OIDC identita odpojila nativní účast jako duplicitu.

## Datové toky

### Online start a bridge handshake

1. Host načte release konfiguraci a okamžitě zahájí navigaci na přesný COP HTTPS
   origin ve vlastním pojmenovaném persistentním `WKWebsiteDataStore`. Profil
   není sdílený se Safari ani s výchozím WebKit profilem jiné aplikace.
2. WebKit obslouží síťový nebo dříve cachovaný web shell. Bridge zůstává vypnutý
   během redirectů, pro iframe a na všech ostatních originech.
3. COP Device SDK odešle `bridge.hello` s podporovanými verzemi a ID web
   buildu.
4. Host zvolí kompatibilní verzi, vytvoří náhodný session ID a vrátí capabilities
   včetně omezení a velikostních limitů.
5. Teprve poté web volá povolené metody. Reload nebo změna main-frame originu
   zneplatní session a foreground subscriptions.

Podrobnosti jsou závazně popsány v ADR 0002 a `docs/api.md`.

### Senzory a durable tracking

Foreground `location`, `heading` a `attitude` subscriptions jsou vázané na
bridge session. `tracking.startSession` naproti tomu vytvoří nativně vlastněnou
session, která může v mezích iOS pokračovat po reloadu WebView. Web po novém
handshake získá stav přes `tracking.getSession` a čte vzorky stránkovaně přes
cursor. Uživatel vždy provede explicitní start/stop; background location není
náhradou za relay ani obecný background loop. 3D attitude je v první verzi
foreground-only.

### Sdílené soubory a média

Share Extension zkopíruje podporovanou položku do App Group inboxu, provede
základní typovou a velikostní validaci a skončí. Host po aktivaci publikuje
událost a web položku převezme přes `shares.list`/`shares.claim`. Kamera a
pickery používají stejný `NativeAssetRef`. Upload, oprávnění k reportu a
doménový lifecycle zůstávají ve webu a COP API.

Nativní chat používá pro knihovnu systémový SwiftUI `PhotosPicker`, který se
prezentuje mimo composer menu a nevyžaduje plošný přístup k celé knihovně.
Pořízení nové fotografie používá systémovou celoobrazovkovou kameru po
explicitním tapu uživatele a oprávnění `NSCameraUsageDescription`. Vybrané
médium je ihned zkopírováno do file-backed `MediaPipelineActor`, zkontrolováno
limity chatu a teprve poté předáno Matrix E2EE uploadu; selhání se nesmí tiše
zahodit a zobrazí stručnou uživatelskou chybu.

Jednorázové sdílení polohy v nativním composeru vyžádá čerstvý Core Location
vzorek pouze po explicitním tapu uživatele. Při prvním použití smí host požádat
o oprávnění `When In Use`; odmítnutí nebo nedostupná poloha nesmí zablokovat
ostatní chat. Souřadnice a dostupná přesnost se odešlou jako standardní Matrix
`m.location` uvnitř E2EE místnosti, takže stejnou zprávu zobrazí web i nativní
klient. Jednorázová akce nezapíná průběžné ani background sledování.

Živá poloha navazuje na detail vlastní location zprávy a používá Matrix Rust SDK
live-location relaci MSC3489. Aktivní session vlastní `CommunicationModel`, ne
sheet ani jednotlivá timeline buňka, takže zavření detailu sdílení nepřeruší.
Host zůstává jediným vlastníkem Core Location oprávnění a dodává jen explicitně
vyžádané krátkodobé vzorky. Aktualizace jsou omezené na interval 15 sekund a
session se ukončí ručně nebo po 15 minutách, 1 hodině či 8 hodinách.

### Autentizace, nativní komunikace a registrace push zařízení

COP web vlastní svou OIDC relaci v odděleném WebKit origin storage.
`CSMCommunicationKit` vlastní druhou, nativní Authorization Code + PKCE relaci
pro veřejný klient `csm-mobile`, ukládá ji do Keychainu a používá ji k získání
COP/CSM Matrix bootstrapu. Session se nesdílejí a native nikdy nečte WebKit
storage. Jeden actor-isolated token lifecycle obnovuje krátkodobý access token
při startu i za běžného provozu, ukládá rotovaný refresh token a sdílí jedinou
probíhající obnovu mezi souběžnými požadavky. Výpadek sítě, dočasná
nedostupnost identity provideru ani lokální zrušení Face ID nejsou logout.
Credentials se smažou až po explicitním odhlášení, wipe nebo potvrzeném OAuth
`invalid_grant`; revokace a změna subjectu zároveň čistí subject-bound stores
bez zpřístupnění dat předchozího uživatele.

COP Mobile podporuje i uživatele, kteří webovou mapu vůbec nepoužívají.
Při otevření chatu komunikační modul nejprve tiše obnoví svou nativní Keychain
session; pokud neexistuje, explicitní tap na Chat smí otevřít nativní
Authorization Code + PKCE tok uvnitř aplikace. WebKit bearer token se
nekopíruje do nativního Keychainu a oba OIDC klienty zůstávají oddělené.

Stejná nativní session vlastní také registraci zařízení u CSM Messaging.
Registrace je platná teprve tehdy, když obsahuje aktuální běžný APNs token i
oddělený PushKit VoIP token. Obnovuje se při startu, návratu aplikace do
popředí a při změně kteréhokoli tokenu. Příchozí hovor proto nesmí záviset na
tom, zda je připojen nebo přihlášen skrytý webový most.
PushKit token uložený v Keychainu je pouze recovery hint. Klient jej nikdy
neodešle serveru, dokud jej v aktuálním procesu nepotvrdí `PKPushRegistry`.
To brání jednostranně nedoručitelným hovorům po aktualizaci iOS nebo instalaci
nového vývojového buildu, kdy v Keychainu zůstane již neplatná APNs adresa.
Změnu tokenu zpracovává procesní `CSMCommunicationRuntime` a sloučí případné
souběžné APNs/PushKit callbacky do jedné následné registrace. SwiftUI obrazovka
chatu není posluchačem ani podmínkou této synchronizace.

Pokud je webová mapa přihlášená, předá přes exact-origin bridge pouze bounded
opaque očekávaný OIDC `subjectId`. Nativní chat jej porovná s actor subjectem
získaným vlastním bootstrapem. Při neshodě failuje zavřeně a nezobrazí ani
seznam konverzací; nabídne nucené znovupřihlášení. Hodnota není credential a
bridge nikdy nenese cookie, bearer token, profil, Matrix ID nebo obsah zprávy.

Komunikační povrch nepřeměřuje ani znovu nepřičítá horní safe-area inset.
Otevřená konverzace používá systémový `NavigationStack` bar, takže SwiftUI
zajišťuje status bar, Dynamic Island i změnu při otevřené klávesnici. Na iOS
26+ dodává systém nativní Liquid Glass vzhled navigace bez pevné překryvné
hlavičky.
Přímý chat zobrazuje avatar protějšku nebo jeho iniciály; skupina používá jen
vlastní Matrix room avatar nebo iniciály názvu. V detailu skupiny lze tento
avatar samostatně vybrat, změnit nebo odstranit.

APNs token neopouští nativní vrstvu směrem do JavaScriptu a COP jej neukládá.
COP Mobile je jediným vlastníkem process-wide notification delegate; běžný
token, foreground/background delivery a notification actions současně předává
přes úzkou facade do `CSMCommunicationKit`, aby nativní Matrix pusher a deep
link neztrácely lifecycle ani cílovou konverzaci.
Před dokončením foreground, background nebo notification-action callbacku host
awaituje headless zpracování facade. Sdílený runtime se tak spustí a zpracuje
způsobilé metadata-only payloady i bez připojeného SwiftUI chat view.
Metadata-only push přijatý před připravenou nativní session zůstane v omezené
paměťové frontě komunikačního runtime; po dokončení přihlášení a bootstrapu se
atomicky claimne. Stejný payload se proto nezpracuje dvakrát ani nezmizí při
cold startu.
Po doplnění kontraktu si autentizovaný web vyžádá v COP API krátkodobý,
jednorázový device-registration ticket, předá jej metodě bridge a host s ticketem
a APNs tokenem registruje zařízení přímo u CSM Messaging. Tato serverová změna
je blokující podmínkou pro remote push, ne pro lokální notifikace.

Web může otevřít nativní komunikační povrch metodou
`communications.openChat`; payload je prázdný nebo obsahuje jen volitelný
bounded opaque očekávaný OIDC `subjectId`. Modul hostu nevrací token, timeline
ani Matrix interní stav.

### Offline start

- Host vytváří `WKWebView` okamžitě; žádné mazání nebo migrace WebKit dat nesmí
  blokovat první obrazovku. Jednou opakuje navigaci bez cache a potom zobrazí
  lokální fallback.
- COP web v nativním hostu neregistruje browser service worker. Offline start se
  proto neopírá o PWA navigační intercept, který na fyzickém zařízení blokoval
  WebKit proces. Pojmenovaný profil dál bezpečně uchovává cookies, Local Storage,
  IndexedDB a webovou OIDC relaci; nativní Matrix úložiště zůstává oddělené.
- Pokud není k dispozici použitelný shell, zobrazí se lokálně zabalený SwiftUI
  fallback se stavem konektivity a opakováním; bridge ani doménové operace v něm
  nejsou dostupné.
- HTTP chyby hlavního dokumentu se nikdy nezobrazují jako obsah aplikace. Stav
  `408`, `425`, `429` nebo `5xx` host jednou zopakuje bez cache; další neúspěch
  a ostatní `4xx` přepnou na nativní fallback. Chyba subframe nesmí nahradit celý
  aplikační povrch.
- Současný COP offline snapshot je read-only. Offline vytvoření hlášení bude
  povoleno až po implementaci webového outboxu v 01 COP a contract testech.

ADR 0003 stanoví, proč první verze nebalí kopii celého web buildu.

### Push a deep link

CSM Messaging posílá minimální APNs payload. Host zpracuje kategorii a opaque
identifikátor a podle typu otevře autorizovaný nativní chat nebo validovanou COP
web route.
Citlivý obsah není součástí systémové notifikace bez explicitní serverové
politiky. Critical Alerts vyžadují Apple entitlement. Podle ADR 0012 doručí CSM
Messaging minimální PushKit payload `incoming` nebo `ended`. Native oznámí
incoming CallKitu bez čekání, potom načte autoritativní detail z COP API.

Odchozí start vytvoří serverový call záznam s idempotency key. Přijetí,
odmítnutí, zrušení, spojení, ukončení a media failure jsou revizované
idempotentní serverové přechody. Stale revize ani opakovaný tap nemohou vytvořit
druhý hovor.

COP API vydá krátkodobý LiveKit token pouze účastníkovi aktivního hovoru.
CallKit zůstává jediným vlastníkem aktivace `AVAudioSession`; mikrofon se do
LiveKit publikuje až po `provider(_:didActivate:)`. Stav `connected` se
prezentuje až po skutečném připojení vzdáleného LiveKit účastníka. Ukončení vždy
odpojí room, vyčistí CallKit, proximity a audio a zapíše terminální stav do
serverové historie.

Serverová expirace změní nevyzvednutý ringing hovor na `missed` a odešle běžný
terminal `ended` wake. Klient dočte detail a zobrazí „Nepřijatý hovor“ v
konverzaci. Device bridge se na žádné části tohoto toku nepodílí.

## Úložiště a vlastnictví dat

| Data | Úložiště | Vlastník a pravidla |
| --- | --- | --- |
| COP web cache, webová OIDC relace a offline snapshot | persistentní WebKit origin storage | COP web; native obsah nečte ani nekopíruje |
| Nativní OIDC/Matrix credentials a store passphrase | Keychain s device-only accessibility | `CSMCommunicationKit`; nikdy bridge, log ani diagnostický export |
| Nativní Matrix crypto, timeline a communication outbox | chráněný Matrix/application store | `CSMCommunicationKit`; subject/device scope, E2EE a bezpečný cleanup |
| Capability/session stav bridge | paměť procesu | host; zneplatní se při reloadu/navigaci |
| Background tracking samples | chráněný native store | host; subject/session scope, omezená kvóta a retence |
| Share a media soubory | App Group / Application Support s Data Protection | host + extension; opaque ID, hash, kvóta, expirace |
| APNs device token | native technický store a CSM Messaging registry | nikdy COP API, webový JavaScript ani log |
| Relay queue | budoucí šifrovaný native store | pouze experiment; oddělená od webového business outboxu |
| Hlášení a mapová data | COP podle stávajících kontraktů | nevzniká paralelní nativní business model |

Podepisovaný APNs entitlement používá `$(APS_ENVIRONMENT)`: Debug žádá
`development`, Staging a Release `production`. Každý artifact musí být spárován
se stejným APNs prostředím v CSM Messaging: Debug se sandboxem, Staging/Release
s production endpointem. Současný registrační kontrakt prostředí neukládá na
úrovni zařízení a server obsluhuje vždy jen jedno globální prostředí; Debug a
TestFlight tokeny proto nelze bezpečně míchat. Před TestFlight je povinný řízený
cutover na production, nebo samostatně navržený per-device environment kontrakt.

Konkrétní retenční a kvótové hodnoty musí být schváleny v security/privacy
milníku před implementací příslušné služby.

## Externí systémy a kontrakty

| Systém | Úloha | Autorita kontraktu |
| --- | --- | --- |
| COP web/PWA | mapa, hlášení, vrstvy, business workflow a webový klient stejného serverového direct-call kontraktu | repozitář `01 COP` |
| COP API | doménová data a autoritativní direct-call lifecycle + krátkodobé LiveKit credentials | `01 COP/openapi/openapi.json` |
| `CSMCommunicationKit` | nativní chat UI, OIDC/Keychain, Matrix Rust E2EE, offline communication state a call timeline | lokální COP Mobile-owned Swift Package `packages/CSMCommunicationKit` + ADR 0009/0011/0012 |
| Keycloak | oddělené OIDC relace pro web a veřejný nativní PKCE klient | konfigurace a runbooky `01 COP` |
| CSM Messaging / Matrix | APNs/PushKit registry, minimální call wakes, conversation metadata, Matrix bootstrap a E2EE message transport | kontrakt služby CSM Messaging/Matrix |
| LiveKit | nativní a webová audio média jednoho serverově autorizovaného roomu | COP runtime konfigurace a ADR 0012 |
| APNs | systémové doručení notifikací | Apple capability/provisioning |
| iOS Share Sheet | příjem fotek a dokumentů | App Extension kontrakt |
| Budoucí Android host | parita Device API | stejná JSON Schema z `01 COP` |

COP Mobile neposkytuje vlastní REST API. Detail spotřebovávaných a plánovaných
kontraktů je v `docs/api.md`.

## Autentizace a autorizace

- Web používá stávající OIDC/Keycloak flow a bearer tokeny vůči COP API.
- `CSMCommunicationKit` používá samostatný veřejný OIDC/PKCE klient a vlastní
  nativní access/refresh lifecycle v Keychainu. Nikdy nepřebírá webový token a
  nevkládá vlastní authorization rozhodnutí do mapových/report workflow.
- Každá bridge metoda kontroluje session, capability, aktuální permission,
  foreground/background stav a případný serverový kill switch.
- Release bridge je dostupný pouze přes přesnou kombinaci scheme, host a port;
  production baseline je `https://cop.zeleznalady.cz`. Login a další povolené
  navigační originy nikdy nezískají Device API.
- Externí odkazy se otevírají mimo interní WebView. Wildcard origin a bridge v
  iframe jsou zakázané.
- `communications.openChat` prezentuje nativní povrch a smí dodat pouze
  očekávaný OIDC subject jako ochranu proti záměně účtu;
  `calls.updatePresentation` přijme omezený enum stavu a bounded opaque ID.
  Žádná metoda nevystavuje nativní OIDC/Matrix credentials, zprávy, SDP nebo
  ICE kandidáty.
- WebKit media capture je oddělený od Device API bridge: audio-only požadavek
  smí přijít také ze same-origin COP Chat iframe, ale pouze pokud frame i hlavní
  dokument odpovídají přesnému release COP originu. Cross-origin iframe, video
  a kombinované camera+microphone požadavky zůstávají zamítnuté.
  Výchozí port, který `WKSecurityOrigin` hlásí jako `0`, se před porovnáním
  normalizuje na `443` pro HTTPS nebo `80` pro HTTP.

## Distribuce a prostředí

- Samostatný repozitář umožní nezávislý signing a App Store release bez
  přesouvání COP monorepa.
- První target je univerzální iPhone/iPad aplikace s minimem iOS/iPadOS 26.0,
  Swift 6 a stabilním Xcode/SDK. iOS 27 preview API nesmí být produkční
  závislostí.
- První distribuce je interní/TestFlight pilot. Veřejný App Store nebo MDM
  rollout následuje až po permission, privacy, battery a real-device validaci.
- Release používá pouze production originy; staging a debug mají separátní,
  explicitní allowlisty. Debug výjimky nesmějí být zkompilovány do release.
- Web může být nasazován nezávisle pouze v rámci kompatibilní major verze Device
  API. Nekompatibilní web build musí zobrazit řízený stav `BLOCKED`, nikoli
  volat neznámé native metody.

## Omezení platformy

iOS může background práci pozastavit nebo proces ukončit. Host proto garantuje
trvalost stavu explicitní tracking session, nikoli nepřetržité vzorkování,
zvonění nebo relay. Time Sensitive notifikaci může uživatel umlčet. Critical
Alert je samostatně schvalovaná capability. Device-to-device relay zůstane
defaultně vypnutou foreground laboratoří, dokud neprojde iOS–Android fyzický,
bezpečnostní a privacy gate.
