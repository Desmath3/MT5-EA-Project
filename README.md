# MT5 EA Project

![License](https://img.shields.io/badge/license-All%20Rights%20Reserved-red)
![Language](https://img.shields.io/badge/language-MQL5-0A5FA8)
![Platform](https://img.shields.io/badge/platform-MetaTrader%205-1E88E5)
![Last Commit](https://img.shields.io/github/last-commit/Desmath3/MT5-EA-Project)
![Repo Size](https://img.shields.io/github/repo-size/Desmath3/MT5-EA-Project)

A private collection of MetaTrader 5 Expert Advisors (EAs) for automated trading - Bollinger Bands, RSI, moving-average ribbon, breakout/range, SFP (swing failure pattern), VWAP, and the "Ighodalo" gold/CFD strategy family, plus strategies co-developed with named collaborators.

## Table of Contents
- [Description](#description)
- [Repo Layout](#repo-layout)
- [Strategies](#strategies)
- [How to Use](#how-to-use)
- [Requirements](#requirements)
- [Compiled Binaries and Logs](#compiled-binaries-ex5-and-logs)
- [License](#license)
- [Contact](#contact)
- [Disclaimer](#disclaimer)

## Description
Every strategy lives in its own top-level folder holding the `.mq5`/`.mqh` source for every version of that strategy - multiple historical versions are kept side by side rather than deleted (e.g. `SFP/SFP.mq5` through `SFP/SFP v8.mq5`). Compiled `.ex5` binaries are intentionally not tracked (see [below](#compiled-binaries-ex5-and-logs)).

## Repo Layout
A few folders are split into version subfolders where the underlying MQL5 project kept them as separate MetaEditor projects with their own `.mqh` helper modules, or where a hybrid/fork variant is worth keeping visually separate from the main lineage: `MA-Ribbon/2025-V1/`, `VWAP-Flip-Bot/V1/` and `/V2/`, `Limitless-EA-BB/Continuation/` and `/Hybrid/`, `Consolidation-Range-ADX/Hybrid/`, `Belema-SFP/Alex-DIAD-Branch/`. This repo is Expert Advisors only - no indicators.

**Every folder has its own `README.md`** explaining what each file in it is and how it differs from its neighbors - since many folders hold several versions or forks of the same strategy, start there before opening a `.mq5` file cold.

Not everything from the source library made it in:
- **Excluded as third-party**: `BoBiXAU Pro`, `HOPE EA (MT5)`, and `NASDAQ GHOST ROBOT` existed only as compiled `.ex5` binaries with no source - almost certainly purchased/downloaded rather than authored here.
- **No source available**: `Desmond Range Breakout` also only exists as a compiled `.ex5`, so there was nothing to add for it.
- **Excluded by design**: custom indicators (previously `Indicators/Belema` and `Indicators/Ighodalo-SuperTrend-Band`) - this repo is scoped to Expert Advisors only.
- **Not migrated (for now)**: backtest/optimization results (`.set`, `.png`, `.html`, `.xml`, `.zip` reports) - pure test artifacts, not source code.

### A note on consolidation
This repo previously had 52 top-level folders. Several of those turned out - on
actually reading the code, not just the names - to be the exact same
evolving codebase copied under different names over time (confirmed via
`diff`, not guessed from filenames). Those were merged into single folders
with a version-history table in their README:

- **`Limitless-EA-BB/`** absorbs what used to be `EA-BB-2025`, `Ighodalo-EA-BB-2025`, `Ighodalo-EA-BB`, `Limitless-EA-BB-2025`, and the `Alex-DIAD-Limitless-EA-BB*` hybrids - all the same `BB_ReversalEA.mq5` lineage from 2021 through v4.36.
- **`Consolidation-Range-ADX/`** absorbs what used to be `Ebuka`, `Ebuka-EA`, `Ebuka-EA-with-plots`, `Ebuka-Range-Breakout-Hedge`, `Ighodalo-Range-Breakout-with-plots(-reversed)`, `Ighodalo-Range-Breakouts-without-plot`, and the `Alex-DIAD-Ebuka-Range-Breakout-Hedge` hybrid.
- **`Belema-SFP/`** absorbs what used to be `Alex-DIAD` and `Alex-DIAD-Belema-SFP` (a divergent v2.x branch of the same SFP strategy).
- **`BB-Trend-Trader/`** absorbs `Ighodalo-Trendtrader` (confirmed via diff to be the same `CBBReversalEA` class with a MACD filter added).
- **`Ighodalo-Gold-MRA/`** absorbs `Ighodalo-Gold-MRAC` and `MACD-Ribbon` (same "Breakout EA v2 MACD_MA" base with small variations).

Other close relationships exist (e.g. `RSI` / `RSI-Trend-Trader`, `Power-Pivot` / `News-Identifier-Mt5`, `Ighodalo-Gold-BnR` / `Ighodalo-Gold-BnR-Kenton-Royal`) but weren't folded together, usually because one side is a licensed/expiring distribution copy or the divergence is large enough that merging would hide more than it clarifies - each is cross-referenced in the relevant README instead.

## Strategies

### Bollinger Bands
| Folder | Description |
|---|---|
| `BB-Martingale/` | Bollinger Bands + Martingale sizing |
| `BB-Trend-Trader/` | Bollinger Bands trend-following, incl. the MACD-filter variant |
| `Limitless-EA-BB/` | The "BB Reversal" mega-lineage (2021-2025), incl. `Continuation/` and `Hybrid/` variants |

### Moving Average / MACD
| Folder | Description |
|---|---|
| `MA-Ribbon/` | Moving-average ribbon trend system, incl. `2025-V1/` project |
| `MA-Touch/` | Moving-average touch/crossover triggers |
| `MACDBB/` | MACD + Bollinger Bands combination |

### RSI
| Folder | Description |
|---|---|
| `RSI/` | Base RSI strategy |
| `RSI-Martingale/` | RSI + Martingale sizing |
| `RSI-Trend-Trader/` | RSI trend-following |

### SFP (Swing Failure Pattern)
| Folder | Description |
|---|---|
| `SFP/` | Core SFP strategy (v1 through v8) |
| `Belema-SFP/` | Belema's SFP strategy (through V14), incl. the `Alex-DIAD-Branch/` fork |
| `Ighodalo-SFP/` | Ighodalo's own separate SFP implementation |

### Breakout / Range / Structure
| Folder | Description |
|---|---|
| `Breakout-EA/` | Breakout strategy (v1, v2) |
| `EA-BOS/` | Break-of-structure strategy |
| `Fib-Retracement/` | Fibonacci retracement entries/exits |
| `Entry-Formation/` | Entry formation logic |
| `Consolidation-Range-ADX/` | The ADX-gated consolidation-range/breakout mega-lineage (Ebuka → Ighodalo), incl. `Hybrid/` |

### Ighodalo Gold / CFD Family
| Folder | Description |
|---|---|
| `Ighodalo-Gold-BBMA/` | Bollinger Bands + Moving Average combo |
| `Ighodalo-Gold-BnR/` | Break and retest |
| `Ighodalo-Gold-BnR-Kenton-Royal/` | Break and retest, licensed/expiring build |
| `Ighodalo-Gold-CRT/` | Candle range theory strategy |
| `Ighodalo-Gold-MRA/` | MA-ribbon + MACD breakout family (incl. former MRAC/MACD-Ribbon) |
| `Ighodalo-Gold-Milker/` | "Milker" strategy (V2 through V8), descended from BB-Martingale |
| `Ighodalo-Gold-Turning-Points/` | DCA + scale-in turning-points system (base, V2, V3) |

### Ighodalo Other Strategies
| Folder | Description |
|---|---|
| `Ighodalo-Hedger/` | Hedging strategy |
| `Ighodalo-Hedger-Optimized/` | Optimized hedger (v1.21, v2) |
| `Ighodalo-Orb/` | Opening range breakout (base, v2, v3) |
| `Ighodalo-Po3/` | Power of Three strategy |
| `Ighodalo-SuperTrend-Reversal/` | Two SuperTrend reversal implementations, one forked from Limitless-EA-BB |

### VWAP and Misc
| Folder | Description |
|---|---|
| `VWAP-Flip-Bot/` | VWAP flip/swing strategy (V1, V2, incl. Swing Bot variant) |
| `Po3/` | Power of Three strategy (separate implementation from `Ighodalo-Po3`) |
| `Power-Pivot/` | Pivot-point-based strategy |
| `News-Identifier-Mt5/` | Despite the name, closely related to Power-Pivot - see its README |
| `Saro-Trades/` | Saro Trades strategy family (V1 through V7, incl. modular V6/V7 builds) |

## How to Use
1. **Clone the repository**:
   ```
   git clone https://github.com/Desmath3/MT5-EA-Project.git
   ```
2. **Install MetaTrader 5** (version 5.0 or higher).
3. **Add an EA to MetaTrader**:
   - Copy the `.mq5` file you want (e.g. `SFP/SFP v8.mq5`) into the `MQL5/Experts` folder of your MetaTrader 5 installation.
   - Open MetaEditor, and compile it (F7) to produce the `.ex5`.
4. **Attach to a chart**:
   - In MetaTrader 5, attach the compiled EA to your desired chart/timeframe.
   - Configure input parameters as specified in the EA's comments.
5. **Test before trading live**:
   - Use the Strategy Tester to backtest with historical data.
   - Always validate on a demo account before running on a live account.

## Requirements
- MetaTrader 5 platform (version 5.0 or higher)
- A MetaTrader 5 trading account (demo or live)
- MQL5 knowledge for custom modifications

## Compiled Binaries (.ex5) and Logs
`.ex5` files and `*.log` build logs are intentionally excluded from version control (see `.gitignore`) - they're build artifacts, compile inconsistently across MetaTrader versions, and bloat every diff. Compile the `.mq5` source yourself in MetaEditor.

## License
All rights reserved - see [LICENSE](LICENSE). This code is shared publicly for portfolio/reference purposes only; it is not open source, and no license to copy, modify, or redistribute it is granted.

## Contact
For questions, feedback, or collaboration: aghughudesmath@gmail.com or via GitHub: [Desmath3](https://github.com/Desmath3)

## Disclaimer
These EAs are provided for educational and experimental purposes only. Trading involves financial risk, and past performance does not guarantee future results. Test EAs thoroughly on a demo account before using them with real funds.
