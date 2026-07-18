# API a integrační kontrakty

This application does not provide a REST API, so it has no OpenAPI specification.

## Stav

COP Mobile neposkytuje REST API, nemá serverový proces a proto v tomto
repozitáři nevzniká `openapi/openapi.json`. Aplikace:

1. hostuje COP web, který volá stávající COP API;
2. poskytuje webu lokální, verzovaný `COP Device API` přes bezpečný bridge;
3. přes `CSMCommunicationKit` používá schválené OIDC, COP/CSM Messaging a
   Matrix klientské kontrakty pro nativní E2EE chat;
4. jako nativní host volá úzce vymezené technické endpointy, například
   registraci APNs zařízení u CSM Messaging.

Implementován je handshake protokolu `1.0.0`, read-only
`system.getCapabilities` a první foreground slice pro `permissions`, `location`
a `heading`. Ostatní namespace host vrací jako `unsupported`; jejich popis níže
je cílový kontrakt, nikoli tvrzení o hotové funkci.

ADR 0009 navíc zavádí úzké implementované metody
`communications.openChat` a `calls.updatePresentation`. Samotný nativní chat
není transportován přes Device bridge; je SwiftUI povrchem
`CSMCommunicationKit` a používá serverové kontrakty přímo.

### Implementovaný iOS Location + Heading slice

Host aktuálně obsluhuje:

- `permissions.getStatus`, `permissions.request` a `permissions.openSettings`
  s parametrem `{ "permission": "location" }`;
- `location.getCurrent`, `location.startUpdates`, `location.stopUpdates`;
- `heading.startUpdates`, `heading.stopUpdates`;
- eventy `permission.changed`, `location.updated`, `heading.updated` a
  `heading.calibrationRequired`.

`location.getCurrent` a `location.startUpdates` přijímají prázdné parametry nebo
`desiredAccuracy` s hodnotou `best` či `balanced`. Současný provider pro obě
hodnoty používá `kCLLocationAccuracyBest`; volba zůstává v kontraktu pro budoucí
energetickou politiku. Start metody vyžadují aktivní aplikaci. Subscription končí
při navigaci, reloadu, zániku bridge session nebo změně oprávnění. Slice nic
neukládá, neodesílá na server a nezapíná background location.

Native nikdy nevyvolá systémový dialog z handshake, capability dotazu ani
`location.getCurrent`. Dialog může vyvolat pouze explicitní
`permissions.request`. Výsledek rozlišuje systémový status a přesnost
`full`/`reduced`; MVP automaticky nežádá temporary full accuracy.

## Autorita kontraktů

| Kontrakt | Autoritativní umístění | Spotřebitel |
| --- | --- | --- |
| COP REST API | `01 COP/openapi/openapi.json` | COP web; výjimečně nativní technická služba |
| COP Device JSON Schema | `01 COP/packages/cop-device-contract` | web, iOS, později Android |
| TypeScript `CopDevice` SDK | `01 COP/packages/cop-device-sdk` | COP web a browser/mock adapter |
| Bridge contract fixtures | contract package v `01 COP`; zde připnutý artifact `1.0.0` | TypeScript, Swift a Kotlin CI |
| CSM Messaging REST | autoritativní OpenAPI služby CSM Messaging | native push registrace a `CSMCommunicationKit` |
| Matrix Client-Server/E2EE | Matrix/Synapse a připnutý Matrix Rust SDK | `CSMCommunicationKit` |
| Native communications module API | Swift Package produkt `CSMCommunicationKit` | COP Mobile SwiftUI host |

Mobilní repozitář nesmí ručně založit konkurenční „master“ kopii TypeScript
typů nebo JSON Schema. Může obsahovat generované Swift/Kotlin modely, zamčenou
verzi schémat a test fixtures jako build input, ale změna kontraktu začíná v
`01 COP`.

## Existující COP REST rozhraní

Následující rozhraní už existují a jejich skutečný wire formát je vždy určen
aktuálním `01 COP/openapi/openapi.json`.

| Metoda a cesta | Účel pro thin host | Poznámka |
| --- | --- | --- |
| `GET /api/v1/mobile/bootstrap` | bezpečná konfigurace, profil, capabilities a read-only snapshot | webový povrch jej přímo nepotřebuje; nativní komunikace smí spotřebovat jen explicitně podporovanou část |
| `GET /api/v1/mobile/offline-snapshot` | policy-filtered read-only data | není offline write/outbox kontrakt |
| `POST /api/v1/mobile/devices` | audit mobilní session/capabilities | výslovně není APNs registry |
| `GET /api/v1/mobile/devices` | seznam spárovaných zařízení | přístup uživatele dle COP autorizace |
| `DELETE /api/v1/mobile/devices/{deviceId}` | revokace spárovaného zařízení | musí zůstat sladěno s push/device revokací |
| `POST /api/v1/mobile/pairing/sessions` | založení krátkodobého párování | webová část pairing flow |
| `GET /api/v1/mobile/pairing/sessions/{code}` | stav pairing session | metadata-only |
| `POST /api/v1/mobile/pairing/sessions/{code}/claim` | převzetí kódu nativní aplikací | kandidát pro zachování bundle ID a deep linku |
| `POST /api/v1/mobile/pairing/sessions/{code}/confirm` | potvrzení pairing session webem | neuděluje bridge důvěru libovolnému originu |
| `POST /api/v1/mobile/mesh/ingest` | ingest šifrované/podepsané relay obálky | mimo MVP, nesmí se vydávat za hotový mesh |
| `GET /api/v1/mobile/mesh/acks` | ACK kurzor pro relay obálky | mimo MVP |
| community report + attachment endpointy | draft, upload slot, upload/complete a submit | vlastní je webové report workflow |
| `GET/POST/DELETE /api/v1/push/web/*` | browser Web Push | nesmí se použít jako APNs registry |
| `/.well-known/apple-app-site-association` a `/mobile/pair/{code}` | universal link a pairing fallback | zachovat kompatibilitu `csm://`/AASA |

COP API používá OIDC bearer token a současný COP error envelope s
`correlationId`; thin host nesmí jeho chyby přemapovat na nový serverový
formát. Bridge má vlastní lokální error contract popsaný níže.

## Nativní komunikační kontrakty

`CSMCommunicationKit` je klient, nikoli nový backend. Používá:

- OIDC discovery/authorize/token/logout flow pro veřejný klient `csm-mobile`,
  Authorization Code + PKCE a redirect scheme `csm`;
- COP messaging bootstrap a conversation metadata podle autoritativního COP
  OpenAPI;
- CSM Messaging device/notification preference kontrakty podle autoritativní
  dokumentace služby;
- Matrix Client-Server API přes připnutý Matrix Rust SDK pro session restore,
  sync, E2EE timeline, send queue, media a recovery.
- COP `POST /api/v1/ai/chat-agent/query` pouze pro explicitní přímou konverzaci
  `COP AI Assistant`. Native posílá aktuální otázku a bezpečný identifikátor
  konverzace, nikoli historii roomu nebo Matrix/E2EE tajemství; odpověď se
  publikuje zpět přes Matrix E2EE.

Konkrétní JSON response se nesmí ručně opisovat do tohoto repozitáře. Autoritou
zůstávají OpenAPI služby a verzované Swift modely `CSMCommunicationKit`.
Komunikační modul hostu zveřejňuje pouze SwiftUI surface; nevystavuje access či
refresh token, Matrix device secret, recovery material, decrypted timeline ani
interní service objekty.

Webová a nativní OIDC/Matrix session jsou dvě různá klientská zařízení. Musí mít
odlišné stabilní device ID a samostatný revoke/logout lifecycle. Bridge není
token exchange ani náhrada OIDC.

## Plánované COP Device API

Web používá jediný objekt `CopDevice`. Browser/PWA dostane
`BrowserCopDeviceAdapter`, iOS host `NativeCopDeviceAdapter` a testy mohou
použít deterministický mock. Web se nesmí větvit podle `isIOS` nebo
`isAndroid`.

### Namespaces a minimální surface

| Namespace | Plánované metody | Lifecycle |
| --- | --- | --- |
| `system` | `getCapabilities`, `getAppInfo`, `getDeviceState` | read-only, bez permission dialogu |
| `permissions` | `getStatus`, `request`, `openSettings` | `request` pouze po explicitní user action |
| `location` | `getCurrent`, `startUpdates`, `stopUpdates` | foreground subscription vázaná na bridge session |
| `heading` | `startUpdates`, `stopUpdates` | kompas; obsahuje true/magnetic reference a accuracy |
| `attitude` | `startUpdates`, `stopUpdates` | quaternion + roll/pitch/yaw, první verze pouze foreground |
| `tracking` | `startSession`, `getSession`, `readSamples`, `stopSession` | explicitní durable native-owned background session |
| `connectivity` | `getState`, `startMonitoring`, `stopMonitoring` | stav path oddělený od ověřené dosažitelnosti COP |
| `media` | `capturePhoto`, `pickPhoto`, `pickDocument`, `getAssetMetadata`, `releaseAsset` | vrací pouze opaque asset reference |
| `shares` | `list`, `claim`, `discard` | inbox naplněný Share Extension |
| `notifications` | `getStatus`, `requestAuthorization`, `scheduleLocal`, `cancelLocal`, `registerRemote` | APNs token zůstává native-only |
| `communications` | `openChat` | prázdný request pouze otevře nativní SwiftUI chat; nevrací obsah ani auth stav |
| `calls` | `updatePresentation`, `acknowledgeAction` | přechodné zrcadlení bounded webového call state do SwiftUI/CallKit a potvrzení uživatelského CallKit povelu; žádná signalizace nebo média |
| `relay` | `getStatus`, `start`, `stop`, `enqueue`, `listQueue` | budoucí, opt-in, feature flag, iOS foreground-oriented |

`location.startUpdates` není background tracking. Reload WebView ukončí
foreground subscriptions, ale nesmí ukončit uživatelem spuštěnou
`tracking` session. Po novém handshake web obnoví pohled na tracking přes
`getSession` a cursor-based `readSamples`.

### Capability model

Každá capability vrací jeden ze stavů:

- `supported`
- `unsupported`
- `experimental`
- `restricted`
- `temporarilyUnavailable`

Součástí jsou aktuální permission, pravdivé `supportsBackground`, omezení,
maximální payload/asset velikost a případný požadavek na foreground. Odmítnutá
permission není `unsupported`; dočasná nedostupnost senzoru není
`permissionDenied`.

### Měřicí vzorky

Každý location/heading/attitude vzorek musí obsahovat:

- UTC timestamp měření a informaci o stáří/cached původu;
- přesnost a invalid/uncalibrated stav;
- zvolený reference frame;
- pouze naměřené hodnoty, nikdy simulovaný fallback.

`course` je směr pohybu, `heading` orientace vůči severu a `attitude` 3D
natočení telefonu. Tyto hodnoty nejsou zaměnitelné.

### NativeAssetRef

`NativeAssetRef` obsahuje pouze opaque `assetId`, MIME type, jméno,
velikost, hash, čas, expiraci, rozměry pokud existují a zdroj
(`camera`, `photoPicker`, `documentPicker`, `shareExtension`). Musí
podporovat alespoň obraz, video, PDF a povolené dokumenty.

Bridge nikdy neposílá:

- base64 obsah souboru;
- absolutní filesystem cestu;
- security-scoped URL;
- neomezený EXIF obsah.

Binary upload handoff musí být před implementací médií doplněn do contract
package a navázán na existující COP attachment upload slot. Native nesmí dostat
obecný arbitrary-URL uploader; povolený descriptor musí být serverem vydaný,
časově omezený a hostově validovaný.

## Bridge wire protocol

ADR 0002 je autoritou pro bezpečnostní rozhodnutí. Contract package musí dodat
minimálně schémata request, response, event, handshake, capabilities,
location/heading/attitude sample, tracking session/sample, asset reference a
share item.

### Handshake

```text
web -> native: bridge.hello(supportedVersions, webBuildId)
native -> web: bridge.ready(selectedVersion, sessionId, capabilities, limits)
```

Bez překryvu podporovaných verzí se bridge neaktivuje a web zobrazí stav
`BLOCKED`. Verze používá Semantic Versioning: změna major je breaking, minor
přidává volitelné capability/metody a patch opravuje kompatibilní chování.

### Envelope

Request obsahuje nejméně:

```json
{
  "kind": "request",
  "protocolVersion": "1.0.0",
  "id": "UUID",
  "sessionId": "UUID",
  "method": "location.getCurrent",
  "sentAt": "RFC3339",
  "params": {}
}
```

Response nese stejné `id`, `sessionId`, `ok` a buď validované
`result`, nebo sanitizovaný `error`. Event obsahuje `eventId`,
`sessionId`, monotónní `sequence`, `type`, `occurredAt` a
`payload`.

Pravidla:

- schema se validuje v TypeScriptu i Swiftu;
- main-frame origin se ověřuje při každé zprávě, nikoli jen při navigaci;
- neznámá metoda vrací `UNSUPPORTED`;
- request má timeout a podporované dlouhé operace cancel;
- stejné request ID nesmí operaci spustit dvakrát;
- starý session ID po reloadu nebo navigaci vrací `SESSION_EXPIRED`;
- bridge JSON má baseline limit 64 KiB; per-method limit může být přísnější;
- binary payload ani webový/APNs token není součástí bridge logu;
- native OIDC/Matrix token, chat event, recovery key, SDP ani ICE candidate není
  součástí bridge requestu, response nebo eventu;
- eventy se do JavaScriptu předávají argumenty/structured data, ne interpolací
  neověřeného textu do zdrojového kódu.

### Chybové kódy

Minimální stabilní sada:

```text
UNSUPPORTED
PERMISSION_NOT_DETERMINED
PERMISSION_DENIED
PERMISSION_RESTRICTED
INVALID_REQUEST
INVALID_STATE
ORIGIN_NOT_ALLOWED
MAIN_FRAME_REQUIRED
PROTOCOL_VERSION_UNSUPPORTED
SESSION_EXPIRED
TIMEOUT
CANCELLED
NOT_FOREGROUND
NOT_READY
TRANSPORT_UNAVAILABLE
PAYLOAD_TOO_LARGE
QUEUE_FULL
ASSET_NOT_FOUND
ASSET_EXPIRED
RATE_LIMITED
INTERNAL
```

`message` je bezpečný pro zobrazení uživateli; interní detail patří pouze do
redigovaného nativního logu. `details` nesmí obsahovat cestu, token, přesnou
polohu ani obsah přílohy.

## Události

První kontrakt počítá minimálně s těmito skupinami:

- `device.ready`, `device.capabilities.changed`;
- `permission.changed`;
- `location.updated/error`, `heading.updated/calibrationRequired`,
  `attitude.updated/error`;
- `tracking.stateChanged`, `tracking.samplesAvailable`,
  `tracking.error`;
- `connectivity.changed`;
- `media.assetExpired`, `shares.received`;
- `notifications.opened`;
- `calls.answerRequested`, `calls.rejectRequested`, `calls.endRequested` jako
  úzké user-action eventy pro přechodný webový media engine. Každý nese stabilní
  UUID `actionId`, bounded `callId` a `roomId`; opakované doručení stejného
  `actionId` je retry, nikoli nový uživatelský povel;
- budoucí `relay.*` stavové a transportní události.

Notifikační/deep-link event nese pouze validovanou interní route nebo opaque ID.
Nesmí nařídit navigaci na libovolnou URL.

### Native communications a call presentation

`communications.openChat` přijímá `{}` nebo přesně
`{ "subjectId": "<opaque-oidc-sub>" }` (po trimu nejvýše 160 znaků) a vrací
`{ "opened": true }`. Volitelný subject je pouze očekávaná identita pro
fail-closed porovnání s nezávisle přihlášeným nativním actorem. Metoda
nevytváří session, nepřijímá room ID, token, profil ani obsah zprávy a neposílá
do webu chatový stav.

`calls.updatePresentation` přijímá jen:

- bounded opaque `callId` a `roomId`;
- volitelný bounded display `title`;
- `direction`: `incoming` nebo `outgoing`;
- `phase`: `ringing`, `connecting`, `connected`, `ended` nebo `failed`;
- volitelný `kind`: `direct` nebo `group`;
- pro skupinový hovor nejvýše 20 bounded presentation záznamů v
  `participants`/`eligibleParticipants`, každý pouze s `userId`, display name a
  boolean `connected`.

Neterminální update je povolen jen aktivní aplikaci, pro nejvýše jednu call
identity a po validním stavovém přechodu. `ended`/`failed` může pouze uklidit
již známý hovor. Při zániku bridge session se známý web-owned hovor označí jako
failed a CallKit presentation se odstraní. Procesní kvóta je 40 update requestů
za 60 sekund a nejvýše čtyři nové call identity v klouzavém pětiminutovém
okně; překročení vrací `RATE_LIMITED`.

`calls.acknowledgeAction` přijímá přesně `actionId`, `callId`, `roomId` a
`outcome` (`succeeded` nebo `failed`). Identita musí odpovídat čekajícímu
nativnímu povelu. CallKit `reject`, `end` ani `mute` se neoznačí jako splněný
před kladným potvrzením, které COP Chat odešle až po dokončení příslušné operace
Matrix call enginu. `CXAnswerCallAction` se po konfiguraci audia splní předem,
aby CallKit aktivoval session; Matrix answer přesto čeká na stejné ACK a při
selhání hovor fail-closed ukončí. Native opakuje event se stejným `actionId`;
answer má 35sekundový cold-start limit, ostatní akce 12 sekund. COP Chat drží
před provedením nejvýše 30 sekund bounded pending command, takže cold-start
command nezmizí jen proto, že Matrix call snapshot ještě není připravený.
Neznámé nebo pozdní ACK vrací
`{ "acknowledged": false }` a nemění CallKit stav.
Záporný ACK, nativní timeout i CallKit `timedOutPerforming` vynutí process-wide
invalidaci a reload webového media enginu, ukončení presentation a deaktivaci
audio session. Matrix answer/mute v této větvi selžou; `end`/`reject` lze fulfillnout
až po tomto nuceném lokálním uzavření. Remote `ended` zruší všechny čekající
akce stejného call UUID, aby pozdější retry nemohl hovor obnovit.

Nativní detail konverzace může vyslat `calls.startRequested` s opaque call/room
ID a `kind`. Start používá stabilní `actionId`, bounded retry a identity-bound
ACK stejně jako ostatní call povely; opakování stejného ID není nový hovor.
Aktivní skupinový call view může vyslat
`calls.addParticipantsRequested` s nejvýše pěti unikátními Matrix user ID z
aktuálního `eligibleParticipants`. Obě akce používají stabilní `actionId` a
bounded ACK/retry delivery. Seznam v UI není autorizační rozhodnutí: web a COP API musí členství
znovu ověřit před odesláním cíleného VoIP wake.

Metoda řídí pouze nativní presentation state. SDP, ICE candidates, TURN
credentials, media tracks, Matrix access token ani celý Matrix event jsou
zakázané. Native nesmí vytvořit stav `connected` odhadem; přebírá jej až po
potvrzení současného webového Matrix/WebRTC enginu. Plně nativní media contract
neexistuje a vyžaduje samostatný ADR/gate.

## Push registrační ticket

Implementovaný kontrakt zachovává tyto hranice:

- iOS registrace předá CSM Messaging běžný `deviceToken` a oddělený
  `voipDeviceToken`; veřejná odpověď ani následné čtení zařízení nevrací žádný;
- `voipDeviceToken` se smí použít pouze pro `chat.voice_call.incoming` a
  `chat.voice_call.ended` podle ADR 0008;

- COP `POST /api/v1/mobile/devices` neukládá APNs token;
- CSM Messaging `POST /api/v1/devices` dnes očekává uživatelský access token
  nebo schválený jednorázový registration ticket;
- webový push registration flow nekopíruje webový OIDC token do nativní vrstvy.
  Samostatná nativní OIDC session `CSMCommunicationKit` není bridge credential a
  nemění tuto hranici.

`01 COP/openapi/openapi.json` obsahuje autentizovaný endpoint:

```http
POST /api/v1/mobile/device-registration-tickets
Authorization: Bearer <COP web access token>
```

Vrací 120 sekund platný jednorázový bearer ticket omezený na:

- subject aktuálně přihlášeného uživatele;
- audience CSM Messaging device registration;
- účel APNs registrace;
- platformu iOS, bundle ID a app-instance ID;
- krátkou expiraci a unikátní `jti`.

Web po explicitním zapnutí oznámení předá ticket metodě
`notifications.registerRemote`. Native připojí APNs
token až do přímého požadavku na CSM Messaging. Ticket nesmí autorizovat běžné
COP/Matrix API a CSM Messaging musí zabránit opakovanému použití `jti`.
CSM Messaging ověřuje HMAC podpis, audience, účel, subject, platformu, bundle,
app-instance binding, expiraci a jednorázové `jti`. Sdílený signing secret je
pouze serverová konfigurace a musí mít nejméně 32 bytes; není součástí aplikace,
ticketu ani logů.

## Offline report a synchronizace

Aktuální COP PWA ukládá read-only snapshot, ale nepovoluje manuální hlášení v
offline fallbacku. Thin host tuto mezeru nesmí skrýt nativním formulářem.
Budoucí práce v `01 COP`:

1. webový report outbox nad existujícím community-report workflow;
2. stabilní client-generated report ID a existující idempotency mechanismus;
3. korelace web outbox položky s `NativeAssetRef`;
4. retry, conflict a user-visible sync lifecycle;
5. contract testy airplane-mode -> reconnect.

Native tracking/share/relay queue a webový business outbox jsou různé fronty.
Nesmějí se sloučit ani potvrdit bez explicitního correlation ID.

## Kompatibilita a testování kontraktu

- Contract CI v `01 COP` validuje JSON Schema a TypeScript adapter.
- iOS CI spustí stejné valid/invalid fixtures proti Swift decoderu a validatoru.
- Každá nová metoda obsahuje success, permission denied, unsupported, timeout,
  malformed input, duplicate ID a stale session fixture.
- Web musí projít testy s native, browser i mock adaptérem.
- `CSMCommunicationKit` musí projít své OIDC/Matrix/E2EE contract a migration
  testy proti připnutému SDK a staging backendům.
- `communications.openChat` a `calls.updatePresentation` mají validní,
  malformed, origin/frame, duplicate ID, stale session a payload-limit fixtures.
- Release gate ověří nekompatibilní web/host verzi jako řízený `BLOCKED` stav.
- Změna COP REST API vždy začíná úpravou JSON-first OpenAPI; tento dokument
  nenahrazuje binding wire contract.
