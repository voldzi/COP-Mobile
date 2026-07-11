# Observability a diagnostika

## Stav

Ve fázi 0 neexistuje runtime. Níže uvedené názvy jsou závazný návrh pro první
iOS 26 implementaci, nikoli tvrzení o aktuálně emitovaných datech. Mobilní
aplikace neposkytuje `/health`, `/ready`, metrics endpoint ani vlastní backend.

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

## Navržené metriky

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
