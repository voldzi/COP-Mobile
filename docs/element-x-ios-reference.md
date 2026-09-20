# Element X iOS jako referenční implementace

- Datum ověření: 2026-09-20
- Referenční větev: `develop`
- Rozhodnutí: převzít všechny prokazatelně lepší a produktově relevantní vzory,
  ale nekopírovat AGPL aplikační zdroje ani UI.

## Proč je relevantní

Element X iOS je aktivně vyvíjený SwiftUI klient nad stejným Matrix Rust SDK,
které používá `CSMCommunicationKit`. Je vhodným upstream vzorem pro lifecycle
relace, timeline, média, notifikace, obnovu šifrování, přístupnost a testování.

COP Mobile a Jizda zůstávají vlastní produkty. Používají vlastní OIDC, CSM
bootstrap, omezenou komunikační doménu a serverem řízené přímé hovory. Element X
proto není drop-in knihovna ani náhrada těchto hranic.

## Licenční hranice

- `element-x-ios` je AGPL-3.0 nebo komerčně licencovaný.
- Aplikační obrazovky, služby a Compound komponenty se nekopírují bez
  samostatného licenčního rozhodnutí.
- `matrix-rust-components-swift` je samostatný Apache-2.0 distribuční balíček a
  zůstává schváleným bodem opětovného použití.
- Všechny níže uvedené změny jsou vlastní implementace podle veřejně
  pozorovaného produktového a architektonického vzoru.

Zdroje:

- https://github.com/element-hq/element-x-ios
- https://github.com/element-hq/element-x-ios/blob/develop/LICENSE
- https://github.com/element-hq/matrix-rust-components-swift

## Převzaté lepší vzory

| Vzor Element X | Výsledek v COP Mobile |
| --- | --- |
| Matrix Rust přes samostatný Swift package | Přesně připnuto na `26.09.17` |
| FFI izolované za aplikační gateway | `MatrixRustSDK` importuje jediný soubor; SwiftUI používá CSM typy a úzké služby |
| Bounded a deterministická timeline | Okno 500 položek, stránkování a jediná redukční cesta |
| Stabilní offline outbox | Persistovaný šifrovaný outbox, stabilní transaction ID a deduplikace |
| Recovery a session stavy | Samostatné stavy obnovy, zamknutí, nesouladu účtu a nedostupnosti |
| Samostatný Notification Service Extension | Přidán target `COPMobileNotificationService` |
| Malé extension jádro bez plného Matrix SDK | Přidán produkt `CSMNotificationCore` pouze nad Foundation/CryptoKit |
| Privacy-safe notifikace | Serverový title/body, přílohy a neznámá metadata se zahazují; zůstane obecný lokalizovaný text a opaque thread ID |
| Samostatný accessibility test target | Přidán `COPMobileAccessibilityTests` a scheme `COPMobile-Accessibility` |
| Automatizovaný audit hlavních stavů | Kontroluje kontrast, Dynamic Type, hit region, popisy, ořez textu a traits |
| Oddělené unit/UI/accessibility testy | Zapojeno do `scripts/check.sh` |
| Výkonové brány dlouhé timeline | Existující testy pokrývají 1/100/1 000/10 000 zpráv |
| Vlastní design systém | Zachován CSM design systém; audit opravil kontrast a škálování stavových obrazovek a řádků |

Upgrade Matrix Rust z `26.09.07` na `26.09.17` prošel balíčkovými testy a byl
ověřen buildem obou hostů. Reakce byly přizpůsobeny aktuálnímu SDK kontraktu.

## Co už naše doména řeší lépe nebo stejně

- COP OIDC a account-binding jsou omezenější než obecná volba homeserveru.
- Hovory používají autoritativní COP API, LiveKit, CallKit a PushKit pouze pro
  skutečný VoIP hovor.
- Explicitní sdílení polohy a krizové workflow zůstávají pod CSM policy.
- Média, composer, odpovědi, editace, reakce, náhledy a recovery už mají vlastní
  implementaci přizpůsobenou krizové komunikaci a retenčním pravidlům.

## Záměrně nepřevzaté části

- celý Element X repozitář, root coordinators, branding, telemetry a onboarding;
- Compound UI zdroje nebo kopie obrazovek bez vyřešené licence;
- Matrix call signaling, které by obešlo COP API a současný LiveKit/CallKit tok;
- Service Locator nebo velký globální dependency bag;
- Share Extension bez dokončeného autoritativního COP Device API pro opaque
  asset handoff. Mrtvá nebo obcházející upload cesta by zhoršila bezpečnost;
- dešifrování E2EE obsahu v notification extension před schválením App Group,
  Keychain access group, provisioningu a locked-device testu. Současná obecná
  notifikace je bezpečný produkční fallback.

## Release gate pro notifikace

Server musí posílat metadata-only APNs payload s `mutable-content: 1`, platnou
expirací a allowlisted kategorií. Podepsaný artifact musí obsahovat extension a
správný APNs topic. Na fyzickém zařízení se ověří foreground, background,
ukončená aplikace, zamčené zařízení, timeout extension, tap/deep link a stav bez
sítě. Do splnění shared-crypto gate se nikde neslibuje náhled E2EE plaintextu.

## Pravidlo průběžného upstream auditu

Při každém plánovaném Matrix Rust upgrade:

1. porovnat verzi se skutečně resolvovanou verzí referenční aplikace a upstream
   Swift package;
2. projít release notes a otevřené iOS/Xcode regresní issue;
3. připnout přesnou verzi a revision v `Package.resolved`;
4. spustit unit, UI a accessibility testy i Debug/Release build COP Mobile a
   Jizdy;
5. na zařízení otestovat login, sync, E2EE recovery, offline outbox, přílohu a
   APNs/NSE lifecycle.


## Hlasové a videohovory v Element X

Aktuální větev `develop` rozlišuje `CallIntent.audio` a `CallIntent.video`.
Přímá konverzace nabízí samostatné tlačítko hlasu a videa; intent se propisuje
do `CXStartCallAction.isVideo` a `CXCallUpdate.hasVideo`. `CXProvider` deklaruje
podporu videa. Moderní nativní větev používá MatrixRTC transport a nativní media
stack, zatímco starší větev řídí vložený Element Call widget. WebView hovor se
záměrně nepřihlašuje CallKitu, protože systémový audio port musí vlastnit proces,
který skutečně vlastní média.

Referenční zdroje:

- https://github.com/element-hq/element-x-ios/blob/develop/ElementX/Sources/Other/CallIntent.swift
- https://github.com/element-hq/element-x-ios/blob/develop/ElementX/Sources/Services/ElementCall/ElementCallService.swift
- https://github.com/element-hq/element-x-ios/blob/develop/ElementX/Sources/Services/ElementCall/ElementCallWidgetDriver.swift
- https://github.com/element-hq/element-x-ios/blob/develop/ElementX/Sources/Screens/RoomScreen/View/RoomCallControlsToolbar.swift

COP přebírá oddělení audio/video intentu, CallKit pravdivost a jednoho vlastníka
médií. Nepřebírá MatrixRTC signalizaci ani widget, protože COP API je autorita
stavu a LiveKit je schválený media transport. Současný kontrakt
`cop-voice-call-v1` je pouze hlasový; UI proto nesmí nabízet kameru ani nastavit
`hasVideo`, dokud serverový kontrakt, oprávnění, webový klient a testy nepodporují
video jako jednu kompatibilní funkci.
