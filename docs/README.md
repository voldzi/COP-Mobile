# COP Mobile Documentation

Toto je aktivní dokumentační sada pro tenký nativní host COP. Historické a
překonané analýzy patří do `archive/`.

## Aktivní dokumenty

| Dokument | Účel |
| --- | --- |
| [repository-assessment.md](repository-assessment.md) | Ověřený stav COP, starého nativního klienta, mezery a doporučený postup |
| [implementation-plan.md](implementation-plan.md) | Fázovaný, repository-aware postup a akceptační brány |
| [architecture.md](architecture.md) | Hranice web/native, komponenty, data flow a deployment |
| [product-design.md](product-design.md) | Uživatelé, journeys, systémové surface a UX pravidla |
| [api.md](api.md) | Konzumovaná REST API a veřejný COP Device API/bridge kontrakt |
| [security.md](security.md) | Threat model, auth, bridge, storage, push a relay brány |
| [permissions-and-privacy.md](permissions-and-privacy.md) | Permission matrix, consent, retence a store deklarace |
| [test-strategy.md](test-strategy.md) | Contract, unit, integration, UI a real-device akceptace |
| [operations.md](operations.md) | Prostředí, konfigurace, build/release model a rollback |
| [observability.md](observability.md) | Privacy-safe logy, metriky, diagnostika a korelace |
| [runbook.md](runbook.md) | Konkrétní provozní a testovací scénáře |
| [open-questions.md](open-questions.md) | Zbývající rozhodovací a externí brány |
| [adr/](adr/) | Architektonická rozhodnutí |
| [archive/](archive/) | Historické a superseded materiály |

## Kontraktová autorita

COP Mobile neposkytuje REST API, a proto nemá vlastní `openapi/openapi.json`.
Autoritativní COP REST kontrakt je `01 COP/openapi/openapi.json`. Autoritativní
Device API schémata a TypeScript web SDK budou vznikat v COP repozitáři; tento
repozitář spotřebuje připnutý export a ověří stejné fixtures ve Swiftu a později
v Kotlinu.

## Pravidla údržby

- Jeden aktivní dokument na téma; nepřidávat varianty typu `architecture 2`.
- Změna bridge, auth, storage, background režimu, permissions, distribuce nebo
  relay vyžaduje aktualizaci příslušného dokumentu a ADR.
- Neověřený experiment ani simulátorový výsledek se nesmí popsat jako
  produkční nebo fyzicky ověřený stav.
- Dokumentace musí rozlišovat současný skeleton, plánovanou implementaci a
  externí brány, které tým ani kód nemůže sám schválit.
