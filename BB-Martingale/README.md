# BB Martingale

A Bollinger Bands entry strategy with Martingale position sizing (`BB MartingaleEA.mq5`).

| File | What changed |
|---|---|
| `BB Martingale.mq5` | Base version (428 lines): initial lot size, lot multiplier, and max Martingale steps. |
| `BB Martingale V2.mq5` | Grows to ~772 lines: adds session filters (`TradeNewYork`/`TradeLondon`/`TradeTokyo`/`TradeSydney`), `MartingalePips`, `BaseTP_Pips`, and a daily-reset option. |
| `BB Martingale V3.mq5` | Grows further to ~1139 lines on top of V2's feature set. |

## Related but not merged here
`Ighodalo-Gold-Milker` shares this exact "BB MartingaleEA.mq5" origin but has grown 3-6x larger with gold-specific specialization - see that folder's README.
