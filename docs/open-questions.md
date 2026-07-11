# Otevřené otázky a externí brány

Fáze 0 nemá otevřený blocker. Následující položky musí být uzavřeny před
uvedeným milníkem; do té doby platí bezpečný fallback.

## OQ-001: Staging a debug originy

- Stav: otevřeno
- Vlastník: COP provoz
- Dopad: release/debug allowlist, App-Bound Domains, integrační testy
- Rozhodnutí potřebné do: zahájení iOS feasibility hostu
- Bezpečný fallback: release povolí pouze `https://cop.zeleznalady.cz`; lokální
  origin existuje jen v explicitním debug buildu.

## OQ-002: OIDC, WebAuthn a App-Bound Domains ve WebView

- Stav: vyžaduje real-device spike
- Vlastník: COP + IAM/Keycloak
- Dopad: login, callback, refresh, případné budoucí step-up/WebAuthn
- Rozhodnutí potřebné do: ukončení fáze 2
- Bezpečný fallback: web vlastní OIDC; bridge je na login originu vypnutý. Pokud
  embedded flow neprojde, release se zablokuje a navrhne se samostatný
  `ASWebAuthenticationSession` handoff ADR, nikoli druhé trvalé přihlášení.

## OQ-003: Jednorázový APNs registration ticket

- Stav: kontrakt není implementovaný
- Vlastník: COP API + CSM Messaging
- Dopad: native registrace APNs bez kopírování webového refresh tokenu
- Rozhodnutí potřebné do: fáze 3 / remote push
- Bezpečný fallback: capability remote push je `temporarilyUnavailable`; APNs
  token se neposílá do JavaScriptu ani COP device store.

## OQ-004: Bundle ID, signing a nástupnictví staré aplikace

- Stav: doporučený default `cz.zeleznalady.csm.messenger`, čeká signing audit
- Vlastník: Apple Developer/App Store správce
- Dopad: APNs topic, AASA, `csm://` deep links, instalace vedle legacy aplikace
- Rozhodnutí potřebné do: vytvoření podepsaného app targetu
- Bezpečný fallback: nevytvářet nový App ID ani provisioning profil; dokumenty
  předpokládají kompatibilní náhradu, nikoli paralelní produkční aplikaci.

## OQ-005: Critical Alerts entitlement

- Stav: externí schválení Apple není uděleno
- Vlastník: produkt + Apple account holder
- Dopad: zvuk při mute/Focus pro schválené kritické události
- Rozhodnutí potřebné do: až po Time Sensitive MVP, před critical release
- Bezpečný fallback: ordinary/Time Sensitive pouze; capability i copy o
  Critical Alerts jsou vypnuté.

## OQ-006: Tracking účel, retence a serverová synchronizace

- Stav: produktově/právně neuzavřeno
- Vlastník: produkt, security, privacy/legal
- Dopad: retention, Data Protection, consent, případný background upload
- Rozhodnutí potřebné do: fáze 4
- Bezpečný fallback: bounded lokální session, bez background server uploadu,
  explicitní Start/Stop a uživatelské smazání.

## OQ-007: Typy, kvóty a retence sdílených souborů

- Stav: vyžaduje datovou klasifikaci a backend limity
- Vlastník: COP reports/media + security
- Dopad: Share Extension activation rule, App Group quota, upload
- Rozhodnutí potřebné do: Share Extension implementace
- Bezpečný fallback: pouze explicitně allowlisted obrázky a PDF, konzervativní
  byte limit, krátká TTL a žádný automatický upload.

## OQ-008: Webový offline report outbox a idempotence

- Stav: chybí v aktuálním COP PWA
- Vlastník: COP web/API
- Dopad: zapisovatelný offline režim a pravdivý reconnect sync
- Rozhodnutí potřebné do: fáze 5
- Bezpečný fallback: offline COP je read-only; native fallback nevytváří vlastní
  report workflow.

## OQ-009: Testovací zařízení a účty

- Stav: inventář nepotvrzen
- Vlastník: QA/provoz
- Dopad: real-device release gate
- Rozhodnutí potřebné do: první podepsaný TestFlight build
- Bezpečný fallback: simulátorové výsledky se označí pouze jako dílčí; release
  bez dvou iPhonů a relevantního iPadu nevznikne.

## OQ-010: Veřejný App Store, Custom App nebo MDM

- Stav: TestFlight-first je schválený, finální distribuce není určena
- Vlastník: produkt/procurement
- Dopad: review, managed config, privacy a rollout/rollback
- Rozhodnutí potřebné do: produkční pilot po TestFlight
- Bezpečný fallback: interní TestFlight bez tvrzení o veřejné dostupnosti.

## OQ-011: Google Nearby Connections

- Stav: mimo MVP; privacy/procurement nerozhodnuto
- Vlastník: security/privacy/procurement
- Dopad: cross-platform relay POC a SDK telemetry
- Rozhodnutí potřebné do: relay laboratoř
- Bezpečný fallback: pouze mock transport; žádný Google SDK v production targetu.

## OQ-012: Relay identita a end-to-end key lifecycle

- Stav: neexistuje schválený návrh
- Vlastník: security architecture
- Dopad: citlivé store-and-forward payloady, revokace a recovery
- Rozhodnutí potřebné do: jakýkoli relay mimo testovací opaque data
- Bezpečný fallback: sensitive payloads zakázané; relay production flag off.

## OQ-013: WebKit cached-start důkaz

- Stav: unit testy PWA prošly, fyzický WKWebView test neproběhl
- Vlastník: iOS implementace + QA
- Dopad: tvrzení o offline startu po prvním online spuštění
- Rozhodnutí potřebné do: ukončení fáze 2
- Bezpečný fallback: lokální technický fallback. Celý web artifact se začne
  balit pouze po novém ADR, pokud cache nedá požadovanou spolehlivost.

## OQ-014: Skutečný VoIP požadavek

- Stav: běžný webový hovor existuje, native CallKit/PushKit scope není schválen
- Vlastník: produkt + messaging
- Dopad: telefonní incoming-call UX při background/terminated stavu
- Rozhodnutí potřebné do: samostatná post-MVP VoIP feasibility fáze
- Bezpečný fallback: standardní call notification otevře web; PushKit/CallKit
  se nepoužije jako alarmový workaround.
