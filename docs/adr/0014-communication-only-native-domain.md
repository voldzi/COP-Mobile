# ADR 0014: Nativní balíček vlastní pouze komunikaci

## Status

Accepted — 2026-07-20

## Context

COP Mobile je tenký hybridní host. Webová část COP již autoritativně poskytuje
mapu, hlášení, vrstvy a ostatní business workflow, zatímco iOS musí spolehlivě
poskytnout chat, hovory a capability zařízení. Převzatý komunikační balíček
však stále obsahoval víceúčelový `AppModel` a kompiloval mapové, reportovací,
relay, radio-planning a watch zdroje. I při přepínači `communicationOnly` tak
existovala druhá nativní doménová implementace, širší invalidace SwiftUI stavu
a nejasné vlastnictví navigace a push akcí.

## Decision

1. `CSMCommunicationKit` používá jediný `CommunicationModel`. Původní
   víceúčelový `AppModel` se odstraňuje bez kompatibilní vrstvy.
2. Komunikační model vlastní pouze:
   - nativní OIDC session a bezpečnostní odemknutí;
   - registraci APNs/VoIP zařízení a komunikační push;
   - Matrix bootstrap, E2EE recovery a crypto-store lifecycle;
   - seznam konverzací, stránkovanou timeline, reakce, média a offline outbox;
   - direct-call řídicí kontrakt.
3. Mapová data, hlášení, vrstvy, radar, offline mapové balíky, relay runtime,
   radio plánování a watch synchronizace nejsou součástí komunikačního targetu.
4. Senzory telefonu, oprávnění, lifecycle a WebView vlastní aplikace
   `apps/ios`. Web je používá výhradně přes verzovaný Device bridge.
5. Deep link nebo akce z chatu směřující k mapě či hlášení pouze předá
   navigační destinaci webovému hostu. Nativní chat nenačítá ani neukládá
   odpovídající doménový stav.
6. Projektový validátor blokuje návrat `AppModel.swift`, odstraněných
   cross-domain zdrojů a map/report/relay/watch vlastnictví v
   `CommunicationModel`.

## Consequences

### Positive

- výsledná aplikace má jednoznačnou hranici web versus native;
- změny mapy a hlášení nemohou invalidovat chat ani spouštět jeho bootstrap;
- komunikační target kompiluje méně zdrojů a má menší prostor pro regresi;
- webová a mobilní varianta používají stejné COP workflow bez paralelního
  nativního formuláře;
- aplikace zůstává samostatná a nemá build ani runtime závislost na původní
  velké iOS aplikaci.

### Negative

- nativní chat nemůže offline zobrazit mapu ani upravovat hlášení; tuto
  zkušenost musí pravdivě řešit webový host a jeho cache;
- sdílené API modely zatím obsahují několik relay/report datových kontraktů
  potřebných smíšeným COP klientem, ale žádný odpovídající runtime se
  nekompiluje ani neinicializuje.

## Verification gate

- generické iOS sestavení musí projít bez `AppModel.swift`;
- `scripts/validate-ios-project.py` musí blokovat cross-domain regresi;
- přihlášení, otevření cached chatu, odeslání, reconnect, push, E2EE recovery a
  direct call musí zůstat pokryté komunikačními testy;
- otevření funkce mimo chat musí přepnout na webový COP bez vytváření
  nativního mapového nebo reportovacího stavu.
