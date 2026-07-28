//+------------------------------------------------------------------+
//|                                      Belema ORB Expert Advisor    |
//|                        Open Range Breakout Strategy Expert Advisor |
//|           Built with Customizable Sessions & Trade Management     |
//+------------------------------------------------------------------+
#property copyright "Belema"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Trades Open Range Breakout strategy with customizable session times and power candle confirmation."
#property description "Retains trade management features from SFP EA, including hedging, FVG confirmation, and more."

// --- Includes ---
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

// --- Enums ---
enum ENUM_ORDER_EXECUTION_TYPE
{
   EXECUTION_TYPE_LIMIT,  // Place a Limit Order
   EXECUTION_TYPE_MARKET  // Place a Market Order
};

// --- Input Parameters ---

// **ORB Settings**
input string SessionStartTime = "09:30"; // Session start time (HH:MM)
input int SessionDurationMinutes = 30;   // Session duration in minutes
input int PowerCandleWindow = 2;         // Candles before breakout to check for power candles

// **Session Filters** (Retained from SFP EA)
input bool TradeNewYork = true;  // Trade during New York session
input bool TradeLondon  = true;  // Trade during London session
input bool TradeTokyo   = false; // Trade during Tokyo session
input bool TradeSydney  = false; // Trade during Sydney session

// **Trade Management** (Retained from SFP EA)
input ENUM_ORDER_EXECUTION_TYPE OrderExecutionType = EXECUTION_TYPE_LIMIT; // Choose order execution type
input bool EnableHedge          = true;  // Enable/Disable hedging trades
input int  ATR_Period           = 14;    // ATR period for stop loss (on custom 35-min TF)
input double ATR_SL_Multiplier  = 2.0;   // ATR multiplier for stop loss
input double RiskPercent        = 1.0;   // Risk percentage per trade
input double RR_Ratio           = 2.0;   // Risk-reward ratio for take profit
input int  MaxTradesPerDay      = 2;     // Max trades per day
input int  EA_MagicNumber       = 12345; // Magic number for trades
input int  PendingOrderExpiryCandles = 10; // Cancel pending order after this many candles (from SFP EA)

// **Exit & Breakeven Conditions** (Retained from SFP EA)
input bool EnableBreakeven         = true;  // Enable breakeven adjustment
input double BreakevenTriggerReward = 1.0;  // Reward multiplier to trigger breakeven
input double BreakevenReward       = 0.1;   // Reward multiplier for new SL
input bool EnableReversalExit      = true;  // Enable reversal exit
input int  LookbackHighLow         = 5;     // Lookback period for reversal exit

// **Indicator Settings** (Retained from SFP EA)
input int    PowerCandlePeriods      = 14;   // SMA Periods for power candles
input double PowerCandleMultiplier   = 1.5;  // Multiplier for power candles
input color  BullPowerColor          = clrLimeGreen; // Bullish power candle color
input color  BearPowerColor          = clrRed;       // Bearish power candle color
input color  BullFvgColor            = clrDarkGreen; // Bullish FVG color
input color  BearFvgColor            = clrDarkRed;   // Bearish FVG color
input int    MaxFvgsToDisplay        = 5000; // Max FVGs to display on chart
input int    MaxPowerCandlesToDisplay = 1000; // Max power candles to display

// **FVG Logic** (Retained from SFP EA)
input bool UseFVGConfirmation = true; // Enable FVG confirmation for trades
input int  FindFVGLimit       = 10;   // Max candles to find FVG after breakout

// --- Global Variables & Structures ---

// **ORB Variables**
datetime SessionStart;
datetime SessionEnd;
bool InSession = false;
double ORH = 0;  // Opening Range High
double ORL = 0;  // Opening Range Low
bool ORSet = false;
datetime LastDay = 0;

// **Trade Management Objects**
CTrade Trade;
CPositionInfo PositionInfo;
COrderInfo OrderInfo;

// **Trade Counters**
int TradesToday = 0;
int LastTradeDay = 0;

// **New Bar Tracking**
datetime LastBarTime = 0;

// **Structure for Pending Orders** (Reintroduced from SFP EA)
struct PendingOrderInfo
{
   ulong ticket;       // Order ticket
   datetime setupTime; // Time order was placed
};
PendingOrderInfo pendingOrders[];

// **Structure for FVG Objects** (Retained from SFP EA)
struct FVGObject
{
   string name;
   double high;
   double low;
   datetime startTime;
};
FVGObject bullFvgs[];
FVGObject bearFvgs[];

// **Array for Power Candle Objects** (Retained from SFP EA)
string powerCandleObjects[];

// --- Helper Functions ---

// **Check for Open Buy Positions**
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

// **Check for Open Sell Positions**
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

// **Check if Candle is a Power Candle**
bool IsPowerCandle(int shift, bool isBullish)
{
   if(shift + PowerCandlePeriods >= iBars(_Symbol, _Period)) return false;
   double sum_range = 0;
   for(int i = 0; i < PowerCandlePeriods; i++)
   {
      if(shift + i >= iBars(_Symbol, _Period)) return false;
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

// **Check for Fair Value Gap**
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

// **Plot Power Candle**
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

// **Plot FVG**
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

// **Update Indicator Plots**
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

// **Get Session Start Time for a Given Day**
datetime GetSessionStartTime(datetime date)
{
   MqlDateTime dt;
   TimeToStruct(date, dt);
   string dateStr = StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day);
   string sessionStartStr = dateStr + " " + SessionStartTime;
   return StringToTime(sessionStartStr);
}

// **Get Session End Time**
datetime GetSessionEndTime(datetime sessionStart)
{
   return sessionStart + SessionDurationMinutes * 60;
}

// **Calculate OR for the Day from Historical Data**
void CalculateORForDay(datetime day)
{
   datetime sessionStart = GetSessionStartTime(day);
   datetime sessionEnd = GetSessionEndTime(sessionStart);
   int startShift = iBarShift(_Symbol, _Period, sessionStart, true);
   int endShift = iBarShift(_Symbol, _Period, sessionEnd, true);
   if(startShift == -1 || endShift == -1) return;
   double high = iHigh(_Symbol, _Period, startShift);
   double low = iLow(_Symbol, _Period, startShift);
   for(int i = startShift; i >= endShift; i--)
   {
      if(i < 0) break;
      high = MathMax(high, iHigh(_Symbol, _Period, i));
      low = MathMin(low, iLow(_Symbol, _Period, i));
   }
   ORH = high;
   ORL = low;
   ORSet = true;
   SessionStart = sessionStart;
   SessionEnd = sessionEnd;
   PlotORLevels();
}

// **Plot OR Levels as Box** (Persistent Daily Range)
void PlotORLevels()
{
   string nameBox = "ORB_Box_" + TimeToString(SessionStart);
   if(ObjectFind(0, nameBox) == -1)
   {
      if(ObjectCreate(0, nameBox, OBJ_RECTANGLE, 0, SessionStart, ORH, SessionEnd, ORL))
      {
         ObjectSetInteger(0, nameBox, OBJPROP_COLOR, clrGray);
         ObjectSetInteger(0, nameBox, OBJPROP_FILL, true);
         ObjectSetInteger(0, nameBox, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nameBox, OBJPROP_HIDDEN, false);
         ObjectSetInteger(0, nameBox, OBJPROP_BACK, true);
      }
   }
}

// **Check if There is a Power Candle Within the Window**
bool IsPowerCandleInWindow(int shift, bool isBullish)
{
   for(int i = shift; i >= shift - PowerCandleWindow && i >= 0; i--)
   {
      if(IsPowerCandle(i, isBullish))
      {
         return true;
      }
   }
   return false;
}

// **Check ORB Breakouts**
void CheckORBBreakouts()
{
   int shift = 1; // Previous bar
   if(iBars(_Symbol, _Period) <= shift) return;
   double close = iClose(_Symbol, _Period, shift);
   if(close > ORH)
   {
      if(IsPowerCandleInWindow(shift, true))
      {
         if(!UseFVGConfirmation || HasFVG(shift, true))
         {
            ENUM_ORDER_TYPE type = (OrderExecutionType == EXECUTION_TYPE_MARKET) ? ORDER_TYPE_BUY : ORDER_TYPE_BUY_LIMIT;
            double entryPrice = (OrderExecutionType == EXECUTION_TYPE_LIMIT) ? ORH : 0;
            PlaceTrade(type, entryPrice, ORH, true, _Period, SessionStart);
         }
      }
   }
   else if(close < ORL)
   {
      if(IsPowerCandleInWindow(shift, false))
      {
         if(!UseFVGConfirmation || HasFVG(shift, false))
         {
            ENUM_ORDER_TYPE type = (OrderExecutionType == EXECUTION_TYPE_MARKET) ? ORDER_TYPE_SELL : ORDER_TYPE_SELL_LIMIT;
            double entryPrice = (OrderExecutionType == EXECUTION_TYPE_LIMIT) ? ORL : 0;
            PlaceTrade(type, entryPrice, ORL, false, _Period, SessionStart);
         }
      }
   }
}

// **Calculate Custom 35-Min ATR**
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

// **Calculate Lot Size**
double CalculateLotSize(double slDistance)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0 || slDistance <= 0)
   {
      Print("Invalid parameters for lot size calculation: tickValue=", tickValue, ", tickSize=", tickSize, ", slDistance=", slDistance);
      return 0;
   }
   double riskAmount = accountBalance * (RiskPercent / 100.0);
   double slPoints = slDistance / tickSize;
   if(slPoints <= 0)
   {
      Print("Invalid stop loss points: ", slPoints);
      return 0;
   }
   double lotSize = riskAmount / (slPoints * tickValue);
   lotSize = NormalizeDouble(lotSize, 2);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   lotSize = MathRound(lotSize / lotStep) * lotStep; // Align with lot step
   return lotSize;
}

// **Place Trade**
bool PlaceTrade(ENUM_ORDER_TYPE type, double entryPrice, double level, bool isBuy, ENUM_TIMEFRAMES tf, datetime pivotTime)
{
   // --- Trade Gatekeeper ---
   if(TradesToday >= MaxTradesPerDay || !IsWithinSession())
   {
      return false;
   }

   // --- Hedge Check ---
   if(!EnableHedge)
   {
      if((type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT) && HasOpenSellPositions())
      {
         Print("Hedging disabled. Cannot place a Buy trade while a Sell position is open.");
         return false;
      }
      if((type == ORDER_TYPE_SELL || type == ORDER_TYPE_SELL_LIMIT) && HasOpenBuyPositions())
      {
         Print("Hedging disabled. Cannot place a Sell trade while a Buy position is open.");
         return false;
      }
   }

   // --- ATR Logic ---
   double atr_35m = GetCustom35MinATR();
   if(atr_35m <= 0)
   {
      Print("Failed to get custom 35-min ATR. Cannot place trade.");
      return false;
   }
   double slDistance = atr_35m * ATR_SL_Multiplier;
   long min_stop_points = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_stop_distance = min_stop_points * _Point;
   if(slDistance < min_stop_distance)
   {
      slDistance = min_stop_distance;
   }
   double lotSize = CalculateLotSize(slDistance);
   if(lotSize <= 0)
   {
      Print("Calculated lot size is zero or negative.");
      return false;
   }

   Trade.SetExpertMagicNumber(EA_MagicNumber);
   string tfStr = EnumToString(tf);
   string tradeType = (type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT) ? "Buy" : "Sell";
   string comment = "ORB " + tradeType + " at " + (isBuy ? "ORH" : "ORL") + " " + DoubleToString(level, _Digits) + " on " + TimeToString(pivotTime, TIME_DATE|TIME_MINUTES);

   if(type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT)
   {
      // --- Limit Order Logic ---
      double normalized_entry = NormalizeDouble(entryPrice, _Digits);
      double sl = (type == ORDER_TYPE_BUY_LIMIT) ? normalized_entry - slDistance : normalized_entry + slDistance;
      double tp = (type == ORDER_TYPE_BUY_LIMIT) ? normalized_entry + slDistance * RR_Ratio : normalized_entry - slDistance * RR_Ratio;

      // --- Invalid Price Check ---
      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick))
      {
         Print("Failed to get tick data: ", GetLastError());
         return false;
      }
      if(type == ORDER_TYPE_BUY_LIMIT && normalized_entry >= tick.ask)
      {
         Print("Buy Limit price ", DoubleToString(normalized_entry, _Digits), " is invalid. Executing at Market.");
         return PlaceTrade(ORDER_TYPE_BUY, 0, level, isBuy, tf, pivotTime);
      }
      if(type == ORDER_TYPE_SELL_LIMIT && normalized_entry <= tick.bid)
      {
         Print("Sell Limit price ", DoubleToString(normalized_entry, _Digits), " is invalid. Executing at Market.");
         return PlaceTrade(ORDER_TYPE_SELL, 0, level, isBuy, tf, pivotTime);
      }

      bool order_sent = false;
      if(type == ORDER_TYPE_BUY_LIMIT)
      {
         if(Trade.BuyLimit(lotSize, normalized_entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment))
         {
            order_sent = true;
            ulong ticket = Trade.ResultOrder();
            if(ticket > 0)
            {
               int size = ArraySize(pendingOrders);
               ArrayResize(pendingOrders, size + 1);
               pendingOrders[size].ticket = ticket;
               pendingOrders[size].setupTime = iTime(_Symbol, _Period, 0);
            }
         }
         else
         {
            Print("Buy Limit order failed: ", GetLastError());
            return false;
         }
      }
      else if(type == ORDER_TYPE_SELL_LIMIT)
      {
         if(Trade.SellLimit(lotSize, normalized_entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment))
         {
            order_sent = true;
            ulong ticket = Trade.ResultOrder();
            if(ticket > 0)
            {
               int size = ArraySize(pendingOrders);
               ArrayResize(pendingOrders, size + 1);
               pendingOrders[size].ticket = ticket;
               pendingOrders[size].setupTime = iTime(_Symbol, _Period, 0);
            }
         }
         else
         {
            Print("Sell Limit order failed: ", GetLastError());
            return false;
         }
      }

      if(order_sent)
      {
         TradesToday++;
         Print("Trade Placed: ", tradeType, " at ", DoubleToString(normalized_entry, _Digits),
               ". SL: ", DoubleToString(sl, _Digits), ", TP: ", DoubleToString(tp, _Digits),
               ". Time: ", TimeToString(TimeCurrent()));
         return true;
      }
   }
   else if(type == ORDER_TYPE_BUY || type == ORDER_TYPE_SELL)
   {
      // --- Market Order Logic ---
      double marketPrice = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl = (type == ORDER_TYPE_BUY) ? marketPrice - slDistance : marketPrice + slDistance;
      double tp = (type == ORDER_TYPE_BUY) ? marketPrice + slDistance * RR_Ratio : marketPrice - slDistance * RR_Ratio;

      bool order_sent = false;
      if(type == ORDER_TYPE_BUY)
      {
         if(Trade.Buy(lotSize, _Symbol, marketPrice, sl, tp, comment))
         {
            order_sent = true;
         }
         else
         {
            Print("Buy Market order failed: ", GetLastError());
            return false;
         }
      }
      else if(type == ORDER_TYPE_SELL)
      {
         if(Trade.Sell(lotSize, _Symbol, marketPrice, sl, tp, comment))
         {
            order_sent = true;
         }
         else
         {
            Print("Sell Market order failed: ", GetLastError());
            return false;
         }
      }

      if(order_sent)
      {
         TradesToday++;
         Print("Trade Executed: ", tradeType, " at ", DoubleToString(marketPrice, _Digits),
               ". SL: ", DoubleToString(sl, _Digits), ", TP: ", DoubleToString(tp, _Digits),
               ". Time: ", TimeToString(TimeCurrent()));
         return true;
      }
   }
   return false;
}

// **Manage Pending Orders**
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

// **Enforce Hedge Rule**
void EnforceHedgeRule()
{
   if(EnableHedge) return;

   // If we have open buy positions, cancel all pending sell limit orders
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

   // If we have open sell positions, cancel all pending buy limit orders
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

// **Check Breakeven**
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
// **Check Reversal Exit**
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

// **Check if Within Trading Session**
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

// --- Main Functions ---

int OnInit()
{    // Expiration date: July 17th, 2025 23:59:59 GMT
   datetime ExpirationDate = StringToTime("2025.11.17 23:59:59");
   if(TimeCurrent() > ExpirationDate)
   {
      Print("EA expired. Trading disabled, please send an email to @ighodaloxauusd@gmail.com or contact @__ighodalo on X(twitter");
      return(INIT_FAILED);
   }
   
   Trade.SetExpertMagicNumber(EA_MagicNumber);
   ChartSetInteger(ChartID(), CHART_SHOW_GRID, false);
   return INIT_SUCCEEDED;
}

void OnTick()
{  
   datetime ExpirationDate = StringToTime("2025.11.17 23:59:59");
   if(TimeCurrent() > ExpirationDate)
   {
      Print("EA expired. Trading disabled, please send an email to @ighodaloxauusd@gmail.com or contact @__ighodalo on X(twitter");
      return;
   }
   
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime != LastBarTime)
   {
      datetime currentTime = TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(currentTime, dt);
      datetime currentDay = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
      if(currentDay != LastDay)
      {
         LastDay = currentDay;
         SessionStart = GetSessionStartTime(currentDay);
         SessionEnd = GetSessionEndTime(SessionStart);
         InSession = false;
         ORH = 0;
         ORL = 0;
         ORSet = false;
         TradesToday = 0;
         LastTradeDay = dt.day;
      }
      datetime barTime = iTime(_Symbol, _Period, 0);
      if(barTime >= SessionStart && barTime < SessionEnd)
      {
         if(!InSession)
         {
            InSession = true;
            ORH = iHigh(_Symbol, _Period, 0);
            ORL = iLow(_Symbol, _Period, 0);
         }
         else
         {
            ORH = MathMax(ORH, iHigh(_Symbol, _Period, 0));
            ORL = MathMin(ORL, iLow(_Symbol, _Period, 0));
         }
      }
      else if(InSession)
      {
         InSession = false;
         ORSet = true;
         PlotORLevels();
      }
      else if(barTime >= SessionEnd && !ORSet)
      {
         CalculateORForDay(currentDay);
      }
      if(ORSet)
      {
         CheckORBBreakouts();
      }
      UpdateIndicatorPlots();
      ManagePendingOrders();
      LastBarTime = currentBarTime;
   }
   CheckBreakeven();
   CheckReversalExit();
   EnforceHedgeRule();
}

void OnDeinit(const int reason)
{
   // Do not delete ORB boxes to keep historical ranges
   ObjectsDeleteAll(0, "PowerCandle_");
   ObjectsDeleteAll(0, "FVG_");
}