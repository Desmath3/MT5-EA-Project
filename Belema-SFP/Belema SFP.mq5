//+------------------------------------------------------------------+
//|                                                      Belema SFP.mq5  |
//|                    Swing Failure Pattern Expert Advisor          |
//|             Built with Multi-Timeframe & Integrated Indicators   |
//+------------------------------------------------------------------+
#property copyright "Belema"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Trades Swing Failure Patterns with Multi-Timeframe levels, Power Candles, and FVG."

// --- Includes ---
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

// --- Input Parameters ---

// Session Filters
input bool TradeNewYork = true;         // Trade during New York session
input bool TradeLondon  = true;         // Trade during London session
input bool TradeTokyo   = false;        // Trade during Tokyo session
input bool TradeSydney  = false;        // Trade during Sydney session

// Multi-Timeframe POI Settings
input bool EnableM5_POI  = true;        // Enable 5 Minute POI
input bool EnableM15_POI = true;        // Enable 15 Minute POI
input bool EnableM30_POI = true;        // Enable 30 Minute POI
input bool EnableH1_POI  = true;        // Enable 1 Hour POI
input bool EnableH4_POI  = true;        // Enable 4 Hour POI
input bool EnableD1_POI  = false;       // Enable Daily POI

// SFP Core Logic Settings
input int  LeftBars             = 15;   // Bars to left for pivot detection
input int  RightBars            = 15;   // Bars to right for pivot detection
input int  BreakoutGraceCandles = 3;    // Max bars for power candle after break
input int  ReclaimLookbackCandles = 5;  // Max bars for reclaim after breakout
input int  ReclaimGraceCandles  = 3;    // Max bars for power candle after reclaim
input int  PendingOrderExpiryCandles = 10; // Cancel pending order after this many candles

// Risk & Trade Management
input int  ATR_Period           = 14;   // ATR period for stop loss
input double ATR_SL_Multiplier  = 2.0;  // ATR multiplier for stop loss
input double RiskPercent        = 1.0;  // Risk percentage per trade
input double RR_Ratio           = 2.0;  // Risk-reward ratio for take profit
input int  MaxTradesPerDay      = 2;    // Max trades per day
input int  EA_MagicNumber       = 12345;// Magic number for trades

// Exit & Breakeven Conditions
input bool EnableBreakeven      = true; // Enable breakeven adjustment
input double BreakevenTriggerReward = 1.0; // Reward multiplier to trigger breakeven
input double BreakevenReward    = 0.1;  // Reward multiplier for new SL
input bool EnableReversalExit   = true; // Enable reversal exit
input int  LookbackHighLow      = 5;    // Lookback period for reversal exit

// Indicator Settings
input int  PowerCandlePeriods   = 14;   // SMA Periods for power candles
input double PowerCandleMultiplier = 1.5;// Multiplier for power candles
input color BullPowerColor      = clrLimeGreen; // Bullish power candle color
input color BearPowerColor      = clrRed;   // Bearish power candle color
input color BullFvgColor        = clrDarkGreen; // Bullish FVG color
input color BearFvgColor        = clrDarkRed;   // Bearish FVG color
input int  MaxFvgsToDisplay     = 5000; // Max FVGs to display on chart
input int  MaxPowerCandlesToDisplay = 1000; // Max power candles to display

// --- Global Variables & Structures ---

// Structure for levels and SFP state
struct LevelInfo {
    double price;                       // Price of the level
    ENUM_TIMEFRAMES timeframe;          // Timeframe of the level
    datetime time;                      // Time of the pivot bar
    bool isResistance;                  // True if resistance, false if support
    bool breakoutDetected;              // Price broke the level
    int breakoutCandleShift;            // Shift of breakout candle
    bool breakoutPowerCandleConfirmed;  // Power candle confirmed breakout
    int breakoutPowerCandleShift;       // Shift of breakout power candle
    bool reclaimDetected;               // Price reclaimed the level
    int reclaimCandleShift;             // Shift of reclaim candle
    bool reclaimPowerCandleConfirmed;   // Power candle confirmed reclaim
    int reclaimPowerCandleShift;        // Shift of reclaim power candle
    bool fvgFoundOnReclaim;             // FVG found on reclaim power candle
    int fvgCandleShift;                 // Shift of FVG candle
    bool tradePlaced;                   // True if trade placed
};
LevelInfo levels[]; // Array of detected levels

// Structure for pending orders
struct PendingOrderInfo {
    ulong ticket;                       // Order ticket
    datetime setupTime;                 // Time order was placed
};
PendingOrderInfo pendingOrders[];

// Structure for FVG objects
struct FVGObject {
    string name;                        // Object name
    double high;                        // High of FVG
    double low;                         // Low of FVG
    datetime startTime;                 // Start time of FVG
};
FVGObject bullFvgs[];
FVGObject bearFvgs[];

// Array for power candle objects
string powerCandleObjects[];

// Indicator handles
int ATR_Handle;

// Trade management objects
CTrade Trade;
CPositionInfo PositionInfo;
COrderInfo OrderInfo;

// Trade counters
int TradesToday = 0;
int LastTradeDay = 0;

// New bar tracking
datetime LastBarTime = 0;

// --- Helper Functions ---

// Check if candle is a power candle
bool IsPowerCandle(int shift, bool isBullish) {
    if (shift + PowerCandlePeriods >= iBars(_Symbol, _Period)) return false;
    double sum_range = 0;
    for (int i = 0; i < PowerCandlePeriods; i++) {
        if (shift + i >= iBars(_Symbol, _Period)) return false;
        double open_i = iOpen(_Symbol, _Period, shift + i);
        double close_i = iClose(_Symbol, _Period, shift + i);
        sum_range += MathAbs(close_i - open_i);
    }
    double avg_range = sum_range / PowerCandlePeriods;
    double open_curr = iOpen(_Symbol, _Period, shift);
    double close_curr = iClose(_Symbol, _Period, shift);
    double body_curr = MathAbs(close_curr - open_curr);
    bool is_large = body_curr > avg_range * PowerCandleMultiplier;
    bool is_correct_direction = (isBullish && close_curr > open_curr) || (!isBullish && close_curr < open_curr);
    return is_large && is_correct_direction;
}

// Check for Fair Value Gap
bool HasFVG(int shift, bool isBullish) {
    if (shift + 2 >= iBars(_Symbol, _Period)) return false;
    double high_curr = iHigh(_Symbol, _Period, shift);
    double low_curr = iLow(_Symbol, _Period, shift);
    double high_prev2 = iHigh(_Symbol, _Period, shift + 2);
    double low_prev2 = iLow(_Symbol, _Period, shift + 2);
    if (isBullish) return low_curr > high_prev2;
    else return high_curr < low_prev2;
}

// Plot power candle
void PlotPowerCandle(int shift, bool isBullish) {
    if (shift >= iBars(_Symbol, _Period)) return;
    datetime t = iTime(_Symbol, _Period, shift);
    double price = isBullish ? iLow(_Symbol, _Period, shift) : iHigh(_Symbol, _Period, shift);
    color paint = isBullish ? BullPowerColor : BearPowerColor;
    int arrow_code = isBullish ? 233 : 234;
    string name = "PowerCandle_" + TimeToString(t) + "_" + IntegerToString(shift);
    if (ObjectFind(0, name) == -1) {
        if (ObjectCreate(0, name, OBJ_ARROW, 0, t, price)) {
            ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrow_code);
            ObjectSetInteger(0, name, OBJPROP_COLOR, paint);
            ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
            int size = ArraySize(powerCandleObjects);
            ArrayResize(powerCandleObjects, size + 1);
            powerCandleObjects[size] = name;
            if (ArraySize(powerCandleObjects) > MaxPowerCandlesToDisplay) {
                string old_name = powerCandleObjects[0];
                ObjectDelete(0, old_name);
                ArrayRemove(powerCandleObjects, 0, 1);
            }
        }
    }
}

// Plot FVG
void PlotFVG(int shift, bool isBullish) {
    if (shift + 2 >= iBars(_Symbol, _Period)) return;
    datetime time_curr_bar = iTime(_Symbol, _Period, shift);
    datetime time_prev1_bar = iTime(_Symbol, _Period, shift + 1);
    double high_curr = iHigh(_Symbol, _Period, shift);
    double low_curr = iLow(_Symbol, _Period, shift);
    double high_prev2 = iHigh(_Symbol, _Period, shift + 2);
    double low_prev2 = iLow(_Symbol, _Period, shift + 2);
    double fvg_p1, fvg_p2;
    color fvg_color;
    string prefix;
    if (isBullish) {
        if (low_curr <= high_prev2) return;
        fvg_p1 = high_prev2;
        fvg_p2 = low_curr;
        fvg_color = BullFvgColor;
        prefix = "FVG_Bull_";
    } else {
        if (high_curr >= low_prev2) return;
        fvg_p1 = low_prev2;
        fvg_p2 = high_curr;
        fvg_color = BearFvgColor;
        prefix = "FVG_Bear_";
    }
    string name = prefix + TimeToString(time_curr_bar) + "_" + IntegerToString(shift);
    if (ObjectFind(0, name) == -1) {
        if (ObjectCreate(0, name, OBJ_RECTANGLE, 0, time_prev1_bar, fvg_p1, time_curr_bar, fvg_p2)) {
            ObjectSetInteger(0, name, OBJPROP_COLOR, fvg_color);
            ObjectSetInteger(0, name, OBJPROP_FILL, true);
            ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
            FVGObject new_fvg;
            new_fvg.name = name;
            new_fvg.high = MathMax(fvg_p1, fvg_p2);
            new_fvg.low = MathMin(fvg_p1, fvg_p2);
            new_fvg.startTime = time_prev1_bar;
            if (isBullish) {
                int size = ArraySize(bullFvgs);
                ArrayResize(bullFvgs, size + 1);
                bullFvgs[size] = new_fvg;
                if (ArraySize(bullFvgs) > MaxFvgsToDisplay) {
                    ObjectDelete(0, bullFvgs[0].name);
                    ArrayRemove(bullFvgs, 0, 1);
                }
            } else {
                int size = ArraySize(bearFvgs);
                ArrayResize(bearFvgs, size + 1);
                bearFvgs[size] = new_fvg;
                if (ArraySize(bearFvgs) > MaxFvgsToDisplay) {
                    ObjectDelete(0, bearFvgs[0].name);
                    ArrayRemove(bearFvgs, 0, 1);
                }
            }
        }
    }
}

// Update indicators
void UpdateIndicatorPlots() {
    int current_bar_shift = 0;
    int prev_completed_bar_shift = 1;
    if (iBars(_Symbol, _Period) < 1) return;
    datetime current_time = iTime(_Symbol, _Period, current_bar_shift);
    double low_current = iLow(_Symbol, _Period, current_bar_shift);
    double high_current = iHigh(_Symbol, _Period, current_bar_shift);
    for (int i = ArraySize(bullFvgs) - 1; i >= 0; i--) {
        if (low_current <= bullFvgs[i].high) {
            ObjectDelete(0, bullFvgs[i].name);
            ArrayRemove(bullFvgs, i, 1);
        } else {
            ObjectSetInteger(0, bullFvgs[i].name, OBJPROP_TIME, 1, current_time);
        }
    }
    for (int i = ArraySize(bearFvgs) - 1; i >= 0; i--) {
        if (high_current >= bearFvgs[i].low) {
            ObjectDelete(0, bearFvgs[i].name);
            ArrayRemove(bearFvgs, i, 1);
        } else {
            ObjectSetInteger(0, bearFvgs[i].name, OBJPROP_TIME, 1, current_time);
        }
    }
    if (iBars(_Symbol, _Period) <= prev_completed_bar_shift) return;
    if (IsPowerCandle(prev_completed_bar_shift, true)) PlotPowerCandle(prev_completed_bar_shift, true);
    if (IsPowerCandle(prev_completed_bar_shift, false)) PlotPowerCandle(prev_completed_bar_shift, false);
    if (HasFVG(prev_completed_bar_shift, true)) PlotFVG(prev_completed_bar_shift, true);
    if (HasFVG(prev_completed_bar_shift, false)) PlotFVG(prev_completed_bar_shift, false);
}

// Pivot high check
bool IsPivotHighTF(ENUM_TIMEFRAMES tf, int idx) {
    int total_bars_tf = iBars(_Symbol, tf);
    if (idx < RightBars || idx + LeftBars >= total_bars_tf) return false;
    double value = iHigh(_Symbol, tf, idx);
    for (int i = idx - RightBars; i <= idx + LeftBars; i++) {
        if (i == idx) continue;
        if (iHigh(_Symbol, tf, i) >= value) return false;
    }
    return true;
}

// Pivot low check
bool IsPivotLowTF(ENUM_TIMEFRAMES tf, int idx) {
    int total_bars_tf = iBars(_Symbol, tf);
    if (idx < RightBars || idx + LeftBars >= total_bars_tf) return false;
    double value = iLow(_Symbol, tf, idx);
    for (int i = idx - RightBars; i <= idx + LeftBars; i++) {
        if (i == idx) continue;
        if (iLow(_Symbol, tf, i) <= value) return false;
    }
    return true;
}

// Detect pivots
void DetectPivots(ENUM_TIMEFRAMES tf) {
    int totalBars = iBars(_Symbol, tf);
    if (totalBars < LeftBars + RightBars + 1) return;
    int idx = RightBars;
    if (idx >= totalBars || idx < 0) return;
    datetime pivot_time = iTime(_Symbol, tf, idx);
    datetime end_plot_time = iTime(_Symbol, _Period, 0);
    if (IsPivotHighTF(tf, idx)) {
        double pivot_price = iHigh(_Symbol, tf, idx);
        bool exists = false;
        for (int i = 0; i < ArraySize(levels); i++) {
            if (levels[i].timeframe == tf && levels[i].isResistance && MathAbs(levels[i].price - pivot_price) < _Point * 10) {
                exists = true;
                break;
            }
        }
        if (!exists) AddLevel(pivot_price, tf, pivot_time, true, end_plot_time);
    }
    if (IsPivotLowTF(tf, idx)) {
        double pivot_price = iLow(_Symbol, tf, idx);
        bool exists = false;
        for (int i = 0; i < ArraySize(levels); i++) {
            if (levels[i].timeframe == tf && !levels[i].isResistance && MathAbs(levels[i].price - pivot_price) < _Point * 10) {
                exists = true;
                break;
            }
        }
        if (!exists) AddLevel(pivot_price, tf, pivot_time, false, end_plot_time);
    }
}

// Add level
void AddLevel(double price, ENUM_TIMEFRAMES tf, datetime time, bool isResistance, datetime end_plot_time) {
    int n = ArraySize(levels);
    ArrayResize(levels, n + 1);
    levels[n].price = price;
    levels[n].timeframe = tf;
    levels[n].time = time;
    levels[n].isResistance = isResistance;
    levels[n].breakoutDetected = false;
    levels[n].breakoutPowerCandleConfirmed = false;
    levels[n].reclaimDetected = false;
    levels[n].reclaimPowerCandleConfirmed = false;
    levels[n].fvgFoundOnReclaim = false;
    levels[n].tradePlaced = false;
    string tfStr = EnumToString(tf);
    string typeStr = isResistance ? "Resistance" : "Support";
    string name = "Level_" + tfStr + "_" + typeStr + "_" + TimeToString(time);
    if (ObjectCreate(0, name, OBJ_TREND, 0, time, price, end_plot_time, price)) {
        ObjectSetInteger(0, name, OBJPROP_COLOR, isResistance ? clrRed : clrBlue);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, name, OBJPROP_RAY, true);
        string label_name = name + "_Label";
        if (ObjectCreate(0, label_name, OBJ_TEXT, 0, time, price)) {
            ObjectSetString(0, label_name, OBJPROP_TEXT, tfStr + " " + typeStr);
            ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 8);
            ObjectSetInteger(0, label_name, OBJPROP_COLOR, isResistance ? clrRed : clrBlue);
            ObjectSetInteger(0, label_name, OBJPROP_XOFFSET, 10);
            ObjectSetInteger(0, label_name, OBJPROP_YOFFSET, isResistance ? -10 : 10);
            ObjectSetInteger(0, label_name, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, label_name, OBJPROP_HIDDEN, false);
        }
    }
}

// Update levels
void UpdateLevels() {
    ENUM_TIMEFRAMES enabledTFs[] = {PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1};
    bool enables[] = {EnableM5_POI, EnableM15_POI, EnableM30_POI, EnableH1_POI, EnableH4_POI, EnableD1_POI};
    for (int i = 0; i < ArraySize(enabledTFs); i++) {
        if (enables[i]) DetectPivots(enabledTFs[i]);
    }
}

// Set limit order (defined before use to avoid undeclared identifier)
void SetLimitOrder(ENUM_ORDER_TYPE type, double price) {
    double atr[];
    ArraySetAsSeries(atr, true);
    if (CopyBuffer(ATR_Handle, 0, 1, 1, atr) <= 0) return;
    double slDistance = atr[0] * ATR_SL_Multiplier;
    double lotSize = CalculateLotSize(slDistance);
    if (lotSize <= 0) return;
    double sl = (type == ORDER_TYPE_BUY_LIMIT) ? price - slDistance : price + slDistance;
    double tp = (type == ORDER_TYPE_BUY_LIMIT) ? price + slDistance * RR_Ratio : price - slDistance * RR_Ratio;
    Trade.SetExpertMagicNumber(EA_MagicNumber);
    if (type == ORDER_TYPE_BUY_LIMIT) {
        if (!Trade.BuyLimit(lotSize, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "SFP Buy Limit")) {
            Print("Buy Limit order failed: ", GetLastError());
            return;
        }
    } else if (type == ORDER_TYPE_SELL_LIMIT) {
        if (!Trade.SellLimit(lotSize, price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "SFP Sell Limit")) {
            Print("Sell Limit order failed: ", GetLastError());
            return;
        }
    }
    ulong ticket = Trade.ResultOrder();
    if (ticket > 0) {
        int size = ArraySize(pendingOrders);
        ArrayResize(pendingOrders, size + 1);
        pendingOrders[size].ticket = ticket;
        pendingOrders[size].setupTime = iTime(_Symbol, _Period, 0);
    }
}

// Calculate lot size
double CalculateLotSize(double slDistance) {
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double riskAmount = accountBalance * (RiskPercent / 100.0);
    double slPoints = slDistance / tickSize;
    double lotSize = riskAmount / (slPoints * tickValue);
    lotSize = NormalizeDouble(lotSize, 2);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    if (lotSize < minLot) lotSize = minLot;
    if (lotSize > maxLot) lotSize = maxLot;
    return lotSize;
}

// Process resistance level
void ProcessResistanceLevel(int level_idx) {
    int current_bar_shift = 1;
    if (iBars(_Symbol, _Period) <= current_bar_shift) return;
    double current_close = iClose(_Symbol, _Period, current_bar_shift);

    if (!levels[level_idx].breakoutPowerCandleConfirmed) {
        if (current_close > levels[level_idx].price) {
            if (!levels[level_idx].breakoutDetected) {
                levels[level_idx].breakoutDetected = true;
                levels[level_idx].breakoutCandleShift = current_bar_shift;
            }
            for (int j = 0; j <= BreakoutGraceCandles; j++) {
                int check_shift = current_bar_shift + j;
                if (check_shift >= iBars(_Symbol, _Period)) break;
                if (iClose(_Symbol, _Period, check_shift) > levels[level_idx].price && IsPowerCandle(check_shift, true)) {
                    levels[level_idx].breakoutPowerCandleConfirmed = true;
                    levels[level_idx].breakoutPowerCandleShift = check_shift;
                    Comment("SFP: Resistance Breakout Confirmed at ", TimeToString(iTime(_Symbol, _Period, check_shift)));
                    break;
                }
            }
        } else if (levels[level_idx].breakoutDetected) {
            levels[level_idx].breakoutDetected = false;
            levels[level_idx].breakoutPowerCandleConfirmed = false;
        }
    }

    if (levels[level_idx].breakoutPowerCandleConfirmed && !levels[level_idx].reclaimPowerCandleConfirmed) {
        int bars_since_power_breakout = current_bar_shift - levels[level_idx].breakoutPowerCandleShift;
        if (bars_since_power_breakout > ReclaimLookbackCandles) {
            levels[level_idx].breakoutPowerCandleConfirmed = false;
            levels[level_idx].breakoutDetected = false;
        } else if (current_close < levels[level_idx].price) {
            if (!levels[level_idx].reclaimDetected) {
                levels[level_idx].reclaimDetected = true;
                levels[level_idx].reclaimCandleShift = current_bar_shift;
            }
            for (int j = 0; j <= ReclaimGraceCandles; j++) {
                int check_shift = current_bar_shift + j;
                if (check_shift >= iBars(_Symbol, _Period)) break;
                if (iClose(_Symbol, _Period, check_shift) < levels[level_idx].price && IsPowerCandle(check_shift, false)) {
                    levels[level_idx].reclaimPowerCandleConfirmed = true;
                    levels[level_idx].reclaimPowerCandleShift = check_shift;
                    Comment("SFP: Resistance Reclaim Confirmed at ", TimeToString(iTime(_Symbol, _Period, check_shift)));
                    break;
                }
            }
        } else if (levels[level_idx].reclaimDetected) {
            levels[level_idx].reclaimDetected = false;
            levels[level_idx].reclaimPowerCandleConfirmed = false;
        }
    }

    if (levels[level_idx].reclaimPowerCandleConfirmed && !levels[level_idx].fvgFoundOnReclaim && !levels[level_idx].tradePlaced) {
        if (HasFVG(levels[level_idx].reclaimPowerCandleShift, false)) {
            levels[level_idx].fvgFoundOnReclaim = true;
            levels[level_idx].fvgCandleShift = levels[level_idx].reclaimPowerCandleShift;
            double fvg_candle_high = iHigh(_Symbol, _Period, levels[level_idx].fvgCandleShift);
            double fvg_candle_low = iLow(_Symbol, _Period, levels[level_idx].fvgCandleShift);
            double entry_price = (fvg_candle_high + fvg_candle_low) / 2.0;
            SetLimitOrder(ORDER_TYPE_SELL_LIMIT, entry_price);
            levels[level_idx].tradePlaced = true;
            TradesToday++;
            Comment("SFP: SELL LIMIT placed for ", levels[level_idx].price, " at ", entry_price);
        }
    }
}

// Process support level
void ProcessSupportLevel(int level_idx) {
    int current_bar_shift = 1;
    if (iBars(_Symbol, _Period) <= current_bar_shift) return;
    double current_close = iClose(_Symbol, _Period, current_bar_shift);

    if (!levels[level_idx].breakoutPowerCandleConfirmed) {
        if (current_close < levels[level_idx].price) {
            if (!levels[level_idx].breakoutDetected) {
                levels[level_idx].breakoutDetected = true;
                levels[level_idx].breakoutCandleShift = current_bar_shift;
            }
            for (int j = 0; j <= BreakoutGraceCandles; j++) {
                int check_shift = current_bar_shift + j;
                if (check_shift >= iBars(_Symbol, _Period)) break;
                if (iClose(_Symbol, _Period, check_shift) < levels[level_idx].price && IsPowerCandle(check_shift, false)) {
                    levels[level_idx].breakoutPowerCandleConfirmed = true;
                    levels[level_idx].breakoutPowerCandleShift = check_shift;
                    Comment("SFP: Support Breakout Confirmed at ", TimeToString(iTime(_Symbol, _Period, check_shift)));
                    break;
                }
            }
        } else if (levels[level_idx].breakoutDetected) {
            levels[level_idx].breakoutDetected = false;
            levels[level_idx].breakoutPowerCandleConfirmed = false;
        }
    }

    if (levels[level_idx].breakoutPowerCandleConfirmed && !levels[level_idx].reclaimPowerCandleConfirmed) {
        int bars_since_power_breakout = current_bar_shift - levels[level_idx].breakoutPowerCandleShift;
        if (bars_since_power_breakout > ReclaimLookbackCandles) {
            levels[level_idx].breakoutPowerCandleConfirmed = false;
            levels[level_idx].breakoutDetected = false;
        } else if (current_close >= levels[level_idx].price) {
            if (!levels[level_idx].reclaimDetected) {
                levels[level_idx].reclaimDetected = true;
                levels[level_idx].reclaimCandleShift = current_bar_shift;
            }
            for (int j = 0; j <= ReclaimGraceCandles; j++) {
                int check_shift = current_bar_shift + j;
                if (check_shift >= iBars(_Symbol, _Period)) break;
                if (iClose(_Symbol, _Period, check_shift) > levels[level_idx].price && IsPowerCandle(check_shift, true)) {
                    levels[level_idx].reclaimPowerCandleConfirmed = true;
                    levels[level_idx].reclaimPowerCandleShift = check_shift;
                    Comment("SFP: Support Reclaim Confirmed at ", TimeToString(iTime(_Symbol, _Period, check_shift)));
                    break;
                }
            }
        } else if (levels[level_idx].reclaimDetected) {
            levels[level_idx].reclaimDetected = false;
            levels[level_idx].reclaimPowerCandleConfirmed = false;
        }
    }

    if (levels[level_idx].reclaimPowerCandleConfirmed && !levels[level_idx].fvgFoundOnReclaim && !levels[level_idx].tradePlaced) {
        if (HasFVG(levels[level_idx].reclaimPowerCandleShift, true)) {
            levels[level_idx].fvgFoundOnReclaim = true;
            levels[level_idx].fvgCandleShift = levels[level_idx].reclaimPowerCandleShift;
            double fvg_candle_high = iHigh(_Symbol, _Period, levels[level_idx].fvgCandleShift);
            double fvg_candle_low = iLow(_Symbol, _Period, levels[level_idx].fvgCandleShift);
            double entry_price = (fvg_candle_high + fvg_candle_low) / 2.0;
            SetLimitOrder(ORDER_TYPE_BUY_LIMIT, entry_price);
            levels[level_idx].tradePlaced = true;
            TradesToday++;
            Comment("SFP: BUY LIMIT placed for ", levels[level_idx].price, " at ", entry_price);
        }
    }
}

// Check session
bool IsWithinSession() {
    datetime gm = TimeGMT();
    MqlDateTime dt;
    TimeToStruct(gm, dt);
    int minutes = dt.hour * 60 + dt.min;
    bool ok = false;
    if (TradeNewYork && minutes >= 12 * 60 && minutes < 21 * 60) ok = true;
    if (TradeLondon && minutes >= 7 * 60 && minutes < 12 * 60) ok = true;
    if (TradeTokyo && minutes >= 0 && minutes < 7 * 60) ok = true;
    if (TradeSydney && (minutes >= 22 * 60 || minutes < 0)) ok = true;
    return ok;
}

// Manage pending orders
void ManagePendingOrders() {
    for (int i = ArraySize(pendingOrders) - 1; i >= 0; i--) {
        if (!OrderSelect(pendingOrders[i].ticket)) {
            ArrayRemove(pendingOrders, i, 1);
            continue;
        }
        int bars_since_setup = iBarShift(_Symbol, _Period, pendingOrders[i].setupTime);
        if (bars_since_setup >= PendingOrderExpiryCandles) {
            if (Trade.OrderDelete(pendingOrders[i].ticket)) {
                ArrayRemove(pendingOrders, i, 1);
            }
        }
    }
}

// Breakeven check
// Breakeven check
void CheckBreakeven() {
    if (!EnableBreakeven) return;

    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (!PositionSelectByTicket(ticket) || PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber) continue;

        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double sl = PositionGetDouble(POSITION_SL);
        double tp = PositionGetDouble(POSITION_TP);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        
        if(sl == 0) continue; // Cannot manage a trade with no initial SL

        double risk = MathAbs(openPrice - sl);
        if(risk == 0) continue; // Avoid division by zero or nonsensical calculations

        // Get the live market tick for accurate checks
        MqlTick current_tick;
        if(!SymbolInfoTick(_Symbol, current_tick)) continue; 

        // --- CORRECTED AND ROBUST LOGIC ---

        if (posType == POSITION_TYPE_BUY) {
            // 1. Define trigger and new SL specifically for a BUY
            double triggerPrice = openPrice + risk * BreakevenTriggerReward;
            double newSL = openPrice + risk * BreakevenReward;

            // 2. Check if already at breakeven
            if (sl >= newSL) continue;

            // 3. Check if trigger is met (using current bid price)
            if (current_tick.bid >= triggerPrice) {
                // 4. Before modifying, ensure new SL is valid (below current bid)
                if (newSL < current_tick.bid) {
                    if(Trade.PositionModify(ticket, newSL, tp)) {
                        Print("Breakeven triggered for BUY position #", ticket, ". New SL set to ", DoubleToString(newSL, _Digits));
                    }
                }
            }
        }
        else if (posType == POSITION_TYPE_SELL) {
            // 1. Define trigger and new SL specifically for a SELL
            double triggerPrice = openPrice - risk * BreakevenTriggerReward; // <-- TYPO FIXED
            double newSL = openPrice - risk * BreakevenReward;

            // 2. Check if already at breakeven
            if (sl <= newSL) continue;

            // 3. Check if trigger is met (using current ask price)
            if (current_tick.ask <= triggerPrice) {
                // 4. Before modifying, ensure new SL is valid (above current ask)
                if (newSL > current_tick.ask) {
                    if(Trade.PositionModify(ticket, newSL, tp)) {
                        Print("Breakeven triggered for SELL position #", ticket, ". New SL set to ", DoubleToString(newSL, _Digits));
                    }
                }
            }
        }
    }
}
// Reversal exit
void CheckReversalExit() {
    if (!EnableReversalExit) return;
    int hiIdx = iHighest(_Symbol, _Period, MODE_HIGH, LookbackHighLow, 2);
    int loIdx = iLowest(_Symbol, _Period, MODE_LOW, LookbackHighLow, 2);
    double highestHigh = iHigh(_Symbol, _Period, hiIdx);
    double lowestLow = iLow(_Symbol, _Period, loIdx);
    double close1 = iClose(_Symbol, _Period, 1);
    bool revBuy = (close1 > highestHigh);
    bool revSell = (close1 < lowestLow);
    for (int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if (!PositionSelectByTicket(ticket) || PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber) continue;
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        if (revBuy && posType == POSITION_TYPE_SELL) Trade.PositionClose(ticket);
        if (revSell && posType == POSITION_TYPE_BUY) Trade.PositionClose(ticket);
    }
}

// --- Main Functions ---

int OnInit() {
    ATR_Handle = iATR(_Symbol, _Period, ATR_Period);
    if (ATR_Handle == INVALID_HANDLE) {
        Print("ATR initialization failed");
        return INIT_FAILED;
    }
    Trade.SetExpertMagicNumber(EA_MagicNumber);
    ChartSetInteger(ChartID(), CHART_SHOW_GRID, false);
    return INIT_SUCCEEDED;
}

void OnTick() {
    datetime currentBarTime = iTime(_Symbol, _Period, 0);
    if (currentBarTime != LastBarTime) {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        if (dt.day != LastTradeDay) {
            TradesToday = 0;
            LastTradeDay = dt.day;
        }
        if (TradesToday >= MaxTradesPerDay || !IsWithinSession()) return;
        UpdateLevels();
        UpdateIndicatorPlots();
        for (int i = 0; i < ArraySize(levels); i++) {
            if (levels[i].isResistance) ProcessResistanceLevel(i);
            else ProcessSupportLevel(i);
        }
        ManagePendingOrders();
        LastBarTime = currentBarTime;
    }
    CheckBreakeven();
    CheckReversalExit();
}

void OnDeinit(const int reason) {
    IndicatorRelease(ATR_Handle);
    ObjectsDeleteAll(0, "Level_");
    ObjectsDeleteAll(0, "PowerCandle_");
    ObjectsDeleteAll(0, "FVG_");
}