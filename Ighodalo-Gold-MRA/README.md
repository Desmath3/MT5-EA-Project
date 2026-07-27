# Ighodalo Gold MRA

A breakout EA combining MA ribbon and MACD signals (internally "Breakout EA
v2 MACD_MA"). The three files here are close variants of the same base,
confirmed via diff rather than assumed from naming.

| File | What changed |
|---|---|
| `MACD Ribbon (base).mq5` | Base version: MA ribbon + MACD breakout logic, no ADX filter. |
| `Ighodalo Gold MRA.mq5` | Adds an ADX filter (`ADX_Period`, `ADX_Threshold` inputs and handle) on top of the base. |
| `Ighodalo Gold MRAC.mq5` | Diverges from `Ighodalo Gold MRA.mq5` with a different moving-average calculation approach (uses a previous-bar-state tracking method) and no ADX filter - a parallel variant rather than a strict superset. |
