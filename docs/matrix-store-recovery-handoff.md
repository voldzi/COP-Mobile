# Jízda / COP Mobile: obnova místního Matrix store

## Integrace

Použijte nový kompletní release této větve `codex/matrix-store-recovery`,
navazující na neměnný `108f4c2b125bc75b312dcdc57240cd7842f60182`.
Pinujte celý veřejný commit obsahující tento dokument, předaný v release zprávě.
Nekombinujte samostatné kopie souborů s jinou revizí SDK. Zachovány jsou mobility, routing, měření,
identity, notification a hlasové moduly.

`CSMCommunicationHost` zůstává kompatibilní. Sdílené UI při lokální chybě
zobrazuje **Obnovit místní chat** nad composerem. Vložený host získá stejnou
obrazovku bez vlastního resetu. Mimo chybějící/neplatný klíč, AEAD, chybějící
kryptografickou identitu či výslovnou recoveryRequired se rotace nenabízí.
Zamčený telefon se odemkne; nedostupná služba/DB se zopakuje.

Nový veřejný runtime kontrakt:

```swift
var localChatStoreFailure: CSMChatLocalStoreFailure? { get }
var isRecoveringChatStore: Bool { get }
func recoverChatStore(
    authorization: CSMChatStoreRecoveryAuthorization,
    confirmed: Bool
) async throws
// .restoreBackup(recoveryKey: String)
// .confirmedTestHistoryReset
```

Nepředávejte recovery key přes web bridge, URL, logy, clipboard ani host storage.
Tlačítko API smí následovat pouze vědomé potvrzení uživatele. Před obnovou se
kontrolují aktivní hovory; jejich nedostupná evidence obnovu zastaví.

Jízda pro výslovně schválený testovací build vloží do skutečného výstupního
Info.plist `CSMAllowChatRecoveryWithoutBackup` jako Boolean true, jen DEBUG.
Release/ChinaRelease má false nebo položku vynechá. Řetězec "true" ani číslo 1
nepovolují pokračování bez zálohy. Build upgrade nesmí mazat app/Keychain,
installation seed, memberships, SwiftData/CloudKit, historii ani outbox.
Nepřidávejte další paralelní prepare/registraci k `CSMCommunicationHost`.

## Provoz a rollback

Příslušný pending deviceId zůstává stejný po chybě i restartu. Po úspěchu drží
selected ID i při selhání optional bootstrap cache. Původní store/key/session
zůstávají zachované; staré zařízení není automaticky revokováno. Nezvyšuje se
plošná generation v7 a nepoužívá se account-wide reset recovery.

Rollback k původnímu SDK obnoví původní výpočet deviceId a může znovu narazit
na původní AEAD. Nepoužívejte starší verzi k resetování crypto root. Nemažte
routing evidence ani new/old keychain položky. Úspěch nové relace nenahrazuje
ověření doručení a důvěry klíčů s druhým reálným telefonem.

## Ověření

Finální `bash scripts/check.sh` skončil 2026-10-06 úspěšně (exit 0),
Xcode 27.1 / 27A9269, SDK 27.1, iPhone Duo iOS 27.1 simulátor:

| Kontrola | Výsledek |
| --- | --- |
| Skeleton, pinned toolchain, 19 Device API fixtures, iOS config, diff whitespace | PASS |
| COP Mobile unit | 30 testů, 0 selhání |
| COP Mobile launch UI | 5 testů, 0 selhání |
| Shared package XCTest | 161 testů, 2 skipped, 0 selhání |
| Shared package Swift Testing | 2 testy, 0 selhání |
| Accessibility | 2 testy, 0 selhání |
| Nová cílená bezpečnostní sada (zahrnuta v package) | 25 testů, 1 skipped, 0 selhání |

Dva package skips: privátní recorded-road replay není v source repo; systémový
Keychain v package runneru nemá entitlement, přesný OSStatus -34018.
Deterministické atomické add/duplicate-winner testy a reopen simulované služby
prošly. Skutečný Keychain/locked-phone test se netvrdí jako ověřený.

Skutečný pinned Rust SDK vytvořil SQLite; nesprávný passphrase způsobil
AEAD/store cipher chybu a původní passphrase stejnou DB znovu otevřel.
Skutečně obnovený syntetický Olm account read-only guard rozpoznal. Prázdná
Rust-vytvořená DB, nulová a truncated DB neobešly kontrolu již publikovaného
deviceId (server odpovědi zde byly HTTP fixture). Restart po neúspěšném token
cache save drží selected ID; šifrovaný outbox zůstal zachován. Account switch
během obnovy a stale true/false availability byly testovány řízenou async fixture.

První full gate obsahoval TERM UI runneru a následné selhání smoke startu.
Finální sériový celý gate prošel; příčina původního TERM není potvrzená.
Detaily a přesné logy: [akceptační záznam](archive/2026-10-06-matrix-store-recovery-acceptance.md).
Chroma retrieval/reindex nového worktree vracely tool error, index není potvrzen
jako obnovený; relevantní soubory byly ověřeny přímo.

Nové testy rozlišují skutečné Rust SQLite/AEAD od HTTP a Keychain fixture.
Samostatný package runner může vracet Keychain OSStatus -34018 (missing
entitlement); takový test je vykázán jako skipped, nikoli PASS.

### Povinná fyzická akceptace u Jízdy

1. Over-install schváleného buildu bez smazání app či účtů; nezávisle ověřit
   instalovanou verzi a odemčený start.
2. Otevřít Chat, ověřit typed chybu, otevřít Obnovit místní chat; zrušení nesmí
   změnit deviceId/store/key. Potvrzení testovacího režimu vytvoří jediný nový ID.
3. Nová E2EE zpráva oběma směry s druhým telefonem, pozvánky a skutečná důvěra
   klíčů; starou historii bez původního klíče neslibovat.
4. Cold start a opakování: selected ID se nemění, validní relace se neresetuje.
5. Locked-phone Keychain, výpadek během obnovy, expirace 401 a 429/503: žádná
   automatická rotace/mazání; odemčení/nový token obnoví původní relaci.
6. Dva účty a změna během obnovy: starý výsledek se nepublikuje novému účtu,
   nevymaže se cizí encrypted root/key/outbox. Pending retry nevytvoří další ID.
7. Restore ze skutečné existující zálohy se správným/chybným recovery key;
   potvrdit skutečné dešifrování historie, nejen SDK backupState.
8. Regrese sdílených vozidel, směrového routingu, reportů/měření a hlasových
   režimů. Žádný reset ostatních doménových dat není součástí tohoto SDK.
