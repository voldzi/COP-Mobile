# ADR 0002: Verzovaný bezpečný COP Device bridge

## Status

Accepted — 2026-07-11

## Context

COP web potřebuje volat nativní služby zařízení z `WKWebView`: polohu,
heading, attitude, background tracking, média, Share Extension inbox,
konektivitu a notifikace. Jednoduché vystavení
`window.webkit.messageHandlers` by dalo XSS, kompromitované dependency,
iframe nebo chybně povolenému redirectu přímou cestu k citlivým capability.

Remote web a App Store host se navíc vydávají nezávisle. Bridge proto musí
bezpečně odmítnout nekompatibilní web build a podporovat postupné přidávání
capabilities bez platformních podmínek ve webu.

## Decision

### Transport a izolace

- iOS host použije `WKScriptMessageHandlerWithReply`, nikoli neomezený
  fire-and-forget handler.
- Native transport/dispatcher bude registrován v pojmenovaném
  `WKContentWorld` odděleném od page world. Do povoleného main documentu se
  vloží pouze úzký transportní facade potřebný pro autoritativní COP Device SDK;
  interní service objekty ani obecný native object graph nejsou v JavaScriptu.
- SwiftUI obalí `WKWebView` vlastním `WebContainer` protokolem. Bridge,
  origin policy a služby musí být testovatelné bez živého WebView.
- Native -> web eventy se volají pomocí `callAsyncJavaScript`/structured
  arguments. Neověřený text se nikdy neinterpoluje do JavaScript source.
- Message handler používá weak proxy/explicitní teardown, aby nevznikl retain
  cycle a handler po zániku WebView nezůstal aktivní.

### Origin a frame policy

- Release bridge origin je přesně `https://cop.zeleznalady.cz` se standardním
  HTTPS portem. Scheme, host i port se porovnávají normalizovaně; wildcard,
  suffix match a „libovolná subdoména“ jsou zakázané.
- Staging a debug build mají samostatné compile-time konfigurace a explicitní
  seznam originů. Debug origin se nesmí dostat do release artifactu.
- Host ověří `WKFrameInfo.isMainFrame`, `securityOrigin` a aktuální
  main-frame URL při každém requestu. Bridge se nevystaví iframe.
- OIDC/login origin může být povolenou navigací, ale nikdy bridge originem.
  Přechod nebo redirect mimo COP origin okamžitě zneplatní session a odebere
  transport facade.
- Produkční konfigurace použije App-Bound Domains pro COP a potřebný OIDC
  top-level origin jako defense in depth a
  `limitsNavigationsToAppBoundDomains`. Externí odkazy se otevírají v
  systémovém browseru. Subresource potřeby mapy/chatu musí projít integračním
  testem před release.
- `isInspectable` je povolen pouze v debug buildu.

### Handshake a kompatibilita

1. Po potvrzeném main-frame navigation commit na COP originu host založí nový,
   kryptograficky náhodný session nonce, ale ještě nepovolí metody.
2. Web pošle `bridge.hello` se seznamem podporovaných Semantic Versions a
   `webBuildId`.
3. Host zvolí nejvyšší společnou kompatibilní verzi a vrátí
   `bridge.ready`: `sessionId`, app/OS info, capabilities a limity.
4. Bez společné verze vrátí `PROTOCOL_VERSION_UNSUPPORTED`; web zobrazí stav
   `BLOCKED`.
5. Reload, process recreation, main-frame redirect nebo přechod na jiný origin
   session zneplatní. Foreground subscriptions se ukončí. Durable
   `tracking` session pokračuje podle nativního lifecycle a po novém handshake
   se pouze znovu načte její stav.

Major verze je breaking. Minor smí přidat volitelné pole, metodu nebo capability;
patch nemění wire význam. Neznámé pole se ignoruje jen tehdy, když to dovoluje
schema; neznámá metoda vrací `UNSUPPORTED`.

### Envelope a validace

- Request, response, event i handshake mají samostatné JSON Schema z
  `01 COP/packages/cop-device-contract`.
- Každý request obsahuje `protocolVersion`, UUID `id`, `sessionId`,
  allowlisted `method`, `sentAt` a validované `params`.
- Každá response opakuje ID a session, obsahuje `ok` a právě jednu větev
  `result` nebo sanitizovaný `error`.
- Event obsahuje UUID, session, monotónní sequence a UTC timestamp. Web musí
  tolerovat mezeru v sequence po suspend/resume a obnovit snapshot stav
  explicitní metodou.
- Baseline maximální velikost bridge JSON je 64 KiB v UTF-8; per-method limit
  může být nižší. Fotografie, dokumenty, tokeny a relay binary payload se přes
  JSON nepřenášejí.
- Schema a semantic validace probíhá na webové i nativní straně. Native navíc
  kontroluje metodu, permission, capability, app lifecycle, server policy,
  foreground požadavek, quota a rate limit.
- Každý request má contract-defined timeout. Dlouhé operace mají cancellation
  ID nebo explicitní stop metodu.

### Replay, idempotence a flooding

- Host drží bounded záznam request ID pro aktivní session. Stejné ID a stejný
  digest vrátí již dokončenou response; stejné ID s jiným obsahem vrátí
  `INVALID_REQUEST`.
- Request ze staré session vrací `SESSION_EXPIRED` a nic nespouští.
- Rate limit je per session i per method. Jeho překročení vrací
  `RATE_LIMITED`; bridge nesmí blokovat MainActor nekonečnou frontou.
- User-visible permission dialog, kamera, picker, zahájení background trackingu
  a relay vyžadují explicitní uživatelskou akci. Stránka je nesmí spouštět při
  bootstrapu.

### Citlivá data

- Web nedostane APNs token, filesystem path, Keychain hodnotu ani nativní
  diagnostický log.
- Native nečte ani nepřebírá webový OIDC access/refresh token. Výjimkou je
  úzce omezený jednorázový registration ticket popsaný v `docs/api.md`.
- Média používají opaque `NativeAssetRef`; přístup je session nebo explicitně
  durable scoped, s hash, expirací a kvótou.
- Release loguje pouze method, outcome, error code, duration, app/contract
  verzi a náhodný correlation ID. Parametry, přesná poloha, route payload,
  asset metadata a identity se redigují.
- Lokální fresh-install fallback Device bridge vůbec nedostane.

### Stabilní chybové chování

Bridge rozlišuje nejméně unsupported, permission not determined/denied/
restricted, invalid request/state, origin/frame chybu, protocol/session chybu,
timeout/cancel, not foreground/ready, transport unavailable, payload/queue
limit, asset missing/expired, rate limit a internal error. Swift error ani stack
trace se neposílá do webu.

## Consequences

### Positive

- Neoprávněný frame, redirect nebo nekompatibilní web build nedostane native
  capability.
- Stejný contract lze implementovat na Androidu bez vazby webu na Swift.
- Session a idempotence dovolí bezpečně zvládnout reload, retry a duplicate
  message.
- Velké soubory a tokeny nejsou vystaveny v univerzálním JSON kanálu.

### Negative

- Bridge má více stavů a contract testů než přímé message handler volání.
- Pojmenovaný content world a App-Bound Domains vyžadují fyzický WebKit/OIDC
  integrační spike.
- XSS na povoleném COP originu stále může volat capability, které uživatel
  povolil; native policy a user mediation proto zůstávají nutné i po origin
  kontrole.
- Independent web deployment musí zachovat kompatibilitu s již vydanými hosty.

## Alternatives Considered

### Přímý handler v page world bez handshake

Odmítnuto: nemá protocol negotiation, session invalidaci ani dostatečnou
izolaci a výrazně zvyšuje dopad iframe/XSS chyby.

### Custom URL schemes jako command bus

Odmítnuto: špatná request/response ergonomie, složité size/escaping chování a
riziko záměny navigace s privileged operací.

### Local HTTP server na zařízení

Odmítnuto: přidává síťový listener, port/origin problémy a zbytečně větší
attack surface.

### JavaScript bridge z obecného hybrid frameworku

Odmítnuto: stále by vyžadoval stejné origin, schema, permission a lifecycle
kontroly; generic plugin API by vystavilo větší surface.

## Security and Privacy Impact

Bridge je privilegiovaná hranice a musí být součást threat modelu, dependency
review a penetračního testu. Content Security Policy webu a supply-chain
kontroly jsou důležité, ale nenahrazují nativní validaci.

Každá nová metoda musí před přidáním doložit účel, capability, permission,
foreground/background pravidlo, user mediation, vstupní/výstupní schema,
limit, timeout, log redaction a kill switch. Metoda bez těchto údajů nesmí být
zaregistrována.

## Validation

Contract a iOS testy musí pokrýt:

- povolený production main frame a odmítnutý HTTP, host, port, subdoménu,
  iframe a redirect;
- bridge deaktivaci na OIDC a externím originu;
- kompatibilní/nekompatibilní verzi a chybějící handshake;
- malformed JSON, unknown field/method, schema mismatch a payload nad 64 KiB;
- duplicate ID se stejným a odlišným payloadem;
- stale session po reloadu;
- permission denied/restricted, not-foreground a server kill switch;
- request timeout, cancel, rate-limit a handler teardown;
- bezpečné event args s apostrofy, Unicode a HTML/JavaScript textem;
- důkaz, že release bridge/log neobsahuje auth/APNs token, cestu ani přesnou
  polohu;
- App-Bound Domains + Keycloak + map/chat subresources na fyzickém iOS 26
  zařízení.
