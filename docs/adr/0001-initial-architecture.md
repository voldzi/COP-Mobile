# ADR 0001: COP Mobile jako tenký nativní host

## Status

Accepted — 2026-07-11

## Context

COP již má vyspělou webovou/PWA aplikaci s mapou, chatem, OIDC, doménovým
workflow, offline snapshotem a API. Mobilní zařízení ale nabízí funkce, které
web neumí poskytovat dostatečně spolehlivě: přesnou polohu a kompas, explicitní
background tracking, systémový příjem souborů, push/lokální notifikace,
chráněné technické úložiště a později device-to-device transport.

Existující sibling projekt `04 CSM messenger` řeší problém plně nativní
aplikací. Duplikuje mapu, chat, Matrix klienta, report workflow a doménové
modely, cílí na iOS/watchOS 27 a nemá WebView Device bridge. Pokračování touto
cestou by vytvořilo dvě business implementace s rozdílným releasem a chováním.

První produktová platforma má závazné minimum iOS/iPadOS 26.0; Android bude
následovat.

## Decision

1. `06 COP Mobile` bude samostatný aplikační repozitář pro tenké nativní
   hosty. První target bude univerzální iPhone/iPad aplikace s minimem
   iOS/iPadOS 26.0, Swift 6 a stabilním Xcode/SDK.
2. COP web zůstane jediným vlastníkem UI, mapy, chatu, business logiky,
   doménových modelů, doménového outboxu, autorizace a report workflow.
3. iOS host bude tvořit SwiftUI shell, `WKWebView`, bezpečný verzovaný bridge,
   nativní služby zařízení, Share Extension a chráněné technické úložiště.
4. Nativní host poskytne capability namespaces pro system/permissions,
   location, heading, foreground attitude, durable tracking, connectivity,
   media, shares a notifications. Relay je samostatná pozdější experimentální
   capability.
5. JSON Schema, TypeScript `CopDevice` SDK a společné fixtures budou
   autoritativně spravovány v `01 COP`. Mobilní repozitář bude spotřebovávat
   připnutou verzi a validovat Swift modely stejnými fixtures.
6. Web bude vlastnit OIDC relaci v persistentním WebKit origin storage. Nativní
   host nebude implementovat paralelní login ani kopírovat webové access/refresh
   tokeny.
7. Background tracking bude samostatná native-owned session, nikoli životnost
   JavaScript subscription. Start/stop musí provést uživatel a host bude
   komunikovat skutečná systémová omezení.
8. `04 CSM messenger` zůstane referenčním prototypem. Lze z něj po auditu
   převzít izolované technické patterns a fixtures, ne UI, business core,
   Matrix klienta ani doménové modely.
9. Android použije stejný Device contract. Nebude podmínkou pro první iOS
   TestFlight pilot.
10. Relay/mesh nebude součástí MVP, bude defaultně vypnutý a nesmí přenášet
    produkční citlivý obsah před samostatným threat model, identity, key
    management a cross-platform real-device gate.

## Consequences

### Positive

- COP web a backend zůstávají jediným zdrojem business chování.
- Oprava nebo nová webová funkce se nemusí implementovat podruhé ve Swiftu a
  Kotlinu.
- Nativní attack surface je omezený na explicitní capability a technická data.
- iOS a budoucí Android mohou sdílet wire contract a fixtures bez sdílení
  platformního kódu.
- Samostatný repo/release lifecycle odděluje App Store signing od COP web
  deploymentu.

### Negative

- Dostupnost hlavního UI závisí na kompatibilitě remote web buildu, WebKit cache
  a bridge verze.
- Web musí nově umět capability-based UX a později vlastní offline outbox.
- Některé funkce vyžadují změny ve více repozitářích a koordinovaný rollout.
- WebView, OIDC a service-worker chování musí být ověřeno na fyzických
  zařízeních, ne jen simulátorem.

### Required follow-up

- realizovat contract packages a browser/mock adapter v `01 COP`;
- implementovat jednorázový COP/CSM device-registration ticket před remote push;
- doplnit webový report outbox před tvrzením offline write podpory;
- před media uploadem uzavřít bezpečný binary handoff contract;
- zmrazit rozšiřování `04 CSM messenger` jako paralelního klienta po dosažení
  thin-host akceptačního baseline.

## Alternatives Considered

### Pouze PWA

Odmítnuto: nestačí pro Share Extension, spolehlivý push/deep-link lifecycle,
explicitní durable background tracking a budoucí lokální transport.

### Pokračovat v plně nativním 04 CSM messenger

Odmítnuto: duplikuje mapu, chat, auth, reporty a doménový stav; současný target
je iOS 27 a systémová hranice neodpovídá thin hostu.

### Capacitor nebo obecný hybrid framework

Odmítnuto pro první baseline: požadované Share Extension, background tracking,
push a budoucí relay by stejně vyžadovaly vlastní platformní pluginy. Přidaná
runtime vrstva by nezrušila potřebu explicitního secure bridge a komplikovala
by současný remote HTTPS origin, OIDC a PWA cache.

### Zabalit plný web artifact od první verze

Odloženo: build je staticky distribuovatelný, ale lokální origin mění OIDC,
CORS, service worker, asset routing a release coupling. ADR 0003 volí nejprve
remote HTTPS + cache + lokální fallback.

## Security and Privacy Impact

Nativní capability výrazně zvyšují dopad XSS nebo kompromitované webové
dependency. Každá operace proto musí procházet versioned bridge, exact-origin a
main-frame kontrolou, schema/method allowlistem, permission/capability policy,
rate a size limitem. Trusted origin není trusted payload.

Přesná poloha, share inbox, assety a tracking samples jsou chráněná technická
data s kvótou a retenční politikou. Nesmějí vstoupit do release logů ani
telemetry. Webové auth tokeny zůstávají ve WebKit storage a APNs token native +
CSM Messaging.

## Validation

Rozhodnutí je splněno pouze pokud:

- iOS host nezobrazuje žádnou nativní kopii mapy, chatu nebo report workflow;
- stejný COP web build funguje v browseru/PWA a hostu;
- webové contract testy projdou s browser, mock a native adaptérem;
- Swift decoder projde společnými valid/invalid fixtures;
- reload WebView ukončí session subscriptions, ale neztratí stav explicitní
  tracking session;
- fresh-install offline stav ukáže lokální fallback místo prázdné WebView;
- žádný release artifact neobsahuje iOS 27-only produkční závislost.
