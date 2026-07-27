# Belema SFP

Swing Failure Pattern (SFP) EA by Belema. This folder holds two separate
development branches of the same original strategy that diverged from a
common starting point rather than a single straight-line version history.

## Main branch (root of this folder)

| File | Version | What changed |
|---|---|---|
| `Belema SFP.mq5` / `Belema SFP V2.mq5` / `Belema SFP Test Version.mq5` | v1.00 | Base: multi-timeframe SFP levels, power candles, FVG (fair value gap) confirmation. |
| `Belema SFP V3.mq5` / `V4.mq5` | v1.01 | Adds a hedge control parameter. |
| `Belema SFP v5.mq5` | ~1.x | Intermediate iteration between the hedge-control and distance-filter changes. |
| `Belema SFP V6.mq5` / `V7.mq5` | v1.26 | Fixes the trade-distance filter to include pending orders; adds proximity cancellation for limit orders. |
| `Belema SFP V8.mq5` / `V9.mq5` / `V10.mq5` / `V11.mq5` | v2.0 | Bigger jump: adds Dynamic SL, partial closing, and a news filter, integrating trade-management features from the Power Pivot EA. |
| `Belema SFP V12.mq5` | v2.0 (comment says v12.0 - the version property tag wasn't updated) | Follow-up tweak on the v2.0 feature set. |
| `Belema SFP V13.mq5` | v13.0 | Further iteration; adds `tester_file` news cache. |
| `Belema SFP V14.mq5` | v14.0 | Adds `MovingAverages.mqh`, an execution-type enum, and further include dependencies (`OrderInfo.mqh`, `DealInfo.mqh`). |
| `Belema SFP Trial version.mqproj` | - | MetaEditor project file for `Belema SFP Trial version.ex5` (no `.mq5` source was present locally). |

## `Alex-DIAD-Branch/`
A separate fork of the same strategy that split off early (around the v2.x
feature set) and evolved independently, favoring scaling/trailing-stop
features over the main branch's dynamic-SL/news-filter direction:

| File | Version | What changed |
|---|---|---|
| `Alex DIAD (v2.1).mq5` | v2.1 | Adds a virtual ATR-based trailing stop; built with features from the Power Pivot EA v3.6. |
| `Alex DIAD - Belema SFP (v2.5).mq5` | v2.5 | Removes the "Runner" feature; adds an RR-triggered peak-drawdown exit. |
| `Alex DIAD - Belema SFP V2 (v2.6).mq5` | v2.6 | Stale-trade logic now applies per-position individually, and scaling can continue after a stale closure. |
| `Alex DIAD - Belema SFP V3 (v2.7).mq5` | v2.7 | Adds optional single-parameter exponential lot sizing. |

## Related but not merged here
- `Belema-SFP` logic is reused as the *trade management engine* inside several hybrid EAs elsewhere in this repo (`Limitless-EA-BB/Hybrid/`, `Limitless-EA-BB/Continuation/`, `Consolidation-Range-ADX/Hybrid/`) - those combine another strategy's entries with this SFP engine's management.
- `Ighodalo-Gold-CRT` and `Ighodalo-Orb` are explicitly "Based on Belema SFP EA" / reuse its position sizing, but implement different entry logic (CRT, Open Range Breakout) - different strategies, not versions of this one.
