# ADR 0009: Nativní komunikační povrch

## Status

Accepted — 2026-07-11

Částečně nahrazuje rozhodnutí ADR 0001 a ADR 0008 v rozsahu chatu,
autentizace pro chat a prezentace hlasového hovoru. Ostatní rozhodnutí těchto
ADR zůstávají platná.

## Context

Hybridní COP host spolehlivě zpřístupňuje mapu, hlášení a ostatní business
workflow. Komunikace má ale jiné požadavky než mapový web: očekává nativní
navigaci, rychlou offline cache, E2EE lifecycle, systémové přílohy, haptiku a
telefonní chování hovoru včetně CallKit a proximity senzoru.

Referenční projekt `04 CSM messenger` již obsahuje produkčně ověřený nativní
Matrix Rust E2EE klient, OIDC Authorization Code + PKCE, Keychain a chráněné
lokální stores. Tyto schopnosti jsou nyní poskytovány hostitelským aplikacím
přes úzký Swift Package produkt `CSMCommunicationKit` a SwiftUI povrch
`CSMCommunicationHost`.

Matrix Rust SDK v používané verzi nevlastní nativní WebRTC media engine
kompatibilní se současným COP Chat hovorem. Okamžité nahrazení fungujícího
`matrix-js-sdk`/WebRTC toku by proto spojilo UI migraci s novou implementací
signalizace, ICE/TURN a médií a neúměrně zvýšilo riziko.

## Decision

1. COP Mobile bude hybridní podle produktových povrchů:
   - COP web zůstává jediným vlastníkem mapy, hlášení, vrstev, doménových modelů,
     autorizace a ostatních business workflow;
   - `CSMCommunicationKit` vlastní nativní SwiftUI chat, jeho Matrix E2EE
     session, timeline, offline outbox a komunikační lokální stores.
2. Nativní chat používá vlastní OIDC Authorization Code + PKCE session vůči
   schválenému `csm-mobile` klientovi. Webová a nativní OIDC session jsou
   oddělené; tokeny se mezi WebKitem, bridge a modulem nekopírují. Jediný
   actor-isolated lifecycle obnovuje access token při startu i na požadavek,
   bezpečně ukládá rotovaný refresh token a dočasnou síťovou/IdP/Keychain chybu
   nikdy neinterpretuje jako logout.
3. OIDC a Matrix access/refresh tokeny, Matrix device binding a šifrovací
   passphrase se ukládají pouze do Keychainu a chráněných lokálních stores
   spravovaných `CSMCommunicationKit`. Modul nevystavuje credentials hostu ani
   webovému JavaScriptu. OIDC tokeny odstraní jen explicitní logout, bezpečnostní
   wipe nebo serverem potvrzený `invalid_grant`; zrušení lokální biometrie pouze
   uzamkne chráněný obsah a dovolí nové odemknutí.
4. Bridge smí otevřít nativní chat pouze úzkou metodou
   `communications.openChat`. Vedle prázdného payloadu smí exact-origin host
   dodat jen bounded opaque očekávaný OIDC subject. Je to fail-closed ochrana
   proti záměně účtu, nikoli credential: native jej porovná s actorem získaným
   vlastním OIDC/bootstrap tokem. Metoda nepřenáší obsah zpráv, tokeny, profil,
   Matrix identitu ani Matrix eventy.
5. COP Mobile musí podporovat uživatele bez webového použití. Explicitní tap na
   Chat může při chybějící native session spustit OIDC Authorization Code +
   PKCE přímo v aplikaci. Platná Keychain session se obnoví bez login
   probliknutí; neshoda s očekávaným web subjectem blokuje celý chat a nabízí
   nucené znovupřihlášení.
6. Hovor dostane nativní SwiftUI full-screen prezentaci, CallKit lifecycle,
   `AVAudioSession` routing, mute/speaker ovládání a proximity blackout.
   Přechodný bridge `calls.updatePresentation` přenáší jen validovaný stav
   hovoru a opaque `callId`/`roomId`/display title. Aktivní stav lze měnit jen
   ve foregroundu, pouze pro jeden hovor a po povolených přechodech; terminální
   stav je vždy přenesen kvůli bezpečnému úklidu CallKitu. Native navíc drží
   procesní kvótu aktualizací/identit a rozlišuje PushKit call čekající na média
   od hovoru, jehož media engine už vlastní WebView.
7. Do dalšího samostatného gate zůstávají Matrix call signalizace, SDP/ICE a
   WebRTC média ve stávajícím COP Chat `matrix-js-sdk` enginu. Nativní call UI
   není důkazem nativního media enginu ani úspěšného spojení.
   Při startu hovoru z nativního SwiftUI chatu zůstává nativní chat namountovaný
   pod call overlayem; host nesmí odhalit webový chat nebo webový recovery flow
   jen proto, že webový engine zatím připravuje media/call snapshot.
8. PushKit se používá pouze pro skutečný příchozí VoIP hovor. VoIP push se musí
   okamžitě nahlásit CallKitu; obnovení webového media enginu nesmí zdržet
   povinný PushKit completion.
9. COP Mobile zůstává jediným `UNUserNotificationCenterDelegate`. APNs token a
   foreground/background/action callbacky předává do
   `CSMCommunicationNotifications`; vložený modul globální delegate nepřepisuje
   a před připojením chatového surface drží omezenou metadata-only push frontu.
10. Plně nativní WebRTC vyžaduje nové ADR a gate: kompatibilní Matrix signaling,
   auditovanou WebRTC dependency, TURN/ICE interoperabilitu, audio interruption
   state machine, background/terminated real-device testy a bezpečný rollout s
   možností návratu k ověřenému webovému enginu.
11. CallKit user action je dvoufázová: native vytvoří stabilní `actionId` a
    event retryuje do identity-bound ACK z webového Matrix enginu.
    Stejný retry/ACK kanál používá i odchozí start, takže jednorázový povel
    nemůže zmizet před přihlášením web listeneru. Persistentní webový media host
    je od mountu render-active off-screen, aby mohl první start/answer zpracovat.
    End/reject/mute `CXAction` čekají na ACK. Answer je nutná lifecycle výjimka:
    po nativní konfiguraci audia se `CXAnswerCallAction` fulfillne, aby CallKit
    vyvolal `didActivate`; Matrix answer pokračuje jako samostatná spolehlivá
    fail-closed akce. COP Chat drží command do existence odpovídajícího call
    snapshotu nejvýše 30 sekund a deduplikuje retry. Matrix answer má 35sekundové
    cold-start okno, ostatní akce 12 sekund. Timeout/záporné ACK jsou fail-closed;
    chyba JavaScript delivery event requeueuje. `CXProvider` reset vynutí webový
    hangup a pozdní `CXStartCallAction` nesmí regresovat connected/terminal stav.
    Záporný ACK, nativní timeout i CallKit `timedOutPerforming` vynutí reload
    webového media enginu, report/remove call a deaktivaci audia. Teprve po
    forced close se `end`/`reject` může fulfillnout; Matrix answer/mute selže.
    Před `getUserMedia` musí web publikovat call identity; CallKit-owned
    `AVAudioSession` aktivuje výhradně CallKit.
12. Skupinový hlasový hovor se zahajuje z nativního detailu skupiny a v aktivním
    call view lze přes `+` postupně přizvat další aktivní členy místnosti. Native
    přenáší pouze `group` kind, bounded participant presentation a opaque
    `start`/`addParticipants` action; webový Matrix `GroupCall` zůstává jediným
    vlastníkem E2EE signalizace a médií. Peer mesh je omezen na šest účastníků.
    Server znovu ověřuje každého cílového uživatele vůči členství v místnosti.

## Superseded scope

- ADR 0001 body 2, 6 a 8 a jeho zákaz nativního chatu/Matrix klienta jsou v
  tomto přesném rozsahu nahrazeny. Zákaz nativní kopie mapy, report workflow a
  ostatní business logiky zůstává platný.
- ADR 0008 tvrzení, že native nikdy nevlastní Matrix credentials, je nahrazeno
  pouze pro nativní chatovou session uvnitř `CSMCommunicationKit`. Webový call
  engine nadále vlastní přechodnou call signalizaci a média.
- ADR 0008 PushKit/CallKit pravidla, metadata-only payload a zákaz použití VoIP
  pro alarm či keepalive zůstávají platné.

## Consequences

### Positive

- chat může mít nativní navigaci, offline E2EE cache, přílohy, haptiku a iPad
  layout bez duplikace mapy a report workflow;
- host neinterpretuje Matrix credentials ani decrypted chat obsah;
- call presentation odpovídá telefonu a může reagovat na proximity senzor,
  zatímco ověřená webová media cesta zůstává funkční;
- nativní chat a budoucí media engine mají samostatné release gates.

### Negative

- uživatel může mít současně webovou a nativní OIDC session a dvě samostatná
  Matrix zařízení; logout, revokace a recovery UX musí tuto skutečnost
  vysvětlovat a bezpečně obsloužit;
- `CSMCommunicationKit` a Matrix Rust SDK zvětšují binárku, build čas a
  supply-chain surface;
- přechodný hovor závisí na dostupnosti WebView a jeho Matrix/WebRTC session i
  při nativní prezentaci;
- změny komunikačního modulu vyžadují koordinované testy s COP, CSM Messaging,
  Synapse, APNs a TURN.

## Security and privacy impact

- Native OIDC používá veřejný PKCE klient bez vloženého client secretu a přesný
  redirect scheme. Callback state, issuer a redirect URI se musí validovat.
- Tokeny, recovery material, Matrix store passphrase, decrypted timeline a
  přílohy se nesmějí dostat do bridge, push payloadu, logu ani diagnostického
  exportu.
- Lokální Matrix/outbox stores jsou subject- a device-bound, šifrované, chráněné
  Data Protection a při změně účtu nesmí ukázat data předchozího subjectu.
- Web může nativní chat pouze otevřít, dodat očekávaný opaque subject pro
  kontrolu shody a zrcadlit call presentation. Nesmí
  ovládat arbitrary audio, CallKit, URLSession ani Matrix API.
- Package dependency musí být pro release reprodukovatelně připnutá a výsledný
  artifact musí projít privacy manifest, embedded-framework a secret scanem.

## Validation

- nativní OIDC fresh login, refresh, cancel, logout, revoke a subject switch na
  fyzickém iOS 26 zařízení;
- Matrix Rust restore, E2EE send/receive, offline timeline/outbox, reconnect,
  recovery warning a oddělené web/native device ID;
- bridge negativní testy pro `communications.openChat` a
  `calls.updatePresentation`, včetně cizího originu, iframe, malformed payloadu,
  replay a stale session;
- příchozí i odchozí hovor, connecting/connected/failed/ended, mute, speaker,
  Bluetooth, interruption, proximity blackout, zamčený telefon, background a
  system-terminated start;
- skupinový start z nativního chatu, postupné přizvání, odmítnutí uživatele mimo
  místnost, limit šest osob a pokračování hovoru po lokálním odchodu jednoho člena;
- důkaz, že přechodná média stále tečou webovým WebRTC enginem a že native UI
  nikdy neprohlašuje `connected` bez potvrzeného stavu enginu;
- samostatný release blocker pro plně nativní WebRTC; existence call view tento
  gate nesplňuje.
