# MT5 EA Project

![License](https://img.shields.io/badge/license-All%20Rights%20Reserved-red)
![Language](https://img.shields.io/badge/language-MQL5-0A5FA8)
![Platform](https://img.shields.io/badge/platform-MetaTrader%205-1E88E5)
![Last Commit](https://img.shields.io/github/last-commit/Desmath3/MT5-EA-Project)
![Repo Size](https://img.shields.io/github/repo-size/Desmath3/MT5-EA-Project)

A private collection of MetaTrader 5 Expert Advisors (EAs) and custom indicators for automated trading - Bollinger Bands, RSI, moving-average ribbon, breakout/range, SFP (swing failure pattern), VWAP, and the "Ighodalo" gold/CFD strategy family, plus strategies co-developed with named collaborators.

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
A few folders are split into version subfolders where the underlying MQL5 project kept them as separate MetaEditor projects with their own `.mqh` helper modules: `MA-Ribbon/2025-V1/`, `VWAP-Flip-Bot/V1/` and `/V2/`. `Indicators/` holds custom indicators rather than EAs.

Not everything from the source library made it in:
- **Excluded as third-party**: `BoBiXAU Pro`, `HOPE EA (MT5)`, and `NASDAQ GHOST ROBOT` existed only as compiled `.ex5` binaries with no source - almost certainly purchased/downloaded rather than authored here.
- **No source available**: `Desmond Range Breakout` also only exists as a compiled `.ex5`, so there was nothing to add for it.
- **Not migrated (for now)**: backtest/optimization results (`.set`, `.png`, `.html`, `.xml`, `.zip` reports) - pure test artifacts, not source code.

## Strategies

### Bollinger Bands
| Folder | Description |
|---|---|
| `BB-Martingale/` | Bollinger Bands + Martingale sizing |
| `BB-Trend-Trader/` | Bollinger Bands trend-following |
| `EA-BB-2025/` | Bollinger Bands, 2025 iterations (PV, v2, V3, V4) |

### Moving Average / MACD
| Folder | Description |
|---|---|
| `MA-Ribbon/` | Moving-average ribbon trend system, incl. `2025-V1/` project |
| `MA-Touch/` | Moving-average touch/crossover triggers |
| `MACD-Ribbon/` | MACD ribbon indicator-based EA |
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
| `Belema-SFP/` | Belema variant of SFP (through V14) |

### Breakout / Range / Structure
| Folder | Description |
|---|---|
| `Breakout-EA/` | Breakout strategy (v1, v2) |
| `EA-BOS/` | Break-of-structure strategy |
| `Fib-Retracement/` | Fibonacci retracement entries/exits |
| `Entry-Formation/` | Entry formation logic |
| `Ebuka-Range-Breakout-Hedge/` | Range breakout with hedging |

### Alex DIAD Collaborations
| Folder | Description |
|---|---|
| `Alex-DIAD/` | Base Alex DIAD strategy |
| `Alex-DIAD-Belema-SFP/` | Alex DIAD combined with Belema SFP |
| `Alex-DIAD-Ebuka-Range-Breakout-Hedge/` | Alex DIAD combined with Ebuka's range breakout/hedge |
| `Alex-DIAD-Limitless-EA-BB/` | Alex DIAD combined with Limitless EA BB |
| `Alex-DIAD-Limitless-EA-BB-Continuation/` | Continuation variant of the above |

### Ebuka Collaborations
| Folder | Description |
|---|---|
| `Ebuka/` | Base Ebuka strategy (v2) |
| `Ebuka-EA/` | Ebuka EA variant |
| `Ebuka-EA-with-plots/` | Same, with chart plotting added |

### Limitless EA BB
| Folder | Description |
|---|---|
| `Limitless-EA-BB/` | Core Limitless BB strategy (V2 through V8) |
| `Limitless-EA-BB-2025/` | 2025 iteration |
| `Limitless-EA-BB-Continuation/` | Continuation variant (V1.0) |

### Ighodalo Gold / CFD Family
| Folder | Description |
|---|---|
| `Ighodalo-Gold-BBMA/` | Bollinger Bands + Moving Average combo |
| `Ighodalo-Gold-BnR/` | Break and retest |
| `Ighodalo-Gold-BnR-Kenton-Royal/` | Break and retest, Kenton Royal variant |
| `Ighodalo-Gold-CRT/` | Candle range theory strategy |
| `Ighodalo-Gold-MRA/` | MRA strategy |
| `Ighodalo-Gold-MRAC/` | MRAC variant |
| `Ighodalo-Gold-Milker/` | Core "Milker" strategy (V2 through V8) |
| `Ighodalo-Gold-Turning-Points/` | DCA + scale-in turning-points system (V2, V3) |

### Ighodalo Other Strategies
| Folder | Description |
|---|---|
| `Ighodalo-EA-BB/` | Bollinger Bands variant (V3) |
| `Ighodalo-EA-BB-2025/` | 2025 iteration (v2, base) |
| `Ighodalo-Hedger/` | Hedging strategy |
| `Ighodalo-Hedger-Optimized/` | Optimized hedger (v2, base) |
| `Ighodalo-Orb/` | Opening range breakout (v2, v3) |
| `Ighodalo-Po3/` | Power of Three strategy |
| `Ighodalo-Range-Breakout-with-plots/` | Range breakout, with chart plots |
| `Ighodalo-Range-Breakout-with-plots-reversed/` | Reversed-logic variant |
| `Ighodalo-Range-Breakouts-without-plot/` | Range breakout, no plotting |
| `Ighodalo-SFP/` | Ighodalo's own SFP variant (V8) |
| `Ighodalo-SuperTrend-Reversal/` | SuperTrend reversal strategy |
| `Ighodalo-Trendtrader/` | General trend-following EA |

### VWAP and Misc
| Folder | Description |
|---|---|
| `VWAP-Flip-Bot/` | VWAP flip/swing strategy (V1, V2, incl. news filter module) |
| `Po3/` | Power of Three strategy |
| `Power-Pivot/` | Pivot-point-based strategy |
| `News-Identifier-Mt5/` | News event identifier utility EA |
| `Saro-Trades/` | Saro Trades strategy family (V2 through V7, incl. modular V6/V7 builds) |

### Indicators
| Folder | Description |
|---|---|
| `Indicators/Belema/` | Custom Belema indicator |
| `Indicators/Ighodalo-SuperTrend-Band/` | Custom SuperTrend band indicator |

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
