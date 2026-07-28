# MT5 EA Project

## Description
This repository contains a collection of MetaTrader 5 Expert Advisors (EAs) and indicators developed for automated trading, migrated from a local MQL5 working library. Strategies span moving-average/ribbon systems, Bollinger Bands, RSI, breakout/range, SFP (swing failure pattern), VWAP, and a large family of "Ighodalo"-branded gold/CFD strategies, plus a few EAs co-developed with named collaborators (Alex DIAD, Ebuka, Saro, Belema, Desmond). Each strategy has its own top-level folder, and multiple historical versions of a strategy are kept side by side in that folder rather than deleted (e.g. `SFP/SFP.mq5` through `SFP/SFP v8.mq5`).

The EAs are written in MQL5 and compiled for use within the MetaTrader 5 platform.

## Folder Structure
Every strategy lives in its own top-level folder, named after the strategy (spaces replaced with hyphens). A few folders are split into version subfolders (`MA-Ribbon/2025-V1/`, `Saro-Trades` V6/V7 variants, `VWAP-Flip-Bot/V1/` and `/V2/`) where the underlying local library kept them as separate MetaEditor projects with their own `.mqh` helper modules. `Indicators/` holds custom indicators rather than EAs.

Not everything from the local library made it in:
- **Excluded as third-party**: `BoBiXAU Pro`, `HOPE EA (MT5)`, and `NASDAQ GHOST ROBOT` existed only as compiled `.ex5` binaries with no source - almost certainly purchased/downloaded rather than authored here, so they were left out to avoid redistributing someone else's commercial work.
- **No source available**: `Desmond Range Breakout` also only exists as a compiled `.ex5` locally, so there was nothing to add for it.
- **Not migrated (for now)**: backtest/optimization results (`.set`, `.png`, `.html`, `.xml`, `.zip` reports) from the separate `Ighodalo Gold Test Results` folder - left as a future decision since it's pure test artifacts, not source code.

Each folder holds the `.mq5`/`.mqh` source for every version of that strategy. Compiled `.ex5` binaries and build/compile logs are **not** tracked in this repo (see below) - compile from source in MetaEditor.

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
`.ex5` files and `*.log` build logs are intentionally excluded from version control (see `.gitignore`) - they're build artifacts, compile inconsistently across MetaTrader versions, and bloat every diff. Compile the `.mq5` source yourself in MetaEditor instead.

## Contributing
Fork this repository, enhance an EA, and submit a pull request describing the change.

## Contact
For questions, feedback, or collaboration: aghughudesmath@gmail.com or via GitHub: [Desmath3](https://github.com/Desmath3)

## Disclaimer
These EAs are provided for educational and experimental purposes only. Trading involves financial risk, and past performance does not guarantee future results. Test EAs thoroughly on a demo account before using them with real funds.
