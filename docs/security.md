# Bezpečnostní baseline

## Stav a hranice

Repozitář neposkytuje backend. Hybridní host implementuje exact-origin/main-frame
bridge, nativní E2EE komunikační povrch z `CSMCommunicationKit` a nativní call
presentation podle ADR 0009. Web COP je vzdálený, aktualizovatelný kód na
privilegované hranici; trusted origin proto není trusted payload. Nativní
komunikační modul je samostatná privilegovaná hranice se svou OIDC/Matrix
session a encrypted stores.

Chráníme zejména:

- webovou OIDC relaci a WebKit origin storage;
- nativní OIDC/Matrix credentials, Matrix crypto store, recovery stav,
  decrypted timeline a communication outbox;
- nativní permissions a privileged Device API metody;
- přesnou polohu, heading/attitude a tracking samples;
- APNs token a device registration;
- fotografie, dokumenty, metadata a App Group inbox;
- signing/key material a budoucí relay queues;
- integritu bridge, deep linků a release konfigurace.

## Authentication and authorization

- Web COP vlastní svou OIDC Authorization Code + PKCE relaci.
  `CSMCommunicationKit` vlastní oddělenou nativní OIDC/PKCE relaci pro veřejný
  `csm-mobile` klient. Native nečte WebKit token storage a webový token se
  nekopíruje do Keychainu.
- Uživatel může používat jen nativní komunikaci COP Mobile bez webové mapy.
  Embedded chat tiše obnoví vlastní Keychain session a po explicitním tapu na
  Chat může spustit nativní OIDC Authorization Code + PKCE. Webové
  cookies/bearer tokeny se nečtou ani nepřenášejí do nativního klienta.
- Přihlášená mapa smí přes exact-origin bridge předat pouze bounded opaque
  očekávaný OIDC `subjectId`. Native jej porovná s actor subjectem z vlastního
  bootstrapu a při neshodě failuje zavřeně. Toto není credential bridge:
  cookie, bearer/refresh token, profil, Matrix ID ani obsah zpráv se nepřenáší.
- Nativní OIDC callback musí ověřit issuer, redirect URI, state a PKCE verifier;
  aplikace nesmí obsahovat OIDC client secret.
- Nativní access/refresh token a Matrix device/session material jsou dostupné
  pouze uvnitř komunikačního modulu. Host view a bridge dostávají nanejvýš
  redigovaný auth stav, nikdy credential.
- Bridge neposkytuje auth token API. Remote push čeká na jednorázový,
  krátkodobý COP→CSM registration ticket popsaný v `api.md`.
- Doménovou autorizaci mapy, chatu, hlášení a uploadu vždy provádí COP/CSM
  backend nebo Matrix room policy. Udělená systémová permission ani existence
  lokální timeline ji nenahrazuje.
- Nativní autorizace je per-method: platná bridge session, přesný origin a main
  frame, capability, permission, lifecycle/foreground stav, server policy,
  rate/quota limit a případná explicitní user action.

## Secure WebView bridge

Povinné kontroly jsou detailně v ADR 0002:

- `WKScriptMessageHandlerWithReply`, pojmenovaný `WKContentWorld` a úzká facade;
- přesný scheme/host/port allowlist, žádný wildcard nebo suffix match;
- `isMainFrame` a `securityOrigin` při každém requestu;
- handshake, SemVer, náhodný session ID, sequence a invalidace při reloadu či
  navigaci;
- JSON Schema na obou stranách, method allowlist, timeout/cancel, idempotentní
  request ID, 64 KiB baseline limit a per-method rate limit;
- žádná obecná práce se soubory, libovolné URL, reflexe nebo execute/eval metoda;
- native→web event přes structured arguments, ne interpolaci textu do JS;
- release bez Web Inspectoru a debug originů.

XSS na povoleném COP originu stále může volat uživatelem povolenou capability.
Proto citlivé operace vyžadují user mediation a nativní policy i po origin
kontrole. COP web musí udržovat CSP, dependency/supply-chain kontroly a vlastní
XSS ochrany.

## Network and transport security

- Release povoluje pouze HTTPS/TLS originy a nepovoluje arbitrary loads ani
  mixed content. Debug ATS výjimky nesmějí být v release artifactu.
- Certifikátové chyby se fail-closed; žádné tlačítko „pokračovat i tak“.
- Connectivity status nerozhoduje jen podle Wi-Fi. Backend reachability je
  samostatný, kontrolovaný signál.
- Deep link se normalizuje na allowlisted interní route/opaque ID. Libovolná
  externí URL ani `javascript:` se do WebView nenaviguje.
- Nativní komunikace smí volat pouze přesně nakonfigurované HTTPS COP/CSM/Matrix
  a OIDC endpointy. Homeserver z bootstrapu se validuje proti schválené policy;
  redirect, proxy ani media URL nesmí obejít ATS nebo zavést arbitrary request.

## Secrets and signing

- Do Git se neukládají APNs `.p8`, provisioning profily, certificates,
  signing identity, service tokeny, OIDC client secret, access/refresh token,
  Matrix recovery key ani produkční managed config.
- Apple signing a APNs secrets vlastní App Store Connect/CI secret store a CSM
  Messaging. Aplikace obsahuje jen veřejnou konfiguraci nutnou pro client.
- Nativní OIDC/Matrix tokeny, Matrix device binding, technické klíče a store
  passphrase vznikají nebo jsou přijaty pouze uvnitř komunikačního modulu a
  ukládají se v Keychain s device-only accessibility třídou. Nikdy se nelogují,
  nevkládají do UserDefaults ani neexportují diagnostikou.
- `.env.example` je pouze bezpečný vstup budoucích lokálních config skriptů;
  podepsaná aplikace nesmí číst repository `.env` za běhu.

## Protected local storage

- Web auth a COP doménová cache zůstávají v persistentním WebKit data store na
  přesném originu. Native je neinterpretuje.
- `CSMCommunicationKit` vlastní oddělený chráněný Matrix crypto/timeline store,
  encrypted message outbox a bootstrap cache. Každý store je subject- a
  device-bound, má integrity/retention policy a nesmí se zaměnit s WebKit
  IndexedDB.
- AI chat může od hostu získat krátkodobý vzorek aktuální polohy jen tehdy,
  pokud hlavní COP map/device flow už má oprávnění. Komunikační vrstva sama
  systémový permission dialog nikdy nevyvolává; bez oprávnění předá nulovou
  polohu a backend si vyžádá název místa běžnou otázkou.
- Tracking samples, Share inbox a asset metadata používají encrypted/protected
  files, atomic writes, integrity hash, subject/app-instance scope, byte quota,
  TTL a explicitní cleanup.
- App Group je dostupný pouze hostu a Share Extension. Extension přijímá
  nedůvěryhodný `NSItemProvider`, kontroluje UTType, skutečnou velikost, quota a
  bezpečný název; absolutní cesta se nikdy nevrací webu.
- `NativeAssetRef` je náhodný opaque handle. Přístup je session/durable-scope
  bound, expirovatelný a auditovatelný bez obsahu.
- EXIF poloha se nepředává ani neuploaduje bez explicitního doménového consentu.
- Webový a nativní logout jsou oddělené lifecycle. Nativní logout, změna
  subjectu, revokace zařízení a remote wipe nikdy nezpřístupní cache předchozího
  uživatele; cleanup Matrix stores musí upozornit na recovery dopad a nesmí
  smazat webovou session bez explicitní produktové akce.
- Nativní relace zůstává v device-only Keychainu do explicitního logoutu, wipe
  nebo serverem potvrzeného OAuth `invalid_grant`. Access token se obnovuje
  centrálně a na vyžádání; timeout, offline stav, dočasná chyba OIDC a
  nedostupnost chráněných dat nesmí tokeny smazat. Zrušené Face ID pouze uzamkne
  chráněný obsah a nabídne nové odemknutí.

## Background tracking

- Start pouze explicitně ve foregroundu po účelovém vysvětlení; aktivní stav a
  Stop jsou stále dostupné a odpovídají skutečné nativní session.
- Store má bounded frekvenci, retenci a velikost; release logy neobsahují
  souřadnice. Background upload je zakázán do schválení scoped auth delegation.
- Permission revoke, system restriction, force-quit a storage error přejdou do
  pravdivého stopped/degraded stavu; aplikace neslibuje kontinuitu, kterou iOS
  negarantuje.

## Notifications

- APNs token vlastní native + CSM Messaging, nikdy web JavaScript ani COP store.
- Push payload obsahuje minimální ID, typ, expiraci a allowlisted deep link;
  žádný plaintext E2EE obsah, chráněná URL, token ani přesná poloha.
- Ordinary, Time Sensitive a Critical jsou samostatné capability. Critical
  vyžaduje skutečný Apple entitlement a user authorization.
- PushKit/CallKit se podle ADR 0008 používá pouze pro skutečný Matrix VoIP hovor
  a nesmí se použít pro safety alarm, běžnou notifikaci ani background keepalive.
- ADR 0009 přidává nativní SwiftUI call presentation, proximity blackout a
  audio routing, ale signalizace, SDP/ICE a média zůstávají do dalšího gate ve
  webovém Matrix/WebRTC enginu. Bridge přijímá jen bounded presentation state a
  opaque ID; aktivní update vyžaduje foreground, jednu stabilní call identity a
  povolený přechod stavového automatu. Stav `connected` musí pocházet z
  potvrzeného media enginu a `ended`/`failed` musí vždy vyčistit CallKit. Bridge
  povolí nejvýše 40 presentation aktualizací za minutu a čtyři nové call
  identity za pět minut v jednom procesu.
- Skupinový call bridge přijímá pouze bounded `direct`/`group` kind a participant
  presentation bez SDP, ICE, tokenů nebo Matrix eventů. `addParticipants` nese
  nejvýše pět unikátních user ID, která pocházejí z aktuálního eligible seznamu;
  COP API přesto každou identitu znovu ověřuje vůči aktivnímu členství v místnosti.
  Webový E2EE peer mesh je omezen na šest osob.
- CallKit user action používá náhodné stabilní `actionId`, bounded retry a
  identity-bound ACK. Native akci nefulfilluje na základě pouhého doručení do
  JavaScriptu; vyžaduje úspěšné dokončení Matrix commandu a při timeoutu nebo
  záporném ACK failuje. Opakovaný event je idempotentní a pozdní/cizí ACK nesmí
  ovlivnit jiný hovor. Chyba WebKit JavaScript delivery invaliduje session a
  povel bezpečně requeueuje; reset CallKit provideru vynutí ukončení webového
  media enginu.
- Timeout/záporný ACK nikdy nenechá běžet neřízený webový track: host vyvolá
  process-wide reload WebView, reportuje a odstraní call a deaktivuje audio.
  `end`/`reject` smí fulfillnout až po tomto forced close, zatímco `answer`/`mute`
  failuje. CallKit `timedOutPerforming` používá stejnou větev i při suspendu.
- Host zůstává jediným `UNUserNotificationCenterDelegate`; komunikační kit
  přijímá APNs token a delivery/action callbacky pouze přes typovanou nativní
  facade a nesmí delegate hostitele přepsat. Před mountem drží nejvýše 16
  metadata-only push payloadů a při zpracování je atomicky claimne.
- Proximity monitoring je aktivní pouze během relevantního hovoru a po jeho
  ukončení se vždy vypne. Call UI nesmí používat proximity jako auth nebo
  presence signál.
- Background mode `audio` je určen výhradně aktivní CallKit
  `.playAndRecord` session; nesmí sloužit jako keepalive a po end/failure se
  audio session deaktivuje.
- Běžný APNs token a PushKit token jsou oddělené šifrované serverové secrets;
  web ani COP API nesmí dostat žádný z nich.
- APNs acceptance není user acknowledgement. Delivery stavy se nesmějí sloučit.

## Relay production gate

Relay je mimo MVP a production flags jsou off. Transportní šifrování není E2E
ochrana přes nedůvěryhodné hops. Před citlivým payloadem jsou povinné: threat
model, pseudonymní device identity, trust anchor, key provisioning,
rotation/revocation/recovery, E2E encryption, replay/clock-skew ochrana, byte
quota, bezpečné mazání a cross-platform physical tests.

Legacy relay prototyp se nekopíruje jako production contract. Zejména se znovu
navrhne ochrana mutable hop metadata, durable custody/ACK a queue policy.

## Logging, audit and diagnostics

Zakázané hodnoty: přesná poloha, raw sensor sample, obsah/popis souboru, chat či
report text, cookie, bearer/refresh/APNs token, crypto key a raw peer/user/device
ID. Release loguje pouze stabilní operation/method, outcome/error code, duration,
contract/app version a náhodný correlation ID.

Audit musí zachytit bez payloadu: permission změnu, start/stop trackingu,
asset claim/delete, remote registration/revoke, cache clear, config/policy
změnu a security rejection. Lokální audit je bounded; serverové doménové audity
zůstávají v COP/CSM.

## Threats covered

- XSS/compromised dependency, malicious iframe a origin confusion;
- redirect/session fixation, request replay, flood a oversized/malformed JSON;
- path traversal, malicious file/MIME, storage exhaustion a attachment bomb;
- token/log leakage, debug bridge nebo ATS výjimka v release;
- záměna webové a nativní OIDC session, cross-user Matrix cache, neúplný logout,
  recovery-key leakage a podvržený native OIDC callback;
- podvržený call presentation state, PushKit misuse, SDP/ICE leakage do bridge a
  neukončený proximity/audio lifecycle;
- stale/revoked permission, lost/stolen/jailbroken device a cross-user cache;
- malicious relay peer, spoofing, replay, Sybil, traffic analysis a queue DoS.

Jailbreak detekce může být diagnostický/policy signál, ne jediná bezpečnostní
hranice. Rooted/jailbroken zařízení se řeší podle COP/MDM policy fail-closed pro
citlivé capability.

## CI and release gates

- gitleaks a stack-appropriate dependency/SDK scan;
- contract fixtures, bridge negative/fuzz tests a log-redaction tests;
- artifact review entitlements, Info.plist, ATS, App-Bound Domains, privacy
  manifest, debug flags, `CSMCommunicationKit`/Matrix embedded frameworks,
  package pin a deployment target iOS 26;
- fyzické native OIDC, E2EE chat, offline outbox, call/proximity/audio,
  permission, tracking, APNs, Share Extension a offline testy;
- otevřený security/privacy blocker vypne capability nebo blokuje release.

Security nález se nesmí skrýt mockem ani feature flagem bez bezpečného runtime
fallbacku a jasného vlastníka v `open-questions.md`.
