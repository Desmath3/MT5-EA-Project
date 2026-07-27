# SFP

Swing Failure Pattern EA (`SFP_EA.mq5`) based on support/resistance breakout
events with retrace confirmation - a separate codebase from `../Belema-SFP/`
and `../Ighodalo-SFP/` (same general SFP concept, different author/engine).

| File | What changed |
|---|---|
| `SFP.mq5` | Base: breakout-based support/resistance signals, valid if price retraces within `RetraceCandles`. |
| `SFP v2.mq5` | Adds BB Trend & MA Ribbon filters. |
| `SFP v3.mq5` / `v4.mq5` | Adds session filtering on top of v2. |
| `SFP v5.mq5` / `v6.mq5` / `v7.mq5` | Adds configurable support/resistance count. |
| `SFP v8.mq5` | Adds breakeven and reversal-exit logic. |
| `SFP PV.mq5` | Fullest feature set: partial close, breakeven, reversal exit, BB Trend & MA Ribbon filters, session filtering, and configurable support/resistance count. |
