# ADR 0011: COP Mobile vlastní lokální komunikační balíček

## Status

Accepted — 2026-07-19

## Context

COP Mobile původně spotřebovávala `CSMCommunicationKit` z repozitáře velké
nativní aplikace. Připnutá Git revision sice dávala reprodukovatelný build, ale
nevytvářela skutečně samostatný produkt: odstranění, archivace nebo změna
přístupnosti původního repozitáře by znemožnila čisté sestavení COP Mobile.
Balíček navíc pocházel ze stromu obsahujícího mapu, reporty, relay, watch a další
obrazovky, které do tenké komunikační vrstvy nepatří.

## Decision

- COP Mobile vlastní kopii komunikační vrstvy v
  `packages/CSMCommunicationKit`.
- `apps/ios/project.yml` odkazuje výhradně na tento lokální Swift Package.
  Build ani runtime nepoužívají sibling `04 CSM messenger` ani jeho Git
  repozitář.
- Lokální `Package.swift` explicitně uvádí kompilované chatové obrazovky.
  Mapové, reportovací, relay, watch a původní aplikační SwiftUI obrazovky nejsou
  kopírovány ani kompilovány.
- Výchozí provenance snapshotu je
  `7fc3d3004c30865235f6cd6c075c6a764369b5a0`. Další synchronizace je ruční,
  reviewovaná a omezená na konkrétní komunikační změny.
- Produktové rozhodnutí zachovává bundle ID
  `cz.zeleznalady.csm.messenger`; stará aplikace jej už nebude používat.
- Automatická validace musí odmítnout Git/sibling závislost, vložený legacy
  Xcode projekt i návrat nepovolených aplikačních UI souborů do package targetu.

## Consequences

- COP Mobile lze čistě sestavit, testovat, archivovat a dále vyvíjet i po
  úplném odstranění původní velké iOS aplikace.
- Komunikační opravy mají vlastní review a release lifecycle společný s hostem,
  takže nevzniká skrytý upgrade z cizí větve.
- Bezpečnostní a licenční audit musí kontrolovat lokální snapshot i jeho přímé
  závislosti, zejména Matrix Rust SDK.
- Současný komunikační model ještě používá část interních typů `CSMCore`.
  Ty jsou implementační detail; případné další zmenšení jádra je bezpečný
  refactoring, nikoli podmínka samostatnosti.

## Validation

- čistý XcodeGen build resolving
  `packages/CSMCommunicationKit` z tohoto repozitáře;
- unit testy na iOS 26 simulátoru;
- fresh uninstall/install/launch simulátoru;
- `scripts/validate-ios-project.py` odmítne externí legacy dependency,
  vložený Xcode projekt a nepovolené legacy UI;
- vyhledání nesmí v aktivním projektu najít build cestu na
  `04 CSM messenger` nebo `CSM-messenger.git`.
