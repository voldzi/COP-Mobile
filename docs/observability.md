# Observability a diagnostika

## Stav

COP Mobile má samostatný iOS 26 runtime a lokální komunikační balíček.
Mobilní aplikace neposkytuje `/health`, `/ready`, metrics endpoint ani vlastní
backend. Běžící verze používá redigovaný `OSLog`; kritické operace nativního
chatu mají navíc Instruments signposty. Centrální telemetry backend zatím není
schválený, proto se detailní provozní data neodesílají mimo zařízení.

## Principy

- Observability měří uživatelský a technický výsledek bez doménového payloadu.
- Přesná poloha, heading/attitude samples, text zpráv/hlášení, fotografie,
  dokumenty, cookie/tokeny, APNs token a raw identity se nikdy neposílají.
- Release používá Apple unified logging/`OSLog` s privacy redaction a bounded
  lokální diagnostický snapshot. Debug může být podrobnější, ale nikdy neloguje
  secrets nebo payload.
- Telemetry je samostatné privacy rozhodnutí. Bez schváleného backendu, consentu,
  retence a App Privacy deklarace zůstává pouze lokální redigovaná diagnostika.

## Structured fields

Každý technický záznam používá podle dostupnosti:

```text
timestamp, level, subsystem, category, operation, outcome, errorCode,
durationMs, appVersion, appBuild, webBuildId, protocolVersion,
environment, correlationId
```

Zakázaná pole zahrnují souřadnice, route parametry obsahující uživatelská data,
asset filename/content/MIME metadata nad nezbytnou kategorii, tokeny a
persistentní user/device/peer ID. OSLog privacy annotation je defense in depth,
ne oprávnění hodnotu zaznamenat.

## Correlation

- Bridge request dostane náhodný request/correlation ID; session ID se používá
  jen v paměti a do dlouhodobé telemetry se neposílá celé.
- Web může correlation ID přenést do existujícího COP `X-Correlation-Id` toku.
  Native host nesmí vytvářet nový doménový audit ani přepisovat serverový ID.
- Push používá opaque `notificationId`; APNs acceptance, presentation, open a
  server/user ACK jsou samostatné eventy.
- Asset, outbox a pozdější relay korelace používají opaque ID a nikdy se
  neinterpretují jako serverové doručení.

## Aktuální nativní chat signposty

Kategorie `ChatPerformance` používá Points of Interest signposty bez obsahu
zpráv, identit nebo názvů souborů. Release profiling sleduje minimálně:

```text
conversation-list-local
cached-conversation-open
chat.local-echo
timeline-presentation
```

Signpost zaznamenává pouze začátek, konec a dobu operace. Překročení rozpočtu
vytvoří redigované lokální warning hlášení. Rozpočty jsou release gate:

| Operace | p95 cíl |
|---|---:|
| lokálně uložený seznam konverzací | 700 ms |
| otevření cached konverzace | 200 ms |
| lokální echo | 100 ms |
| tap/context menu a přepočet prezentace | 100 ms |
| dlouhé blokování hlavního vlákna | žádné ≥ 250 ms |

XCTest měří deterministickou část reduceru a prezentace. Instruments ověřuje
scroll, otevření klávesnice a main-thread hangs na sestavení pro skutečné
zařízení; samotný unit test nenahrazuje renderovací měření 60 fps.

## Navržené agregované metriky

Bez high-cardinality labels:

```text
app_start_total{result}
app_start_duration_ms{mode}
webview_navigation_total{result,originClass}
bridge_handshake_total{result,majorVersion}
bridge_request_total{method,result}
bridge_request_duration_ms{method}
bridge_validation_error_total{code}
permission_flow_total{permission,result}
location_sample_age_ms{mode}
heading_invalid_total{reason}
attitude_unavailable_total{reason}
tracking_session_total{transition,result}
tracking_sample_store_items
tracking_sample_store_bytes
share_import_total{kind,result}
share_inbox_items
share_inbox_bytes
notification_event_total{type,result}
offline_boot_total{mode,result}
web_cache_recovery_total{result}
chat_cached_open_duration_ms
chat_local_echo_duration_ms
chat_timeline_presentation_duration_ms
chat_outbox_replay_total{result}
chat_timeline_duplicate_total
chat_offline_message_loss_total
chat_history_page_load_duration_ms
chat_media_prepare_duration_ms{kind}
```

Relay metriky se do produkčního MVP nepřidávají. Laboratorní build později
použije queue bytes/items, peer connections, deduplicated/expired/hop-limit a
transfer result bez peer identity nebo payloadu.

## Operational state místo health endpointu

Diagnostika rozlišuje:

- host process a app/web build;
- WebView main-frame origin a navigation state;
- bridge handshake/version/last safe error;
- COP backend reachability oddělenou od network path;
- permission a capability snapshot;
- active tracking state, poslední sample age/accuracy bucket a queue count/bytes;
- Share inbox count/bytes/oldest-age bucket;
- notification authorization včetně sound/Time Sensitive/Critical setting;
- production feature flags a policy gates.

Zobrazuje bucket/boolean, ne přesné souřadnice, filename, token nebo peer.
Diagnostický panel je debug/internal-only nebo chráněný admin policy; běžný
uživatel vidí pouze srozumitelný provozní stav a nápravu.

## Alerts a release monitoring

Po zavedení schválené telemetry mají alertovat zejména:

- skok `app_start` nebo handshake failure po native/web release;
- nárůst `ORIGIN_NOT_ALLOWED`, schema/protocol mismatch nebo crash/hang;
- APNs registration/delivery degradation v CSM Messaging;
- cached-start/fallback regression;
- překročení p95 rozpočtu seznamu, cached open, local echo nebo prezentace;
- jakákoli duplicita po reconnectu nebo ztracená offline zpráva;
- hang hlavního vlákna ≥ 250 ms nebo regrese 60fps scrollu;
- tracking session končící bez user Stop nebo rostoucí store/quota;
- Share inbox cleanup failure nebo storage exhaustion;
- privacy redaction/secret scan failure — vždy release blocker.

Prahy se stanoví až z pilotních dat; dokumentace nesmí vymyslet SLO bez
měření. Dashboard koreluje app build, web build a backend environment, aby se
odlišil native a remote-web rollback.

## Crash a diagnostic export

- Crash reporter třetí strany vyžaduje SDK/privacy review; bez něj se používají
  Apple/TestFlight crash reports.
- Před uploadem se odstraňují breadcrumbs s route/payloadem a user-entered text.
- Uživatelský diagnostický export je explicitní, zobrazí náhled kategorií a
  obsahuje verze, capability, error codes a agregované counts, nikoli raw logy
  nebo lokální databáze.
- Retence a příjemce exportu musí být popsány privacy policy před produkcí.

## Ověření

Testy vloží canary secrets, souřadnice, filename, Unicode text a token-looking
hodnoty do všech kritických cest a potvrdí jejich absenci v OSLog, crash reportu,
metrics labels a exportu. Artifact review navíc ověří, že release neobsahuje
debug panel, inspector, interní originy ani hardcoded credentials.
