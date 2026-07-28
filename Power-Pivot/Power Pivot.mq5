//+------------------------------------------------------------------+
//|                                                Power Pivot.mq5  |
//|                           Power Pivot Expert Advisor             |
//|                Built with Multi-Timeframe & Integrated Indicators|
//+------------------------------------------------------------------+
#property copyright "Belema"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Trades Power Pivots with power candle confirmation near multi-timeframe levels."
#property description "Adapted from Belema SFP Bot."

// --- Includes ---
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>

// --- Enums ---
enum ENUM_ORDER_EXECUTION_TYPE
  {
   EXECUTION_TYPE_LIMIT,  // Place a Limit Order
   EXECUTION_TYPE_MARKET // Place a Market Order
  };

// --- Input Parameters ---

// Session Filters
input bool TradeNewYork = true;        // Trade during New York session
input bool TradeLondon  = true;        // Trade during London session
input bool TradeTokyo   = false;       // Trade during Tokyo session
input bool TradeSydney  = false;       // Trade during Sydney session

// Multi-Timeframe POI Settings
input bool EnableM5_POI  = true;        // Enable 5 Minute POI
input bool EnableM15_POI = true;        // Enable 15 Minute POI
input bool EnableM30_POI = true;        // Enable 30 Minute POI
input bool EnableH1_POI  = true;        // Enable 1 Hour POI
input bool EnableH4_POI  = true;        // Enable 4 Hour POI
input bool EnableD1_POI  = false;       // Enable Daily POI
input int MaxPOIPerTF = 1; // Maximum number of POI per timeframe

// --- Higher-Timeframe Trend Filter ---
input bool          UseHTFPowerCandleFilter   = true;      // Enable/Disable the HTF Power Candle trend filter
input ENUM_TIMEFRAMES HTFPowerCandleTimeframe = PERIOD_H4; // Timeframe for the trend filter (e.g., H1, H4, D1)

// Power Pivot Core Logic Settings
input int  LeftBars                = 15;    // Bars to left for pivot detection
input int  RightBars               = 15;    // Bars to right for pivot detection
input int  PendingOrderExpiryCandles = 10;  // Cancel pending order after this many candles
input int  LevelExpiryCandles      = 50;    // Expire S/R level after this many bars beyond it
input double MaxDistanceFromLevelAtrMultiplier = 0.1; // ATR multiplier to filter setups too far from level (0 = disabled)

// Risk & Trade Management
input ENUM_ORDER_EXECUTION_TYPE OrderExecutionType = EXECUTION_TYPE_LIMIT; // Choose order execution type
input bool   EnableHedge           = true;  // Enable/Disable hedging trades
input int    ATR_Period            = 14;    // ATR period for stop loss (on custom 35-min TF)
input double ATR_SL_Multiplier     = 2.0;   // ATR multiplier for stop loss
input double RiskPercent           = 1.0;   // Risk percentage per trade
input double RR_Ratio              = 2.0;   // Risk-reward ratio for take profit
input int    MaxTradesPerDay       = 2;     // Max trades per day
input int    MaxTradesPerLevel     = 1;     // Max trades to take at a single S/R level
input int    EA_MagicNumber        = 12345; // Magic number for trades
input double MinTradeDistanceAtrMultiplier = 0.5; // Minimum distance from existing trades as an ATR multiplier (0 = disabled)

// Partial Profit Taking
input bool   EnablePartialClose    = true;  // Enable partial close
input double PartialCloseAtrMultiplier = 1.0; // ATR multiplier to trigger partial close
input double PartialClosePercent   = 50.0;  // % of position to close

// Exit & Breakeven Conditions
input bool   EnableBreakeven        = true;  // Enable breakeven adjustment
input double BreakevenTriggerReward = 1.0;   // Reward multiplier to trigger breakeven
input double BreakevenReward        = 0.1;   // Reward multiplier for new SL
input bool   EnableReversalExit     = true;  // Enable reversal exit
input int    LookbackHighLow        = 5;     // Lookback period for reversal exit
input bool   EnableLossReversalExit = true;  // Enable reversal exit when in loss
input int    LossLookbackHighLow    = 5;     // Lookback period for loss reversal exit

// Premium & Discount Filter
input bool EnablePremiumDiscountFilter = true; // Enable premium/discount filter on HTF range
input int RangeLookback = 20; // Lookback for premium/discount range on HTF

// Indicator Settings
input int    PowerCandlePeriods       = 14;      // SMA Periods for power candles
input double PowerCandleMultiplier    = 1.5;     // Multiplier for power candles
input color  BullPowerColor           = clrLimeGreen; // Bullish power candle color
input color  BearPowerColor           = clrRed;       // Bearish power candle color
input color  BullFvgColor             = clrDarkGreen; // Bullish FVG color
input color  BearFvgColor             = clrDarkRed;   // Bearish FVG color
input int    MaxFvgsToDisplay         = 5000;    // Max FVGs to display on chart
input int    MaxPowerCandlesToDisplay = 1000;    // Max power candles to display

// FVG Logic
input bool UseFVGConfirmation = true; // Enable FVG confirmation for trades
input int  FindFVGLimit       = 10;   // Max candles to find FVG after power candle

// --- Global Variables & Structures ---

// Structure for levels and Power Pivot state
struct LevelInfo
  {
   double          price;                     // Price of the level
   ENUM_TIMEFRAMES timeframe;                 // Timeframe of the level
   datetime        time;                      // Time of the pivot bar
   bool            isResistance;              // True if resistance, false if support
   int             tradesTaken;               // Counter for trades taken at this level
   int             barsBeyondLevel;           // Number of consecutive bars beyond the level
   bool            expired;                   // True if level is expired
  };
LevelInfo levels[]; // Array of detected levels

// Structure for pending orders
struct PendingOrderInfo
  {
   ulong    ticket;    // Order ticket
   datetime setupTime; // Time order was placed
  };
PendingOrderInfo pendingOrders[];

// Structure for FVG objects
struct FVGObject
  {
   string   name;      // Object name
   double   high;      // High of FVG
   double   low;       // Low of FVG
   datetime startTime; // Start time of FVG
  };
FVGObject bullFvgs[];
FVGObject bearFvgs[];

// Array for power candle objects
string powerCandleObjects[];

// Array for partial closed positions
ulong partialClosedTickets[];

// Trade management objects
CTrade        Trade;
CPositionInfo PositionInfo;
COrderInfo    OrderInfo;

// Trade counters
int TradesToday    = 0;
int LastTradeDay   = 0;

// New bar tracking
datetime LastBarTime = 0;

// HTF Trend global variable
int htfTrend = 0; // 1 for Bullish, -1 for Bearish, 0 for Neutral/Disabled

// --- Helper Functions ---

// Check if there are any open buy positions with our magic number
bool HasOpenBuyPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i))
        {
         if(PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber && PositionInfo.PositionType() == POSITION_TYPE_BUY)
           {
            return true;
           }
        }
     }
   return false;
  }

// Check if there are any open sell positions with our magic number
bool HasOpenSellPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i))
        {
         if(PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber && PositionInfo.PositionType() == POSITION_TYPE_SELL)
           {
            return true;
           }
        }
     }
   return false;
  }

// Checks if there is an open trade originating from a specific level price.
bool IsOpenTradeFromLevel(double level_price)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i))
        {
         if(PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber)
           {
            string comment = PositionInfo.Comment();
            int at_pos = StringFind(comment, "@ ");
            if(at_pos != -1)
              {
               string price_str = StringSubstr(comment, at_pos + 2);
               double trade_level_price = StringToDouble(price_str);
               if(MathAbs(trade_level_price - level_price) < _Point * 5)
                 {
                  return true;
                 }
              }
           }
        }
     }
   return false;
  }

// Checks for a power candle on ANY specified timeframe.
bool IsPowerCandleTF(int shift, bool isBullish, ENUM_TIMEFRAMES timeframe)
  {
   if(shift + PowerCandlePeriods >= iBars(_Symbol, timeframe)) return false;
   
   double sum_range = 0;
   for(int i = 0; i < PowerCandlePeriods; i++)
     {
      if(shift + i >= iBars(_Symbol, timeframe)) return false;
      double open_i = iOpen(_Symbol, timeframe, shift + i);
      double close_i = iClose(_Symbol, timeframe, shift + i);
      sum_range += MathAbs(close_i - open_i);
     }
   double avg_range = sum_range / PowerCandlePeriods;
   
   double open_curr = iOpen(_Symbol, timeframe, shift);
   double close_curr = iClose(_Symbol, timeframe, shift);
   double body_curr = MathAbs(close_curr - open_curr);
   
   bool is_large = body_curr > avg_range * PowerCandleMultiplier;
   bool is_correct_direction = (isBullish && close_curr > open_curr) || (!isBullish && close_curr < open_curr);
   
   return is_large && is_correct_direction;
  }

// Check if candle is a power candle on the chart's timeframe
bool IsPowerCandle(int shift, bool isBullish)
  {
   return IsPowerCandleTF(shift, isBullish, _Period);
  }

// Check for Fair Value Gap
bool HasFVG(int shift, bool isBullish)
  {
   if(shift + 2 >= iBars(_Symbol, _Period)) return false;
   double high_curr = iHigh(_Symbol, _Period, shift);
   double low_curr = iLow(_Symbol, _Period, shift);
   double high_prev2 = iHigh(_Symbol, _Period, shift + 2);
   double low_prev2 = iLow(_Symbol, _Period, shift + 2);
   if(isBullish) return low_curr > high_prev2;
   else return high_curr < low_prev2;
  }

// Plot power candle
void PlotPowerCandle(int shift, bool isBullish)
  {
   if(shift >= iBars(_Symbol, _Period)) return;
   datetime t = iTime(_Symbol, _Period, shift);
   double price = isBullish ? iLow(_Symbol, _Period, shift) : iHigh(_Symbol, _Period, shift);
   color paint = isBullish ? BullPowerColor : BearPowerColor;
   int arrow_code = isBullish ? 233 : 234;
   string name = "PowerCandle_" + TimeToString(t) + "_" + IntegerToString(shift);
   if(ObjectFind(0, name) == -1)
     {
      if(ObjectCreate(0, name, OBJ_ARROW, 0, t, price))
        {
         ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrow_code);
         ObjectSetInteger(0, name, OBJPROP_COLOR, paint);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
         int size = ArraySize(powerCandleObjects);
         ArrayResize(powerCandleObjects, size + 1);
         powerCandleObjects[size] = name;
         if(ArraySize(powerCandleObjects) > MaxPowerCandlesToDisplay)
           {
            string old_name = powerCandleObjects[0];
            ObjectDelete(0, old_name);
            ArrayRemove(powerCandleObjects, 0, 1);
           }
        }
     }
  }

// Plot FVG
void PlotFVG(int shift, bool isBullish)
  {
   if(shift + 2 >= iBars(_Symbol, _Period)) return;
   datetime time_curr_bar = iTime(_Symbol, _Period, shift);
   datetime time_prev1_bar = iTime(_Symbol, _Period, shift + 1);
   double high_curr = iHigh(_Symbol, _Period, shift);
   double low_curr = iLow(_Symbol, _Period, shift);
   double high_prev2 = iHigh(_Symbol, _Period, shift + 2);
   double low_prev2 = iLow(_Symbol, _Period, shift + 2);
   double fvg_p1, fvg_p2;
   color fvg_color;
   string prefix;
   if(isBullish)
     {
      if(low_curr <= high_prev2) return;
      fvg_p1 = high_prev2;
      fvg_p2 = low_curr;
      fvg_color = BullFvgColor;
      prefix = "FVG_Bull_";
     }
   else
     {
      if(high_curr >= low_prev2) return;
      fvg_p1 = low_prev2;
      fvg_p2 = high_curr;
      fvg_color = BearFvgColor;
      prefix = "FVG_Bear_";
     }
   string name = prefix + TimeToString(time_curr_bar) + "_" + IntegerToString(shift);
   if(ObjectFind(0, name) == -1)
     {
      if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, time_prev1_bar, fvg_p1, time_curr_bar, fvg_p2))
        {
         ObjectSetInteger(0, name, OBJPROP_COLOR, fvg_color);
         ObjectSetInteger(0, name, OBJPROP_FILL, true);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
         FVGObject new_fvg;
         new_fvg.name = name;
         new_fvg.high = MathMax(fvg_p1, fvg_p2);
         new_fvg.low = MathMin(fvg_p1, fvg_p2);
         new_fvg.startTime = time_prev1_bar;
         if(isBullish)
           {
            int size = ArraySize(bullFvgs);
            ArrayResize(bullFvgs, size + 1);
            bullFvgs[size] = new_fvg;
            if(ArraySize(bullFvgs) > MaxFvgsToDisplay)
              {
               ObjectDelete(0, bullFvgs[0].name);
               ArrayRemove(bullFvgs, 0, 1);
              }
           }
         else
           {
            int size = ArraySize(bearFvgs);
            ArrayResize(bearFvgs, size + 1);
            bearFvgs[size] = new_fvg;
            if(ArraySize(bearFvgs) > MaxFvgsToDisplay)
              {
               ObjectDelete(0, bearFvgs[0].name);
               ArrayRemove(bearFvgs, 0, 1);
              }
           }
        }
     }
  }

// Update indicators
void UpdateIndicatorPlots()
  {
   int current_bar_shift = 0;
   int prev_completed_bar_shift = 1;
   if(iBars(_Symbol, _Period) < 1) return;
   datetime current_time = iTime(_Symbol, _Period, current_bar_shift);
   double low_current = iLow(_Symbol, _Period, current_bar_shift);
   double high_current = iHigh(_Symbol, _Period, current_bar_shift);
   for(int i = ArraySize(bullFvgs) - 1; i >= 0; i--)
     {
      if(low_current <= bullFvgs[i].high)
        {
         ObjectDelete(0, bullFvgs[i].name);
         ArrayRemove(bullFvgs, i, 1);
        }
      else
        {
         ObjectSetInteger(0, bullFvgs[i].name, OBJPROP_TIME, 1, current_time);
        }
     }
   for(int i = ArraySize(bearFvgs) - 1; i >= 0; i--)
     {
      if(high_current >= bearFvgs[i].low)
        {
         ObjectDelete(0, bearFvgs[i].name);
         ArrayRemove(bearFvgs, i, 1);
        }
      else
        {
         ObjectSetInteger(0, bearFvgs[i].name, OBJPROP_TIME, 1, current_time);
        }
     }
   if(iBars(_Symbol, _Period) <= prev_completed_bar_shift) return;
   if(IsPowerCandle(prev_completed_bar_shift, true)) PlotPowerCandle(prev_completed_bar_shift, true);
   if(IsPowerCandle(prev_completed_bar_shift, false)) PlotPowerCandle(prev_completed_bar_shift, false);
   if(HasFVG(prev_completed_bar_shift, true)) PlotFVG(prev_completed_bar_shift, true);
   if(HasFVG(prev_completed_bar_shift, false)) PlotFVG(prev_completed_bar_shift, false);
  }

// Determines the market trend from the Higher Timeframe.
void UpdateHTFPowerCandleTrend()
  {
   if(!UseHTFPowerCandleFilter)
     {
      htfTrend = 0; 
      return;
     }

   for(int i = 1; i < 2000; i++) 
     {
      if (i >= iBars(_Symbol, HTFPowerCandleTimeframe)) break;

      if(IsPowerCandleTF(i, true, HTFPowerCandleTimeframe))
        {
         if(htfTrend != 1)  
            Print("HTF Trend Update: Last power candle on ", EnumToString(HTFPowerCandleTimeframe), " was BULLISH. EA will now only look for BUY trades.");
         htfTrend = 1;
         return;
        }
        
      if(IsPowerCandleTF(i, false, HTFPowerCandleTimeframe))
        {
         if(htfTrend != -1) 
            Print("HTF Trend Update: Last power candle on ", EnumToString(HTFPowerCandleTimeframe), " was BEARISH. EA will now only look for SELL trades.");
         htfTrend = -1;
         return;
        }
     }
  }

// Pivot high check
bool IsPivotHighTF(ENUM_TIMEFRAMES tf, int idx)
  {
   int total_bars_tf = iBars(_Symbol, tf);
   if(idx < RightBars || idx + LeftBars >= total_bars_tf) return false;
   double value = iHigh(_Symbol, tf, idx);
   for(int i = idx - RightBars; i <= idx + LeftBars; i++)
     {
      if(i == idx) continue;
      if(iHigh(_Symbol, tf, i) >= value) return false;
     }
   return true;
  }

// Pivot low check
bool IsPivotLowTF(ENUM_TIMEFRAMES tf, int idx)
  {
   int total_bars_tf = iBars(_Symbol, tf);
   if(idx < RightBars || idx + LeftBars >= total_bars_tf) return false;
   double value = iLow(_Symbol, tf, idx);
   for(int i = idx - RightBars; i <= idx + LeftBars; i++)
     {
      if(i == idx) continue;
      if(iLow(_Symbol, tf, i) <= value) return false;
     }
   return true;
  }

// Detect pivots using the pivot candle's timestamp for uniqueness.
void DetectPivots(ENUM_TIMEFRAMES tf)
  {
   int totalBars = iBars(_Symbol, tf);
   if(totalBars < LeftBars + RightBars + 1) return;

   int idx = RightBars;
   if(idx >= totalBars || idx < 0) return;

   datetime pivot_time = iTime(_Symbol, tf, idx);
   datetime end_plot_time = iTime(_Symbol, _Period, 0);

   if(IsPivotHighTF(tf, idx))
     {
      double pivot_price = iHigh(_Symbol, tf, idx);
      bool exists = false;
      for(int i = 0; i < ArraySize(levels); i++)
        {
         if(levels[i].timeframe == tf && levels[i].isResistance && levels[i].time == pivot_time)
           {
            exists = true;
            break;
           }
        }
      if(!exists) AddLevel(pivot_price, tf, pivot_time, true, end_plot_time);
     }

   if(IsPivotLowTF(tf, idx))
     {
      double pivot_price = iLow(_Symbol, tf, idx);
      bool exists = false;
      for(int i = 0; i < ArraySize(levels); i++)
        {
         if(levels[i].timeframe == tf && !levels[i].isResistance && levels[i].time == pivot_time)
           {
            exists = true;
            break;
           }
        }
      if(!exists) AddLevel(pivot_price, tf, pivot_time, false, end_plot_time);
     }
  }

// Add level
void AddLevel(double price, ENUM_TIMEFRAMES tf, datetime time, bool isResistance, datetime end_plot_time)
  {
   // Check and enforce max POI per timeframe per type
   int count = 0;
   int oldest_index = -1;
   datetime oldest_time = D'3000.01.01'; // Future date to find min
   for(int i = 0; i < ArraySize(levels); i++)
     {
      if(levels[i].timeframe == tf && levels[i].isResistance == isResistance && !levels[i].expired)
        {
         count++;
         if(levels[i].time < oldest_time)
           {
            oldest_time = levels[i].time;
            oldest_index = i;
           }
        }
     }
   if(count >= MaxPOIPerTF && MaxPOIPerTF > 0 && oldest_index >= 0)
     {
      // Delete oldest level
      string tfStr = EnumToString(tf);
      string typeStr = levels[oldest_index].isResistance ? "Resistance" : "Support";
      string name = "Level_" + tfStr + "_" + typeStr + "_" + TimeToString(levels[oldest_index].time);
      ObjectDelete(0, name);
      ObjectDelete(0, name + "_Label");
      ArrayRemove(levels, oldest_index, 1);
      Print("Removed oldest ", typeStr, " POI on ", tfStr, " to enforce max limit of ", IntegerToString(MaxPOIPerTF));
     }

   // Now add the new level
   int n = ArraySize(levels);
   ArrayResize(levels, n + 1);
   levels[n].price = price;
   levels[n].timeframe = tf;
   levels[n].time = time;
   levels[n].isResistance = isResistance;
   levels[n].tradesTaken = 0;
   levels[n].barsBeyondLevel = 0;
   levels[n].expired = false;
   string tfStr = EnumToString(tf);
   string typeStr = isResistance ? "Resistance" : "Support";
   string name = "Level_" + tfStr + "_" + typeStr + "_" + TimeToString(time);
   if(ObjectCreate(0, name, OBJ_TREND, 0, time, price, end_plot_time, price))
     {
      ObjectSetInteger(0, name, OBJPROP_COLOR, isResistance ? clrRed : clrBlue);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_RAY, true);
      string label_name = name + "_Label";
      if(ObjectCreate(0, label_name, OBJ_TEXT, 0, time, price))
        {
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
void UpdateLevels()
  {
   ENUM_TIMEFRAMES enabledTFs[] = {PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1};
   bool enables[] = {EnableM5_POI, EnableM15_POI, EnableM30_POI, EnableH1_POI, EnableH4_POI, EnableD1_POI};
   for(int i = 0; i < ArraySize(enabledTFs); i++)
     {
      if(enables[i]) DetectPivots(enabledTFs[i]);
     }
  }

// Calculates a custom ATR based on a 35-minute timeframe.
double GetCustom35MinATR()
  {
   int synthetic_bars_needed = ATR_Period + 1;
   int m5_bars_needed = synthetic_bars_needed * 7;
   MqlRates m5_rates[];
   ArraySetAsSeries(m5_rates, true);
   if(CopyRates(_Symbol, PERIOD_M5, 0, m5_bars_needed, m5_rates) < m5_bars_needed)
     {
      Print("Not enough M5 history to calculate 35-min ATR.");
      return -1.0;
     }

   double sum_tr = 0;

   for(int i = 0; i < ATR_Period; i++)
     {
      int start_idx = i * 7;
      int end_idx = start_idx + 6;
      int prev_start_idx = (i + 1) * 7;
      int prev_end_idx = prev_start_idx + 6;
      if(prev_end_idx >= ArraySize(m5_rates))
        {
         Print("Not enough M5 rates for previous close in custom ATR calc.");
         return -1.0;
        }
      double high = 0;
      double low = 1e10;
      for(int j = start_idx; j <= end_idx; j++)
        {
         high = MathMax(high, m5_rates[j].high);
         low = MathMin(low, m5_rates[j].low);
        }
      double prev_close = m5_rates[prev_end_idx].close;
      double tr = MathMax(high, prev_close) - MathMin(low, prev_close);
      sum_tr += tr;
     }
   return sum_tr / ATR_Period;
  }

// Function to check distance from existing trades AND pending orders
bool IsTradeTooClose(double newEntryPrice)
  {
   if(MinTradeDistanceAtrMultiplier <= 0) return false;

   double atr = GetCustom35MinATR();
   if(atr <= 0)
     {
      Print("Could not get ATR for distance check. Allowing trade as a failsafe.");
      return false;
     }

   double minDistance = atr * MinTradeDistanceAtrMultiplier;

   // Loop through OPEN POSITIONS
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i) && PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber)
        {
         double existingOpenPrice = PositionInfo.PriceOpen();
         if(MathAbs(newEntryPrice - existingOpenPrice) < minDistance)
           {
            Print("Trade Blocked: New trade at ", DoubleToString(newEntryPrice, _Digits),
                  " is too close to existing OPEN POSITION at ", DoubleToString(existingOpenPrice, _Digits),
                  ". Required distance: ", DoubleToString(minDistance, _Digits));
            return true;
           }
        }
     }

   // Loop through PENDING ORDERS
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket) && OrderGetInteger(ORDER_MAGIC) == EA_MagicNumber && OrderGetString(ORDER_SYMBOL) == _Symbol)
        {
         if(OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_LIMIT || OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_LIMIT)
           {
            double existingOrderPrice = OrderGetDouble(ORDER_PRICE_OPEN);
            if(MathAbs(newEntryPrice - existingOrderPrice) < minDistance)
              {
               Print("Trade Blocked: New trade at ", DoubleToString(newEntryPrice, _Digits),
                     " is too close to existing PENDING ORDER at ", DoubleToString(existingOrderPrice, _Digits),
                     ". Required distance: ", DoubleToString(minDistance, _Digits));
               return true;
              }
           }
        }
     }

   return false;
  }

// Places a trade based on the selected execution type.
bool PlaceTrade(ENUM_ORDER_TYPE type, double entryPrice, double level, bool isResistance, ENUM_TIMEFRAMES tf, datetime pivotTime)
  {
   if(TradesToday >= MaxTradesPerDay || !IsWithinSession()) return false;
   
   bool isBuyOrder = (type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT);
   bool isSellOrder = (type == ORDER_TYPE_SELL || type == ORDER_TYPE_SELL_LIMIT);

   if (EnableHedge)
     {
      if (isBuyOrder && HasOpenBuyPositions())
        {
         Print("Trade Blocked (Hedging ON): A Buy position is already open.");
         return false;
        }
      if (isSellOrder && HasOpenSellPositions())
        {
         Print("Trade Blocked (Hedging ON): A Sell position is already open.");
         return false;
        }
     }
   else
     {
      if (PositionsTotal() > 0 && (HasOpenBuyPositions() || HasOpenSellPositions()))
        {
         Print("Trade Blocked (Hedging OFF): A position is already open.");
         return false;
        }
     }

   double potentialEntryPrice = (OrderExecutionType == EXECUTION_TYPE_LIMIT) ? entryPrice : SymbolInfoDouble(_Symbol, isBuyOrder ? SYMBOL_ASK : SYMBOL_BID);
   if (IsTradeTooClose(potentialEntryPrice))
     {
      return false;
     }
   Print("   - Trade Spacing Filter: PASSED. New trade is a safe distance from existing positions/orders.");
   
   if(UseHTFPowerCandleFilter)
     {
      if(isBuyOrder && htfTrend == -1)
        {
         Print("Trade Blocked: Attempting to BUY, but HTF trend is BEARISH. Signal ignored.");
         return false;
        }
      if(isSellOrder && htfTrend == 1)
        {
         Print("Trade Blocked: Attempting to SELL, but HTF trend is BULLISH. Signal ignored.");
         return false;
        }
      Print("   - HTF Trend Filter: PASSED. Trade direction aligns with HTF trend.");
     }

   if(EnablePremiumDiscountFilter)
     {
      int htf_bars = iBars(_Symbol, HTFPowerCandleTimeframe);
      if(htf_bars < RangeLookback + 1)
        {
         Print("Not enough HTF bars for premium/discount filter. Skipping trade.");
         return false;
        }
      int high_shift = iHighest(_Symbol, HTFPowerCandleTimeframe, MODE_HIGH, RangeLookback, 1);
      int low_shift = iLowest(_Symbol, HTFPowerCandleTimeframe, MODE_LOW, RangeLookback, 1);
      double htf_high = iHigh(_Symbol, HTFPowerCandleTimeframe, high_shift);
      double htf_low = iLow(_Symbol, HTFPowerCandleTimeframe, low_shift);
      double midpoint = htf_low + (htf_high - htf_low) / 2.0;
      double current_price = iClose(_Symbol, _Period, 0);
      if(isSellOrder && current_price <= midpoint)
        {
         Print("Sell blocked: Price not in premium zone (above midpoint).");
         return false;
        }
      if(isBuyOrder && current_price >= midpoint)
        {
         Print("Buy blocked: Price not in discount zone (below midpoint).");
         return false;
        }
      Print("   - Premium/Discount Filter: PASSED.");
     }

   double atr_35m = GetCustom35MinATR();
   if(atr_35m <= 0)
     {
      Print("Failed to get custom 35-min ATR. Cannot place trade.");
      return false;
     }
   double slDistance = atr_35m * ATR_SL_Multiplier;
   
   double min_stop_points = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_stop_distance = min_stop_points * _Point;
   if(slDistance < min_stop_distance) slDistance = min_stop_distance;
   
   double lotSize = CalculateLotSize(slDistance);
   if(lotSize <= 0)
     {
      Print("Calculated lot size is zero or negative.");
      return false;
     }

   Trade.SetExpertMagicNumber(EA_MagicNumber);
   string tfStr = EnumToString(tf);
   string levelType = isResistance ? "Resistance" : "Support";
   
   string shortTradeType;
   if(type == ORDER_TYPE_BUY_LIMIT) shortTradeType = "BL";
   else if(type == ORDER_TYPE_SELL_LIMIT) shortTradeType = "SL";
   else if(type == ORDER_TYPE_BUY) shortTradeType = "BM";
   else if(type == ORDER_TYPE_SELL) shortTradeType = "SM";

   string shortTfStr = tfStr;
   StringReplace(shortTfStr, "PERIOD_", "");

   string comment = "Power Pivot " + shortTradeType + " " + shortTfStr + " POI(" + TimeToString(pivotTime, TIME_DATE | TIME_MINUTES) + ") @ " + DoubleToString(level, _Digits);
   
   if(type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT)
     {
      double normalized_entry = NormalizeDouble(entryPrice, _Digits);
      double sl = (type == ORDER_TYPE_BUY_LIMIT) ? normalized_entry - slDistance : normalized_entry + slDistance;
      double tp = (type == ORDER_TYPE_BUY_LIMIT) ? normalized_entry + slDistance * RR_Ratio : normalized_entry - slDistance * RR_Ratio;
      string tradeType = (type == ORDER_TYPE_BUY_LIMIT) ? "Buy Limit" : "Sell Limit";

      MqlTick tick;
      SymbolInfoTick(_Symbol, tick);
      if(type == ORDER_TYPE_BUY_LIMIT && normalized_entry >= tick.ask)
        {
         Print("Buy Limit price ", DoubleToString(normalized_entry, _Digits), " is invalid. Executing at Market.");
         return PlaceTrade(ORDER_TYPE_BUY, 0, level, isResistance, tf, pivotTime);
        }
      if(type == ORDER_TYPE_SELL_LIMIT && normalized_entry <= tick.bid)
        {
         Print("Sell Limit price ", DoubleToString(normalized_entry, _Digits), " is invalid. Executing at Market.");
         return PlaceTrade(ORDER_TYPE_SELL, 0, level, isResistance, tf, pivotTime);
        }

      bool order_sent = false;
      if(type == ORDER_TYPE_BUY_LIMIT)
        {
         if(Trade.BuyLimit(lotSize, normalized_entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment)) order_sent = true;
         else { Print("Buy Limit order failed: ", GetLastError()); return false; }
        }
      else
        {
         if(Trade.SellLimit(lotSize, normalized_entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment)) order_sent = true;
         else { Print("Sell Limit order failed: ", GetLastError()); return false; }
        }
      
      if(order_sent)
        {
         TradesToday++;
         ulong ticket = Trade.ResultOrder();
         if(ticket > 0)
           {
            int size = ArraySize(pendingOrders);
            ArrayResize(pendingOrders, size + 1);
            pendingOrders[size].ticket = ticket;
            pendingOrders[size].setupTime = iTime(_Symbol, _Period, 0);
            Print(">>> TRADE PLACED: ", tradeType, " at ", DoubleToString(normalized_entry, _Digits),
                  " triggered by ", tfStr, " ", levelType, " POI at ", DoubleToString(level, _Digits),
                  ". SL: ", DoubleToString(sl, _Digits), ", TP: ", DoubleToString(tp, _Digits),
                  ". Time: ", TimeToString(TimeCurrent()));
           }
         return true;
        }
     }
   else if(type == ORDER_TYPE_BUY || type == ORDER_TYPE_SELL)
     {
      double marketPrice = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = (type == ORDER_TYPE_BUY) ? marketPrice - slDistance : marketPrice + slDistance;
      double tp = (type == ORDER_TYPE_BUY) ? marketPrice + slDistance * RR_Ratio : marketPrice - slDistance * RR_Ratio;
      string tradeType = (type == ORDER_TYPE_BUY) ? "Buy Market" : "Sell Market";

      bool order_sent = false;
      if(type == ORDER_TYPE_BUY)
        {
         if(Trade.Buy(lotSize, _Symbol, marketPrice, sl, tp, comment)) order_sent = true;
         else { Print("Buy Market order failed: ", GetLastError()); return false; }
        }
      else
        {
         if(Trade.Sell(lotSize, _Symbol, marketPrice, sl, tp, comment)) order_sent = true;
         else { Print("Sell Market order failed: ", GetLastError()); return false; }
        }
      
      if(order_sent)
        {
         TradesToday++;
         Print(">>> TRADE EXECUTED: ", tradeType, " at ", DoubleToString(marketPrice, _Digits),
               " triggered by ", tfStr, " ", levelType, " POI at ", DoubleToString(level, _Digits),
               ". SL: ", DoubleToString(sl, _Digits), ", TP: ", DoubleToString(tp, _Digits),
               ". Time: ", TimeToString(TimeCurrent()));
         return true;
        }
     }
   return false;
  }

// Calculate lot size
double CalculateLotSize(double slDistance)
  {
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double riskAmount = accountBalance * (RiskPercent / 100.0);
   double slPoints = slDistance / tickSize;
   double lotSize = riskAmount / (slPoints * tickValue);
   lotSize = NormalizeDouble(lotSize, 2);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   return lotSize;
  }

// Process resistance level with Power Pivot logic
void ProcessResistanceLevel(int level_idx)
  {
   int current_bar_shift = 1;
   if(iBars(_Symbol, _Period) <= current_bar_shift) return;
   
   double current_close = iClose(_Symbol, _Period, current_bar_shift);
   double level_price = levels[level_idx].price;
   
   if(levels[level_idx].expired) return;

   if(current_close > level_price)
     {
      // Above resistance
      levels[level_idx].barsBeyondLevel++;
      if(levels[level_idx].barsBeyondLevel > LevelExpiryCandles)
        {
         levels[level_idx].expired = true;
         Print("Level Expired: Resistance at ", DoubleToString(level_price, _Digits), " expired after ", IntegerToString(LevelExpiryCandles), " bars beyond.");
         return;
        }

      // Check for bearish power candle without ATR filter
      if(IsPowerCandle(current_bar_shift, false) && levels[level_idx].tradesTaken < MaxTradesPerLevel && !IsOpenTradeFromLevel(level_price))
        {
         Print("--- Evaluating SELL on Bearish Power above Resistance at ", DoubleToString(level_price, _Digits), " ---");

         double entry_price = 0;
         int power_shift = current_bar_shift;
         if(UseFVGConfirmation)
           {
            Print("   - FVG Filter: ENABLED. Searching for Bearish FVG...");
            bool fvg_found = false;
            for(int i = 0; i < FindFVGLimit; i++)
              {
               int check_shift = power_shift - i;
               if(check_shift < 0) break;
               if(HasFVG(check_shift, false))
                 {
                  int middle_shift = check_shift + 1;
                  if(middle_shift < iBars(_Symbol, _Period))
                    {
                     entry_price = (iHigh(_Symbol, _Period, middle_shift) + iLow(_Symbol, _Period, middle_shift)) / 2.0;
                     fvg_found = true;
                     Print("   - FVG Filter: PASSED. Found FVG, entry price set to ", DoubleToString(entry_price, _Digits));
                     break;
                    }
                 }
              }
            if(!fvg_found)
              {
               Print("   - FVG Filter: FAILED. No Bearish FVG found. Signal ignored.");
               return;
              }
           }
         else
           {
            Print("   - FVG Filter: DISABLED. Using Power Candle for entry.");
            double power_open = iOpen(_Symbol, _Period, power_shift);
            double power_close = iClose(_Symbol, _Period, power_shift);
            entry_price = (power_open + power_close) / 2.0;
           }

         if(entry_price > 0 || OrderExecutionType == EXECUTION_TYPE_MARKET)
           {
            ENUM_ORDER_TYPE order_type_to_place = (OrderExecutionType == EXECUTION_TYPE_MARKET) ? ORDER_TYPE_SELL : ORDER_TYPE_SELL_LIMIT;
            if(PlaceTrade(order_type_to_place, entry_price, level_price, levels[level_idx].isResistance, levels[level_idx].timeframe, levels[level_idx].time))
              {
               levels[level_idx].tradesTaken++;
              }
           }
        }
     }
   else
     {
      // Below resistance
      levels[level_idx].barsBeyondLevel = 0;

      // Check for bearish power candle with ATR filter
      if(IsPowerCandle(current_bar_shift, false) && levels[level_idx].tradesTaken < MaxTradesPerLevel && !IsOpenTradeFromLevel(level_price))
        {
         Print("--- Evaluating SELL on Bearish Power below Resistance at ", DoubleToString(level_price, _Digits), " ---");

         double atr = GetCustom35MinATR();
         if(atr > 0 && MaxDistanceFromLevelAtrMultiplier > 0)
           {
            double distance = MathAbs(current_close - level_price);
            if(distance > atr * MaxDistanceFromLevelAtrMultiplier)
              {
               Print("   - ATR Distance Filter: FAILED. Price too far from level (", DoubleToString(distance, _Digits), " > ", DoubleToString(atr * MaxDistanceFromLevelAtrMultiplier, _Digits), "). Signal ignored.");
               return;
              }
            Print("   - ATR Distance Filter: PASSED.");
           }

         double entry_price = 0;
         int power_shift = current_bar_shift;
         if(UseFVGConfirmation)
           {
            Print("   - FVG Filter: ENABLED. Searching for Bearish FVG...");
            bool fvg_found = false;
            for(int i = 0; i < FindFVGLimit; i++)
              {
               int check_shift = power_shift - i;
               if(check_shift < 0) break;
               if(HasFVG(check_shift, false))
                 {
                  int middle_shift = check_shift + 1;
                  if(middle_shift < iBars(_Symbol, _Period))
                    {
                     entry_price = (iHigh(_Symbol, _Period, middle_shift) + iLow(_Symbol, _Period, middle_shift)) / 2.0;
                     fvg_found = true;
                     Print("   - FVG Filter: PASSED. Found FVG, entry price set to ", DoubleToString(entry_price, _Digits));
                     break;
                    }
                 }
              }
            if(!fvg_found)
              {
               Print("   - FVG Filter: FAILED. No Bearish FVG found. Signal ignored.");
               return;
              }
           }
         else
           {
            Print("   - FVG Filter: DISABLED. Using Power Candle for entry.");
            double power_open = iOpen(_Symbol, _Period, power_shift);
            double power_close = iClose(_Symbol, _Period, power_shift);
            entry_price = (power_open + power_close) / 2.0;
           }

         if(entry_price > 0 || OrderExecutionType == EXECUTION_TYPE_MARKET)
           {
            ENUM_ORDER_TYPE order_type_to_place = (OrderExecutionType == EXECUTION_TYPE_MARKET) ? ORDER_TYPE_SELL : ORDER_TYPE_SELL_LIMIT;
            if(PlaceTrade(order_type_to_place, entry_price, level_price, levels[level_idx].isResistance, levels[level_idx].timeframe, levels[level_idx].time))
              {
               levels[level_idx].tradesTaken++;
              }
           }
        }
     }
  }

// Process support level with Power Pivot logic
void ProcessSupportLevel(int level_idx)
  {
   int current_bar_shift = 1;
   if(iBars(_Symbol, _Period) <= current_bar_shift) return;

   double current_close = iClose(_Symbol, _Period, current_bar_shift);
   double level_price = levels[level_idx].price;
   
   if(levels[level_idx].expired) return;

   if(current_close < level_price)
     {
      // Below support
      levels[level_idx].barsBeyondLevel++;
      if(levels[level_idx].barsBeyondLevel > LevelExpiryCandles)
        {
         levels[level_idx].expired = true;
         Print("Level Expired: Support at ", DoubleToString(level_price, _Digits), " expired after ", IntegerToString(LevelExpiryCandles), " bars beyond.");
         return;
        }

      // Check for bullish power candle without ATR filter
      if(IsPowerCandle(current_bar_shift, true) && levels[level_idx].tradesTaken < MaxTradesPerLevel && !IsOpenTradeFromLevel(level_price))
        {
         Print("--- Evaluating BUY on Bullish Power below Support at ", DoubleToString(level_price, _Digits), " ---");

         double entry_price = 0;
         int power_shift = current_bar_shift;
         if(UseFVGConfirmation)
           {
            Print("   - FVG Filter: ENABLED. Searching for Bullish FVG...");
            bool fvg_found = false;
            for(int i = 0; i < FindFVGLimit; i++)
              {
               int check_shift = power_shift - i;
               if(check_shift < 0) break;
               if(HasFVG(check_shift, true))
                 {
                  int middle_shift = check_shift + 1;
                  if(middle_shift < iBars(_Symbol, _Period))
                    {
                     entry_price = (iHigh(_Symbol, _Period, middle_shift) + iLow(_Symbol, _Period, middle_shift)) / 2.0;
                     fvg_found = true;
                     Print("   - FVG Filter: PASSED. Found FVG, entry price set to ", DoubleToString(entry_price, _Digits));
                     break;
                    }
                 }
              }
            if(!fvg_found)
              {
               Print("   - FVG Filter: FAILED. No Bullish FVG found. Signal ignored.");
               return;
              }
           }
         else
           {
            Print("   - FVG Filter: DISABLED. Using Power Candle for entry.");
            double power_open = iOpen(_Symbol, _Period, power_shift);
            double power_close = iClose(_Symbol, _Period, power_shift);
            entry_price = (power_open + power_close) / 2.0;
           }

         if(entry_price > 0 || OrderExecutionType == EXECUTION_TYPE_MARKET)
           {
            ENUM_ORDER_TYPE order_type_to_place = (OrderExecutionType == EXECUTION_TYPE_MARKET) ? ORDER_TYPE_BUY : ORDER_TYPE_BUY_LIMIT;
            if(PlaceTrade(order_type_to_place, entry_price, level_price, levels[level_idx].isResistance, levels[level_idx].timeframe, levels[level_idx].time))
              {
               levels[level_idx].tradesTaken++;
              }
           }
        }
     }
   else
     {
      // Above support
      levels[level_idx].barsBeyondLevel = 0;

      // Check for bullish power candle with ATR filter
      if(IsPowerCandle(current_bar_shift, true) && levels[level_idx].tradesTaken < MaxTradesPerLevel && !IsOpenTradeFromLevel(level_price))
        {
         Print("--- Evaluating BUY on Bullish Power above Support at ", DoubleToString(level_price, _Digits), " ---");

         double atr = GetCustom35MinATR();
         if(atr > 0 && MaxDistanceFromLevelAtrMultiplier > 0)
           {
            double distance = MathAbs(current_close - level_price);
            if(distance > atr * MaxDistanceFromLevelAtrMultiplier)
              {
               Print("   - ATR Distance Filter: FAILED. Price too far from level (", DoubleToString(distance, _Digits), " > ", DoubleToString(atr * MaxDistanceFromLevelAtrMultiplier, _Digits), "). Signal ignored.");
               return;
              }
            Print("   - ATR Distance Filter: PASSED.");
           }

         double entry_price = 0;
         int power_shift = current_bar_shift;
         if(UseFVGConfirmation)
           {
            Print("   - FVG Filter: ENABLED. Searching for Bullish FVG...");
            bool fvg_found = false;
            for(int i = 0; i < FindFVGLimit; i++)
              {
               int check_shift = power_shift - i;
               if(check_shift < 0) break;
               if(HasFVG(check_shift, true))
                 {
                  int middle_shift = check_shift + 1;
                  if(middle_shift < iBars(_Symbol, _Period))
                    {
                     entry_price = (iHigh(_Symbol, _Period, middle_shift) + iLow(_Symbol, _Period, middle_shift)) / 2.0;
                     fvg_found = true;
                     Print("   - FVG Filter: PASSED. Found FVG, entry price set to ", DoubleToString(entry_price, _Digits));
                     break;
                    }
                 }
              }
            if(!fvg_found)
              {
               Print("   - FVG Filter: FAILED. No Bullish FVG found. Signal ignored.");
               return;
              }
           }
         else
           {
            Print("   - FVG Filter: DISABLED. Using Power Candle for entry.");
            double power_open = iOpen(_Symbol, _Period, power_shift);
            double power_close = iClose(_Symbol, _Period, power_shift);
            entry_price = (power_open + power_close) / 2.0;
           }

         if(entry_price > 0 || OrderExecutionType == EXECUTION_TYPE_MARKET)
           {
            ENUM_ORDER_TYPE order_type_to_place = (OrderExecutionType == EXECUTION_TYPE_MARKET) ? ORDER_TYPE_BUY : ORDER_TYPE_BUY_LIMIT;
            if(PlaceTrade(order_type_to_place, entry_price, level_price, levels[level_idx].isResistance, levels[level_idx].timeframe, levels[level_idx].time))
              {
               levels[level_idx].tradesTaken++;
              }
           }
        }
     }
  }

// Check session
bool IsWithinSession()
  {
   datetime gm = TimeGMT();
   MqlDateTime dt;
   TimeToStruct(gm, dt);
   int minutes = dt.hour * 60 + dt.min;
   bool ok = false;
   if(TradeNewYork && minutes >= 12 * 60 && minutes < 21 * 60) ok = true;
   if(TradeLondon && minutes >= 7 * 60 && minutes < 12 * 60) ok = true;
   if(TradeTokyo && minutes >= 0 && minutes < 7 * 60) ok = true;
   if(TradeSydney && (minutes >= 22 * 60 || minutes < 0)) ok = true;
   return ok;
  }

// Manage pending orders
void ManagePendingOrders()
  {
   for(int i = ArraySize(pendingOrders) - 1; i >= 0; i--)
     {
      if(!OrderSelect(pendingOrders[i].ticket))
        {
         ArrayRemove(pendingOrders, i, 1);
         continue;
        }
      int bars_since_setup = iBarShift(_Symbol, _Period, pendingOrders[i].setupTime);
      if(bars_since_setup >= PendingOrderExpiryCandles)
        {
         if(Trade.OrderDelete(pendingOrders[i].ticket))
           {
            Print("Pending order #", pendingOrders[i].ticket, " expired and was deleted.");
            ArrayRemove(pendingOrders, i, 1);
           }
        }
     }
  }

// Enforce hedge rule by canceling opposing pending orders
void EnforceHedgeRule()
  {
   if(EnableHedge) return;
   if(HasOpenBuyPositions())
     {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong ticket = OrderGetTicket(i);
         if(OrderSelect(ticket))
           {
            if(OrderGetInteger(ORDER_MAGIC) == EA_MagicNumber && OrderGetString(ORDER_SYMBOL) == _Symbol)
              {
               if(OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_LIMIT)
                 {
                  if(Trade.OrderDelete(ticket))
                    {
                     Print("Hedging disabled. Canceled pending Sell Limit order #", ticket, " due to open Buy position.");
                    }
                 }
              }
           }
        }
     }
   if(HasOpenSellPositions())
     {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong ticket = OrderGetTicket(i);
         if(OrderSelect(ticket))
           {
            if(OrderGetInteger(ORDER_MAGIC) == EA_MagicNumber && OrderGetString(ORDER_SYMBOL) == _Symbol)
              {
               if(OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_LIMIT)
                 {
                  if(Trade.OrderDelete(ticket))
                    {
                     Print("Hedging disabled. Canceled pending Buy Limit order #", ticket, " due to open Sell position.");
                    }
                 }
              }
           }
        }
     }
  }

// Breakeven check
void CheckBreakeven()
  {
   if(!EnableBreakeven) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket) || PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber) continue;
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(sl == 0) continue;
      double risk = MathAbs(openPrice - sl);
      if(risk == 0) continue;
      MqlTick current_tick;
      if(!SymbolInfoTick(_Symbol, current_tick)) continue;
      if(posType == POSITION_TYPE_BUY)
        {
         double triggerPrice = openPrice + risk * BreakevenTriggerReward;
         double newSL = openPrice + risk * BreakevenReward;
         if(sl >= newSL) continue;
         if(current_tick.bid >= triggerPrice)
           {
            if(newSL < current_tick.bid)
              {
               if(Trade.PositionModify(ticket, newSL, tp))
                 {
                  Print("Breakeven triggered for BUY position #", ticket, ". New SL set to ", DoubleToString(newSL, _Digits));
                 }
              }
           }
        }
      else if(posType == POSITION_TYPE_SELL)
        {
         double triggerPrice = openPrice - risk * BreakevenTriggerReward;
         double newSL = openPrice - risk * BreakevenReward;
         if(sl <= newSL) continue;
         if(current_tick.ask <= triggerPrice)
           {
            if(newSL > current_tick.ask)
              {
               if(Trade.PositionModify(ticket, newSL, tp))
                 {
                  Print("Breakeven triggered for SELL position #", ticket, ". New SL set to ", DoubleToString(newSL, _Digits));
                 }
              }
           }
        }
     }
  }

// Partial close check
void CheckPartialClose()
  {
   if(!EnablePartialClose) return;
   double atr = GetCustom35MinATR();
   if(atr <= 0) return;
   double trigger_distance = atr * PartialCloseAtrMultiplier;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i))
        {
         if(PositionInfo.Symbol() != _Symbol || PositionInfo.Magic() != EA_MagicNumber) continue;
         ulong ticket = PositionInfo.Ticket();
         bool already_partial = false;
         for(int j = 0; j < ArraySize(partialClosedTickets); j++)
           {
            if(partialClosedTickets[j] == ticket)
              {
               already_partial = true;
               break;
              }
           }
         if(already_partial) continue;
         double openPrice = PositionInfo.PriceOpen();
         ENUM_POSITION_TYPE posType = PositionInfo.PositionType();
         MqlTick current_tick;
         if(!SymbolInfoTick(_Symbol, current_tick)) continue;
         double current_price = (posType == POSITION_TYPE_BUY) ? current_tick.bid : current_tick.ask;
         double profit_distance = (posType == POSITION_TYPE_BUY) ? (current_price - openPrice) : (openPrice - current_price);
         if(profit_distance >= trigger_distance)
           {
            double volume = PositionInfo.Volume();
            double close_volume = volume * (PartialClosePercent / 100.0);
            double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            close_volume = vol_step * MathRound(close_volume / vol_step);
            if(close_volume > 0 && close_volume < volume)
              {
               if(Trade.PositionClosePartial(ticket, close_volume))
                 {
                  Print("Partial profit taken for position #", ticket, ". Closed ", DoubleToString(close_volume, 2), " lots at ", DoubleToString(profit_distance / atr, 2), " ATR profit.");
                  int size = ArraySize(partialClosedTickets);
                  ArrayResize(partialClosedTickets, size + 1);
                  partialClosedTickets[size] = ticket;
                 }
               else
                 {
                  Print("Failed to take partial profit for position #", ticket, ": ", GetLastError());
                 }
              }
           }
        }
     }
  }

// Reversal exit
void CheckReversalExit()
  {
   if(!EnableReversalExit) return;
   int hiIdx = iHighest(_Symbol, _Period, MODE_HIGH, LookbackHighLow, 2);
   int loIdx = iLowest(_Symbol, _Period, MODE_LOW, LookbackHighLow, 2);
   double highestHigh = iHigh(_Symbol, _Period, hiIdx);
   double lowestLow = iLow(_Symbol, _Period, loIdx);
   double close1 = iClose(_Symbol, _Period, 1);
   bool revBuy = (close1 > highestHigh);
   bool revSell = (close1 < lowestLow);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket) || PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber) continue;
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(revBuy && posType == POSITION_TYPE_SELL) Trade.PositionClose(ticket);
      if(revSell && posType == POSITION_TYPE_BUY) Trade.PositionClose(ticket);
     }
  }

// Loss reversal exit
void CheckLossReversalExit()
  {
   if(!EnableLossReversalExit) return;
   int hiIdx = iHighest(_Symbol, _Period, MODE_HIGH, LossLookbackHighLow, 2);
   int loIdx = iLowest(_Symbol, _Period, MODE_LOW, LossLookbackHighLow, 2);
   double highestHigh = iHigh(_Symbol, _Period, hiIdx);
   double lowestLow = iLow(_Symbol, _Period, loIdx);
   double close1 = iClose(_Symbol, _Period, 1);
   bool revBuy = (close1 > highestHigh);
   bool revSell = (close1 < lowestLow);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket) || PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber) continue;
      double profit = PositionGetDouble(POSITION_PROFIT);
      if(profit >= 0) continue;
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(revBuy && posType == POSITION_TYPE_SELL) Trade.PositionClose(ticket);
      if(revSell && posType == POSITION_TYPE_BUY) Trade.PositionClose(ticket);
     }
  }

// --- Main Functions ---

int OnInit()
  {
   Trade.SetExpertMagicNumber(EA_MagicNumber);
   ChartSetInteger(ChartID(), CHART_SHOW_GRID, false);
   UpdateHTFPowerCandleTrend();
   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   // Expiration date: December 17th, 2025 23:59:59 GMT
   datetime ExpirationDate = StringToTime("2025.12.17 23:59:59");
   if(TimeCurrent() > ExpirationDate)
     {
      Print("EA expired. Trading disabled, please send an email to @ighodaloxauusd@gmail.com or contact @__ighodalo on X(twitter");
      return;
     }
   
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime != LastBarTime)
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.day != LastTradeDay)
        {
         TradesToday = 0;
         LastTradeDay = dt.day;
        }
      
      UpdateHTFPowerCandleTrend();
      
      UpdateLevels();
      for(int i = ArraySize(levels) - 1; i >= 0; i--)
        {
         if(levels[i].isResistance) ProcessResistanceLevel(i);
         else ProcessSupportLevel(i);
        }
      
      for(int i = ArraySize(levels) - 1; i >= 0; i--)
        {
         if(levels[i].expired)
           {
            string tfStr = EnumToString(levels[i].timeframe);
            string typeStr = levels[i].isResistance ? "Resistance" : "Support";
            string name = "Level_" + tfStr + "_" + typeStr + "_" + TimeToString(levels[i].time);
            ObjectDelete(0, name);
            ObjectDelete(0, name + "_Label");
            ArrayRemove(levels, i, 1);
           }
        }
      
      UpdateIndicatorPlots();
      ManagePendingOrders();
      LastBarTime = currentBarTime;
     }
   
   CheckBreakeven();
   CheckPartialClose();
   CheckReversalExit();
   CheckLossReversalExit();
   EnforceHedgeRule();
   
   // Clean up partial closed tickets array
   for(int i = ArraySize(partialClosedTickets) - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(partialClosedTickets[i]))
        {
         ArrayRemove(partialClosedTickets, i, 1);
        }
     }
  }

void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "Level_");
   ObjectsDeleteAll(0, "PowerCandle_");
   ObjectsDeleteAll(0, "FVG_");
   Print("Power Pivot EA Deinitialized. All chart objects removed.");
  }