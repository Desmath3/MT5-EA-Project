# Limitless EA BB

A Bollinger Bands reversal EA. This is the single longest-running lineage in the
repo: it started life as `BB_ReversalEA.mq5` in 2021, got rebranded under
Ighodalo's name in 2025, and was later renamed "Limitless EA BB" as it grew a
news filter, session filters, and progressively more advanced exit logic. All
of the files below are the *same strategy* at different points in that
history - nothing here is a separate idea, just successive rewrites.

## Version history (oldest to newest)

| File | Era / version | What changed |
|---|---|---|
| `EA BB 2025.mq5` / `EA BB V3.mq5` | 2021, "[Your Name]" copyright | Original `BB_ReversalEA.mq5` base: BB reversal entries, slippage/magic number inputs. |
| `EA BB 2025 PV.mq5` | 2021 | A parameter/pivot variant of the same base. |
| `EA BB 2025 v2.mq5` | 2025, Ighodalo | First Ighodalo-owned copy of the same base (copyright changed, logic mostly unchanged). |
| `EA BB V4.mq5` | 2021→2025 | Renamed internally to `EA_BB_V4_fixed.mq5`; adds a session start-hour input. |
| `Ighodalo EA BB 2025.mq5` / `Ighodalo EA BB 2025 v2.mq5` | 2025, Ighodalo v1.4 | Adds `TradeNewYork` session toggle on top of the 2025 rebrand. |
| `Limitless EA BB 2025.mq5` | 2025, Ighodalo | Renamed "Limitless" but content-identical generation to the `Ighodalo EA BB 2025` files. |
| `Limitless EA BB V2.mq5` | v4.28 | First version under the "Limitless EA BB Vx.xx" internal numbering. Power-candle confirmation, multi-timeframe filters. |
| `Limitless EA BB V3.mq5` / `V4.mq5` | v4.35 | Fixes an "Unsupported filling mode" partial-close error. (`V4.mq5` is byte-identical to what was previously duplicated as `Ighodalo EA BB V3.mq5` - the duplicate was dropped.) |
| `Limitless EA BB V5.mq5` | v4.35 | Minor follow-up tweak on V4. |
| `Limitless EA BB V6.mq5` / `V7.mq5` / `V8.mq5` | v4.36 | Adds an opposite-BB exit alongside ATR-based partial closes; replaces the old "long loss" exit. |

## `Continuation/`
Same engine, but the entry logic breaks out of an extreme Bollinger Band and
enters on the retrace to the middle band, instead of trading reversals at the
band extremes:
- `Limitless EA BB Continuation V1.0.mq5` - the native continuation entry, own trade management.
- `Alex DIAD - Limitless EA BB Continuation.mq5` - the same continuation entry logic, but with its trade management swapped out for the Belema SFP scaling engine (v2.7). A hybrid, not a straight version bump.

## `Hybrid/`
- `Alex DIAD - Limitless EA BB.mq5` - takes this family's BB reversal *entries* and manages trades with the Belema SFP scaling engine instead of this family's own management. Copyright "Belema & Ighodalo".

## Related but not merged here
- **Ighodalo Gold Milker** (`../Ighodalo-Gold-Milker/`) shares origin with `BB-Martingale`, not this family.
- **Ighodalo SuperTrend Reversal** (`../Ighodalo-SuperTrend-Reversal/`) is a direct fork of this family's v4.36 - same engine, but Bollinger Bands were ripped out and replaced with SuperTrend bands. See that folder's README for the fork point.
