# BB Trend Trader

A Bollinger Bands trend-following EA (internally `EA_BB_V5_fixed.mq5`, class
`CBBReversalEA`) - distinct from the `Limitless-EA-BB` family, which trades
BB *reversals* rather than trend continuation.

| File | What changed |
|---|---|
| `BB Trend Trader.mq5` | Base version. |
| `Ighodalo Trendtrader (with MACD filter).mq5` | Same `CBBReversalEA` class and engine (confirmed via diff), with a MACD confirmation filter added: extra `UseMACDFilter`/`MACDFastPeriod`/`MACDSlowPeriod`/`MACDSignalPeriod` inputs, an MACD indicator handle, and the filter wired into entry confirmation. |
