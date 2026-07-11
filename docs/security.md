# Bezpečnostní baseline

## Stav a hranice

Repozitář je ve fázi 0 a neposkytuje backend. Dokument definuje povinné kontroly
budoucího iOS 26 hostu. Web COP je vzdálený, aktualizovatelný kód na privilegované
hranici; trusted origin proto není trusted payload.

Chráníme zejména:

- webovou OIDC/Matrix relaci a WebKit origin storage;
- nativní permissions a privileged Device API metody;
- přesnou polohu, heading/attitude a tracking samples;
- APNs token a device registration;
- fotografie, dokumenty, metadata a App Group inbox;
- signing/key material a budoucí relay queues;
- integritu bridge, deep linků a release konfigurace.

## Authentication and authorization

- Web COP zůstává vlastníkem OIDC Authorization Code + PKCE relace. Native host
  nečte WebKit token storage, nekopíruje refresh token do Keychain a nezavádí
  paralelní login.
- Bridge neposkytuje auth token API. Remote push čeká na jednorázový,
  krátkodobý COP→CSM registration ticket popsaný v `api.md`.
- Doménovou autorizaci mapy, chatu, hlášení a uploadu vždy provádí COP/CSM
  backend. Udělená systémová permission ji nenahrazuje.
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

## Secrets and signing

- Do Git se neukládají APNs `.p8`, provisioning profily, certificates,
  signing identity, service tokeny, OIDC client secret, access/refresh token,
  Matrix recovery key ani produkční managed config.
- Apple signing a APNs secrets vlastní App Store Connect/CI secret store a CSM
  Messaging. Aplikace obsahuje jen veřejnou konfiguraci nutnou pro client.
- Nativní technické klíče vznikají na zařízení a ukládají se v Keychain s
  vhodnou accessibility třídou; nikdy se nelogují ani neexportují diagnostikou.
- `.env.example` je pouze bezpečný vstup budoucích lokálních config skriptů;
  podepsaná aplikace nesmí číst repository `.env` za běhu.

## Protected local storage

- Web auth, Matrix a doménová cache zůstávají v persistentním WebKit data store
  na přesném originu. Native je neinterpretuje.
- Tracking samples, Share inbox a asset metadata používají encrypted/protected
  files, atomic writes, integrity hash, subject/app-instance scope, byte quota,
  TTL a explicitní cleanup.
- App Group je dostupný pouze hostu a Share Extension. Extension přijímá
  nedůvěryhodný `NSItemProvider`, kontroluje UTType, skutečnou velikost, quota a
  bezpečný název; absolutní cesta se nikdy nevrací webu.
- `NativeAssetRef` je náhodný opaque handle. Přístup je session/durable-scope
  bound, expirovatelný a auditovatelný bez obsahu.
- EXIF poloha se nepředává ani neuploaduje bez explicitního doménového consentu.
- Logout, změna subjectu a remote wipe policy nikdy nezpřístupní cache předchozího
  uživatele. Vymazání WebKit/Matrix dat musí upozornit na recovery dopad.

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
- PushKit/CallKit se nesmí použít pro safety alarm; je přípustný pouze pro
  skutečný VoIP hovor po samostatném ADR.
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
- stale/revoked permission, lost/stolen/jailbroken device a cross-user cache;
- malicious relay peer, spoofing, replay, Sybil, traffic analysis a queue DoS.

Jailbreak detekce může být diagnostický/policy signál, ne jediná bezpečnostní
hranice. Rooted/jailbroken zařízení se řeší podle COP/MDM policy fail-closed pro
citlivé capability.

## CI and release gates

- gitleaks a stack-appropriate dependency/SDK scan;
- contract fixtures, bridge negative/fuzz tests a log-redaction tests;
- artifact review entitlements, Info.plist, ATS, App-Bound Domains, privacy
  manifest, debug flags, embedded frameworks a deployment target iOS 26;
- fyzické permission, tracking, APNs, Share Extension a offline testy;
- otevřený security/privacy blocker vypne capability nebo blokuje release.

Security nález se nesmí skrýt mockem ani feature flagem bez bezpečného runtime
fallbacku a jasného vlastníka v `open-questions.md`.
