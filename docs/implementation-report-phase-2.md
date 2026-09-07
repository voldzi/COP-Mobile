# Phase 2 iOS implementation report

## Status

Implementovaný iOS/iPadOS 26 host je samostatně sestavitelný a testovatelný.
Simulátorový důkaz nenahrazuje fyzickou interoperabilitu APNs, PushKit,
CallKit, mikrofonu, audio routes, background lifecycle ani finální
TestFlight/App Store akceptaci.

## Implementovaný baseline

- XcodeGen projekt, Swift 6, minimum iOS/iPadOS 26 a schválený Xcode 27 beta;
- záměrně zachovaný bundle ID `cz.zeleznalady.csm.messenger`;
- dedikovaný persistentní WebKit profil, přesný origin allowlist, bounded
  loading/retry/fallback a verzovaný Device bridge `1.0.0`;
- nativní chat, OIDC/PKCE, Keychain, Matrix Rust E2EE, timeline a offline
  outbox z lokálního `packages/CSMCommunicationKit`;
- nativní direct-call engine s CallKit/PushKit, autoritativním COP API stavem a
  LiveKit audio podle ADR 0012; bez call bridge a webového media enginu;
- aplikace nemá build ani runtime závislost na `04 CSM messenger` nebo jeho Git
  repozitáři; hranici chrání ADR 0011 a projektový validátor;
- tichá obnova nativní session bez automatického browser login flow, ochrana
  proti stale souběžnému bootstrapu a explicitní přihlášení jen po akci
  uživatele;
- jediný zdravý message stream bez souběžného polling loopu, obnovení textu při
  neúspěšném sendu a timeline, která nestrhává uživatele dolů při čtení historie;
- externí navigace pouze na credential-free HTTPS a bridge event retry bez
  destruktivního reloadu celé webové aplikace;
- bounded čekání na APNs/PushKit token místo nekonečného startu.

## Ověření 2026-07-19

| Kontrola | Výsledek | Hranice důkazu |
| --- | --- | --- |
| Skeleton a dokumentace | Pass | lokální validátor |
| Device contract `1.0.0` | Pass, 19 fixtures | lokální validátor |
| Samostatnost iOS projektu | Pass | lokální package, žádný legacy project/Git source |
| Toolchain | Pass | Xcode 27.0 beta `27A5228h`, iOS SDK 27.0 |
| Swift build a unit/contract testy | Pass, 27 testů na každé verzi | iOS 26 a iOS 27 simulátor |
| CSM VoIP push parser | Pass | exact incoming/ended payload + odmítnutí neznámého typu |
| Fresh uninstall/install/launch | Pass | iOS 26.5 simulátor, produkční COP shell |
| Fyzická zařízení a hovory | Vyžaduje opakování | simulátor neověří PushKit/audio/radio |
| TestFlight/produkční distribuce | Neprovedeno v této změně | samostatný release krok |

## Zbývající release gates

1. Dvousměrný fyzický test nativního přihlášení, E2EE zpráv, příloh, reconnectu
   a změny uživatele.
2. APNs/PushKit registrace a obousměrný direct hovor mezi iOS 26 a iOS 27
   včetně LiveKit audia oběma směry, mikrofonu, speaker/Bluetooth, interruption,
   odmítnutí, zrušení, ukončení a nepřijaté historie.
3. Fyzický iPad layout, rotace, klávesnice a multitasking.
4. Archive/privacy manifest/entitlement audit a interní TestFlight promotion
   téhož sestavení.
