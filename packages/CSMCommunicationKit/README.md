# CSMCommunicationKit

Tento adresář je zdroj pravdy pro znovupoužitelnou nativní komunikační vrstvu.
Balíček vlastní repozitář COP Mobile; přímo jej sestavuje COP Mobile a přes
lokální Swift Package referenci také Jizda. Žádný host nemá build ani runtime
závislost na původní velké iOS aplikaci `04 CSM messenger`.

## Původ a hranice

- výchozí auditovaný snapshot: commit
  `7fc3d3004c30865235f6cd6c075c6a764369b5a0`;
- každý host má vlastní bundle, sandbox a výchozí Keychain access group;
- veřejný OIDC klient `csm-mobile` a callback `csm://oauth/callback` jsou sdílené
  přes izolovanou `ASWebAuthenticationSession`;
- `Package.swift` explicitně kompiluje nativní chat, OIDC/PKCE, Keychain,
  Matrix Rust E2EE, timeline, outbox, přílohy a komunikační notifikace;
- původní mapové, reportovací, relay, watch a aplikační SwiftUI obrazovky nejsou
  součástí balíčku ani výsledné aplikace.
- samostatný produkt `CSMNotificationCore` neodkazuje Matrix SDK ani UI a sdílí
  s Notification Service Extension pouze privacy-safe prezentační policy;
- `CSMVoiceCallKit` je jediná implementace CallKit, PushKit a LiveKit audia pro
  COP Mobile i Jízdu. Každý host má vlastní PushKit token a Keychain namespace.
- veřejný CarPlay adaptér vrací pouze omezené snapshoty konverzací a zpráv a
  bezpečné operace pro odeslání. Autentizace, Matrix endpointy, E2EE klíče a
  transport zůstávají uvnitř `CSMCommunicationRuntime`;
- všechny tři produkty balíčku jsou statické knihovny. Hlasové policy testy
  proto běží v testovacím targetu balíčku a hostované aplikační testy je
  nelinkují podruhé.

`CommunicationModel` vlastní pouze přihlášení, Matrix/E2EE, seznam konverzací,
otevřenou stránkovanou timeline, outbox, push a hovory. Původní víceúčelový
`AppModel` a zdroje mapy, field-readiness, relay runtime, radio plánování a
watch synchronizace byly odstraněny. Akce mimo komunikaci pouze vrátí
uživatele do webového COP hostu.

Call-control požadavky používají omezené opakování pouze pro explicitní stav
COP API `FST_UNDER_PRESSURE`. Jiné chyby 4xx/5xx se neopakují, takže se
stavový přechod hovoru nemůže nechtěně zdvojit. Matrix device ID obsahuje také
nesekretní identitu instalace uloženou v aplikačním kontejneru. Po reinstalaci
proto vznikne skutečně nové E2EE zařízení namísto opětovného použití serverové
identity, jejíž lokální kryptografické úložiště bylo smazáno.

## Údržba

Změny se provádějí a testují přímo zde. Aktualizace z historického projektu
není automatická: musí jít o vědomý diff konkrétních komunikačních souborů,
bez kopírování celé aplikace, a musí projít validátorem, sestavením i testy
COP Mobile. Do `apps/ios/project.yml` se nesmí vrátit cesta na sibling checkout
ani Git dependency původní aplikace.


## Hostitelské aplikace

- COP Mobile odkazuje balíček z `apps/ios/project.yml`.
- Jizda odkazuje stejný checkout z
  `../DELTA_ACR/06 COP Mobile/packages/CSMCommunicationKit`.
- Host předává pouze omezené callbacky pro polohu a navigaci do COP. Tokeny,
  Matrix přihlašovací údaje ani dešifrovaný obsah se přes hostitelské rozhraní
  nepředávají.
- Texty veřejného rozhraní musí zůstat neutrální vůči názvu hostitelské aplikace.
