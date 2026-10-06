# Matrix recovery diagnostics: následná akceptace 2026-10-06

## Rozsah a neměnný candidate

Kompletní SDK candidate `e6d0f2aea7b67d86164748d8b60e23b6f318c9f4` má
parent `2708100c2e650a0bb3726c7d5b0fa94fd2a3aed9`, který obsahuje celý
union `108f4c2b125bc75b312dcdc57240cd7842f60182`. Candidate checkout
`/Users/voldzi/.codex/worktrees/cop-matrix-recovery-diagnostics/06 COP Mobile`
je pro souběžné sestavení Jízdy neměnný. Finální release přidává pouze tento
akceptační dokument a aktualizuje předání v jiném checkoutu; SDK zdroje,
aplikace, scripts a fixtures zůstávají identické.

## Skutečný nález a oprava

Jízda 1.2 (16) byla over-install aktualizací spuštěna na obou reálných
telefonech; fyzická akceptace ale neprokázala funkční obnovu či E2EE zprávy.
Ve 13:53 nebyla obnova viditelná, ve 13:58 uživatel potvrdil její zobrazení.
Technický stav hlásil typovanou chybu odemknutí místního store. Původní příčina
AEAD konkrétního telefonu není potvrzená.

Zdrojová kontrola doložila přepsání typované chyby pozdější síťovou chybou a
String-only diagnostiku implicitního reopen. Oprava přenáší typovanou scoped
diagnostiku wrapper → model, ponechá potvrzenou chybu při HTTP/network failure,
vymaže ji po verified-open/recovery či změně scope. Implicitní reopen používá
fenced configure; in-flight configure nepředstírá otevřenou novou relaci.
Model navíc chrání delayed diagnostic read proti novému úspěšnému configure.
Scope zahrnuje provider/homeserver/user/device, nikoli rotující token.

Obnova má stejný explicitní vstup v banneru, composeru, menu konverzace a Stavu
chatu. Status nejprve zavře svůj sheet a teprve po onDismiss otevře obnovu.
Samotné otevření obnovovacího dialogu nic nemaže a nepotvrzuje. HTTP 401/429/503,
zamčený Keychain a nedostupná DB nepovolují reset. Žádná REST/server/CallKit/AI
změna, automatická relink, Keychain wipe, revokace starého zařízení ani zásah
na reálném telefonu není součástí této revize.

## Výsledky

Cílená sada skončila exit 0: 35 testů, 1 skipped (-34018), 0 failure.
Log `/private/tmp/cop-matrix-recovery-diagnostics-targeted-fenced.log`.
Předchozí cílený build odhalil async XCTest autoclosure chybu v novém testu;
opravena. Další test odhalil neúplný fixture: refreshConversations neměl
ConversationMetadataProviding a zprávy tedy neotevřel. Test nyní používá
skutečnou selectConversation cestu a ověřuje implicitní reopen i bez outboxu
v modelu. Nešlo o potvrzení produktového úspěchu v těchto neúspěšných bězích.

První kompletní gate skončil **exit 65**: 30 unit PASS; 4 UI PASS a 1 UI FAIL
`testChatRemainsReachableAfterMapFailure`, assertion řádek 57 `chat.workspace`.
Fallback i tlačítko „Otevřít komunikaci“ existovaly a tap proběhl. Záznam UI
hierarchie ukázal ActivityIndicator „Otevírám chat“. Automation session před
startem trvala přibližně 49 sekund; po tap chat nenaběhl v původním 8s limitu.
Příčina zdržení není potvrzená. Žádný test, timeout ani SDK kód nebyl mezi
prvním full gate a opakováním změněn. Testy se nevyřazovaly.

- Původní log: `/private/tmp/cop-matrix-recovery-diagnostics-check.log`.
- xcresult: `/Users/voldzi/Library/Developer/Xcode/DerivedData/COPMobile-cmbhgekvvwjdfxbryvicucclzsdi/Logs/Test/Test-COPMobile-2026.10.06_14-24-19-+0200.xcresult`.
- Export konkrétního testu: `/private/tmp/cop-matrix-recovery-diagnostics-ui-attachments`.
- Hierarchie: `776E7535-921D-42BC-95AD-01240D7C7DE0.txt`.
- Následný automatický simctl diagnose byl cíleně ukončen, aby se uzavřel již
  dokončený neúspěšný xcresult. Žádný simulátor ani cizí proces nebyl resetován.

Opakování kompletního gate skončilo **exit 0** nad neměnným candidate na iPhone Duo
`101C6F6D-5BD8-41EC-8183-9EBED780FDD7`, Xcode 27.1 / 27A9269, SDK 27.1.
Finální log `/private/tmp/cop-matrix-recovery-diagnostics-check-final.log`.
Celý shell proces skončil exit 0; nikoli jen průběžným TEST SUCCEEDED.

| Gate | Výsledek |
| --- | --- |
| Skeleton, exact Apple pin, 19 Device fixtures, iOS config, diff | PASS |
| COP Mobile unit | 30, 0 failures |
| COP Mobile launch UI | 5, 0 failures |
| Shared package XCTest | 171, 2 skipped, 0 failures |
| Shared package Swift Testing | 2, 0 failures |
| Accessibility | 2, 0 failures |
| Cílená safety/diagnostics sada (zahrnuta v package) | 35, 1 skipped, 0 failures |

Nezávislé read-only review Jízdy potvrdilo scoped/sticky diagnostiku, false
before verified open, delayed diagnostic revision/session/scope fence i
vstupy obnovy; žádný další konkrétní blocker nebyl nalezen. Původní checkouty
108f4c2 a 2708100 i frozen e6d0f2a zůstaly nezměněné.

## Co zůstává fyzicky neověřené

Potvrzená obnova bez historie na postiženém telefonu, nové E2EE zprávy oběma
směry a po restartu, skutečná důvěra nového zařízení, správný/chybný recovery
key skutečné zálohy, skutečný Keychain při locked phone a všechny nové vstupy
obnovy v menu/Status/composeru. Package orchestration/HTTP/Keychain fixtures
nejsou reálné výsledky telefonů. Dva skips plné package sady: nepřítomný privátní
recorded-road fixture a Keychain entitlement -34018. Skutečný pinned Rust
SQLite/cipher roundtrip je od těchto fixtures odlišen v předchozím předání.

## Backend, samostatné opravy Jízdy a hranice

Read-only COP API kontrola na docker.home.cz byla healthy. V okně 13:35–14:00
CEST bylo bezpečně agregováno 684 spojených request/response: 598×200, 42×202,
44×201; žádné 401/403/5xx. Device registration 42×202, Matrix bootstrap 6×200,
voice calls 74×200 a 3×201. API odpověď nedokazuje doručení APNs ani vyzvánění.
Skutečný messaging upstream comm.home.cz:4050 má SSH z Macu timeout; přes
schválený docker.home.cz byl publickey denied. APNs delivery logy proto nejsou
ověřené, nepoužita jiná messaging instance a žádná síťová či produkční změna.

Historické vehicle event snapshots jsou neměnné projekce; aktuální oprávnění
určuje current GET/sync envelope. Nově pozvaný člen nemusí být v creation
snapshotu. Opravu detailu, uchování user-confirmed binding během transient
nil-scope a process cold-launch voice preparation vlastní Jízda. Tato revize
SDK ji nenahrazuje ani nepředstírá přijetí všech hlášených fyzických závad.
Chroma retrieval/reindex byly nedostupné; zdrojově cíleně ověřeno, index není
prohlášen za aktualizovaný.
