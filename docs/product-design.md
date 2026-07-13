# Produktový návrh

## Stav a závazná rozhodnutí

Tento dokument popisuje cílovou zkušenost produktu **CSM** po rozhodnutí
ADR 0009. Repozitář obsahuje iOS host, nativní komunikační povrch a nativní
prezentaci hovoru; plně nativní WebRTC zůstává dalším gate.

- Minimální podporovaná verze je **iOS 26**. Starší verze iOS nejsou podporované.
- CSM je hybridní host existujícího webu COP, nikoli druhá implementace mapy a
  report workflow.
- Web COP zůstává jediným vlastníkem mapy, vrstev, business logiky, doménových
  modelů, autorizace a workflow hlášení.
- `CSMCommunicationKit` vlastní nativní SwiftUI chat, vlastní OIDC/PKCE session,
  Keychain, Matrix Rust E2EE a chráněný offline communication state.
- Nativní host vlastní také bridge, senzory, tracking, Share Extension, APNs,
  CallKit, audio routing a proximity presentation.
- První distribuční kanál je interní TestFlight. Android následuje až po
  stabilizaci sdíleného Device API a iOS hostu.
- Relay/mesh není součástí MVP. Zůstává vypnutý a později vznikne jako oddělený
  laboratorní experiment bez citlivých produkčních dat.

## Produktový záměr

CSM zpřístupní uživateli stejný COP, který používá v prohlížeči, a doplní ho o
telefonní komunikační zkušenost. Mapa a hlášení zůstávají známým webovým COP;
chat se otevírá jako rychlý nativní E2EE povrch a hovor jako systémově přirozená
CallKit/SwiftUI obrazovka. Přechod mezi povrchy nesmí měnit identitu konverzace
ani vytvářet konkurenční mapové či report workflow.

Úspěch produktu znamená, že:

- mapa a business workflow mají stejný obsah a chování v browseru i v CSM;
- webový a nativní chat interoperují přes stejné Matrix rooms a E2EE pravidla,
  i když představují dvě oddělená klientská zařízení;
- nativní capability jsou přístupné přes jeden verzovaný `CopDevice` kontrakt;
- odmítnuté oprávnění nikdy nezablokuje funkce COP, které je nepotřebují;
- uživatel vždy pozná, zda probíhá tracking, zda je obsah offline a zda bylo
  hlášení skutečně odesláno;
- aplikace po prvním online načtení otevře cached web shell bez internetu a na
  čerstvé offline instalaci zobrazí použitelný lokální fallback;
- push otevře správný nativní chat nebo webovou route bez citlivého obsahu v
  payloadu;
- žádný release neslibuje nepřerušitelné vyzvánění, přesnost GPS nebo background
  běh, které operační systém negarantuje.

## Cíloví uživatelé

| Uživatel / role | Primární potřeba | Signál úspěchu |
| --- | --- | --- |
| Uživatel COP v terénu | Otevřít mapu nebo nativní chat, připojit polohu či soubor a přijmout výstrahu | Dokončí úkol v jednom hostu a bez záměny mapového a komunikačního povrchu |
| Volající/příjemce hovoru | Přijmout, uskutečnit a ukončit skutečný VoIP hovor jako běžnou telefonní akci | CallKit a full-screen UI ukazují pravdivý stav, správně routují zvuk a reagují na přiložení k uchu |
| Uživatel s aktivním sledováním | Výslovně spustit a ukončit přesnější sběr polohy i při zhasnuté obrazovce | Vždy vidí aktivní stav, dopad na baterii a poslední čas měření |
| Příjemce výstrahy | Rozpoznat notifikaci a přejít na relevantní obsah v COP | Deep link otevře autorizovanou webovou route, nebo bezpečný fallback |
| Správce pilotu / podpora | Ověřit verzi, capability a stav oprávnění bez přístupu k citlivému obsahu | Diagnostika vysvětlí chybu bez polohy, tokenů a payloadů v logu |
| Vývojář/tester | Reprodukovat bridge, offline a systémové scénáře | Výsledek je doložen na konkrétním fyzickém zařízení s iOS 26 |

## Rozsah MVP pro iOS 26

MVP obsahuje:

1. SwiftUI host s bezpečným `WKWebView`, trvalým webovým úložištěm a přesným
   allowlistem originů.
2. Handshake a capability-based bridge mezi webem a nativními službami.
3. Aktuální polohu, heading/kompas a 3D attitude ve foregroundu, vždy včetně
   času, přesnosti, validity a dostupných omezení.
4. Uživatelem explicitně spuštěnou background tracking session. Tracking musí
   být nativně vlastněný, přežít reload WebView a mít trvale dostupné Stop.
5. Pořízení fotografie, systémový výběr fotografie nebo dokumentu a Share
   Extension pro příjem položek z jiných aplikací. Bridge předává pouze opaque
   asset handle, nikdy filesystem cestu ani base64 soubor.
6. Běžné a Time Sensitive APNs/lokální notifikace s deep linkem do webu COP.
   Critical Alerts jsou samostatný gate závislý na schválení Applem.
7. Cached start po dřívějším online načtení a lokální informativní fallback při
   čerstvé instalaci bez sítě.
8. Minimalizovanou, redigovanou diagnostiku pro interní pilot.
9. Nativní SwiftUI chat přes `CSMCommunicationKit`, nativní OIDC/PKCE,
   Keychain, Matrix Rust E2EE, chráněnou timeline a offline message outbox.
10. Nativní full-screen call presentation, CallKit/PushKit, mute/speaker route,
    duration a proximity blackout nad dočasným webovým Matrix/WebRTC enginem.

MVP neobsahuje:

- nativní mapu, report formulář, vyhodnocování výstrah ani kopii COP business
  modelů;
- background attitude nebo garantovaný sběr po force-quit aplikace;
- plně nativní WebRTC media engine, dokud neprojde samostatný signaling/ICE/TURN
  a real-device gate;
- garantované přehrání zvuku při mute/Focus bez Critical Alerts entitlementu;
- produkční relay, mesh, Wi-Fi Aware, Nearby Connections ani citlivý
  store-and-forward;
- Android implementaci, Watch aplikaci, lokální AI a plné offline kopie
  business logiky;
- nový backend pro push, upload nebo offline sync bez změny autoritativních COP
  kontraktů.

## Kritické uživatelské cesty

| Cesta | Vstup | Požadovaný výsledek | Chyba / fallback |
| --- | --- | --- | --- |
| První online start | Ikona CSM | Načte se důvěryhodný COP origin, proběhne login a bridge handshake | Nepovolený origin bridge nedostane; síťová chyba zobrazí lokální fallback s Retry |
| První otevření nativního chatu | Tlačítko Chat nebo `communications.openChat` | Otevře se SwiftUI chat; bez nativní session proběhne OIDC/PKCE login a Matrix bootstrap | Cancel/denied/network chyba ponechá web COP funkční a nevystaví token diagnostice |
| Nativní E2EE zpráva | Composer v konverzaci | Zpráva vstoupí do encrypted outboxu, Matrix ji odešle a UI rozliší pending/sent/failed | Offline položka zůstane lokálně, retry nevytvoří duplicitní serverový event |
| Nativní dotaz COP AI | Composer v přímé konverzaci `COP AI Assistant` | Aktuální otázka se zpracuje kanonickým COP AI endpointem a odpověď se vrátí jako E2EE Matrix zpráva | Historie roomu se do COP neposílá; selhání AI nezmění doručení původní uživatelské zprávy |
| Příchozí hovor | VoIP push nebo aktivní Matrix invite | CallKit okamžitě oznámí skutečný hovor a SwiftUI zobrazí ringing/connecting/connected | Expirovaný/ukončený hovor se zavře; presentation nikdy nepředstírá media connection |
| Skupinový hovor | Telefon v detailu skupiny nebo `+` v aktivním hovoru | Uživatel zahájí hovor a v elegantním nativním pickeru postupně přizve dostupné členy; stav ukazuje počet připojených | Připojený či nečlenský uživatel se nenabídne/nepřijme; po dosažení šesti osob se přidávání skryje |
| Hovor u ucha | Connected hovor se sluchátkovou routou | Proximity senzor zčerná povrch a blokuje náhodné tapy; po oddálení obnoví ovládání | Po ukončení se monitoring vždy vypne; Bluetooth/speaker nepoužívají falešný blackout |
| Opakovaný offline start | Ikona CSM, bez sítě | Do 3 s se zobrazí cached web shell a pravdivý stav `OFFLINE_CACHED` | Poškozená/nekompatibilní cache přejde na lokální fallback, nikoli na prázdný WebView |
| Čerstvá instalace offline | Ikona CSM, bez předchozího startu | Lokální obrazovka vysvětlí, že COP ještě nebyl stažen, ukáže konektivitu a Retry | Není dostupný nativní report formulář; nevzniká falešné „odesláno“ |
| Jednorázová poloha | Akce ve webovém workflow | Web zobrazí polohu, přesnost, stáří a stav precise/reduced | Odmítnutí nabídne pokračování bez polohy a odkaz do Nastavení |
| Kompas a natočení | Akce ve webu, aplikace ve foregroundu | Web dostává throttlovaná validní měření a umí je zastavit | Nevalidní/nekalibrované měření je označeno, nikoli nahrazeno course |
| Background tracking | Výslovné Start po vysvětlení dopadu | Aktivní session pokračuje v mezích iOS, má systémově viditelný stav a Stop | Revokace, force-quit nebo omezení systému session přeruší a web zobrazí poslední pravdivý stav |
| Sdílení do CSM | Share Sheet ve Fotkách/Souborech | Extension bezpečně zkopíruje podporovaný soubor do App Group inboxu; host po dovoleném handoffu nebo příští aktivaci otevře webový import | Nepodporovaný/velký soubor je odmítnut před kopírováním s jasným důvodem |
| Push výstraha | APNs nebo lokální notifikace | Tap otevře správnou autorizovanou route v COP | Neplatná route otevře bezpečnou domovskou stránku; neautentizovaný uživatel projde loginem |
| Odmítnutí oprávnění | Systémový dialog | Dotčená capability se vypne, ostatní COP zůstane funkční | Aplikace dialog neopakuje; další změnu nabízí přes Nastavení po akci uživatele |

## Povrchy a vlastnictví UI

| Povrch | Účel | Vlastník | Pravidlo |
| --- | --- | --- | --- |
| COP WebView | Mapa, hlášení, vrstvy, webový login a business workflow; přechodně call media engine | COP web | Nativní host neupravuje význam business stavů ani WebRTC connection state |
| Nativní chat | Seznam, konverzace, composer, E2EE/offline stav a komunikační nastavení | `CSMCommunicationKit` | Vlastní OIDC/Matrix session; žádný token nebo decrypted payload přes bridge |
| Aktivní hovor | Příchozí/odchozí full-screen UI, status, duration, mute, route, přizvání člena a end | CSM native + CallKit | Web zrcadlí pouze bounded state; do dalšího gate vlastní média webový engine; skupina má limit šest osob |
| Proximity blackout | Ochrana obrazovky a dotyků při connected handset hovoru | iOS sensor + CSM native | Jen po dobu relevantního hovoru; není to auth/presence signál |
| Launch/loading shell | Bezpečný start a rozlišení loading/offline/error | CSM native | Jen technický stav, žádná doménová data ani navigace COP |
| Offline fallback | Čerstvý offline start nebo nepoužitelná cache | CSM native | Konektivita, Retry, verze a bezpečná nápověda; bez nativního reportu v MVP |
| Permission pre-prompt | Vysvětlení konkrétního účelu před systémovým dialogem | Web text + native systémová akce | Zobrazí se až po uživatelské akci; odmítnutí se respektuje |
| Tracking status | Aktivní režim, přesnost, baterie a Stop | Native stav prezentovaný webu; systémová indikace iOS | Musí zůstat dostupný i po reloadu webu |
| Share Extension | Přijetí fotografie/dokumentu do technického inboxu | CSM native extension | Neobsahuje report formulář; pouze validuje, kopíruje a předá handle |
| Systémová notifikace | Upozornění a vstupní deep link | iOS/APNs + COP route | Payload je minimální; zvuková úroveň odpovídá udělené autorizaci |
| Diagnostika pilotu | Capability, verze, oprávnění a poslední redigovaná chyba | CSM native | Dostupná jen interně; nikdy nezobrazuje token, přesnou polohu ani obsah zprávy |

## Informační architektura a stavový model

CSM má dva vědomě oddělené produktové povrchy: COP a Komunikace. COP route řídí
web; chat má vlastní nativní `NavigationStack`/`NavigationSplitView` uvnitř
`CSMCommunicationKit`. Nativní chat se může prezentovat přes celý displej nad
stále živým WebView, aby návrat neztratil COP route ani webový call engine.
Aktivní call overlay má nejvyšší prioritu bez ohledu na zvolený povrch.

Domovská obrazovka chatu používá jedinou kompaktní nativní hlavičku `Chat`,
vyhledávání nahoře, přepínač `Skupiny / Lidé`, vodorovné `Oblíbené` a úsporné
chronologické řádky. Host nesmí přidávat druhou hlavičku; zavření, připravenost,
nová zpráva a nová skupina zůstávají v nativních toolbar menu.

Minimální provozní stavy jsou:

| Stav | Význam | Povolené chování |
| --- | --- | --- |
| `ONLINE` | COP backend je ověřeně dostupný | Standardní webové workflow a dostupné native capability |
| `DEGRADED` | Síť existuje, ale COP nebo část závislostí není ověřeně dostupná | Cached data a pouze operace, které web označí jako bezpečné |
| `OFFLINE_CACHED` | Není backend; je dostupný dříve uložený web shell | Read-only nebo outbox operace pouze podle skutečné capability COP |
| `OFFLINE_FALLBACK` | Není bezpečně použitelný web shell | Lokální technická nápověda, konektivita a Retry |
| `SYNCING` | Webový outbox synchronizuje | Zobrazit průběh; položku neoznačit jako doručenou před serverovým ACK |
| `BLOCKED` | Origin, verze protokolu nebo bezpečnostní kontrola selhala | Bridge vypnout, zobrazit bezpečnou chybu a diagnostický kód |
| `CHAT_AUTH_REQUIRED` | Nativní communication session není dostupná | Zobrazit nativní OIDC login; webovou session nekopírovat ani automaticky neodhlašovat |
| `CHAT_OFFLINE` | Matrix není dostupný, ale lokální E2EE store je odemčený | Zobrazit cached timeline a encrypted pending outbox s pravdivým stavem |
| `CALL_RINGING/CONNECTING/CONNECTED` | Nativní prezentace stavu potvrzeného call enginem | CallKit/SwiftUI ovládání; `CONNECTED` pouze po potvrzení media enginu |

`RELAY_ONLY` a relay fronta patří až do pozdější experimentální fáze a nesmějí
měnit význam stavů MVP.

## Design systém a interakce

- WebView používá beze změny design systém COP. CSM nesmí styl webu překrývat
  injektovaným CSS ani duplikovat jeho komponenty.
- Nativní chat používá vlastní konzistentní CSM design založený na SwiftUI,
  systémových materiálech a SF Symbols. Může být stejně přirozený jako moderní
  messengery, ale nekopíruje chráněný vizuální vzhled iMessage nebo WhatsApp.
- Call view používá velké, jednoznačné telefonní akce, stav spojení, duration a
  route label. Černý proximity overlay nesmí mít skrytě aktivní ovládací prvky.
- Potvrzený tap v hlavním WebView doprovází jemná systémová selection haptika.
  Gesture recognizer neruší webový touch/click, scroll ani zoom a nevyžaduje
  chráněné oprávnění. Haptika je doplněk; nikdy není jediným nositelem stavu.
- Lokální nativní povrchy používají standardní komponenty iOS 26, Dynamic Type,
  systémové barvy, Safe Area a SF Symbols. Vizuální identita CSM se promítne do
  ikony, názvu a schválených brand tokenů, ne do vlastního paralelního systému.
- Pohyb je minimální, respektuje Reduce Motion a nesmí skrývat čekání na síť,
  lokaci nebo oprávnění. Loading má timeout a přechod do pojmenovaného stavu.
- Akce s dopadem na soukromí mají explicitní aktivaci. Start a Stop trackingu
  nesmějí být závislé pouze na gestu, časovači nebo přítomnosti WebView.
- Každá systémová chyba má krátký uživatelský text a stabilní diagnostický kód;
  interní detail patří do redigovaného logu.

## Přístupnost a zařízení

Nativní povrchy musí splnit WCAG 2.2 AA tam, kde je standard aplikovatelný, a
Apple accessibility guidance pro iOS 26:

- VoiceOver čte stav offline, tracking, přesnost i tlačítko Stop;
- všechny ovládací prvky podporují Dynamic Type bez ořezu;
- stav není sdělen pouze barvou nebo pohybem;
- touch targety jsou nejméně systémového doporučeného rozměru;
- Reduce Motion, Increase Contrast, Bold Text a Voice Control neblokují cestu;
- iPhone podporuje portrait i landscape tam, kde je podporuje web COP;
- iPadOS 26 je před vydáním samostatně ověřen, pokud bude target označen jako
  univerzální aplikace.

Přístupnost mapy a formulářů zůstává odpovědností COP webu. Nativní chat a call
view jsou odpovědností `CSMCommunicationKit`/hostu a musí mít správné pořadí
VoiceOver, Dynamic Type, klávesnici, Reduce Motion a call-control labels. CSM
release zároveň nesmí zhoršit focus, zoom ani čtečku obrazovky ve `WKWebView`.

## Důvěra a pravdivé systémové sliby

- „Poloha“ vždy zahrnuje přesnost a čas; „směr pohybu“ se nevydává za kompas.
- „Tracking aktivní“ znamená aktivní nativní session, ne pouze zapnuté
  oprávnění. Force-quit a systémová omezení jsou popsána jako přerušení.
- Běžné a Time Sensitive notifikace mohou být uživatelem umlčeny. Critical
  Alerts se nezobrazují jako dostupné, dokud není entitlement a autorizace.
- CallKit/PushKit nebude použit k imitaci krizového vyzvánění bez skutečného
  VoIP hovoru.
- Nativní call obrazovka neznamená nativní média. Do dalšího gate se stav
  spojení odvozuje pouze z potvrzeného webového Matrix/WebRTC enginu.
- „E2EE“ znamená aktivní Matrix encryption path; existence Keychain položky ani
  lokální cached preview sama o sobě není důkazem obnovitelnosti staré historie.
- „Odesláno“ smí web zobrazit až po autoritativním serverovém potvrzení.
- Experimentální relay nikdy není prezentován jako garantovaná nebo always-on
  mesh síť.

## Produktové signály a vizuální QA

Bez citlivého payloadu se vyhodnocuje zejména úspěšnost startu, handshake,
permission flow, deep linku, cached startu, background session a Share
Extension importu. Přesná poloha, obsah hlášení, fotografie, tokeny ani raw peer
ID se do telemetry neposílají.

Před každým pilotním releasem musí být vizuálně ověřeno:

- online, degraded, cached-offline, fresh-install fallback a blocked stav;
- udělené, odmítnuté, omezené a za běhu odebrané oprávnění;
- tracking ve foregroundu, backgroundu, po reloadu WebView a po přerušení;
- share flow pro podporovaný, nepodporovaný a příliš velký soubor;
- notifikace a deep link při odemčeném i zamčeném zařízení;
- nativní OIDC login/cancel/refresh/logout, chat inbox, E2EE timeline, offline
  outbox, delivery/error stav a přepnutí web/native Matrix zařízení;
- ringing, connecting, connected, failed a ended call view, mute, speaker,
  Bluetooth, proximity blackout a návrat po ukončení;
- VoiceOver, Dynamic Type, Reduce Motion, dark mode a landscape;
- že nativní povrchy nevytvářejí druhou mapu ani report workflow a call UI
  netvrdí plně nativní WebRTC před splněním gate.
