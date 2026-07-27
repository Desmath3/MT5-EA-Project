# Saro Trades

A Martingale-style DCA/scale-in EA that evolved significantly across its
version history, including a structural shift from single-file to modular.

| File | What changed |
|---|---|
| `Saro Trades.mq5` | V1 base: Martingale lot multiplier, max steps. |
| `Saro Trades V2.mq5` | Adds `EnumToString` helper fixes for compile errors (no logic change beyond that). |
| `Saro Trades V3.mq5` | Adds an ATR multiplier to the Martingale step sizing. |
| `Saro Trades V4.mq5` | "V3 Simplified with DCA" - reworks V3 into a simpler DCA-based structure, adds magic number/slippage input group. |
| `Saro Trades V5.mq5` | "DCA + Scale-in" - adds a proper scale-in system on top of V4's DCA base. |
| `Saro Trades V7 G.mq5` | Internally labeled "Saro Trades V6" despite the V7-ish filename - a "General Settings"-grouped input variant of the DCA+Scale-in engine. |
| `Saro Trades V7.mq5` | Internally "Saro Trades V6 - Consolidated single-file version. Logic unchanged" from the modular `SaroTradesV6.mq5` below, plus added scale-in debug logging. |
| `SaroTradesV6.mq5` (+ `SaroTradesV6_Engine_Core.mqh`, `_Engine_ScaleIn.mqh`, `_Strategy.mqh`) | The modular version of the V6 DCA+Scale-in engine, split across files instead of one flat `.mq5`. |
| `SaroTradesV7.mq5` (+ matching `.mqh` files) | Modular V7 - a further iteration of the same DCA+Scale-in architecture, next version up from V6. |

Note the confusing numbering: the flat `Saro Trades V7 G.mq5` and `Saro Trades V7.mq5` files both internally identify as "V6" in their header comments, while the real "V7" engine lives in the modular `SaroTradesV7.mq5` + `.mqh` set - the version number in the filename doesn't always match what the file calls itself internally.
