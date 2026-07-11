# Provoz a distribuce

## Současný stav

Repozitář je ve fázi 2 a má generovaný SwiftUI/Xcode target. Není zde produkční
deployment, signing material, Android target ani přijatý fyzický test. Lokální
kontrola je:

```bash
bash scripts/check.sh
```

`scripts/check.sh` validuje skeleton, připnutý kontrakt, iOS konfiguraci,
vygeneruje projekt a spustí testy na dostupném iOS 26 simulátoru. Podepsaný
archive ani upload zatím definován není.

## Prostředí a předpoklady

Aktuálně ověřeno na workstation:

- Node.js 24 a pnpm 10 jsou dostupné pro související COP práci;
- lokální Xcode je beta Xcode 27, a proto není schváleným production release
  baseline;
- Java/Android SDK/adb/Gradle nejsou nainstalované;
- XcodeGen 2.44.1 je dostupný;
- produkční COP origin je `https://cop.zeleznalady.cz`;
- minimum nového app targetu je iOS/iPadOS 26.0.

CI používá runner `macos-26`, explicitně vybírá stabilní Xcode 26.5 a před
buildem ověřuje Xcode/iOS SDK major, Swift 6 a
`IPHONEOS_DEPLOYMENT_TARGET=26.0`. Lokální Xcode 27 beta tímto gate správně
neprojde.

## Inicializace a lokální build

```bash
git status --short --branch
bash scripts/check.sh
"/Users/voldzi/Documents/Development/18 2026/chromadb/tools/chroma-dev.sh" reindex --root .
```

Reindex není build gate; slouží retrieval-first práci. Secret ani produkční
`.env` se při setupu nevytváří.

## Konfigurace

`.env.example` je vstup pouze pro budoucí lokální config-generation tooling.
Podepsaná aplikace jej nesmí číst za runtime. Veřejné hodnoty budou později
generovány do typed build configuration; secrets zůstávají v Keychain/CI/serveru.

| Název | Povinný | Bezpečný default | Účel |
| --- | --- | --- | --- |
| `COP_MOBILE_ENVIRONMENT` | ano | `development` | Výběr debug/staging/release veřejné konfigurace |
| `COP_IOS_BUNDLE_ID` | ano | `cz.zeleznalady.csm.messenger` | Kompatibilní App ID, APNs topic a deep-link identita; podléhá signing auditu |
| `COP_IOS_MINIMUM_VERSION` | ano | `26.0` | Závazný deployment target |
| `COP_WEB_ORIGIN` | ano | `https://cop.zeleznalady.cz` | Přesný hlavní release origin; ne wildcard |
| `COP_OIDC_ISSUER` | ano | `https://login.zeleznalady.cz/realms/cop` | Navigační OIDC origin, nikdy bridge origin |
| `COP_CSM_MESSAGING_BASE_URL` | ano pro push | `https://msg.zeleznalady.cz` | CSM Messaging device registry/delivery boundary |
| `COP_DEVICE_CONTRACT_VERSION` | ano po fázi 1 | `1.0.0` | Připnutý export autoritativního COP Device kontraktu |
| `COP_NATIVE_BRIDGE_ENABLED` | ano | `true` | Provozní gate nad bezpečnostními kontrolami, ne jejich náhrada |
| `COP_CRITICAL_ALERTS_ENABLED` | ano | `false` | Zůstává false bez Apple entitlementu a schválené policy |
| `COP_NEARBY_RELAY_ENABLED` | ano | `false` | Relay production gate |
| `COP_RELAY_SENSITIVE_PAYLOADS_ENABLED` | ano | `false` | Samostatný fail-closed content gate |

Release build selže při neznámém environmentu, HTTP originu, wildcardu,
debug hostu, iOS targetu pod/nad schválenou baseline bez ADR nebo při relay/
Critical flagu bez odpovídajícího entitlement/policy důkazu.

## Plánované build varianty

| Varianta | Účel | Bridge origin | Debugging | Distribuce |
| --- | --- | --- | --- | --- |
| Debug | Lokální vývoj a mock services | explicitní localhost/dev allowlist | povoleno | simulátor/podepsané dev zařízení |
| Staging | OIDC, APNs a integrační ověření | zatím otevřená OQ-001 | redigovaná diagnostika, Web Inspector podle interní policy | interní TestFlight |
| Release | Pilot/produkce | pouze `https://cop.zeleznalady.cz` | Web Inspector a debug originy vypnuté | TestFlight, později schválený store/MDM kanál |

Staging origin není možné vymyslet; do jeho schválení nevznikne staging release
allowlist.

## Budoucí CI a release flow

S prvními targety se doplní a v `AGENTS.md` přesně zopakují tyto kroky:

1. generace projektu z verzovaného XcodeGen manifestu;
2. ověření připnutého Device contract artifactu a shared fixtures;
3. Swift build, unit, integration a UI testy pro iOS 26;
4. lint/static analysis, secret a dependency/SDK scan;
5. skeleton, docs, privacy manifest, entitlement a release-config audit;
6. podepsaný archive a export pro interní TestFlight;
7. oddělený real-device test report před promotion stejného buildu.

Produkční app se nebuildí z `04 CSM messenger`. Tento projekt má vlastní signing
a release historii; legacy repo zůstává referencí.

## Rollout

1. Interní dev build pouze s `system.getCapabilities()` a lokálním fallbackem.
2. Interní TestFlight pro WebView/OIDC/offline/bridge feasibility.
3. Capability po capability: push, sensors/tracking, Share Extension.
4. Offline report až po webovém outboxu v COP.
5. Android a relay pouze v samostatných pozdějších programech.

Remote/server kill switches mohou capability vypnout, ale nesmějí povolit něco,
co build, entitlement, permission nebo security policy nepovoluje.

## Rollback

- App Store/TestFlight neumí spolehlivě vynutit downgrade již nainstalované
  aplikace. První ochrana je remote disable citlivé capability a kompatibilní
  server/web fallback.
- Vadný web release se rollbackuje v COP deploymentu se zachováním bridge
  compatibility window.
- Vadný native build se přestane distribuovat a vydá se opravený build s vyšším
  build number. Kritická capability se do té doby vypne server policy/flag.
- Rollback nesmí automaticky smazat WebKit/Matrix storage, tracking data nebo
  Share inbox. Migrace musí být forward/backward testovaná nebo fail-closed.
- Relay a sensitive payload flags zůstávají false i při rollbacku konfigurace.

## Lokální data, backup a recovery

- Repozitář nemá serverovou databázi ani backup.
- Native tracking/share stores budou excluded from backup podle klasifikace,
  protected a bounded. Serverový zdroj pravdy zůstává COP/CSM.
- WebKit/Matrix storage není zahrnuta do diagnostického exportu. Clear-data
  vyžaduje potvrzení a upozornění na offline/E2EE recovery dopad.
- Reinstalace není serverová revokace; device registry potřebuje explicitní
  expiry/revoke workflow.

## Provozní limity

- Přesná poloha, attitude a radio mají battery budget; výchozí frekvence se
  potvrdí měřením, ne odhadem.
- Share/asset a tracking stores mají explicitní byte quota, TTL a cleanup;
  konkrétní hodnoty jsou blokované OQ-006/OQ-007.
- Bridge baseline JSON limit je 64 KiB; binary data bridge nepřenáší.
- iOS background/force-quit a APNs delivery nejsou garantované.
- Relay není health dependency MVP a v release musí být vypnutý.

## Externí závislosti

- COP web/API a jeho OpenAPI/Device contracts;
- Keycloak/OIDC;
- CSM Messaging a APNs;
- Apple signing, entitlements a App Store Connect/TestFlight;
- fyzická iOS 26 zařízení pro release gate;
- později Google Nearby pouze po explicitním procurement/privacy rozhodnutí.

Výpadek závislosti se mapuje na pojmenovaný degraded stav; aplikace neoznačí
Wi-Fi jako důkaz dostupného COP backendu.
