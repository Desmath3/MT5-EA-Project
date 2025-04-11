# MT5 EA Project

## Description
This repository contains a collection of MetaTrader 5 Expert Advisors (EAs) developed for automated trading. These EAs implement specific trading strategies, including moving average-based systems, Fibonacci retracement levels, Bollinger Bands, and custom indicators. The project includes multiple versions and upgrades of each EA, such as:

- **EA BB 2025**: Based on the Bollinger Bands strategy.
- **MA ribbon**: Utilizes multiple moving averages for trend analysis.
- **MA Touch**: Triggers trades based on moving average crossovers or touches.
- **Fib Retracement**: Uses Fibonacci levels for entry and exit points.
- **SFP**: Implements a custom strategy defined by the developer.
- **Other versions**: Includes upgrades (e.g., v2, v3, v4, v5) and compiled `.ex5` files.

The EAs are written in MQL5 and compiled for use within the MetaTrader 5 platform. Development began in January 2023, with the initial release uploaded on October 15, 2023.

## How to Use
1. **Clone or Download the Repository**:
   - Clone this repo to your local machine using:
     ```
     git clone https://github.com/your-username/MT5-EA-Project.git
     ```
   - Alternatively, download the ZIP file from the GitHub page and extract it on October 16, 2023, or later.

2. **Install MetaTrader 5**:
   - Ensure MetaTrader 5 (version 5.0 or higher) is installed on your computer by October 20, 2023.

3. **Add EAs to MetaTrader**:
   - Copy the `.mq5` files (e.g., `EA_BB_2025_PV.mq5`, `MA_ribbon_upgrade_v2.mq5`) to the `MQL5/Experts` folder in your MetaTrader 5 installation directory by October 22, 2023.
   - Compile the `.mq5` files in MetaTrader 5 (open MetaEditor, drag the files in, and click "Compile") by October 23, 2023.

4. **Attach to Charts**:
   - Open MetaTrader 5 on October 24, 2023, and attach the compiled `.ex5` files to your desired currency pair or asset chart.
   - Configure input parameters (e.g., periods, levels) as specified in each EA’s comments section by October 25, 2023.

5. **Test and Optimize**:
   - Use the MetaTrader 5 Strategy Tester to backtest each EA with historical data starting October 26, 2023.
   - Adjust settings to optimize performance for your trading preferences by October 30, 2023.

## Requirements
- **MetaTrader 5 Platform** (version 5.0 or higher)
- A MetaTrader 5 trading account (demo or live) activated by October 20, 2023
- MQL5 knowledge for custom modifications

## File Structure
- `.mq5` files: Source code for each EA (e.g., `EA_BB_2025_PV.mq5`, `MA_Touch_2025_v2.mq5`).
- `.ex5` files: Compiled executable versions of the EAs.
- `README.md`: This file, providing project overview.
- `requirements.txt`: List of dependencies (if any).
- `LICENSE`: License information.
- `.gitignore`: Files to ignore in version control.

## Installation Notes
- Compiled `.ex5` files are included for convenience, but recompile the `.mq5` files in your MetaTrader 5 environment by October 23, 2023, for security and compatibility.
- Do not upload sensitive data (e.g., account credentials) to this repository.

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing
Fork this repository, suggest improvements, or submit pull requests. Enhance any EA (e.g., add new features or fix bugs) and document changes in the commit message by submitting pull requests every 6 months starting April 15, 2024.

## Contact
For questions, feedback, or collaboration, reach out to me at [your-email@example.com] or via my GitHub profile: [your-github-username].

## Changelog
- **[Initial Release]**: Uploaded initial collection of EAs including BB 2025, MA ribbon, MA Touch, Fib Retracement, and SFP with various versions on October 15, 2023.
- **[Next Update]**: Performance reports, additional EAs, or optimizations will be added on April 15, 2024, and every 6 months thereafter.

## Disclaimer
These EAs are provided for educational and experimental purposes only. Use them at your own risk starting October 26, 2023. Trading involves financial risk, and past performance does not guarantee future results. Test EAs thoroughly with demo accounts before using them with real funds by November 1, 2023.
