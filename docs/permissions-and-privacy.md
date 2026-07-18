# Oprávnění a soukromí

## Účel a závazný baseline

Tento dokument je produktový a implementační kontrakt pro iOS 26. Nenahrazuje
právní posouzení ani App Store privacy declarations. Každé nové oprávnění,
entitlement, typ shromažďovaných dat nebo SDK třetí strany vyžaduje aktualizaci
tohoto dokumentu před začleněním do release buildu.

Závazné principy:

- CSM nežádá žádné chráněné oprávnění při prvním startu.
- Systémový dialog následuje až po konkrétní akci uživatele a stručném
  kontextovém vysvětlení účelu.
- Oprávnění se žádá v nejnižším rozsahu potřebném pro danou funkci.
- Odmítnutí se respektuje a neopakuje se v cyklu. Ostatní COP zůstane funkční.
- Web COP rozhoduje o business účelu; native vrstva pouze provede autorizovanou
  technickou operaci a vrátí capability/status.
- Systémové oprávnění není samo o sobě souhlas se serverovým zpracováním. Účel,
  právní titul, audit a odvolání doménového consentu vlastní COP.
- Přesná poloha, obsah hlášení, fotografie, dokumenty, auth tokeny a raw device
  identifikátory nesmějí do telemetry ani běžných release logů.
- Relay je mimo MVP. Jeho oprávnění a SDK se v produkčním targetu neaktivují,
  dokud neprojdou samostatným security, privacy a procurement gate.

Relevantní zdroje Applu: [protected resources](https://developer.apple.com/documentation/bundleresources/information_property_list/protected_resources),
[location authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services),
[background location](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background),
[App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups/)
a [Critical Alerts entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.usernotifications.critical-alerts).

## Permission UX

Každá permission cesta má stejný stavový model:

1. Web zjistí capability a aktuální stav bez vyvolání dialogu.
2. Uživatel spustí konkrétní funkci, například „Přidat aktuální polohu“.
3. Web zobrazí účel, rozsah, dopad na baterii/retenci a možnost pokračovat bez
   capability. Text musí odpovídat lokalizovanému system purpose stringu.
4. Bridge přijme `permissions.request` pouze z důvěryhodného main frame a po
   platném handshake.
5. Native vrstva vyvolá nejvýše jeden systémový dialog pro tento krok.
6. Výsledek vrátí jako `granted`, `denied`, `restricted`, `notDetermined` nebo
   detailnější capability stav. Web nesmí odhadovat stav z chyby.
7. Po odmítnutí se zobrazí funkční fallback. Odkaz do Nastavení se nabízí až po
   další explicitní akci, nikoli automaticky.
8. Změna oprávnění za běhu okamžitě ukončí dotčené subscription/session a vyšle
   `permission.changed` s redigovaným důvodem.

Permission pre-prompt nesmí tvrdit, že je oprávnění povinné pro COP jako celek,
pokud je povinné jen pro volitelnou funkci. Uživateli se nezobrazuje falešná
volba „později“, po které se systémový dialog otevře bez další akce.

## iOS 26 permission matrix pro MVP

Aktuální implementace zahrnuje pouze foreground When In Use slice pro polohu a
heading. Všechny tři konfigurace obsahují schválený
`NSLocationWhenInUseUsageDescription`; neobsahují Always klíč, location
background mode ani entitlement. Přesné souřadnice a heading jsou pouze v paměti
a předávají se platné bridge session, nikoli do nativních logů nebo telemetry.

APNs implementace znovu používá schválený topic
`cz.zeleznalady.csm.messenger`, vyžaduje explicitní zapnutí oznámení a registruje
aktuální device token přímo u CSM Messaging jednorázovým ticketem. Raw APNs
token ani samostatný PushKit VoIP token se nikdy neposílá do COP webu nebo COP
API. Background modes jsou omezeny na `audio`, `remote-notification` a `voip`;
`audio` je aktivní pouze během skutečné CallKit `.playAndRecord` session a
`voip` je podle ADR 0008 vyhrazen výhradně skutečnému Matrix hlasovému hovoru.

| Funkce | Deklarace / capability | Kdy se žádá | Chování při odmítnutí | Povinná pro core app |
| --- | --- | --- | --- | --- |
| Jednorázová poloha a heading | `NSLocationWhenInUseUsageDescription` | Po akci vyžadující polohu nebo kompas | Web pokračuje bez polohy; zobrazí stav a volitelný odkaz do Nastavení | Ne |
| Precise location | Stav `CLAccuracyAuthorization`; v MVP se nežádá dočasné zvýšení přes purpose key | Pouze se zjišťuje při location flow | Reduced Accuracy se pravdivě zobrazí; přesná funkce se označí jako omezená | Ne |
| Face ID / biometrické odemknutí | `NSFaceIDUsageDescription` + LocalAuthentication | Jen když serverová bezpečnostní politika vyžaduje místní odemknutí chráněných krizových dat | Obsah zůstane uzamčený; žádný biometrický údaj neopouští Secure Enclave/iOS | Podle policy |
| Aktivní background tracking | Background Modes: `location`; stále výchozí When In Use autorizace | Až po samostatném vysvětlení, explicitním Start a aktivaci background session ve foregroundu | Session se nespustí nebo se bezpečně ukončí; COP zůstane dostupný | Jen pro tracking |
| Always location | `NSLocationAlwaysAndWhenInUseUsageDescription` | **V MVP se nežádá** | Po force-quit se kontinuita negarantuje | Ne; změna vyžaduje nové schválení |
| 3D attitude ve foregroundu | `NSMotionUsageDescription` při použití Core Motion API | Při prvním zapnutí funkce natočení zařízení | Funkce vrátí denied/unsupported; heading a ostatní COP pokračují samostatně | Ne |
| Fotoaparát | `NSCameraUsageDescription` | Po volbě „Vyfotit“ | Nabídne systémový výběr existující fotografie/souboru nebo pokračování bez přílohy | Ne |
| Výběr fotografie | Systémový `PhotosPicker`/`PHPicker`; bez plošného přístupu do knihovny | Po volbě „Vybrat fotografii“ | Uživatel může picker zrušit bez změny oprávnění | Ne |
| Plný přístup do Photo Library | `NSPhotoLibraryUsageDescription` | **Mimo MVP**; picker jej nepotřebuje | Funkce není nabízena | Ne |
| Výběr dokumentu | Systémový document picker; přístup pouze k uživatelem vybrané položce | Po volbě „Vybrat dokument“ | Zrušení vrátí `CANCELLED`, workflow pokračuje bez souboru | Ne |
| Příjem přes Share Sheet | Share Extension + App Groups entitlement pro host i extension | Bez runtime permission; uživatel sám zvolí CSM v Share Sheet | Extension odmítne nepodporovaný typ/velikost bez čtení dalšího obsahu | Ne |
| Běžné/lokální notifikace | `UNUserNotificationCenter`; pro remote push Push Notifications capability a `aps-environment` v podepsaném buildu | Po vysvětlení hodnoty výstrah, nikoli automaticky při startu | Výstrahy zůstávají dostupné po otevření COP; zobrazí se návod do Nastavení | Ne |
| Time Sensitive notifikace | Podepsaný entitlement `com.apple.developer.usernotifications.time-sensitive`; kontrola aktuálního system setting | Společně s běžným notifikačním flow, bez zastaralé `UNAuthorizationOption.timeSensitive`, pouze pro serverem klasifikované události | Doručí se podle běžných pravidel; neslibuje průchod přes Focus | Ne |
| Critical Alerts | Apple entitlement `com.apple.developer.usernotifications.critical-alerts` + samostatná autorizace | **Mimo MVP, dokud Apple entitlement neschválí** | Funkce a copy o kritickém vyzvánění nejsou dostupné | Ne |
| Universal links | Associated Domains entitlement, minimálně schválený COP applink | Bez runtime permission | Neplatný link otevře bezpečnou home route po autentizaci | Ne |
| APNs background content | Background Modes: `remote-notification` | V MVP jen pokud schválený push kontrakt skutečně používá silent push | Bez něj se nespoléhá na background refresh; viditelný push zůstává oddělený | Ne |
| Zvuk skutečného hovoru po zamčení | Background Modes: `audio` + aktivní CallKit/AVAudioSession | Jen po dobu přijatého nebo odchozího hlasového hovoru | Ukončení/selhání vždy deaktivuje audio session; žádný keepalive | Ne |

### Závazné purpose stringy

Finální české a anglické texty musí před releasem projít produktovým a privacy
review. Význam nesmí být širší než implementace. Doporučený český baseline:

| Key | Český významový baseline |
| --- | --- |
| `NSLocationWhenInUseUsageDescription` | „CSM používá polohu při práci s COP k zobrazení vaší pozice, směru a k připojení polohy pouze k akci, kterou spustíte.“ |
| `NSMotionUsageDescription` | „CSM používá údaje o natočení telefonu při aktivní práci s orientací v COP.“ |
| `NSFaceIDUsageDescription` | „CSM používá Face ID pouze tehdy, když bezpečnostní politika COP vyžaduje místní biometrické odemknutí před zobrazením krizových dat.“ |
| `NSCameraUsageDescription` | „CSM použije fotoaparát pouze tehdy, když pořídíte fotografii jako přílohu ve workflow COP.“ |
| `NSMicrophoneUsageDescription` | „CSM používá mikrofon pouze během hlasového hovoru, který zahájíte nebo přijmete v COP Chatu.“ |

`NSLocationAlwaysAndWhenInUseUsageDescription`, `NSPhotoLibraryUsageDescription`,
`NSFaceIDUsageDescription` a `NSUserTrackingUsageDescription` se do MVP
nepřidávají bez funkce, která je skutečně potřebuje. Mikrofon je povolen pouze
pro uživatelem zahájený nebo přijatý webový hlasový hovor. CSM nepoužívá App
Tracking Transparency pro analytické nebo reklamní sledování.
Integrovaný COP Chat může mikrofon požádat ze same-origin iframe; nativní host
ověřuje shodu přesného originu iframe, hlavního COP dokumentu a žádosti WebKitu.
Před udělením WebKit media-capture oprávnění host explicitně ověří nebo vyžádá
`AVAudioApplication` record permission a teprve po souhlasu asynchronně aktivuje
audio session. Přechody audio session jsou serializované; neprobíhají blokujícím
voláním na hlavním vlákně.

### Background modes a zakázané zkratky

- `location` je povolen pouze během uživatelem spuštěné tracking session. Stop
  musí být dostupný ve webu i přes nativní stav po reloadu WebView.
- `remote-notification` není náhradou za kontinuální proces a přidá se jen pro
  konkrétní, otestovaný silent-push scénář.
- `voip` se nesmí použít k imitaci vyzvánění. PushKit/CallKit patří pouze ke
  skutečnému VoIP hovoru a implementace je vymezena ADR 0008.
- `audio`, Bluetooth background modes ani background location se nesmějí použít
  k udržování budoucí relay služby při životě.
- Background execution je best effort podle iOS. Force-quit uživatelem je
  pravdivě prezentován jako přerušení, ne jako tichá chyba.

## Share Extension a soubory

Share Extension běží v odděleném procesu a nesmí implementovat report workflow.
Provádí pouze tento omezený tok:

1. přijme explicitně podporované UTType položky;
2. před kopírováním ověří počet, deklarovaný typ a limit velikosti;
3. bezpečně načte `NSItemProvider`, přepočítá skutečnou velikost a hash;
4. uloží kopii s Data Protection do App Group inboxu pod náhodným opaque ID;
5. uloží minimální metadata bez absolutní cesty a bez zbytečného EXIF;
6. oznámí hostu dostupnou položku a skončí;
7. web si položku přes bridge vyzvedne a vloží ji do existujícího workflow.

Výchozí bezpečná politika do rozhodnutí v `open-questions.md`:

- pouze fotografie, PDF a běžné dokumenty výslovně povolené allowlistem;
- žádné adresáře, spustitelné soubory, skripty ani automatické rozbalování
  archivů;
- EXIF geolocation se před předáním odstraňuje; zachování vyžaduje explicitní
  volbu v konkrétním webovém workflow;
- neclaimnutá položka expiruje po 24 hodinách;
- claimnutá položka se smaže po potvrzeném převzetí webovým outboxem, nejpozději
  po 24 hodinách; pokud je produktově nutná delší offline retence, musí být před
  implementací schválena a uživateli viditelná;
- App Group container je vyloučen z běžného backupu a má byte quota i cleanup
  při startu/aktivaci;
- web dostává `NativeAssetRef`, nikoli filesystem URL nebo base64 obsah.

## Datový inventář nativní vrstvy

| Data | Účel | Uložení | Výchozí retence | Telemetry / log |
| --- | --- | --- | --- | --- |
| Bridge session ID a sequence | Ochrana a pořadí requestů/eventů | Paměť | Do reloadu/navigace | Jen agregovaný výsledek handshake |
| Capability a permission status | Správné webové chování | Paměť; poslední neautoritativní snapshot volitelně | Do další kontroly systému | Stav bez osobního obsahu |
| Background location samples | Překlenutí WebView reloadu a krátkého výpadku | Chráněný native spool, šifrovací klíč v Keychain | Do ACK převzetí, max. 24 h jako bezpečný fallback | Nikdy souřadnice; jen count, age bucket, error |
| Heading/attitude samples | Foreground orientace | Paměť | Pouze aktivní subscription | Jen valid/invalid count a latency |
| Share inbox asset | Předání uživatelem vybraného souboru webu | App Group container s file protection | Do ACK převzetí, max. 24 h | Pouze typová kategorie, size bucket, výsledek |
| APNs device token | Registrace zařízení u schváleného backendu | Native proces; chráněné technické úložiště podle kontraktu | Do změny tokenu, logoutu nebo zrušení registrace | Nikdy plný token |
| Push deep-link metadata | Otevření route | Paměť / krátká pending položka | Do zpracování, max. 24 h | Route category a výsledek, bez parametrů |
| Diagnostické chyby | Podpora pilotu | Unified Logging s privacy redaction | Podle schválené log policy | Bez payloadu, tokenu, souřadnic a raw ID |
| Web cookies/IndexedDB/cache | OIDC a COP offline stav | Persistentní `WKWebsiteDataStore` | Vlastní politika COP; vymazání při logout/delete flow | Native obsah nečte ani nekopíruje |

Položky s nevyřešeným serverovým účelem se nesmějí synchronizovat „pro jistotu“.
Native spool je technická fronta, nikoli druhý doménový outbox. Převzetí musí mít
korelační ID a jednoznačný ACK; samotné přečtení JavaScriptem není potvrzení
serverového doručení.

## Notifikace, zvuk a APNs privacy

- APNs token zůstává v nativní vrstvě a nesmí být vydán libovolnému JavaScriptu.
  Preferovaný kontrakt používá krátkodobý jednorázový registrační ticket vydaný
  autentizovaným COP webem a nativní registraci proti CSM Messaging.
- Push payload obsahuje pouze opaque notification/event ID, kategorii, čas a
  povolenou route. Citlivý text se načítá po otevření a autorizaci z COP.
- `interruption-level` je odvozen ze serverové klasifikace a uživatelského
  nastavení. Native klient nesmí libovolně eskalovat běžný push.
- Time Sensitive může uživatel vypnout. Critical může obejít mute/Focus pouze s
  Apple entitlementem a samostatným souhlasem; ani poté se neslibuje doručení na
  nedostupné zařízení.
- Logout, zrušení zařízení a smazání účtu musí zneplatnit backendovou registraci
  tokenu; pouhé smazání lokálního tokenu nestačí.

## Budoucí relay oprávnění — mimo MVP

Následující deklarace nesmějí být v produkčním MVP aktivní jen „do zásoby“:

| Budoucí funkce | Možná deklarace | Gate před aktivací |
| --- | --- | --- |
| Local network / Bonjour | `NSLocalNetworkUsageDescription`, přesný `NSBonjourServices` allowlist | Schválený transport, purpose string, fyzické testy, privacy review |
| Bluetooth transport | `NSBluetoothAlwaysUsageDescription` | Konkrétní BLE use case, lifecycle a background omezení; žádný raw device name |
| Wi-Fi Aware na iOS 26 | Příslušný Wi-Fi Aware entitlement a service declarations | Apple entitlement, interoperabilita, App Store a device-support ověření |
| Nearby Connections | SDK deklarace, případná local-network/Bluetooth oprávnění podle skutečné verze SDK | Procurement/DPA, SDK privacy manifest, telemetry audit, iOS↔Android test |

Relay je vždy samostatný opt-in, má viditelný aktivní stav, okamžitý Stop, byte
quota a Clear Cache. Peer identita je pseudonymní. Citlivé payloady zůstávají
zakázané, dokud není schválen threat model, device identity, distribuce a rotace
klíčů, revokace a standardní E2E šifrování.

## Privacy manifest, App Store a dodavatelé

Před každým TestFlight/App Store releasem se musí:

1. vygenerovat seznam všech frameworků/SDK včetně tranzitivních závislostí;
2. ověřit jejich `PrivacyInfo.xcprivacy`, required-reason APIs, síťové endpointy,
   sběr dat a tracking domény;
3. sladit skutečný sběr s App Store Connect Privacy Nutrition Labels;
4. ověřit účel a lokalizaci všech `UsageDescription` stringů;
5. diffnout entitlements výsledného podepsaného `.app` a Share Extension;
6. ověřit, že release neobsahuje debug origin, Web Inspector, testovací
   certifikát, nepoužitá oprávnění ani relay SDK/flag v aktivním stavu;
7. aktualizovat privacy notice COP a záznam o zpracování, pokud se mění účel,
   kategorie dat, příjemce nebo retence.

Google Nearby Connections ani jiné SDK třetí strany nesmí být přidáno do
produkční distribuce před písemným rozhodnutím o privacy/procurement dopadech.

## Uživatelská kontrola a mazání

- Uživatel může kdykoli zastavit tracking a smazat jeho neodeslaný native spool.
- Uživatel může vymazat čekající Share inbox; před smazáním se zobrazí počet a
  celková velikost, nikoli náhledy citlivého obsahu na zamčené obrazovce.
- Logout ukončí subscription, tracking podle potvrzené produktové politiky,
  zneplatní bridge session a spustí registraci odhlášení push tokenu.
- „Vymazat lokální data“ odstraní native technická data i webový website data
  store po explicitním potvrzení. Neslibuje serverové smazání; to probíhá přes
  autoritativní COP účetní workflow.
- Reinstalace aplikace není považována za spolehlivou revokaci serverové device
  identity. Backend musí podporovat expiraci a zrušení registrace.

## Release privacy gate

Release je blokovaný, pokud není doloženo:

- oprávnění jsou vyžádána pouze in-context a mají funkční denied/restricted
  fallback;
- všechny purpose stringy odpovídají skutečnému chování v češtině i angličtině;
- background tracking je viditelný, explicitně zastavitelný a fyzicky otestovaný;
- logy a export diagnostiky neobsahují souřadnice, soubory, tokeny ani payload;
- App Group inbox má protection, quota, expiraci a bezpečný cleanup;
- APNs registrace je autentizovaná a token není exponován webovému originu;
- App Store privacy answers a privacy manifest odpovídají binárnímu artifactu;
- všechny otevřené otázky s dopadem na právní základ, retenci nebo příjemce dat
  mají rozhodnutí, nebo je dotčená capability v release vypnutá.
