# ADR 0008: Real VoIP Calls with PushKit and CallKit

- Status: accepted
- Date: 2026-07-11

## Context

Matrix voice calls work in the foreground web client, but ordinary APNs cannot
reliably wake a suspended or terminated iOS host in time to present an incoming
call. The existing COP wake endpoint already emits metadata-only incoming and
ended call events without SDP, ICE candidates, message plaintext or tokens.

## Decision

- COP Mobile registers a separate PushKit VoIP token together with its ordinary
  APNs token through the existing one-time registration-ticket flow.
- CSM Messaging sends only `chat.voice_call.incoming` and
  `chat.voice_call.ended` through APNs `voip` delivery and the
  `cz.zeleznalady.csm.messenger.voip` topic. Other notifications remain normal
  APNs alerts.
- Every incoming VoIP push is reported immediately to CallKit. Answer, reject
  and end actions are forwarded through the exact-origin Device Bridge and the
  existing host-to-chat command contract.
- Matrix remains the signalling and media owner. Native code owns wake-up,
  CallKit lifecycle and `AVAudioSession` routing only; it never receives Matrix
  credentials, SDP, ICE candidates or decrypted chat content.
- The `voip` background mode is used exclusively for real voice calls. It is
  forbidden for alarms, safety notifications, tracking or generic background
  execution.

## Consequences

- Calls can ring when the app is suspended or terminated by the system. A user
  force-quit still disables reliable relaunch until the app is opened again.
- The device must have completed VoIP-token registration while authenticated.
- Call acceptance can wait briefly for the WebView, OIDC session and Matrix
  client to restore; the native action is queued across the bridge handshake.
- APNs acceptance and CallKit presentation remain observable stages, not proof
  that Matrix media connected.

## Validation

- inspect the signed app for `voip` and `remote-notification` background modes;
- validate separate ordinary and VoIP tokens remain secret at every API layer;
- test incoming, answer, reject, remote end and audio-route changes on a
  physical device with the app foregrounded, suspended and terminated;
- confirm non-call notification types never use the VoIP topic or push type.

