# Consolidation Range ADX

A range/consolidation-breakout EA gated by ADX. Originally based on
Zeiierman's `ZeiRangeADX` indicator concept, then rewritten into a full EA by
Ebuka, then further extended by Ighodalo. Everything in this folder is the
same lineage, not separate strategies.

## Version history

| File | Version | What changed |
|---|---|---|
| `Ebuka v2.mq5` | v2.5 | Base: `ZeiRangeADX.mq5` - "Consolidation Range with Signals", copyright "Zeiierman (Modified)". This is the indicator-turned-EA starting point. |
| `Ebuka EA.mq5` | v3.7 (stable) | Rewritten as `Ebuka_EA.mq5`, "Consolidation Range ADX-Only EA", synchronized to closed-bar logic. Copyright "Ebuka". |
| `Ebuka EA with plots.mq5` | v3.7 | Identical version to `Ebuka EA.mq5` with indicator plotting added on chart. |
| `Ighodalo Range Breakouts without plot.mq5` | - | Its header comment still says "Ebuka_EA.mq5 v3.7 (Stable Version)" (a stale copy-pasted header - the actual code differs substantially, ~400 vs ~285 lines), so treat the header as unreliable and the code as its own iteration rather than an exact copy. |
| `Ighodalo Range Breakout with plots.mq5` | v3.70 | Renamed internally to `Ighodalo Range Breakout.mq5`, copyright "Ighodalo Gold ERB". Same "with plots" idea, next generation. |
| `Ighodalo Range Breakout with plots reversed.mq5` | v3.71 | Same as above, plus flipped trade logic (buys on step-down, sells on step-up instead of the normal direction). |
| `Ebuka Range Breakout - Hedge.mq5` | v5.1 | Furthest evolved version: "Advanced Entries", adds a Breakout/Reverse/Both entry-style toggle and a unified retrace multiplier. Internally still named `Ighodalo Range Breakout.mq5`. |

## `Hybrid/`
- `Alex DIAD - Ebuka Range Breakout - Hedge.mq5` - explicitly "Combined EA: Entries from Ighodalo Range Breakout, Management from Belema SFP" (copyright "Combined by Grok"). Takes this family's entries and manages trades with the Belema SFP engine instead - a hybrid, not a version bump.
