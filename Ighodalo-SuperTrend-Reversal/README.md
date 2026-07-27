# Ighodalo SuperTrend Reversal

Two genuinely different implementations (verified via diff - not near-duplicates
despite the similar folder-mate names), both trading SuperTrend reversals.

| File | What it is |
|---|---|
| `Ighodalo SuperTrend Reversal.mq5` | A direct fork of `../Limitless-EA-BB/` at v4.36 (internally still named `Limitless EA ST V4.36.mq5`): "Integrated SuperTrend Bands logic directly into EA; removed Bollinger Bands." Keeps that lineage's news-cache system, synthetic 35-minute ATR, and market-structure-shift exits, just with SuperTrend swapping out Bollinger Bands as the entry signal. |
| `Ighodalo SuperTrend Reversals.mq5` | Internally named `Supertrend EA ST V1.mq5` - an earlier/parallel v1 implementation, not a version of the file above. Confirmed via diff to be genuinely different code (different structure, different property blocks), not a copy. |
