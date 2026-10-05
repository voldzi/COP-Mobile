# Verified COP and Matrix identities; read-only lookup

Status: implemented; publication and production acceptance pending. No real-account, conversation-membership or voice-call mutations are acceptance steps.

## Contract and authorization

`POST /api/v1/messaging/matrix/identities/lookup`, authenticated COP request, body only `{"conversationId":"..."}`. Actor comes exclusively from verified COP auth. Arbitrary user IDs, actor names and message/content fields return400. Existing `/resolve` retains its provisioning semantics and must never be used as a fallback for lookup.

COP calls Messaging server-to-server `/api/v1/matrix/identities/lookup` using the existing service token and derived actor header. Messaging additionally requires a service-token-authenticated caller with an explicit actor ID, then checks that actor's current membership through `Conversations.get`. It reads only existing entries through `MatrixIdentityStore.lookup_existing`; no `get_or_create`, Synapse admin API, password write, reactivation, identity creation or persistence occurs. Missing entries are explicitly unresolved. No names, tokens, passwords, chat content or account enumeration are returned.

Response `cop-messaging-identity-lookup-v1`: `providerId=csm.messaging`, `status=online`, `warnings=[]`, `actorUserId`, `conversationId`, optional `matrixRoomId`, `identities=[{userId,matrixUserId}]`, `unresolvedUserIds`, `validUntil` (UTC,30seconds). Pair keys and Matrix server/localpart are exact, case-sensitive identifiers. Members partition into pairs or unresolved IDs, unique at most100. Mappings describe stored bindings; they do not prove a Synapse account remains active. COP rejects malformed/wrong-scope/conflicting upstream responses with503. Nonmember403, absent conversation404, timeout/disabled/outage503; anonymous401. Response `Cache-Control:no-store`. Route budget120/minute follows existing rate-limiter identity/IP semantics; no new auth bypass.

SDK validates actor, conversation, actual Matrix room, full COP membership snapshot, own bootstrap Matrix ID, one-to-one mapping and expiry. It never guesses aliases by stripping `cop_`/hash/server or matching names. The mapping is ephemeral and excluded from Codable conversation caches. Auth/account changes invalidate in-flight list results. With missing/partial/conflicting mappings the Matrix enricher keeps COP's membership snapshot rather than concatenating two transport namespaces. Direct peer requires exactly one other member and a recognized self; ambiguous peers are unavailable and same titles do not merge unrelated chats. Server namespace and case are preserved.

## Viewer-specific call presentation

Existing voice call response adds optional `call.peer={subjectId,displayName?}`. COP derives the exact other one-to-one participant for the authenticated viewer and reads that COP profile without mutation. No username/title/Matrix-localpart guess and no browser-selected peer. Absent/failed profile read retains only the known subject ID. Unauthorized or multi-party call produces no peer. Existing shared `title` remains unchanged for compatibility; it can contain the callee's name and is not an incoming caller identity.

SDK `CSMVoiceCall.presentationTitle` validates `peer.subjectId` against the expected other participant. Incoming API calls without a confirmed name show generic `COP kontakt`. First incoming APNs announcement continues using explicit server-owned `senderDisplayName`; after API reconciliation the temporary push title is discarded. Media, signaling, auth, CallKit and PushKit policies are unchanged.

## Rollout and acceptance

Roll out Messaging lookup first, then COP API, then SDK pin. Images extend the exact running images, replacing only tested runtime files. Preserve existing APNs ticket and vehicle audit/profile fixes, env/secrets/compose/networks and other services. Rollback to the immediate prior images is schema-safe: no writes or migrations are introduced; SDK handles404/503 by using existing metadata without speculative aliases. Public pins and actual image/runtime proof are appended after deployment.

Tests: isolated two-user lookups, missing/conflicting mappings, authorization and scope, no store mutations/secrets, exact outbound lookup path/body (never resolve), server outage, metadata/Matrix identity dedup, self-peer ambiguity, account mismatch, expiry, changed membership, no mapping persistence, viewer-specific caller/callee distinction and APNs field precedence. Full regression and approved Xcode27.1 gate are required. Actual two-phone incoming calls/member presentation remain separate physical acceptance; synthetic tests do not prove it.

The new lookup is internal to CommunicationModel refresh; hosts must not implement localpart/name alias guessing. SDK CSMVoiceCall adds optional peer and presentationTitle; use presentationTitle for API-reconciled incoming caller UI. The old title retains compatible serialization. App Review/China voice policy is unchanged by this release.
