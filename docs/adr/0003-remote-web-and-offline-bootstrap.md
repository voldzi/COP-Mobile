# ADR 0003: Remote HTTPS web and offline bootstrap

## Status

Accepted — 2026-07-11

## Context

COP web a chat už používají společný produkční HTTPS origin, service worker,
content-hashované Vite assety, IndexedDB a OIDC origin storage. Zabalit celý web
do aplikace by změnilo origin, CORS, OIDC redirecty, service-worker lifecycle a
rychlost vydávání webových oprav. Pouhé `load(URLRequest)` ale na čerstvé
offline instalaci může skončit prázdnou WebView a WebKit cache není absolutní
garance trvalého uložení.

## Decision

- Hlavní UI se v první iOS verzi načítá z přesného release originu
  `https://cop.zeleznalady.cz` v persistentním `WKWebsiteDataStore.default()`.
- Produkční host nepoužívá `file://`, libovolný custom scheme ani lokální HTTP
  server jako hlavní autentizovaný origin.
- Service worker a IndexedDB zůstávají webovým mechanismem pro cached shell,
  COP snapshot, chat/crypto state a budoucí doménový outbox. Nativní host tuto
  storage neinterpretuje ani nekopíruje.
- Při startu host rozlišuje `ONLINE`, `DEGRADED`, `OFFLINE_CACHED`,
  `OFFLINE_FALLBACK`, `BLOCKED` a `UPDATING` podle pravdivých signálů WebKit,
  bridge kompatibility a backend reachability.
- Čerstvá instalace bez použitelného shellu zobrazí lokální SwiftUI fallback se
  stavem sítě, vysvětlením, retry a diagnostickým ID. Fallback nemá Device bridge
  ani vlastní report/chat/map workflow.
- Po prvním online načtení se podporovaný offline start prohlašuje pouze tehdy,
  když fyzický iOS 26 test prokáže načtení shellu po process kill, restartu,
  airplane mode a update web release.
- Pokud storage-pressure a cold-start testy nedají požadovanou garanci, celý
  verzovaný COP web artifact lze přidat až novým ADR. Musí jít o stejný webový
  build, nikoli nativní kopii business UI, a předem se vyřeší origin, OIDC,
  CSP/CORS, chat assets a update/rollback.

## Web release compatibility

- Host a web nejprve vyjednají Device API verzi. Nekompatibilní web zobrazí
  řízený `BLOCKED` stav a bridge zůstane vypnutý.
- Host necacheuje API response jako náhradu serverové autorizace. Policy-filtered
  doménový snapshot vlastní web.
- Release zachová nejméně jednu kompatibilní předchozí bridge major/minor řadu
  podle contract support policy, aby nasazení webu nerozbilo vydané aplikace.
- Fallback nikdy nemaže WebKit data automaticky. Vymazání cache je explicitní,
  potvrzená diagnostická akce s upozorněním na offline a E2EE dopad.

## Authentication and navigation

- Web vlastní OIDC relaci. Host nepřepisuje `localStorage`, IndexedDB ani
  cookies a neinjektuje access/refresh token.
- Keycloak může být navigačně povolen, ale bridge je na jeho originu vždy
  deaktivovaný. Externí obsah se otevírá mimo interní WebView.
- App-Bound Domains, redirecty, callback storage a chat/map subresources musí
  projít samostatným real-device spike před release.

## Consequences

### Positive

- Uživatel dostává stejný web a business chování jako browser bez čekání na
  App Store release.
- OIDC, Matrix E2EE storage, service worker a same-origin routování se nemusí v
  první fázi přestavovat.
- Fresh-install offline stav je použitelný a pravdivý i bez duplikace workflow.

### Negative

- Offline shell po prvním načtení závisí na chování a kapacitě WebKit storage.
- Nezávislý web release musí dodržet bridge kompatibilitu.
- Garantovaný offline zápis hlášení vyžaduje webový outbox; lokální fallback jej
  nenahrazuje.

## Security and Privacy Impact

Persistentní WebKit store obsahuje auth a E2EE data, proto nesmí být sdílen s
nepovoleným originem, logován ani automaticky exportován. Native fallback nemá
přístup k WebKit tokenům ani bridge capability. Vymazání dat musí být
subject-aware a respektovat dopad na Matrix recovery.

## Validation

- fresh install online/offline;
- první online warm-up, process kill a airplane-mode cold start;
- restart zařízení, storage pressure, low-data mode a pomalá síť;
- deployment nového webu, chybějící lazy chunk a kompatibilní/nekompatibilní
  bridge verze;
- OIDC login/refresh/logout, callback a externí link na fyzickém iOS 26;
- chat, map assets, IndexedDB a service worker po background/foreground;
- žádná blank screen ani nekonečný spinner bez lokálního únikového stavu.
