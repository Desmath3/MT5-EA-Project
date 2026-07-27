# Ighodalo Gold Milker

Descended from the same `BB MartingaleEA.mq5` origin as `../BB-Martingale/`,
but grown far beyond a "variant" - from 428 lines at the shared starting
point to 2627 lines by V8, specialized for gold trading. Kept as its own
folder rather than merged into `BB-Martingale` given how much it has diverged.

| File | Lines | What changed |
|---|---|---|
| `Ighodalo Gold Milker.mq5` | 1161 | Base - same `BB MartingaleEA.mq5` header/origin as `BB-Martingale`, already substantially grown. |
| `Ighodalo Gold Milker V2.mq5` | 1551 | Still headed `BB MartingaleEA.mq5`; adds a distinct `BBMartingale_News_Cache.csv` tester file. |
| `Ighodalo Gold Milker V2 C.mq5` | 1562 | Rebranded header to "Ighodalo Gold Milker.mq5" (copyright "Ighodalo V2 C") - a parallel "C" variant of V2. |
| `Ighodalo Gold Milker V3.mq5` | 1734 | Next size increment. |
| `Ighodalo Gold Milker V3 C.mq5` | 1562 | Same line count as `V2 C.mq5` - likely a near-identical "C" variant carried forward rather than a fresh rewrite. |
| `Ighodalo Gold Milker V4.mq5` | 1988 | Adds a `BaseTP_Pips` input. |
| `Ighodalo Gold Milker V5.mq5` | 2072 | Drops the old `PIP_SIZE` define in favor of other pip handling. |
| `Ighodalo Gold Milker V6.mq5` | 2167 | First version with the copyright string actually updated to "Ighodalo V6" (V2-V5 all carried a stale "Ighodalo V3 C" copyright even as the code moved on). |
| `Ighodalo Gold Milker V7.mq5` | 2570 | Adds `EnumToString` helper functions to fix undeclared-identifier compile errors. |
| `Ighodalo Gold Milker V8.mq5` | 2627 | Same `EnumToString` fix as V7, largest/latest version. |
| `Ighodalo Gold Milker V8 License.ex5` (not tracked - `.ex5` only, no source) | - | A separately compiled/licensed build of V8; excluded from version control like all `.ex5` files. |
