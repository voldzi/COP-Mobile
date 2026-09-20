# ADR 0013: Adopt licenčně bezpečné hardening vzory z Element X

- Status: Accepted
- Datum: 2026-09-20

## Kontext

Element X iOS je vyzrálý SwiftUI klient nad stejným Matrix Rust SDK. Jeho
aplikační repozitář je AGPL-3.0 nebo komerčně licencovaný, takže COP Mobile
nesmí kopírovat aplikační zdroje, obrazovky ani Compound komponenty bez
samostatného licenčního rozhodnutí. Architektonické principy, testovací členění
a samostatný Apache-2.0 Matrix distribuční balíček lze použít bezpečně.

## Rozhodnutí

- Zachovat jediný import Matrix Rust SDK v aplikační gateway a vlastní CSM typy
  směrem do SwiftUI.
- Přidat malý `CSMNotificationCore` bez Matrix a UI závislostí. Je jediným
  zdrojem pravidel pro redigovanou prezentaci metadata-only APNs payloadu.
- Přidat Notification Service Extension. Rozšíření nepřijímá serverový title ani
  body, odstraňuje neznámá metadata, vytváří opaque thread ID a při timeoutu
  vrací stejný bezpečný obecný obsah.
- E2EE plaintext se do APNs nepřidává. Pozdější dešifrování v extension vyžaduje
  schválený App Group, Keychain access group, provisioning a fyzický device test.
- Přidat samostatný accessibility test target s automatickým Xcode auditem
  hlavních stavů komunikace a spouštět jej v úplné lokální kontrole.
- Session recovery, bounded timeline, offline outbox a výkonové testy zůstávají
  vlastní implementací, protože už naplňují stejné produktové principy.

## Důsledky

- NSE zlepší soukromí a konzistenci notifikací i bez přístupu ke kryptografickému
  store; nezobrazuje obsah zprávy na zamčeném zařízení.
- CSM notification policy lze testovat bez spuštění hostitelské aplikace a bez
  linkování Matrix Rust SDK.
- Každá změna klíčového komunikačního UI musí projít accessibility targetem.
- Share Extension se nepřidává bez dokončení autoritativního COP Device API pro
  opaque asset handoff; jinak by vznikla nepoužitelná nebo obcházející cesta.
- Push dešifrování, App Group a sdílený Keychain zůstávají samostatným release
  gate, protože simulátor nemůže doložit provisioning ani locked-device chování.
