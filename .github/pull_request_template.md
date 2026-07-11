## Summary

- Popište změnu a uživatelský/provozní dopad.

## Checks

- [ ] změna je úzce vymezená a reviewable
- [ ] relevantní testy a buildy prošly
- [ ] `bash scripts/validate-skeleton.sh` prošel
- [ ] Device API změna aktualizuje autoritativní COP schema a shared fixtures
- [ ] produkt/UX změna aktualizuje `docs/product-design.md`
- [ ] permissions/privacy změna aktualizuje příslušnou dokumentaci a store metadata
- [ ] background, storage, auth, bridge nebo relay rozhodnutí má ADR
- [ ] `.env.example` a provozní konfigurace zůstávají synchronní
- [ ] nebyl přidán secret, token, provisioning profil ani citlivý log
- [ ] neprovedené real-device testy jsou explicitně uvedeny

## Operational Impact

- Uveďte změny konfigurace, distribuce, oprávnění, rollbacku a otevřené brány.
