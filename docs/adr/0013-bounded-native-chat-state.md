# ADR 0013: Omezený a obrazovkově vlastněný stav nativního chatu

## Status

Accepted — 2026-07-20

## Context

Původní komunikační model soustředil přihlášení, seznam konverzací, otevřenou
timeline, synchronizaci, offline frontu, média i prezentační transformace do
jednoho širokého `AppModel`. SwiftUI proto sledovalo změny, které s aktuální
obrazovkou nesouvisely, a opakovaně třídilo a seskupovalo celou historii.
Timeline se načítala jako neomezené pole, média se mohla materializovat do
paměti a souběžný stream/polling měl více cest pro stejnou událost.

Takové uspořádání není přijatelné pro cílové místnosti s tisíci zprávami,
offline restart, reconnect bez duplicit a plynulý iOS 26 povrch.

## Decision

1. Veřejný `CSMCommunicationHost` zůstává jediným vstupem aplikace. Uvnitř
   komunikačního balíčku jsou odděleny:
   - `ChatSessionStore` pro nativní session a aktivní účet;
   - `ConversationListStore` pro malé immutable snapshoty seznamu;
   - `TimelineStore` pro jedinou právě otevřenou místnost;
   - čistý `TimelineReducer` jako jediná cesta pro replace, upsert, potvrzení,
     reakci a smazání;
   - `OutboxActor` nad perzistentní šifrovanou frontou se stabilním
     `transactionId`;
   - `MediaPipelineActor` pro file-backed přípravu mimo hlavní actor;
   - `SearchIndex` pro průběžný index otevřeného okna;
   - `TimelineSynchronizationController` pro právě jeden stream nebo
     kontrolovaný polling fallback.
2. SwiftUI obrazovka vlastní `ChatTimelinePresentationStore`. Seskupování,
   filtrování a tvorba řádků běží pouze při změně revision nebo dotazu a mimo
   hlavní actor. `body` nedostává neomezenou doménovou timeline.
3. V paměti se drží nejvýše 500 zpráv otevřené místnosti. Lokální historie je
   šifrovaná po stránkách, výchozí stránka má 200 zpráv a starší data se načítají
   explicitně. Při posunu do starší historie se omezené okno posune ke starším
   datům a označí, že existují novější zprávy; uživatel se může jednou akcí
   vrátit na nejnovější okno. Doplnění stránky zachová vizuální anchor místo
   skoku timeline.
4. Velké odchozí přílohy jsou file-backed. UI a upload pracují s URL; celý
   soubor se nevkládá do observable state.
5. Stream a polling nesmí běžet paralelně. Polling se zapne jen jako fallback
   po nedostupném nebo ukončeném streamu a generation token odmítne stale
   výsledek předchozí místnosti.
6. Veřejné uživatelské chyby jsou stručné. Technický detail patří pouze do
   redigovaného logu.
7. Výkonnostní limity jsou release gate, nikoli doporučení:
   cached seznam do 700 ms p95, cached konverzace do 200 ms p95, local echo a
   interakce do 100 ms p95, žádný hang hlavního vlákna alespoň 250 ms,
   60 fps textový scroll, nula duplicit po reconnectu a nula ztracených offline
   zpráv.

## Consequences

### Positive

- změna mapy, profilu nebo registrace zařízení neinvaliduje timeline;
- reducer poskytuje jedno deterministické místo pro deduplikaci;
- restart a reconnect používají stejný stabilní transaction ID;
- paměť a čas renderu nezávisí na celkové délce místnosti;
- UI může používat standardní `NavigationStack`, systémová menu, Dynamic Type,
  VoiceOver a iOS 26 Liquid Glass pouze v navigaci a ovládání.

### Negative

- full-text hledání mimo načtené okno vyžaduje samostatný serverový nebo
  perzistentní index;
- velká místnost vyžaduje explicitní stránkování a anchor-safe doplnění řádků.

## Verification gate

- fixtures 1, 100, 1 000 a 10 000 zpráv;
- náraz 100 událostí a opakované doručení bez duplicity;
- offline enqueue, restart store, reconnect a právě jedno potvrzení;
- stránkování šifrované historie;
- file-backed velká příloha bez vložení payloadu do modelu;
- E2EE recovery a souběžná reakce z webu;
- Instruments/MetricKit kontrola scrollu, paměti a main-thread hangs na
  podporovaném fyzickém iPhonu.
