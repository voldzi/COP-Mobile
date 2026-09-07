# ADR 0012: Serverem vlastněné přímé hlasové hovory

## Status

Accepted — 2026-07-19

Nahrazuje call bridge, webový Matrix/WebRTC media engine a skupinové hovory z
ADR 0009. Historická kompatibilita s těmito cestami není součástí řešení.

## Context

Předchozí návrh rozděloval jeden hovor mezi CallKit v COP Mobile, stav v
JavaScriptu, Matrix call signalizaci a webová WebRTC média. Každá vrstva měla
vlastní timeout a lifecycle. Výsledkem byly ghost hovory, nedoručené příchozí
hovory, rozdílný stav na obou telefonech a návrat uživatele do webového chatu.

COP Mobile je samostatná aplikace a potřebuje jediný stavový automat, nativní
audio cestu a stejné chování jako webový klient bez závislosti na WebView.

## Decision

1. COP API je jedinou autoritou pro direct-call lifecycle. Vytvoření,
   přijetí, odmítnutí, zrušení, spojení, ukončení, media failure a expirace jsou
   revizované idempotentní přechody jednoho serverového záznamu.
2. Hovor je povolen pouze pro přímou konverzaci s právě jedním protějškem.
   Skupinové hovory a AI hovory nejsou podporovány a UI u nich telefon nenabízí.
3. COP Mobile načítá a mění call state přímo přes COP REST API. Call state,
   command ACK, SDP, ICE ani media credentials neprocházejí Device bridgem nebo
   WebView.
4. CSM Messaging doručuje PushKit payload pouze pro
   `chat.voice_call.incoming` a `chat.voice_call.ended`. Payload obsahuje
   `callId`, `roomId` a display jméno. Native jej okamžitě oznámí CallKitu a
   autoritativní detail vždy dočte z COP API. PushKit token se uchovává v
   Keychain, při aktivaci aplikace se synchronizuje s `PKPushRegistry` a obnoví
   registraci zařízení. Foreground klient smí jako doplňkovou obnovu načíst
   aktivní serverové hovory a prezentovat dosud neznámý příchozí hovor.
5. LiveKit je jediný media transport. COP API vydá krátkodobý room-scoped token
   pouze účastníkovi aktivního hovoru. Token se neukládá, neloguje a není součástí
   push payloadu.
6. CallKit je jediným vlastníkem aktivace `AVAudioSession`. LiveKit mikrofon se
   publikuje teprve po skutečné CallKit audio aktivaci. Mute, speaker/Bluetooth,
   interruption, proximity a teardown vlastní native.
7. Stav `connected` vznikne až po serverovém acceptu a skutečném připojení
   vzdáleného LiveKit účastníka. Lokální spinner ani systémová CallKit obrazovka
   nejsou důkaz spojení.
8. Ukončené, odmítnuté a nepřijaté hovory jsou běžné položky konverzační
   historie. Missed call je serverová terminální fáze; push k úklidu používá
   standardní `chat.voice_call.ended`.
9. Webový COP Chat používá stejný COP API lifecycle a stejný LiveKit room.
   Rozdíl klienta nesmí měnit stavový automat ani význam historie.
10. Když je webový COP vložený do COP Mobile, jeho media větev je pasivní.
    CallKit/LiveKit vlastní pouze native; vložený dokument nesmí pod stejnou
    identitou vytvořit druhé připojení.

## Consequences

### Positive

- oba klienty sdílejí jeden autoritativní stav a historii;
- příchozí hovor nezávisí na načteném WebView ani webové Matrix session;
- audio a systémové ovládání jsou plně nativní;
- neexistuje skrytá kompatibilní větev, která by mohla převzít hovor;
- nepřijatý hovor je deterministický výsledek serverové expirace.

### Negative

- produkce vyžaduje dostupný LiveKit endpoint, správné krátkodobé tokeny a
  fyzické ověření APNs/PushKit/CallKit/audio na podporovaných verzích iOS;
- při výpadku COP API nelze bezpečně vytvořit ani změnit stav hovoru;
- skupinový hlasový hovor vyžaduje případné nové samostatné rozhodnutí a jiný
  serverový model.

## Security and privacy

- COP API autorizuje každou operaci podle OIDC subjektu a účastenství;
- revize a idempotency key zabraňují opakovanému nebo opožděnému přechodu;
- LiveKit token je krátkodobý, room-scoped a umožňuje jen potřebné publish/
  subscribe operace;
- push payload neobsahuje zprávy, tokeny, media adresu ani přesnou polohu;
- diagnostika smí obsahovat call ID a redigovaný stav, nikdy token nebo audio.

## Verification gate

- serverové unit/contract testy všech přechodů a expirace;
- shodný push payload parser na iOS 26 a 27;
- dvousměrný fyzický hovor iOS 26 ↔ iOS 27, zvuk oběma směry, mute, speaker,
  odmítnutí, zrušení a ukončení;
- terminated/background příjem přes PushKit;
- nepřijatý hovor v historii obou klientů;
- WebView reload nebo jeho úplná nedostupnost nesmí ovlivnit aktivní hovor.
