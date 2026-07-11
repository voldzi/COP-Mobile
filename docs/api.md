# API a integrační kontrakty

This application does not provide a REST API, so it has no OpenAPI specification.

## Stav

COP Mobile neposkytuje REST API, nemá serverový proces a proto v tomto
repozitáři nevzniká `openapi/openapi.json`. Aplikace:

1. hostuje COP web, který volá stávající COP API;
2. poskytuje webu lokální, verzovaný `COP Device API` přes bezpečný bridge;
3. jako nativní klient volá pouze úzce vymezené technické endpointy, například
   registraci APNs zařízení u CSM Messaging.

Implementován je handshake protokolu `1.0.0`, read-only
`system.getCapabilities` a první foreground slice pro `permissions`, `location`
a `heading`. Ostatní namespace host vrací jako `unsupported`; jejich popis níže
je cílový kontrakt, nikoli tvrzení o hotové funkci.

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
| CSM Messaging REST | autoritativní OpenAPI služby CSM Messaging | native push registrace |

Mobilní repozitář nesmí ručně založit konkurenční „master“ kopii TypeScript
typů nebo JSON Schema. Může obsahovat generované Swift/Kotlin modely, zamčenou
verzi schémat a test fixtures jako build input, ale změna kontraktu začíná v
`01 COP`.

## Existující COP REST rozhraní

Následující rozhraní už existují a jejich skutečný wire formát je vždy určen
aktuálním `01 COP/openapi/openapi.json`.

| Metoda a cesta | Účel pro thin host | Poznámka |
| --- | --- | --- |
| `GET /api/v1/mobile/bootstrap` | bezpečná konfigurace, profil, capabilities a read-only snapshot | původně pro plně nativního klienta; thin host jej přímo nepotřebuje pro web UI |
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
- budoucí `relay.*` stavové a transportní události.

Notifikační/deep-link event nese pouze validovanou interní route nebo opaque ID.
Nesmí nařídit navigaci na libovolnou URL.

## Push registrační ticket

Implementovaný kontrakt zachovává tyto hranice:

- COP `POST /api/v1/mobile/devices` neukládá APNs token;
- CSM Messaging `POST /api/v1/devices` dnes očekává uživatelský access token;
- web vlastní OIDC relaci a nativní host ji nemá kopírovat.

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
- Release gate ověří nekompatibilní web/host verzi jako řízený `BLOCKED` stav.
- Změna COP REST API vždy začíná úpravou JSON-first OpenAPI; tento dokument
  nenahrazuje binding wire contract.
