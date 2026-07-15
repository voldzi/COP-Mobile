# Runbook

## Použití

Fáze 2 má spustitelný feasibility host a níže uvedené WebView/bridge kroky jsou
aktuální. Senzory, tracking, Share Extension a push části zůstávají budoucím
runbookem. Nikdy nemažte WebKit/Matrix nebo native data jako první diagnostický
krok.

## iOS build nebo test selže

1. Spusťte `python3 scripts/validate-device-contract.py` a
   `python3 scripts/validate-ios-project.py`.
2. Vygenerujte projekt znovu přes `cd apps/ios && xcodegen generate`; ruční
   změny `.xcodeproj` nejsou zdroj pravdy.
3. Spusťte `bash scripts/test-ios.sh`. Skript vybere dostupný iOS 26 iPhone
   simulátor nebo respektuje `COP_IOS_SIMULATOR_ID`.
4. Pro release/CI spusťte `bash scripts/verify-apple-toolchain.sh`. Musí projít
   pouze schválený Xcode 27.0 beta build a iOS SDK 27.0; změna pinu vyžaduje
   vědomou aktualizaci ADR 0007 a ověřovacích důkazů.
5. Zkontrolujte `docs/implementation-report-phase-2.md` a nerozšiřujte
   simulátorový výsledek na fyzický, OIDC nebo offline důkaz.
6. Pro instalaci na fyzické zařízení musí být zařízení odemčené, spárované,
   dostupné v `xcrun devicectl list devices` a musí mít zapnutý Developer Mode.
   Tento režim vyžaduje potvrzení a restart přímo na zařízení; neobcházejte jej.

## Skeleton validation selže

1. Spusťte `bash scripts/validate-skeleton.sh` z kořene repozitáře.
2. Doplňte pouze chybějící autoritativní dokument nebo opravte hlášený nesoulad
   `AGENTS.md`/`CLAUDE.md` či iOS minimum.
3. Ověřte `git diff --check` a že nebyl přidán `openapi/openapi.json`; aplikace
   neposkytuje REST API.
4. Po dokumentační změně reindexujte Chroma.

## Self-hosted iOS CI zůstane ve frontě

1. V `~/actions-runner-cop-mobile` spusťte `./svc.sh status`; služba má být
   `Started` a GitHub runner `online` s labelem `xcode-27-beta`.
2. Zkontrolujte nejnovější `~/actions-runner-cop-mobile/_diag/Runner_*.log` bez
   kopírování credential nebo request payloadů do issue.
3. Ověřte odchozí HTTPS pro `pipelines*.actions.githubusercontent.com`,
   `broker.actions.githubusercontent.com` a přidělený
   `run-actions-*.actions.githubusercontent.com` endpoint.
4. Self-hosted job checkoutuje přesný `$GITHUB_SHA` přes SSH; ověřte proto také
   `ssh -T git@github.com`. Nepřepisujte checkout na pull request head z
   nedůvěryhodného forku.
5. Lokální runner `.env` používá HTTP/1.1 kompatibilní režim. Neměňte VPN,
   firewall ani segmentaci jako automatický workaround; síťovou změnu musí
   schválit vlastník infrastruktury.
6. Pull request z veřejného forku se na self-hosted runneru nesmí spustit.

## Aplikace se nespustí nebo zůstane prázdná

1. Zaznamenejte app build, iOS build, web build, environment a correlation ID.
2. Rozlište native crash, loading timeout, WebView navigation error a
   `OFFLINE_FALLBACK`; blank screen bez timeoutu je chyba.
3. Ověřte network path a samostatně HTTPS reachability COP originu.
4. Zkontrolujte TLS/ATS chybu, povolený origin a zda release neobsahuje debug
   konfiguraci.
5. Nabídněte Retry. Cache nemažte, dokud není potvrzené poškození a uživatel
   neodsouhlasí E2EE/offline dopad.
6. Pokud jde o regresi web release, rollbackujte COP web; pokud native build,
   vypněte dotčenou capability a stáhněte build z distribuce.

## Bridge hlásí BLOCKED nebo nekompatibilní protokol

1. Porovnejte app/contract/web build a stabilní error code.
2. Ověřte přesný main-frame scheme, host a port; OIDC/iframe bridge mít nemá.
3. Potvrďte, že web poslal `bridge.hello` a existuje společná podporovaná verze.
4. Nezapínejte wildcard ani debug origin jako workaround.
5. Obnovte kompatibilní web release nebo host build; stará session se nesmí
   znovu aktivovat bez handshake.

## OIDC login nebo refresh nefunguje

1. Ověřte Keycloak dostupnost, callback URL, cookies/WebKit persistent store a
   App-Bound Domains na fyzickém zařízení.
2. Potvrďte, že bridge zůstal na OIDC originu vypnutý a native nekopíruje token.
3. Offline stav nesmí posílat expirovaný token do API; zachová jen povolený
   cached read-only stav.
4. Neřešte problém druhým nativním loginem. Eskalujte OQ-002 a případný
   `ASWebAuthenticationSession` návrh samostatným ADR.

## Cached offline start selže

1. Určete, zda jde o fresh install, dříve warmed cache, storage eviction nebo
   nekompatibilní web asset.
2. V fresh install zobrazte lokální fallback — očekávaný stav, ne incident.
3. U warmed cache ověřte service worker/cache warmup, potřebné chat assets a
   poslední úspěšný web build.
4. Zopakujte process kill + airplane mode na stejném fyzickém zařízení.
5. Cache clear je poslední explicitní krok; po něm je aplikace offline pouze ve
   fallbacku a Matrix recovery může vyžadovat zásah uživatele.

## Tracking nepokračuje nebo nejde zastavit

1. Zobrazte native tracking state nezávisle na WebView a ověřte, že session
   skutečně vznikla explicitním Start ve foregroundu.
2. Zkontrolujte Location Services, When In Use/reduced stav, background mode,
   Low Power, system restriction a případný force-quit.
3. Při revoke/error session bezpečně ukončete; nesnažte se obcházet iOS pomocí
   audia nebo jiného background mode.
4. Stop musí zůstat dostupný i při nefunkčním webu. Pokud ne, capability se
   vypne a release je blokovaný.
5. Exportujte pouze state/error/timing; nikdy trasu nebo souřadnice.

## Share Extension položka chybí nebo je zaseknutá

1. Ověřte shodný App Group entitlement hostu a extension v podepsaném artifactu.
2. Zkontrolujte UTType, skutečnou velikost, quota, volné místo a Data Protection
   při zamčeném zařízení.
3. Nepracujte s domnělou filesystem cestou z provideru; extension musí bezpečně
   dokončit kopii a atomický manifest.
4. Pending asset nemažte při dočasně nedostupném webu. Claim/expiry/clear jsou
   samostatné stavy.
5. Poškozený nebo oversized obsah odmítněte se stabilním kódem, bez parsování či
   uploadu.

## Push nedorazí nebo není slyšitelný

1. Rozlište device registration, CSM Messaging intake, APNs acceptance,
   systémovou prezentaci, tap/open a user ACK.
2. Ověřte notification permission, sound setting, Time Sensitive setting,
   Focus/mute/Scheduled Summary, token environment/topic a expiraci payloadu.
3. Potvrďte, že CSM Messaging používá live konfiguraci a odpovídající
   sandbox/production APNs environment.
4. Debug/development token posílejte pouze přes sandbox; TestFlight/Release
   production token pouze přes production endpoint. Aktuální server neumí obě
   prostředí současně. Při cutoveru deaktivujte registrace z předchozího
   prostředí a znovu ověřte počet iOS zařízení.
5. Neoznačujte Time Sensitive jako guaranteed audible. Critical testujte pouze
   se skutečným entitlementem; CallKit/PushKit nepoužívejte pro výstrahu.
6. Při kritické provozní potřebě aktivujte schválený redundantní serverový kanál.

## Device registration ticket selže

1. Ověřte expiraci, audience, subject/app-instance binding a jednorázový `jti`.
2. Ticket ani APNs token nelogujte; používejte pouze correlation ID.
3. Replay musí být odmítnut, ale nesmí zrušit dříve platnou registraci.
4. Dokud COP/CSM kontrakt nefunguje, capability zůstane
   `temporarilyUnavailable`; nevracejte se k persistentnímu web bearer tokenu.

## Storage je plné nebo data nelze dešifrovat

1. Změřte pouze counts/bytes/age buckets pro tracking a share stores.
2. Nejprve odstraňte bezpečně expirované položky podle policy; neodeslaná data
   nemažte potichu.
3. Keychain/file protection chybu neřešte vytvořením nového klíče nad starými
   ciphertexty. Store označte blocked a nabídněte explicitní clear/recovery.
4. WebKit/Matrix a native stores jsou oddělené; globální mazání vyžaduje
   potvrzení a dokumentovaný dopad.

## COP zůstane na „Načítám COP“

1. Ověřte veřejný HTTPS origin a zachyťte `WKNavigationDelegate` přechody.
   Commit bez `didFinish`, při kterém nereaguje ani JavaScript, značí poškozený
   persistentní WebKit runtime, ne automaticky výpadek COP API.
2. Ověřte, že host používá vlastní pojmenovaný persistentní data store a že COP
   web při přítomnosti native transportu neregistruje browser service worker.
   Start aplikace nesmí čekat na `removeData` completion handler WebKitu.
3. Host po osmi sekundách jednou zopakuje navigaci bez cache. Cookies, Local
   Storage, IndexedDB, webovou OIDC relaci ani nativní Matrix store automaticky
   nemažte; globální odinstalace není standardní opravou.
4. Pokud se ani opakovaná navigace nedokončí, zobrazte lokální fallback s opakováním
   a diagnostickým kódem a pokračujte kontrolou TLS, origin policy a web buildu.

## Relay je aktivní v release nebo přijímá citlivý payload

1. Jde o security incident: okamžitě aktivujte serverový kill switch a zastavte
   distribuci buildu.
2. Zachovejte redigovanou verzi/config/flag evidence, ne peer nebo payload data.
3. Ověřte `COP_NEARBY_RELAY_ENABLED=false` a
   `COP_RELAY_SENSITIVE_PAYLOADS_ENABLED=false` v release artifactu.
4. Neobnovujte relay bez threat-model, procurement, identity/E2E a physical
   interoperability gate.

## Rollback po vadném release

1. Určete, zda regresi přinesl web, native app, Device contract nebo backend.
2. Web vraťte na kompatibilní release; native capability vypněte server policy.
3. Vadný TestFlight/App Store build odstraňte z distribuce a vydejte opravený
   build s vyšším build number — neslibujte vzdálený downgrade instalace.
4. Nemigrujte ani nemažte lokální data během nouzového rollbacku bez testovaného
   plánu.
5. Po opravě zopakujte real-device scénář a zapište app/web/backend buildy.

## Eskalace

- COP web/API a Device schema: vlastník `01 COP`.
- Keycloak/OIDC: IAM správce.
- APNs/device delivery: CSM Messaging + Apple account holder.
- signing/TestFlight/entitlements: Apple Developer/App Store správce.
- privacy/retence/Critical/relay: produkt + security/privacy owner.

Konkrétní kontaktní osoby nejsou v repozitáři a nesmějí být vymyšleny; doplní
se před prvním pilotním release podle provozního on-call procesu.
