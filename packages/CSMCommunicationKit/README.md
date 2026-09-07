# CSMCommunicationKit for COP Mobile

Tento adresář je lokální, aplikací COP Mobile vlastněná kopie komunikační vrstvy.
COP Mobile ji sestavuje přímo z tohoto repozitáře a nemá build ani runtime
závislost na původní velké iOS aplikaci `04 CSM messenger`.

## Původ a hranice

- výchozí auditovaný snapshot: commit
  `7fc3d3004c30865235f6cd6c075c6a764369b5a0`;
- hostitelský bundle ID zůstává záměrně
  `cz.zeleznalady.csm.messenger`;
- `Package.swift` explicitně kompiluje nativní chat, OIDC/PKCE, Keychain,
  Matrix Rust E2EE, timeline, outbox, přílohy a komunikační notifikace;
- původní mapové, reportovací, relay, watch a aplikační SwiftUI obrazovky nejsou
  součástí balíčku ani výsledné aplikace.

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
