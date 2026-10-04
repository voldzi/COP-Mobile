# Shared vehicles and private Dispatch SDK

Date2026-10-04. Public source contract published separately from production and
physical-device acceptance. COP binding: shared-mobility-v1.openapi.json in COP.
Public facades: CSMMobility.swift, CSMMobilityContracts.swift,
CSMDispatchEncryption.swift. No host access to CSMCore or arbitrary HTTP/token
bridge. Existing PKCE login and Keychain access remain owned by the SDK.

Use mobilitySessionScope for stable account-scoped vehicle outbox. Each transport
captures a separate session generation; logout/relogin to the same account rejects
late responses. Observe csmMobilitySessionChanged and clear UI/in-memory GPS.
Create/accept wrappers contain exact operationId,confirmed and vehicle/group;
invitation queued receipts do not imply vehicle data revisions or SMTP delivery.
Email-verified identity from server is required for inbox acceptance.

Instantiate CSMDispatchEncryption(expectedScope:) and registerDevice(name:) before
readiness. The facade owns account-specific X25519 private keys in non-syncing
WhenUnlockedThisDeviceOnly Keychain; no private key is returned. Registration
operation/key/name survive retries. Device revoke clears key only after confirmed
server response. A session notification permanently invalidates the object.

Keep explicit consent/local zones in Jízda. Never auto start or restore sharing.
Seal fresh actual CLLocation through sealGPS; do not serialize coordinates in
Dispatch HTTP. Publish only ciphertext, no GPS retry queue. For received markers,
openPoint inside a fresh authoritative snapshot. Hide all previous markers on
changed activeShares/sequence, stop, expiry, account/key/roster change. Mark age>60s
stale and hide age>180s; refresh time does not replace observation time.

Use dispatchOwnedShares only to find and stop an orphaned start/pending stop.
Persist only stop/start operation identifiers, never GPS; keep pending-stop barrier
until confirmed:true. No restart, reconnect or login restores consent. Private
zone entry sends stop reason only, never zone geometry. Existing conversation
list/native direct calls stay separate; group voice/PTT is not implemented here.

Cipher uses ephemeral-recipient and sender-static-recipient X25519, HKDF-SHA256,
AES256-GCM. SaltSHA256(lowercase shareUUID UTF8), info
cop-dispatch-point-v1-authenticated. AAD sorted JSON: protocol,groupId,shareId,
senderDeviceId,recipientDeviceId,audienceHash,membershipRevision,sequence,observedAt.
No location history is stored in COP DB/logs/backups/SIM; latest ciphertext stays
in API RAM up to180s plus5s cleanup. COP directory is the trust anchor; this is
not independent human device verification. Server restart invalidates all shares.

Toolchain exactpin updated by explicit human approval to Xcode27.1/build27A9269,
SDK27.1. Test/build evidence and actual deployed COP revision are recorded in COP
handoff29. Simulator checks never establish physical background/network acceptance.

A timed-out start may commit after a GET snapshot. Before abandoning/recovering a
pending start, call dispatchCancelStart(operationId:newCancellationUUID,
startOperationId:persistedStartUUID) under its original account scope. The server
serializes a persistent cancellation tombstone against start and stops any already
committed share. Confirmed cancellation blocks a late request from reviving
consent, even across restart. ownedShares supplements this barrier, not replaces it.

Participant chat/call uses dispatchParticipantConversation(groupId,accountId,
request,expectedScope), with a server-verified active roster and exact encrypted
direct conversation. openDispatchParticipantConversation selects that result in
CSMCommunicationHost. Existing explicit startVoiceCall(roomID:) remains separate;
no call starts automatically and no group room/PTT is created. Voice keeps its
existing server-authorized LiveKit transport; map encryption is not a claim that
voice media is server-blind E2EE.
