# MT5 EA Project

## Description
This repository contains a collection of MetaTrader 5 Expert Advisors (EAs) developed for automated trading. These EAs implement specific trading strategies, including moving average-based systems, Fibonacci retracement levels, Bollinger Bands, RSI, breakout, and swing-failure-pattern (SFP) systems. Each strategy has its own folder, and multiple historical versions of a strategy are kept side by side in that folder (e.g. `SFP/SFP.mq5` through `SFP/SFP v8.mq5`).

The EAs are written in MQL5 and compiled for use within the MetaTrader 5 platform.

## Folder Structure
- `BB-Martingale/` - Bollinger Bands + Martingale strategy
- `BB-Trend-Trader/` - Bollinger Bands trend-following strategy
- `Breakout-EA/` - Breakout strategy (v1, v2)
- `EA-BB-2025/` - Bollinger Bands strategy, 2025 iterations (PV, v2, V3, V4)
- `EA-BOS/` - Break-of-structure strategy
- `Entry-Formation/` - Entry formation logic
- `Fib-Retracement/` - Fibonacci retracement strategy
- `MA-Ribbon/` - Moving average ribbon strategy, including the `2025-V1/` MetaEditor project
- `MACD-Ribbon/` - MACD ribbon indicator-based EA
- `MA-Touch/` - Moving average touch/crossover strategy
- `RSI/` - Base RSI strategy
- `RSI-Martingale/` - RSI + Martingale strategy
- `RSI-Trend-Trader/` - RSI trend-following strategy
- `SFP/` - Swing failure pattern strategy (v1 through v8)

Each folder holds the `.mq5` source for every version of that strategy. Compiled `.ex5` binaries are **not** tracked in this repo (see below) - compile them yourself in MetaEditor.

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

## Compiled Binaries (.ex5)
`.ex5` files are intentionally excluded from version control (see `.gitignore`) - they're build artifacts, compile inconsistently across MetaTrader versions, and bloat every diff. Compile the `.mq5` source yourself in MetaEditor instead.

## Contributing
Fork this repository, enhance an EA, and submit a pull request describing the change.

## Contact
For questions, feedback, or collaboration: aghughudesmath@gmail.com or via GitHub: [Desmath3](https://github.com/Desmath3)

## Disclaimer
These EAs are provided for educational and experimental purposes only. Trading involves financial risk, and past performance does not guarantee future results. Test EAs thoroughly on a demo account before using them with real funds.
