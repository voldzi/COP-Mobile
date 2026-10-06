# ADR 0021: bezpečná obnova místního Matrix úložiště

- Stav: implementováno, fyzická akceptace zůstává samostatnou bránou.
- Datum: 2026-10-06.
- Rozsah: sdílený CSMCommunicationKit; COP Mobile a Jízda.

## Důvod

Jízda 1.2 (15) na reálném telefonu hlásila selhání store cipher / AEAD.
Nesprávný klíč nebo poškozená šifrovaná data mohou tuto chybu způsobit;
příčinu konkrétního telefonu nelze zpětně potvrdit pouze z chybové zprávy.
Dosavadní load/save umělo nahradit chybějící či neplatný passphrase i vedle
existující DB a duplicate Keychain add používalo update. Skrytý recovery retry
uměl smazat Matrix root a použít stejné deviceId.

## Rozhodnutí

1. Matrix passphrase vzniká atomickým `SecItemAdd`; duplicate znamená načíst
   vítězný klíč, nikdy `SecItemUpdate`. Keychain dostupnost se nerozhoduje jen
   podle nepřítomné hodnoty: zamčený telefon a systémová chyba jsou retry.
2. Procesové fronty serializují inicializaci podle store a instance klienta.
   Revize chrání konfiguraci, lifecycle a publikování relace po await. Host
   nesmí vytvářet další souběžný runtime pro stejné úložiště.
3. Jakýkoli existující soubor v crypto root je chráněný stav, včetně nulové DB.
   Chybějící nebo neplatný klíč se nenahrazuje. Symlinky nejsou podporované.
   Root/data/cache jsou excluded-from-backup; klíč je WhenUnlockedThisDeviceOnly.
4. Samotná SQLite hlavička nedokazuje existující kryptografickou identitu.
   Pro pinned MatrixRustSDK 26.09.17 se pouze čte existence neprázdného
   `kv['account']`. Chyba čtení nesmí znamenat potvrzenou absenci účtu.
   SQLite BUSY/LOCKED/IOERR/unknown schema je `storeUnavailable` bez nabídky
   rotace; prokazatelné poškození zůstává odlišnou chybou. Bez account guard
   ověří `whoami` a nepřítomnost publikovaných device keys před ClientBuilder.
5. HTTP 401 obnoví běžný bootstrap pro stejné zařízení. HTTP 429/503 nebo
   nedostupný Keychain/DB nejsou důvod pro kryptografický reset.
6. Obnova místního store vyžaduje samostatné potvrzení. Existující autentizovaný
   COP bootstrap vytvoří nové Matrix deviceId/session. `whoami` musí potvrdit
   přesný Matrix user/device; čerstvá DB nesmí přepsat již publikované klíče.
7. Pending a selected deviceId jsou v nesekretní routovací evidenci oddělené
   podle issuer/client/COP origin/COP subject/installation. Pending se opakuje
   po přerušení, selected se potvrdí až po úspěchu. Selhání optional token cache
   po durable commit nesmí vytvořit další deviceId; restart získá token pro
   stejné selected ID. Generace v7 ani installation seed se plošně nemění.
8. Starý root, klíč, bootstrap, historie a outbox zůstávají zachované; nic se
   globálně nemaže. Staré Matrix zařízení není touto opravou revokováno.
   Případná cílená revokace je samostatný lifecycle krok. Zachování souborů
   není příslib, že bez původního klíče půjde starou historii dešifrovat.
9. Běžná obnova používá uživatelův recovery key a vyžaduje úspěch SDK recover
   a backup enablement. Klíč není persistentní ani v COP requestu/logu.
   Nové explicitně obnovované zařízení automaticky nevytváří cross-signing
   ani backup; tento režim drží per-root marker i po studeném startu.
10. Jen DEBUG a skutečný Info.plist Boolean `CSMAllowChatRecoveryWithoutBackup`
    umožní po potvrzení testovací pokračování bez obnovy staré historie.
    Missing/string/number a Release se nepovolují. Nejde o account-wide E2EE
    reset ani skryté launch argumenty. Nový testovací device nemusí být důvěryhodný
    pro ostatní zařízení; příjem jejich klíčů vyžaduje fyzickou E2EE akceptaci.

11. Typovaná diagnostika místního store prochází offline transportem až do modelu.
    Rozsah je provider/homeserver/Matrix user/device, nikoli rotující token.
    Pozdější HTTP či síťová chyba již potvrzenou chybu store nemaže. Změna
    rozsahu nebo úspěšné ověřené otevření/obnova ji vymaže; textové řetězce
    síťových chyb se nepovažují za důkaz porušení šifrování. Implicitní reopen
    používá stejnou revision-fenced configure cestu jako běžná inicializace.
12. Stejná explicitní obnova je dostupná v banneru, composeru, Stavu chatu
    a nabídce konverzace pouze pro typovanou chybu s permitsRecovery. Přechod
    ze Stavu chatu nejprve zavře jeho sheet; obnova se otevře po onDismiss.
    Žádná z těchto vstupních akcí sama nepotvrzuje obnovu ani nemaže data.

## Důsledky a hranice

Žádná změna REST, účetních dat, AI, mobilního routingu, CallKitu ani serverové
konfigurace. Sdílený host používá stejnou obnovovací obrazovku. Pokud čisté
zařízení s novým deviceId selže při síti/záloze, pending evidence a nový root
se zachovají pro retry; nepřidává se automatický destructive retry.

[Postup integrace a skutečně ověřené výsledky](../matrix-store-recovery-handoff.md).

Upstream: [SQLite account storage](https://matrix-org.github.io/matrix-rust-sdk/src/matrix_sdk_sqlite/crypto_store.rs.html),
[Matrix device login](https://spec.matrix.org/latest/client-server-api/#post_matrixclientv3login).
