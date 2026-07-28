//+------------------------------------------------------------------+
//| Belema SFP EA (Enhanced) - v2.6 with Individual Stale Logic      |
//| Swing Failure Pattern with Scaling In                            |
//| v2.6: Stale trade logic now applies to each position individually|
//|       and allows scaling to continue after a stale closure.      |
//| 1. Progressive Profit-Lock Breakeven (Corrected Calculation)     |
//| 2. Peak Profit Drawdown Exit (RR-Triggered)                      |
//| 3. Individual Time-Based Stop for Stale Trades                   |
//+------------------------------------------------------------------+
#property copyright "Belema"
#property link      "https://www.mql5.com"
#property version   "2.6"
#property description "Combines SFP logic with scaling in to double account."
#property description "v2.6: Stale trade logic now per-position, allows continued scaling."

// --- Includes ---
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>
#include <Trade/DealInfo.mqh>
// This file is used by the Strategy Tester to simulate news events.
// The EA will create this file automatically when run on a live chart.
#property tester_file "SFP_NewsCache.csv"

// --- ENUMERATIONS ---
enum ENUM_EXECUTION_TYPE
  {
   AGGRESSIVE,
   SEMI_AGGRESSIVE,
   CONSERVATIVE
  };

// --- INPUT PARAMETERS ---
input group "Session Management"
input bool   TradeNewYork = true; // Trade during New York session (12:00-21:00 GMT)
input bool   TradeLondon = true; // Trade during London session (7:00-12:00 GMT)
input bool   TradeTokyo = true; // Trade during Tokyo session (0:00-7:00 GMT)
input bool   TradeSydney = true; // Trade during Sydney session (22:00-0:00 GMT)
input group "Point of Interest (POI) Settings"
input bool   EnableM5_POI = true; // Detect Pivots on M5 timeframe
input bool   EnableM15_POI = true; // Detect Pivots on M15 timeframe
input bool   EnableM30_POI = true; // Detect Pivots on M30 timeframe
input bool   EnableH1_POI = true; // Detect Pivots on H1 timeframe
input bool   EnableH4_POI = true; // Detect Pivots on H4 timeframe
input bool   EnableD1_POI = false; // Detect Pivots on D1 timeframe
input int    MaxPOIPerTF = 7; // Maximum number of Support/Resistance levels per timeframe
input group "SFP Core Logic & Filters"
input ENUM_EXECUTION_TYPE ExecutionType = AGGRESSIVE; // Execution type
input bool   UseHTFPowerCandleFilter = true; // Filter trades based on Higher Timeframe trend
input ENUM_TIMEFRAMES HTFPowerCandleTimeframe = PERIOD_H4; // Timeframe for the HTF trend filter
input int    LeftBars = 22; // Bars to the left for pivot detection
input int    RightBars = 22; // Bars to the right for pivot detection
input int    ReclaimLookbackCandles = 8; // Max bars for reclaim after breakout
input int    ReclaimGraceCandles = 10; // Max bars for power candle after reclaim
input int    LevelExpiryCandles = 15; // How many bars price can close beyond a level before it expires
input int    SignalExpiryCandles = 30; // Candles before signal expires
input int    MaxActiveSignals = 2; // Max active signals per direction
input group "Risk & Position Management"
input int    ATR_Period = 14; // Period for ATR calculation
input int    MaxTradesPerDay = 50; // Maximum trades allowed in a single day
input int    MaxTradesPerLevel = 1; // Maximum trades allowed at a single POI level
input int    EA_MagicNumber = 174355; // Unique identifier for trades managed by this EA
input bool   EnableHedge = false; // Allow simultaneous Buy and Sell trades
input group "Strategy Settings"
input double InitialRiskPercent = 5.0;
input double InitialRiskDollar = 0;
input double ProfitTargetPercent = 100.0;
input double ProfitTargetDollar = 0;
input double SL_Multiplier = 1.5;
input double Add_Multiplier = 1.0;
input double Add_Lot_Multiplier = 1.0; // Lot size multiplier for scaling-in (e.g., 1.0 = same as initial lot)
input int    MaxPositions = 5;
input int    BreakevenOffsetPips = 0; // Pips to add to BE price to cover costs
input int    Slippage = 3;
input group "Trailing Stop"
input bool   EnableTrailingStop = true;         // Enable/Disable Trailing Stop
input double TrailingStartATR = 2.0;         // ATR multiple to start trailing
input double TrailingStopATR = 1.5;         // ATR multiple for trailing distance
input group "Profit Keeper: SL Management"
input bool   EnableProgressiveBE = true;      // True: Progressive Reward Lock | False: Basket Breakeven
input group "Profit Keeper: Peak Drawdown"
input bool   EnablePeakDrawdownExit = true;   // Enable Peak Profit Drawdown Exit
input double PeakDrawdownStartRR = 2.0;     // RR multiple to start monitoring for drawdown
input double PeakProfitDrawdownPercent = 30.0;// Exit if profit retraces by X% from its peak
input group "Profit Keeper: Stale Trade"
input bool   EnableStaleTradeExit = true;     // Enable Stale Trade Exit
input int    StaleTradeBars = 24;           // Bars before a trade is considered stale (e.g., 24 H1 bars = 1 day)
input group "Chart & Visuals"
input int    PowerCandlePeriods = 20; // Lookback period for calculating average candle body size
input double PowerCandleMultiplier = 1.7; // Multiplier to define a "Power Candle"
input color  BullPowerColor = 3329330; // Color for bullish power candles
input color  BearPowerColor = 255; // Color for bearish power candles
input int    MaxPowerCandlesToDisplay = 1000; // Max Power Candle arrows on chart
input group "News Management"
input bool   EnableNewsManagement = true; // Enable/Disable the news filter system
input int    NewsCheckIntervalSeconds = 3600; // How often to check for new news events (1 hour)
input int    MinsBefore = 10; // Do not trade X minutes before high-impact news
input int    MinsAfter = 10; // Do not trade X minutes after high-impact news

// --- GLOBAL STRUCTURES & VARIABLES ---
struct CachedNewsEvent
  {
   datetime time;
   string   country;
   int      importance;
  };
CachedNewsEvent g_cached_news[];
string g_news_cache_filename = "SFP_NewsCache.csv";

struct LevelInfo
  {
   double          price;
   ENUM_TIMEFRAMES timeframe;
   datetime        time;
   bool            isResistance;
   bool            breakoutDetected;
   int             breakoutCandleShift;
   bool            reclaimDetected;
   int             reclaimCandleShift;
   bool            reclaimPowerCandleConfirmed;
   int             reclaimPowerCandleShift;
   datetime        reclaimPowerCandleTime;
   int             tradesTaken;
   int             barsBeyondLevel;
   bool            expired;
   bool            validated;
  };
LevelInfo levels[];
LevelInfo internal_levels[];

struct SignalInfo
  {
   bool            isBuy;
   double          entryLevel;
   datetime        timeCreated;
   int             triggerShift;
   double          levelPrice;
   bool            isResistance;
   ENUM_TIMEFRAMES timeframe;
   datetime        pivotTime;
  };
SignalInfo activeSignals[];

string powerCandleObjects[];

CTrade        Trade;
CPositionInfo PositionInfo;
COrderInfo    OrderInfo;
CDealInfo     DealInfo;

int      TradesToday = 0;
int      LastTradeDay = 0;
datetime LastBarTime = 0;
int      htfTrend = 0;

datetime nextNewsTime = 0;
datetime lastNewsCheck = 0;
datetime lastManagedNews = 0;
bool     inSleepMode = false;
bool     pendingSleep = false;
datetime sleepStart = 0;
datetime sleepEndTime = 0;
string   base_currency = StringSubstr(_Symbol, 0, 3);
string   quote_currency = StringSubstr(_Symbol, 3, 3);
int      internal_left;
int      internal_right;

// Scaling variables for buy
double   initialATR_buy = 0;
double   initialLot_buy = 0;
double   initialEntry_buy = 0;
double   initialBalance_buy = 0;
double   lastEntry_buy = 0;
int      positionsCount_buy = 0;
datetime initialTradeTime_buy = 0;

// Scaling variables for sell
double   initialATR_sell = 0;
double   initialLot_sell = 0;
double   initialEntry_sell = 0;
double   initialBalance_sell = 0;
double   lastEntry_sell = 0;
int      positionsCount_sell = 0;
datetime initialTradeTime_sell = 0;

// --- Advanced Profit Keeping Global Variables ---
double   initialRiskAmount_buy = 0;
double   initialRiskAmount_sell = 0;
double   peakProfit_buy = 0;
double   peakProfit_sell = 0;

// --- Stale Trade Management ---
double skippedBuyLevels[];
double skippedSellLevels[];

// --- Virtual Trailing Stop Variables ---
double virtualSL_buy = 0;
double virtualSL_sell = 0;

//+------------------------------------------------------------------+
//| NEWS SYSTEM FUNCTIONS                                            |
//+------------------------------------------------------------------+
string CurrencyToCountryCode(string currency)
  {
   if(currency == "USD") return "US";
   if(currency == "EUR") return "EU";
   if(currency == "GBP") return "GB";
   if(currency == "JPY") return "JP";
   if(currency == "CAD") return "CA";
   if(currency == "AUD") return "AU";
   if(currency == "NZD") return "NZ";
   if(currency == "CHF") return "CH";
   if(currency == "CNY") return "CN";
   return "";
  }
void LoadNewsFromCache()
  {
   Print("--- NEWS [TESTER MODE]: Initializing news system for backtest. ---");
   ArrayFree(g_cached_news);
   int file_handle = FileOpen(g_news_cache_filename, FILE_READ | FILE_CSV | FILE_COMMON, ',');
   if(file_handle == INVALID_HANDLE)
     {
      Print("--- NEWS [TESTER MODE] ERROR: Could not find news file '", g_news_cache_filename, "'. Please run the EA on a live chart for 1 minute to create it. ---");
      return;
     }
   Print("--- NEWS [TESTER MODE]: Found cache file. Reading events into memory... ---");
   FileReadString(file_handle);
   FileReadString(file_handle);
   FileReadString(file_handle);
   int count = 0;
   while(!FileIsEnding(file_handle))
     {
      string time_str = FileReadString(file_handle);
      datetime event_time = StringToTime(time_str);
      string country = FileReadString(file_handle);
      int importance = (int)StringToInteger(FileReadString(file_handle));
      if(event_time < StringToTime("2020.01.01") || event_time > StringToTime("2030.12.31")) continue;
      int size = ArraySize(g_cached_news);
      ArrayResize(g_cached_news, size + 1, 1000);
      g_cached_news[size].time = event_time;
      g_cached_news[size].country = country;
      g_cached_news[size].importance = importance;
      count++;
     }
   FileClose(file_handle);
   Print("--- NEWS [TESTER MODE]: Successfully loaded ", count, " news events into memory for this test run. ---");
  }
void DownloadAndCacheNews()
  {
   Print("--- NEWS [LIVE MODE]: Initializing. Attempting to download and cache news history for tester use... ---");
   int file_handle = FileOpen(g_news_cache_filename, FILE_WRITE | FILE_CSV | FILE_COMMON, ',');
   if(file_handle == INVALID_HANDLE)
     {
      Print("--- NEWS [LIVE MODE] ERROR: Could not create the cache file. Check terminal permissions. ---");
      return;
     }
   Print("--- NEWS [LIVE MODE]: Cache file '", g_news_cache_filename, "' opened for writing. ---");
   FileWrite(file_handle, "time_as_string", "country", "importance");
   datetime from = TimeCurrent() - (86400 * 90);
   datetime to = TimeCurrent() + (86400 * 90);
   Print("--- NEWS [LIVE MODE]: Requesting news history from server. This may take a moment... ---");
   MqlCalendarValue values[];
   int total_saved = 0;
   if(CalendarValueHistory(values, from, to))
     {
      Print("--- NEWS [LIVE MODE]: Received ", ArraySize(values), " total events from server. Filtering and saving... ---");
      for(int i = 0; i < ArraySize(values); i++)
        {
         MqlCalendarEvent event_details;
         if(CalendarEventById(values[i].event_id, event_details))
           {
            MqlCalendarCountry country_details;
            if(CalendarCountryById(event_details.country_id, country_details))
              {
               FileWrite(file_handle, TimeToString(values[i].time, TIME_DATE | TIME_MINUTES | TIME_SECONDS),
                         country_details.code, event_details.importance);
               total_saved++;
              }
           }
        }
     }
   else
     {
      Print("--- NEWS [LIVE MODE] ERROR: Call to CalendarValueHistory failed. Terminal may not be connected or news is disabled in settings. ---");
     }
   FileClose(file_handle);
   Print("--- NEWS [LIVE MODE]: Saved ", total_saved, " events. News cache file has been created successfully. You can now use the Strategy Tester. ---");
  }
datetime GetNextHighImpactNewsTime()
  {
   datetime next_event_time = 0;
   datetime now = TimeGMT();
   string relevant_countries[2];
   relevant_countries[0] = CurrencyToCountryCode(base_currency);
   relevant_countries[1] = CurrencyToCountryCode(quote_currency);
   if(MQLInfoInteger(MQL_TESTER))
     {
      for(int i = 0; i < ArraySize(g_cached_news); i++)
        {
         if(g_cached_news[i].time > now && g_cached_news[i].importance == CALENDAR_IMPORTANCE_HIGH)
           {
            if(g_cached_news[i].country == relevant_countries[0] || g_cached_news[i].country == relevant_countries[1])
              {
               if(next_event_time == 0 || g_cached_news[i].time < next_event_time)
                 {
                  next_event_time = g_cached_news[i].time;
                 }
              }
           }
        }
     }
   else
     {
      datetime to = now + 86400 * 7;
      MqlCalendarValue values[];
      for(int c = 0; c < 2; c++)
        {
         if(relevant_countries[c] == "") continue;
         if(CalendarValueHistory(values, now, to, relevant_countries[c]))
           {
            for(int i = 0; i < ArraySize(values); i++)
              {
               MqlCalendarEvent event_details;
               if(CalendarEventById(values[i].event_id, event_details))
                 {
                  if(event_details.importance == CALENDAR_IMPORTANCE_HIGH)
                    {
                     if(next_event_time == 0 || values[i].time < next_event_time)
                       {
                        next_event_time = values[i].time;
                       }
                    }
                 }
              }
           }
        }
     }
   if(next_event_time > 0)
     {
      Print("--- NEWS: Next high-impact news for ", _Symbol, " found at: ", TimeToString(next_event_time), ". ---");
     }
   else
     {
      Print("--- NEWS: No upcoming high-impact news found for ", _Symbol, ". ---");
     }
   return next_event_time;
  }
//+------------------------------------------------------------------+
//| HELPER & INDICATOR FUNCTIONS                                     |
//+------------------------------------------------------------------+
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
bool IsPowerCandle(int shift, bool isBullish)
  {
   return IsPowerCandleTF(shift, isBullish, _Period);
  }
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
void UpdateIndicatorPlots()
  {
   int prev_completed_bar_shift = 1;
   if(iBars(_Symbol, _Period) <= prev_completed_bar_shift) return;
   if(IsPowerCandle(prev_completed_bar_shift, true)) PlotPowerCandle(prev_completed_bar_shift, true);
   if(IsPowerCandle(prev_completed_bar_shift, false)) PlotPowerCandle(prev_completed_bar_shift, false);
  }
void UpdateHTFPowerCandleTrend()
  {
   if(!UseHTFPowerCandleFilter)
     {
      htfTrend = 0;
      return;
     }
   for(int i = 1; i < 2000; i++)
     {
      if(i >= iBars(_Symbol, HTFPowerCandleTimeframe)) break;
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
//+------------------------------------------------------------------+
//| CORE TRADING LOGIC                                               |
//+------------------------------------------------------------------+
bool IsPivotHighTF(ENUM_TIMEFRAMES tf, int idx, int left, int right)
  {
   int total_bars_tf = iBars(_Symbol, tf);
   if(idx < right || idx + left >= total_bars_tf) return false;
   double value = iHigh(_Symbol, tf, idx);
   for(int i = idx - right; i <= idx + left; i++)
     {
      if(i == idx) continue;
      if(iHigh(_Symbol, tf, i) >= value) return false;
     }
   return true;
  }
bool IsPivotLowTF(ENUM_TIMEFRAMES tf, int idx, int left, int right)
  {
   int total_bars_tf = iBars(_Symbol, tf);
   if(idx < right || idx + left >= total_bars_tf) return false;
   double value = iLow(_Symbol, tf, idx);
   for(int i = idx - right; i <= idx + left; i++)
     {
      if(i == idx) continue;
      if(iLow(_Symbol, tf, i) <= value) return false;
     }
   return true;
  }
void DetectPivots(ENUM_TIMEFRAMES tf)
  {
   int totalBars = iBars(_Symbol, tf);
   if(totalBars < LeftBars + RightBars + 1) return;
   int idx = RightBars;
   if(idx >= totalBars || idx < 0) return;
   datetime pivot_time = iTime(_Symbol, tf, idx);
   datetime end_plot_time = iTime(_Symbol, _Period, 0);
   if(IsPivotHighTF(tf, idx, LeftBars, RightBars))
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
   if(IsPivotLowTF(tf, idx, LeftBars, RightBars))
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
void DetectInternalPivots()
  {
   ENUM_TIMEFRAMES tf = _Period;
   int totalBars = iBars(_Symbol, tf);
   if(totalBars < internal_left + internal_right + 1) return;
   int idx = internal_right;
   if(idx >= totalBars || idx < 0) return;
   datetime pivot_time = iTime(_Symbol, tf, idx);
   if(IsPivotHighTF(tf, idx, internal_left, internal_right))
     {
      double pivot_price = iHigh(_Symbol, tf, idx);
      bool exists = false;
      for(int i = 0; i < ArraySize(internal_levels); i++)
        {
         if(internal_levels[i].timeframe == tf && internal_levels[i].isResistance && internal_levels[i].time == pivot_time)
           {
            exists = true;
            break;
           }
        }
      if(!exists)
        {
         int n = ArraySize(internal_levels);
         ArrayResize(internal_levels, n + 1);
         internal_levels[n].price = pivot_price;
         internal_levels[n].timeframe = tf;
         internal_levels[n].time = pivot_time;
         internal_levels[n].isResistance = true;
         internal_levels[n].breakoutDetected = false;
         internal_levels[n].reclaimDetected = false;
         internal_levels[n].reclaimPowerCandleConfirmed = false;
         internal_levels[n].tradesTaken = 0;
         internal_levels[n].barsBeyondLevel = 0;
         internal_levels[n].expired = false;
         internal_levels[n].validated = false;
        }
     }
   if(IsPivotLowTF(tf, idx, internal_left, internal_right))
     {
      double pivot_price = iLow(_Symbol, tf, idx);
      bool exists = false;
      for(int i = 0; i < ArraySize(internal_levels); i++)
        {
         if(internal_levels[i].timeframe == tf && !internal_levels[i].isResistance && internal_levels[i].time == pivot_time)
           {
            exists = true;
            break;
           }
        }
      if(!exists)
        {
         int n = ArraySize(internal_levels);
         ArrayResize(internal_levels, n + 1);
         internal_levels[n].price = pivot_price;
         internal_levels[n].timeframe = tf;
         internal_levels[n].time = pivot_time;
         internal_levels[n].isResistance = false;
         internal_levels[n].breakoutDetected = false;
         internal_levels[n].reclaimDetected = false;
         internal_levels[n].reclaimPowerCandleConfirmed = false;
         internal_levels[n].tradesTaken = 0;
         internal_levels[n].barsBeyondLevel = 0;
         internal_levels[n].expired = false;
         internal_levels[n].validated = false;
        }
     }
  }
void AddLevel(double price, ENUM_TIMEFRAMES tf, datetime time, bool isResistance, datetime end_plot_time)
  {
   int count = 0;
   int oldest_index = -1;
   datetime oldest_time = D'3000.01.01';
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
      string tfStr = EnumToString(tf);
      string typeStr = levels[oldest_index].isResistance ? "Resistance" : "Support";
      string name = "Level_" + tfStr + "_" + typeStr + "_" + TimeToString(levels[oldest_index].time);
      ObjectDelete(0, name);
      ObjectDelete(0, name + "_Label");
      ArrayRemove(levels, oldest_index, 1);
     }
   int n = ArraySize(levels);
   ArrayResize(levels, n + 1);
   levels[n].price = price;
   levels[n].timeframe = tf;
   levels[n].time = time;
   levels[n].isResistance = isResistance;
   levels[n].breakoutDetected = false;
   levels[n].reclaimDetected = false;
   levels[n].reclaimPowerCandleConfirmed = false;
   levels[n].tradesTaken = 0;
   levels[n].barsBeyondLevel = 0;
   levels[n].expired = false;
   levels[n].validated = false;
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
void UpdateLevels()
  {
   ENUM_TIMEFRAMES enabledTFs[] = {PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1};
   bool enables[] = {EnableM5_POI, EnableM15_POI, EnableM30_POI, EnableH1_POI, EnableH4_POI, EnableD1_POI};
   for(int i = 0; i < ArraySize(enabledTFs); i++)
     {
      if(enables[i]) DetectPivots(enabledTFs[i]);
     }
   DetectInternalPivots();
  }
void UpdateInternalExpiry()
  {
   int current_bar_shift = 1;
   double current_close = iClose(_Symbol, _Period, current_bar_shift);
   for(int i = ArraySize(internal_levels) - 1; i >= 0; i--)
     {
      double level_price = internal_levels[i].price;
      bool beyond = internal_levels[i].isResistance ? current_close > level_price : current_close < level_price;
      if(beyond)
        {
         internal_levels[i].barsBeyondLevel++;
         if(internal_levels[i].barsBeyondLevel > LevelExpiryCandles)
           {
            internal_levels[i].expired = true;
           }
        }
      else
        {
         internal_levels[i].barsBeyondLevel = 0;
        }
      if(internal_levels[i].expired)
        {
         ArrayRemove(internal_levels, i, 1);
        }
     }
  }
void CheckForBoS()
  {
   int shift = 1;
   double close = iClose(_Symbol, _Period, shift);
   double high = iHigh(_Symbol, _Period, shift);
   bool bearish_bos = false;
   bool bullish_bos = false;
   for(int i = 0; i < ArraySize(levels); i++)
     {
      if(!levels[i].isResistance && !levels[i].expired && close < levels[i].price)
        {
         bearish_bos = true;
         break;
        }
     }
   if(!bearish_bos)
     {
      for(int i = 0; i < ArraySize(internal_levels); i++)
        {
         if(!internal_levels[i].isResistance && !internal_levels[i].expired && close < internal_levels[i].price)
           {
            bearish_bos = true;
            break;
           }
        }
     }
   for(int i = 0; i < ArraySize(levels); i++)
     {
      if(levels[i].isResistance && !levels[i].expired && high > levels[i].price)
        {
         bullish_bos = true;
         break;
        }
     }
   if(!bullish_bos)
     {
      for(int i = 0; i < ArraySize(internal_levels); i++)
        {
         if(internal_levels[i].isResistance && !internal_levels[i].expired && high > internal_levels[i].price)
           {
            bullish_bos = true;
            break;
           }
        }
     }
   if(bearish_bos)
     {

      for(int i = 0; i < ArraySize(levels); i++)
        {
         if(levels[i].isResistance) levels[i].validated = true;
        }
     }
   if(bullish_bos)
     {
      for(int i = 0; i < ArraySize(levels); i++)
        {
         if(!levels[i].isResistance) levels[i].validated = true;
        }
     }
  }
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
double GetATR()
  {
   return GetCustom35MinATR();
  }
bool PlaceTrade(bool isBuy, double level, bool isResistance, ENUM_TIMEFRAMES tf, datetime pivotTime, int triggerCandleShift)
  {
   if(TradesToday >= MaxTradesPerDay || !IsWithinSession()) return false;
// Prevent same direction entry if already open
   if(isBuy && HasOpenBuyPositions())
     {
      return false;
     }
   if(!isBuy && HasOpenSellPositions())
     {
      return false;
     }
// If hedging disabled, prevent entry if opposite open
   if(!EnableHedge)
     {
      if(isBuy && HasOpenSellPositions())
        {
         return false;
        }
      if(!isBuy && HasOpenBuyPositions())
        {
         return false;
        }
     }
   double marketPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double atr = GetATR();
   if(atr <= 0)
     {
      Print("Failed to get ATR. Cannot place trade.");
      return false;
     }
   double slDistance = atr * SL_Multiplier;
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
   string shortTradeType = isBuy ? "BM" : "SM";
   string shortTfStr = EnumToString(tf);
   StringReplace(shortTfStr, "PERIOD_", "");
   string comment = "SFP|" + shortTradeType + "|" + shortTfStr + "|POI:" + TimeToString(pivotTime, TIME_DATE | TIME_MINUTES) + "|@ " + DoubleToString(level, _Digits);
   double sl = isBuy ? marketPrice - slDistance : marketPrice + slDistance;
   
    // --- New pre-trade stop loss validation logic ---
    MqlTick tick;
    SymbolInfoTick(_Symbol, tick);
    double stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

    bool sl_valid = false;
    if (isBuy) {
        if (tick.bid - sl >= stops_level) {
            sl_valid = true;
        } else {
            Print("BUY SL is too close to BID price. Need at least ", DoubleToString(stops_level, _Digits), " distance. Trade aborted.");
        }
    } else { // isSell
        if (sl - tick.ask >= stops_level) {
            sl_valid = true;
        } else {
            Print("SELL SL is too close to ASK price. Need at least ", DoubleToString(stops_level, _Digits), " distance. Trade aborted.");
        }
    }

    if (!sl_valid) {
        return false;
    }
    // --- End of new pre-trade stop loss validation logic ---

   bool order_sent = false;
   if(isBuy)
     {
      if(Trade.Buy(lotSize, _Symbol, marketPrice, sl, 0, comment)) order_sent = true;
      else { Print("Buy Market order failed: ", GetLastError()); return false; }
     }
   else
     {
      if(Trade.Sell(lotSize, _Symbol, marketPrice, sl, 0, comment)) order_sent = true;
      else { Print("Sell Market order failed: ", GetLastError()); return false; }
     }
   if(order_sent)
     {
      TradesToday++;
      Print(">>> TRADE EXECUTED: ", isBuy ? "Buy Market" : "Sell Market", " at ", DoubleToString(marketPrice, _Digits),
            ". SL: ", DoubleToString(sl, _Digits), ". Time: ", TimeToString(TimeCurrent()));
      if(isBuy)
        {
         initialATR_buy = atr;
         initialLot_buy = lotSize;
         initialBalance_buy = AccountInfoDouble(ACCOUNT_BALANCE);
         initialEntry_buy = Trade.ResultPrice();
         lastEntry_buy = initialEntry_buy;
         positionsCount_buy = 1;
         initialRiskAmount_buy = lotSize * slDistance * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         initialTradeTime_buy = TimeCurrent();
        }
      else
        {
         initialATR_sell = atr;
         initialLot_sell = lotSize;
         initialBalance_sell = AccountInfoDouble(ACCOUNT_BALANCE);
         initialEntry_sell = Trade.ResultPrice();
         lastEntry_sell = initialEntry_sell;
         positionsCount_sell = 1;
         initialRiskAmount_sell = lotSize * slDistance * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         initialTradeTime_sell = TimeCurrent();
        }
      return true;
     }
   return false;
  }
double CalculateLotSize(double slDistance)
  {
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(slDistance <= 0 || tickValue <=0 || tickSize <=0) return 0.0;
   double riskAmount = InitialRiskDollar > 0 ? InitialRiskDollar : accountBalance * (InitialRiskPercent / 100.0);
   double slPoints = slDistance / tickSize;
   double lotSize = riskAmount / (slPoints * tickValue);
   lotSize = NormalizeDouble(lotSize, 2);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lotSize = lotStep > 0 ? MathFloor(lotSize / lotStep) * lotStep : lotSize;
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   return lotSize;
  }
void ProcessResistanceLevel(int level_idx)
  {
   if(!levels[level_idx].validated) return;
   int current_bar_shift = 1;
   if(iBars(_Symbol, _Period) <= current_bar_shift) return;
   double current_high = iHigh(_Symbol, _Period, current_bar_shift);
   double current_close = iClose(_Symbol, _Period, current_bar_shift);
   double level_price = levels[level_idx].price;
   if(levels[level_idx].expired) return;
   if(current_close > level_price)
     {
      levels[level_idx].barsBeyondLevel++;
      if(levels[level_idx].barsBeyondLevel > LevelExpiryCandles)
        {
         levels[level_idx].expired = true;
         return;
        }
     }
   else
     {
      levels[level_idx].barsBeyondLevel = 0;
     }
   if(current_high > level_price && current_close < level_price && !levels[level_idx].reclaimDetected)
     {
      levels[level_idx].breakoutDetected = true;
      levels[level_idx].breakoutCandleShift = current_bar_shift;
      levels[level_idx].reclaimDetected = true;
      levels[level_idx].reclaimCandleShift = current_bar_shift;
      Print("SFP State Update (Resistance ", DoubleToString(level_price, _Digits),"): Wick rejection detected.");
      if(IsPowerCandle(current_bar_shift, false))
        {
         levels[level_idx].reclaimPowerCandleConfirmed = true;
         levels[level_idx].reclaimPowerCandleShift = current_bar_shift;
         levels[level_idx].reclaimPowerCandleTime = iTime(_Symbol, _Period, current_bar_shift);
         Print(" - CONFIRMATION: PASSED. Wick rejection was a power candle.");
        }
     }
   if(!levels[level_idx].reclaimDetected)
     {
      if(!levels[level_idx].breakoutDetected && current_close > level_price)
        {
         levels[level_idx].breakoutDetected = true;
         levels[level_idx].breakoutCandleShift = current_bar_shift;
         Print("SFP State Update (Resistance ", DoubleToString(level_price, _Digits),"): Breakout detected.");
        }
      if(levels[level_idx].breakoutDetected)
        {
         if(current_close < level_price)
           {
            levels[level_idx].reclaimDetected = true;
            levels[level_idx].reclaimCandleShift = current_bar_shift;
            Print("SFP State Update (Resistance ", DoubleToString(level_price, _Digits),"): Reclaim detected. Now searching for power candle...");
           }
         else if(current_bar_shift - levels[level_idx].breakoutCandleShift > ReclaimLookbackCandles)
           {
            levels[level_idx].breakoutDetected = false;
           }
        }
     }
   if(levels[level_idx].reclaimDetected && !levels[level_idx].reclaimPowerCandleConfirmed)
     {
      for(int j = 0; j <= ReclaimGraceCandles; j++)
        {
         int check_shift = levels[level_idx].reclaimCandleShift - j;
         if(check_shift < 0 || check_shift >= iBars(_Symbol, _Period)) continue;
         if(iClose(_Symbol, _Period, check_shift) < level_price && IsPowerCandle(check_shift, false))
           {
            levels[level_idx].reclaimPowerCandleConfirmed = true;
            levels[level_idx].reclaimPowerCandleShift = check_shift;
            levels[level_idx].reclaimPowerCandleTime = iTime(_Symbol, _Period, check_shift);
            Print(" - CONFIRMATION: PASSED. Found Bearish Power Candle at bar shift ", check_shift);
            break;
           }
        }
     }
   if(levels[level_idx].reclaimPowerCandleConfirmed && levels[level_idx].tradesTaken < MaxTradesPerLevel && !IsOpenTradeFromLevel(level_price))
     {
      Print("--- Evaluating SELL Signal at ", DoubleToString(level_price, _Digits), " ---");
      bool isBuy = false;
      if(ExecutionType == AGGRESSIVE)
        {
         PlaceTrade(isBuy, level_price, levels[level_idx].isResistance, levels[level_idx].timeframe, levels[level_idx].time, levels[level_idx].reclaimPowerCandleShift);
        }
      else
        {
         int sellCount = 0;
         for(int k = 0; k < ArraySize(activeSignals); k++)
           {
            if(!activeSignals[k].isBuy) sellCount++;
           }
         if(sellCount >= MaxActiveSignals)
           {
            Print("Max active sell signals reached. Ignoring new signal.");
            levels[level_idx].reclaimPowerCandleConfirmed = false;
            return;
           }
         double entry_level = 0;
         double trig_high = iHigh(_Symbol, _Period, levels[level_idx].reclaimPowerCandleShift);
         double trig_low = iLow(_Symbol, _Period, levels[level_idx].reclaimPowerCandleShift);
         if(ExecutionType == SEMI_AGGRESSIVE)
           {
            entry_level = (trig_high + trig_low) / 2.0;
           }
         else // CONSERVATIVE
           {
            entry_level = MathMin(trig_low, level_price);
           }
         int n = ArraySize(activeSignals);
         ArrayResize(activeSignals, n + 1);
         activeSignals[n].isBuy = isBuy;
         activeSignals[n].entryLevel = entry_level;
         activeSignals[n].timeCreated = iTime(_Symbol, _Period, 0);
         activeSignals[n].triggerShift = levels[level_idx].reclaimPowerCandleShift;
         activeSignals[n].levelPrice = level_price;
         activeSignals[n].isResistance = levels[level_idx].isResistance;
         activeSignals[n].timeframe = levels[level_idx].timeframe;
         activeSignals[n].pivotTime = levels[level_idx].time;
         Print("Added sell signal with entry level ", DoubleToString(entry_level, _Digits));
        }
      levels[level_idx].tradesTaken++;
      levels[level_idx].reclaimPowerCandleConfirmed = false;
      levels[level_idx].reclaimDetected = false;
      levels[level_idx].breakoutDetected = false;
     }
  }
void ProcessSupportLevel(int level_idx)
  {
   if(!levels[level_idx].validated) return;
   int current_bar_shift = 1;
   if(iBars(_Symbol, _Period) <= current_bar_shift) return;
   double current_low = iLow(_Symbol, _Period, current_bar_shift);
   double current_close = iClose(_Symbol, _Period, current_bar_shift);
   double level_price = levels[level_idx].price;
   if(levels[level_idx].expired) return;
   if(current_close < level_price)
     {
      levels[level_idx].barsBeyondLevel++;
      if(levels[level_idx].barsBeyondLevel > LevelExpiryCandles)
        {
         levels[level_idx].expired = true;
         Print("Level Expired: Support at ", DoubleToString(levels[level_idx].price, _Digits), " expired after ", IntegerToString(LevelExpiryCandles), " bars beyond.");
         return;
        }
     }
   else
     {
      levels[level_idx].barsBeyondLevel = 0;
     }
   if(current_low < level_price && current_close > level_price && !levels[level_idx].reclaimDetected)
     {
      levels[level_idx].breakoutDetected = true;
      levels[level_idx].breakoutCandleShift = current_bar_shift;
      levels[level_idx].reclaimDetected = true;
      levels[level_idx].reclaimCandleShift = current_bar_shift;
      Print("SFP State Update (Support ", DoubleToString(level_price, _Digits),"): Wick rejection detected.");
      if(IsPowerCandle(current_bar_shift, true))
        {
         levels[level_idx].reclaimPowerCandleConfirmed = true;
         levels[level_idx].reclaimPowerCandleShift = current_bar_shift;
         levels[level_idx].reclaimPowerCandleTime = iTime(_Symbol, _Period, current_bar_shift);
         Print(" - CONFIRMATION: PASSED. Wick rejection was a power candle.");
        }
     }
   if(!levels[level_idx].reclaimDetected)
     {
      if(!levels[level_idx].breakoutDetected && current_close < level_price)
        {
         levels[level_idx].breakoutDetected = true;
         levels[level_idx].breakoutCandleShift = current_bar_shift;
         Print("SFP State Update (Support ", DoubleToString(level_price, _Digits),"): Breakout detected.");
        }
      if(levels[level_idx].breakoutDetected)
        {
         if(current_close > level_price)
           {
            levels[level_idx].reclaimDetected = true;
            levels[level_idx].reclaimCandleShift = current_bar_shift;
            Print("SFP State Update (Support ", DoubleToString(level_price, _Digits),"): Reclaim detected. Now searching for power candle...");
           }
         else if(current_bar_shift - levels[level_idx].breakoutCandleShift > ReclaimLookbackCandles)
           {
            levels[level_idx].breakoutDetected = false;
           }
        }
     }
   if(levels[level_idx].reclaimDetected && !levels[level_idx].reclaimPowerCandleConfirmed)
     {
      for(int j = 0; j <= ReclaimGraceCandles; j++)
        {
         int check_shift = levels[level_idx].reclaimCandleShift - j;
         if(check_shift < 0 || check_shift >= iBars(_Symbol, _Period)) continue;
         if(iClose(_Symbol, _Period, check_shift) > level_price && IsPowerCandle(check_shift, true))
           {
            levels[level_idx].reclaimPowerCandleConfirmed = true;
            levels[level_idx].reclaimPowerCandleShift = check_shift;
            levels[level_idx].reclaimPowerCandleTime = iTime(_Symbol, _Period, check_shift);
            Print(" - CONFIRMATION: PASSED. Wick rejection was a power candle.");
            break;
           }
        }
     }
   if(levels[level_idx].reclaimPowerCandleConfirmed && levels[level_idx].tradesTaken < MaxTradesPerLevel && !IsOpenTradeFromLevel(level_price))
     {
      Print("--- Evaluating BUY Signal at ", DoubleToString(level_price, _Digits), " ---");
      bool isBuy = true;
      if(ExecutionType == AGGRESSIVE)
        {
         PlaceTrade(isBuy, level_price, levels[level_idx].isResistance, levels[level_idx].timeframe, levels[level_idx].time, levels[level_idx].reclaimPowerCandleShift);
        }
      else
        {
         int buyCount = 0;
         for(int k = 0; k < ArraySize(activeSignals); k++)
           {
            if(activeSignals[k].isBuy) buyCount++;
           }
         if(buyCount >= MaxActiveSignals)
           {
            Print("Max active buy signals reached. Ignoring new signal.");
            levels[level_idx].reclaimPowerCandleConfirmed = false;
            return;
           }
         double entry_level = 0;
         double trig_high = iHigh(_Symbol, _Period, levels[level_idx].reclaimPowerCandleShift);
         double trig_low = iLow(_Symbol, _Period, levels[level_idx].reclaimPowerCandleShift);
         if(ExecutionType == SEMI_AGGRESSIVE)
           {
            entry_level = (trig_high + trig_low) / 2.0;
           }
         else // CONSERVATIVE
           {
            entry_level = MathMin(trig_low, level_price);
           }
         int n = ArraySize(activeSignals);
         ArrayResize(activeSignals, n + 1);
         activeSignals[n].isBuy = isBuy;
         activeSignals[n].entryLevel = entry_level;
         activeSignals[n].timeCreated = iTime(_Symbol, _Period, 0);
         activeSignals[n].triggerShift = levels[level_idx].reclaimPowerCandleShift;
         activeSignals[n].levelPrice = level_price;
         activeSignals[n].isResistance = levels[level_idx].isResistance;
         activeSignals[n].timeframe = levels[level_idx].timeframe;
         activeSignals[n].pivotTime = levels[level_idx].time;
         Print("Added buy signal with entry level ", DoubleToString(entry_level, _Digits));
        }
      levels[level_idx].tradesTaken++;
      levels[level_idx].reclaimPowerCandleConfirmed = false;
      levels[level_idx].reclaimDetected = false;
      levels[level_idx].breakoutDetected = false;
     }
  }
//+------------------------------------------------------------------+
//| TRADE MANAGEMENT FUNCTIONS                                       |
//+------------------------------------------------------------------+
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
void ManagePositionsBeforeNews()
  {
   Print("--- NEWS: Starting position management before high-impact news at ", TimeToString(nextNewsTime), ". ---");
   double atr = GetATR();
   if(atr <= 0)
     {
      Print("--- NEWS: Failed to get ATR. Skipping management. ---");
      return;
     }
   double be_offset = 0.1 * atr;
   int closed = 0, modified = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i) && PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber)
        {
         double profit = PositionInfo.Profit();
         ulong ticket = PositionInfo.Ticket();
         Print("--- NEWS: Checking position #", ticket, ": Profit=", DoubleToString(profit, 2), " ---");
         if(profit < 0)
           {
            if(Trade.PositionClose(ticket))
              {
               Print("--- NEWS: Closed losing position #", ticket, ". ---");
               closed++;
              }
            else
              Print("--- NEWS: Failed to close #", ticket, ": ", GetLastError(), " ---");
           }
         else
           {
            double entry = PositionInfo.PriceOpen();
            double currentSL = PositionInfo.StopLoss();
            double new_sl = (PositionInfo.PositionType() == POSITION_TYPE_BUY) ? entry + be_offset : entry - be_offset;
            new_sl = NormalizeDouble(new_sl, _Digits);
            MqlTick tick;
            SymbolInfoTick(_Symbol, tick);
            double stops_level = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
            if (PositionInfo.PositionType() == POSITION_TYPE_BUY)
              {
               if (new_sl > currentSL && (tick.bid - new_sl) > stops_level)
                 {
                  if (Trade.PositionModify(ticket, new_sl, PositionInfo.TakeProfit()))
                    {
                     Print("--- NEWS: Modified SL for #", ticket, " to ", DoubleToString(new_sl, _Digits), ". ---");
                     modified++;
                    }
                  else
                    Print("--- NEWS: Failed to modify SL for #", ticket, ": ", GetLastError(), " ---");
                 }
              }
            else if (PositionInfo.PositionType() == POSITION_TYPE_SELL)
              {
               if ((new_sl < currentSL || currentSL == 0) && (new_sl - tick.ask) > stops_level)
                 {
                  if (Trade.PositionModify(ticket, new_sl, PositionInfo.TakeProfit()))
                    {
                     Print("--- NEWS: Modified SL for #", ticket, " to ", DoubleToString(new_sl, _Digits), ". ---");
                     modified++;
                    }
                  else
                    Print("--- NEWS: Failed to modify SL for #", ticket, ": ", GetLastError(), " ---");
                 }
              }
           }
        }
     }
   Print("--- NEWS: Management complete. Closed: ", closed, ", Modified: ", modified, " ---");
  }
int CountBuyPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i))
        {
         if(PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber && PositionInfo.PositionType() == POSITION_TYPE_BUY)
           {
            count++;
           }
        }
     }
   return count;
  }
int CountSellPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i))
        {
         if(PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber && PositionInfo.PositionType() == POSITION_TYPE_SELL)
           {
            count++;
           }
        }
     }
   return count;
  }
double CalculateBuyProfit()
  {
   double profit = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i))
        {
         if(PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber && PositionInfo.PositionType() == POSITION_TYPE_BUY)
           {
            profit += PositionInfo.Profit();
           }
        }
     }
   return profit;
  }
double CalculateSellProfit()
  {
   double profit = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i))
        {
         if(PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber && PositionInfo.PositionType() == POSITION_TYPE_SELL)
           {
            profit += PositionInfo.Profit();
           }
        }
     }
   return profit;
  }
void CloseBuyPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i))
        {
         if(PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber && PositionInfo.PositionType() == POSITION_TYPE_BUY)
           {
            Trade.PositionClose(PositionInfo.Ticket());
           }
        }
     }
   Print("Closed all buy positions.");
  }
void CloseSellPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i))
        {
         if(PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber && PositionInfo.PositionType() == POSITION_TYPE_SELL)
           {
            Trade.PositionClose(PositionInfo.Ticket());
           }
        }
     }
   Print("Closed all sell positions.");
  }
void ResetBuyVars()
  {
   initialATR_buy = 0;
   initialLot_buy = 0;
   initialEntry_buy = 0;
   initialBalance_buy = 0;
   lastEntry_buy = 0;
   positionsCount_buy = 0;
   virtualSL_buy = 0;
   initialRiskAmount_buy = 0;
   peakProfit_buy = 0;
   initialTradeTime_buy = 0;
   ArrayFree(skippedBuyLevels);
  }
void ResetSellVars()
  {
   initialATR_sell = 0;
   initialLot_sell = 0;
   initialEntry_sell = 0;
   initialBalance_sell = 0;
   lastEntry_sell = 0;
   positionsCount_sell = 0;
   virtualSL_sell = 0;
   initialRiskAmount_sell = 0;
   peakProfit_sell = 0;
   initialTradeTime_sell = 0;
   ArrayFree(skippedSellLevels);
  }
void AddBuyPosition()
  {
// --- Stop Loss validation before adding position ---
   double current_sl = 0;
// Find the stop loss from any open buy position
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i))
        {
         if(PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber && PositionInfo.PositionType() == POSITION_TYPE_BUY)
           {
            current_sl = PositionInfo.StopLoss();
            break; // Found the SL, no need to loop further
           }
        }
     }

// If for some reason SL is 0, abort adding a trade
   if(current_sl == 0)
     {
      Print("AddBuyPosition skipped: Could not retrieve current stop loss for validation.");
      return;
     }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
     {
      Print("AddBuyPosition skipped: Could not retrieve current tick for validation.");
      return;
     }

   double currentATR = GetATR();
   if(currentATR <= 0)
     {
      Print("AddBuyPosition skipped: Could not retrieve current ATR for validation.");
      return;
     }

// Check if the distance from current price to SL is at least 0.1 ATR
   if((tick.ask - current_sl) < (currentATR * 0.1))
     {
      Print("AddBuyPosition skipped: Current SL is too close. Price-SL distance ", DoubleToString(tick.ask - current_sl, _Digits), " is less than 0.1 ATR (", DoubleToString(currentATR * 0.1, _Digits), ").");
      return;
     }
// --- END of validation ---

   double newLot = initialLot_buy * Add_Lot_Multiplier;

   newLot = NormalizeDouble(newLot, 2);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(newLot < minLot) newLot = minLot;
   if(newLot > maxLot) newLot = maxLot;
   string comment = "Add Buy " + IntegerToString(positionsCount_buy + 1);
// --- CORRECTED: Use the retrieved current_sl instead of 0 ---
   if(Trade.Buy(newLot, _Symbol, 0, current_sl, 0, comment))
     {
      lastEntry_buy = Trade.ResultPrice();
      positionsCount_buy++;
     }
  }
void AddSellPosition()
  {
// --- Stop Loss validation before adding position ---
   double current_sl = 0;
// Find the stop loss from any open sell position
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i))
        {
         if(PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber && PositionInfo.PositionType() == POSITION_TYPE_SELL)
           {
            current_sl = PositionInfo.StopLoss();
            break; // Found the SL, no need to loop further
           }
        }
     }

// If for some reason SL is 0, abort adding a trade
   if(current_sl == 0)
     {
      Print("AddSellPosition skipped: Could not retrieve current stop loss for validation.");
      return;
     }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
     {
      Print("AddSellPosition skipped: Could not retrieve current tick for validation.");
      return;
     }

   double currentATR = GetATR();
   if(currentATR <= 0)
     {
      Print("AddSellPosition skipped: Could not retrieve current ATR for validation.");
      return;
     }

// Check if the distance from current price to SL is at least 0.1 ATR
   if((current_sl - tick.bid) < (currentATR * 0.1))
     {
      Print("AddSellPosition skipped: Current SL is too close. SL-Price distance ", DoubleToString(current_sl - tick.bid, _Digits), " is less than 0.1 ATR (", DoubleToString(currentATR * 0.1, _Digits), ").");
      return;
     }
// --- END of validation ---

   double newLot = initialLot_sell * Add_Lot_Multiplier;

   newLot = NormalizeDouble(newLot, 2);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(newLot < minLot) newLot = minLot;
   if(newLot > maxLot) newLot = maxLot;
   string comment = "Add Sell " + IntegerToString(positionsCount_sell + 1);
// --- CORRECTED: Use the retrieved current_sl instead of 0 ---
   if(Trade.Sell(newLot, _Symbol, 0, current_sl, 0, comment))
     {
      lastEntry_sell = Trade.ResultPrice();
      positionsCount_sell++;
     }
  }
void CheckActiveSignals()
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   for(int i = ArraySize(activeSignals) - 1; i >= 0; i--)
     {
      int bars_since = iBarShift(_Symbol, _Period, activeSignals[i].timeCreated);
      if(bars_since >= SignalExpiryCandles)
        {
         Print("Signal expired after ", bars_since, " bars.");
         ArrayRemove(activeSignals, i, 1);
         continue;
        }
      bool condition_met = false;
      if(activeSignals[i].isBuy)
        {
         if(tick.bid <= activeSignals[i].entryLevel) condition_met = true;
        }
      else
        {
         if(tick.ask >= activeSignals[i].entryLevel) condition_met = true;
        }
      if(condition_met)
        {
         if(PlaceTrade(activeSignals[i].isBuy, activeSignals[i].levelPrice, activeSignals[i].isResistance, activeSignals[i].timeframe, activeSignals[i].pivotTime, activeSignals[i].triggerShift))
           {
            ArrayRemove(activeSignals, i, 1);
           }
        }
     }
  }
void ManageBuyScaling()
  {
   if(!HasOpenBuyPositions()){ ResetBuyVars(); return; }
   double totalProfit = CalculateBuyProfit();
   double targetProfit = ProfitTargetDollar > 0 ? ProfitTargetDollar : initialBalance_buy * (ProfitTargetPercent / 100.0);
   if(initialBalance_buy > 0 && totalProfit >= targetProfit)
     {
      Print("Target profit hit for BUY positions. Closing...");
      CloseBuyPositions();
      return;
     }
   if(positionsCount_buy >= MaxPositions) return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double currentPrice = tick.ask;
   double moveInFavor = currentPrice - lastEntry_buy;
   double currentATR = GetATR();
   if(currentATR <= 0) return;
   double addThreshold = currentATR * Add_Multiplier;
   if(moveInFavor >= addThreshold)
     {
      // A scale-in is triggered. Check if this level is on the skipped list.
      bool isSkipped = false;
      for(int i = 0; i < ArraySize(skippedBuyLevels); i++)
        {
         // Use a small buffer (e.g., 10% of an ATR step) to define "the same level"
         if (MathAbs(currentPrice - skippedBuyLevels[i]) < (addThreshold * 0.1))
           {
            isSkipped = true;
            break;
           }
        }

      if (!isSkipped)
        {
         // Level is not skipped, add the position
         AddBuyPosition();
        }
      else
        {
         // This level is skipped. Do not add a trade, but update lastEntry_buy
         // to "consume" the signal and wait for the next level.
         Print("Scale-in for BUY at ", DoubleToString(currentPrice, _Digits), " skipped as it's a previously closed stale level.");
         lastEntry_buy = currentPrice;
        }
     }
  }
void ManageSellScaling()
  {
   if(!HasOpenSellPositions()){ ResetSellVars(); return; }
   double totalProfit = CalculateSellProfit();
   double targetProfit = ProfitTargetDollar > 0 ? ProfitTargetDollar : initialBalance_sell * (ProfitTargetPercent / 100.0);
   if(initialBalance_sell > 0 && totalProfit >= targetProfit)
     {
      Print("Target profit hit for SELL positions. Closing...");
      CloseSellPositions();
      return;
     }
   if(positionsCount_sell >= MaxPositions) return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double currentPrice = tick.bid;
   double moveInFavor = lastEntry_sell - currentPrice;
   double currentATR = GetATR();
   if(currentATR <= 0) return;
   double addThreshold = currentATR * Add_Multiplier;
   if(moveInFavor >= addThreshold)
     {
       // A scale-in is triggered. Check if this level is on the skipped list.
      bool isSkipped = false;
      for(int i = 0; i < ArraySize(skippedSellLevels); i++)
        {
         // Use a small buffer (e.g., 10% of an ATR step) to define "the same level"
         if (MathAbs(currentPrice - skippedSellLevels[i]) < (addThreshold * 0.1))
           {
            isSkipped = true;
            break;
           }
        }
        
      if (!isSkipped)
        {
         // Level is not skipped, add the position
         AddSellPosition();
        }
      else
        {
         // This level is skipped. Do not add a trade, but update lastEntry_sell
         // to "consume" the signal and wait for the next level.
         Print("Scale-in for SELL at ", DoubleToString(currentPrice, _Digits), " skipped as it's a previously closed stale level.");
         lastEntry_sell = currentPrice;
        }
     }
  }

//+------------------------------------------------------------------+
//| VIRTUAL TRAILING STOP FUNCTIONS                                  |
//+------------------------------------------------------------------+
double GetBasketBreakevenPrice(bool isBuy)
  {
   double sumLotEntry = 0;
   double totalLot = 0;
   ENUM_POSITION_TYPE positionType = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i) && PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber && PositionInfo.PositionType() == positionType)
        {
         sumLotEntry += PositionInfo.Volume() * PositionInfo.PriceOpen();
         totalLot += PositionInfo.Volume();
        }
     }
   if(totalLot == 0) return 0.0;
   return sumLotEntry / totalLot;
  }
void ManageTrailingStop(bool isBuy)
  {
   if(!EnableTrailingStop) return;
   if((isBuy && !HasOpenBuyPositions()) || (!isBuy && !HasOpenSellPositions())) return;

   double atr = GetATR();
   if(atr <= 0) return;

   double bePrice = GetBasketBreakevenPrice(isBuy);
   if(bePrice == 0.0) return;
   
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   double currentPrice = isBuy ? tick.bid : tick.ask;
   double profitInPoints = isBuy ? (currentPrice - bePrice) : (bePrice - currentPrice);

   if(profitInPoints > (TrailingStartATR * atr))
     {
      double newSL = isBuy ? (currentPrice - (TrailingStopATR * atr)) : (currentPrice + (TrailingStopATR * atr));
      newSL = NormalizeDouble(newSL, _Digits);

      if(isBuy)
        {
         if(newSL > virtualSL_buy || virtualSL_buy == 0)
           {
            virtualSL_buy = newSL;
            Print("VIRTUAL TRAIL [BUY]: Updated to ", DoubleToString(virtualSL_buy, _Digits));
           }
        }
      else
        {
         if(newSL < virtualSL_sell || virtualSL_sell == 0)
           {
            virtualSL_sell = newSL;
            Print("VIRTUAL TRAIL [SELL]: Updated to ", DoubleToString(virtualSL_sell, _Digits));
           }
        }
     }
  }
void CheckVirtualStops()
  {
   if(PositionsTotal() == 0) return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   if(HasOpenBuyPositions() && virtualSL_buy > 0)
     {
      if(tick.bid <= virtualSL_buy)
        {
         Print("VIRTUAL SL [BUY] HIT at ", DoubleToString(tick.bid, _Digits), ". Closing all buy positions.");
         CloseBuyPositions();
        }
     }
   if(HasOpenSellPositions() && virtualSL_sell > 0)
     {
      if(tick.ask >= virtualSL_sell)
        {
         Print("VIRTUAL SL [SELL] HIT at ", DoubleToString(tick.ask, _Digits), ". Closing all sell positions.");
         CloseSellPositions();
        }
     }
  }

//+------------------------------------------------------------------+
//| NEW ADVANCED PROFIT KEEPING FUNCTIONS                            |
//+------------------------------------------------------------------+
void ManageBasketStopLoss(bool isBuy)
  {
   int posCount = isBuy ? CountBuyPositions() : CountSellPositions(); // Use live count
   if(posCount < 2) return; // Logic only applies after the second position is added.

   double totalLot = 0;
   double bePrice = GetBasketBreakevenPrice(isBuy);
   if(bePrice == 0.0) return;

   ENUM_POSITION_TYPE type = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i) && PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber && PositionInfo.PositionType() == type)
        {
         totalLot += PositionInfo.Volume();
        }
     }

   if(totalLot == 0) return;

   double newSL = 0;

   if(EnableProgressiveBE) // True: Progressive Reward Lock
     {
      double initialRisk = isBuy ? initialRiskAmount_buy : initialRiskAmount_sell;
      if(initialRisk <= 0) return; // Can't lock profit if initial risk is unknown

      // For N positions, lock (N-1) * R
      double profitToLock = (posCount - 1) * initialRisk;

      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickValue <= 0) return; // Avoid division by zero

      double profitInPoints = (profitToLock / totalLot) / tickValue * _Point;
      newSL = isBuy ? bePrice + profitInPoints : bePrice - profitInPoints;
     }
   else // False: Basket Breakeven
     {
      double offset = BreakevenOffsetPips * _Point;
      newSL = isBuy ? bePrice + offset : bePrice - offset;
     }

   newSL = NormalizeDouble(newSL, _Digits);

   // Apply the new stop loss to all positions in the basket
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i) && PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber && PositionInfo.PositionType() == type)
        {
         double currentSL = PositionInfo.StopLoss();
         bool shouldModify = false;
         if(isBuy && newSL > currentSL)
           {
            shouldModify = true;
           }
         if(!isBuy && (newSL < currentSL || currentSL == 0))
           {
            shouldModify = true;
           }

         if(shouldModify)
           {
            Trade.PositionModify(PositionInfo.Ticket(), newSL, PositionInfo.TakeProfit());
           }
        }
     }
  }

void ManagePeakProfitDrawdown(bool isBuy)
  {
   if(!EnablePeakDrawdownExit) return;
   double currentProfit = isBuy ? CalculateBuyProfit() : CalculateSellProfit();
   double peakProfit = isBuy ? peakProfit_buy : peakProfit_sell;
   double initialRisk = isBuy ? initialRiskAmount_buy : initialRiskAmount_sell;
   if(initialRisk <= 0) return; // Cannot calculate RR without risk
   
   // Check if profit has reached the trigger level
   if(currentProfit >= initialRisk * PeakDrawdownStartRR)
     {
      // Update the peak profit only after the trigger is met
      if(currentProfit > peakProfit)
        {
         peakProfit = currentProfit;
         if(isBuy) peakProfit_buy = peakProfit;
         else peakProfit_sell = peakProfit;
        }

      // Check for drawdown
      if(peakProfit > 0 && currentProfit < peakProfit * (1 - PeakProfitDrawdownPercent / 100.0))
        {
         Print("PEAK DRAWDOWN [", (isBuy ? "BUY" : "SELL"), "] EXIT: Profit retraced from peak of ",
               DoubleToString(peakProfit, 2), " to ", DoubleToString(currentProfit, 2), ". Closing positions.");
         if(isBuy) CloseBuyPositions();
         else CloseSellPositions();
        }
     }
  }

void CheckIndividualStaleTrades()
  {
    if (!EnableStaleTradeExit) return;

    MqlTick tick;
    if (!SymbolInfoTick(_Symbol, tick)) return;

    // Loop backwards because we might be closing positions, which changes the collection
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if (PositionInfo.SelectByIndex(i) && PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber)
        {
            datetime openTime = PositionInfo.Time();
            int barsOpen = iBarShift(_Symbol, _Period, openTime); // This counts full bars since open
            
            // Check if the trade is old enough to be considered stale
            if (barsOpen > StaleTradeBars)
            {
                double entryPrice = PositionInfo.PriceOpen();
                ulong ticket = PositionInfo.Ticket();
                
                // Check for Buy position retracement
                if (PositionInfo.PositionType() == POSITION_TYPE_BUY)
                {
                    if (tick.bid <= entryPrice)
                    {
                        // Check if this is the last remaining buy position
                        if (CountBuyPositions() <= 1)
                        {
                            Print("STALE TRADE EXIT: Initial/last BUY trade #", ticket, " retraced to entry after ", barsOpen, " bars. Closing basket.");
                            CloseBuyPositions(); // This will close the last one and trigger a reset
                        }
                        else // This is a scale-in trade
                        {
                            Print("STALE TRADE EXIT: Scaled-in BUY trade #", ticket, " retraced to entry after ", barsOpen, " bars. Closing only this position and skipping level ", DoubleToString(entryPrice, _Digits), ".");
                            // Add level to the skipped list
                            int size = ArraySize(skippedBuyLevels);
                            ArrayResize(skippedBuyLevels, size + 1);
                            skippedBuyLevels[size] = entryPrice;
                            
                            // Close only this position
                            Trade.PositionClose(ticket);
                        }
                        // Break to re-evaluate on the next tick.
                        break; 
                    }
                }
                // Check for Sell position retracement
                else if (PositionInfo.PositionType() == POSITION_TYPE_SELL)
                {
                    if (tick.ask >= entryPrice)
                    {
                        // Check if this is the last remaining sell position
                        if (CountSellPositions() <= 1)
                        {
                            Print("STALE TRADE EXIT: Initial/last SELL trade #", ticket, " retraced to entry after ", barsOpen, " bars. Closing basket.");
                            CloseSellPositions(); // This will close the last one and trigger a reset
                        }
                        else // This is a scale-in trade
                        {
                             Print("STALE TRADE EXIT: Scaled-in SELL trade #", ticket, " retraced to entry after ", barsOpen, " bars. Closing only this position and skipping level ", DoubleToString(entryPrice, _Digits), ".");
                            // Add level to the skipped list
                            int size = ArraySize(skippedSellLevels);
                            ArrayResize(skippedSellLevels, size + 1);
                            skippedSellLevels[size] = entryPrice;
                            
                            // Close only this position
                            Trade.PositionClose(ticket);
                        }
                        // Break to re-evaluate on the next tick.
                        break;
                    }
                }
            }
        }
    }
}


//+------------------------------------------------------------------+
//| Main MQL5 Functions                                              |
//+------------------------------------------------------------------+
int OnInit()
  {
   Trade.SetExpertMagicNumber(EA_MagicNumber);
   Trade.SetDeviationInPoints(Slippage);
   ChartSetInteger(ChartID(), CHART_SHOW_GRID, false);
   UpdateHTFPowerCandleTrend();
   internal_left = LeftBars / 2;
   internal_right = RightBars / 2;
   if(EnableNewsManagement)
     {
      if(MQLInfoInteger(MQL_TESTER))
        {
         LoadNewsFromCache();
        }
      else
        {
         DownloadAndCacheNews();
        }
      nextNewsTime = GetNextHighImpactNewsTime();
      lastNewsCheck = TimeGMT();
     }
   return INIT_SUCCEEDED;
  }
void OnTick()
  {
   datetime ExpirationDate = StringToTime("2025.12.31 23:59:59");
   if(TimeCurrent() > ExpirationDate)
     {
      Print("EA expired. Trading disabled, please send an email to @ighodaloxauusd@gmail.com or contact @__ighodalo on X(twitter");
      return;
     }
   if(EnableNewsManagement)
     {
      if(pendingSleep && TimeGMT() >= sleepStart)
        {
         pendingSleep = false;
         inSleepMode = true;
         Print("--- NEWS: Entering sleep mode. ---");
        }
      if(inSleepMode && TimeGMT() >= sleepEndTime)
        {
         inSleepMode = false;
         Print("--- NEWS: Exiting sleep mode. ---");
        }
      if(TimeGMT() - lastNewsCheck >= NewsCheckIntervalSeconds)
        {
         lastNewsCheck = TimeGMT();
         nextNewsTime = GetNextHighImpactNewsTime();
        }
      if(nextNewsTime > 0 && nextNewsTime != lastManagedNews)
        {
         long time_to_news = nextNewsTime - TimeGMT();
         if(time_to_news <= (long)MinsBefore * 60 && time_to_news > 0)
           {
            ManagePositionsBeforeNews();
            lastManagedNews = nextNewsTime;
            pendingSleep = true;
            sleepStart = TimeGMT() + 60;
            sleepEndTime = nextNewsTime + MinsAfter * 60 - 60;
           }
        }
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
      if(!inSleepMode)
        {
         UpdateHTFPowerCandleTrend();
         UpdateLevels();
         CheckForBoS();
         for(int i = ArraySize(levels) - 1; i >= 0; i--)
           {
            if(levels[i].isResistance) ProcessResistanceLevel(i);
            else ProcessSupportLevel(i);
           }
         UpdateInternalExpiry();
         UpdateIndicatorPlots();
        }
      LastBarTime = currentBarTime;
     }
   // --- MANAGE ALL OPEN POSITION LOGIC ---
   if(PositionsTotal() > 0)
     {
      if(!HasOpenBuyPositions()) ResetBuyVars();
      if(!HasOpenSellPositions()) ResetSellVars();
      CheckVirtualStops();
      
      // *** NEW: Run individual stale check ***
      CheckIndividualStaleTrades();
      
      ManageBuyScaling();
      ManageSellScaling();
      if(HasOpenBuyPositions())
        {
         ManageTrailingStop(true);
         ManagePeakProfitDrawdown(true);
         // ManageStaleTrades(true); // OLD FUNCTION CALL REMOVED
         ManageBasketStopLoss(true);
        }
      if(HasOpenSellPositions())
        {
         ManageTrailingStop(false);
         ManagePeakProfitDrawdown(false);
         // ManageStaleTrades(false); // OLD FUNCTION CALL REMOVED
         ManageBasketStopLoss(false);
        }
     }
   else
     {
      ResetBuyVars();
      ResetSellVars();
     }
   if(ExecutionType != AGGRESSIVE && !inSleepMode)
     {
      CheckActiveSignals();
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
  }