//+------------------------------------------------------------------+
//| Ighodalo CRT EA - v1.0 |
//| CRT with Advanced Trade Management |
//| Based on Belema SFP EA |
//+------------------------------------------------------------------+
#property copyright "Ighodalo"
#property link "https://www.mql5.com"
#property version "1.0"
#property description "Combines CRT logic with Dynamic SL, Partial Closing, and a News Filter."
#property description "This version integrates the best trade management features from the Power Pivot EA."
// --- Includes ---
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\DealInfo.mqh>
#include <MovingAverages.mqh>
// This file is used by the Strategy Tester to simulate news events.
// The EA will create this file automatically when run on a live chart.
#property tester_file "CRT_NewsCache.csv"
// --- ENUMERATIONS ---
enum ENUM_EXECUTION_TYPE
  {
   AGGRESSIVE,
   SEMI_AGGRESSIVE,
   CONSERVATIVE
  };
enum ENUM_TRADE_DIRECTION {TradeBoth, TradeBuyOnly, TradeSellOnly};
// --- INPUT PARAMETERS ---
input group "Session Management"
input bool TradeNewYork = true; // Trade during New York session (12:00-21:00 GMT)
input bool TradeLondon = true; // Trade during London session (7:00-12:00 GMT)
input bool TradeTokyo = true; // Trade during Tokyo session (0:00-7:00 GMT)
input bool TradeSydney = true; // Trade during Sydney session (22:00-0:00 GMT)
input group "CRT Settings"
input bool EnableM30_CRT = true; // Detect CRT on M30 timeframe
input bool EnableH1_CRT = true; // Detect CRT on H1 timeframe
input bool EnableH2_CRT = true; // Detect CRT on H2 timeframe
input bool EnableH3_CRT = true; // Detect CRT on H3 timeframe
input bool EnableH4_CRT = true; // Detect CRT on H4 timeframe
input bool EnableH6_CRT = true; // Detect CRT on H6 timeframe
input bool EnableH12_CRT = true; // Detect CRT on H12 timeframe
input bool EnableD1_CRT = true; // Detect CRT on D1 timeframe
input bool EnableW1_CRT = true; // Detect CRT on W1 timeframe
input int MaxActiveCRTsPerTF = 3; // Maximum active CRT pairs per timeframe (replaces Max POI)
input bool EnableCRTConfirmation = false; // Wait for second candle close to confirm CRT
input int CRTLookback = 20; // Max Lookback Period for CRT
input int MaxCRTDisplay = 2000; // Max CRT lines to display overall
input int InvalidationCandleCount = 20; // Consecutive closes beyond level to invalidate
input group "CRT Plot Settings"
input color HighColor = clrBlack; // High Line Color
input string HighStyleStr = "Solid"; // High Line Style (Solid, Dashed, Dotted)
input int HighWidth = 1; // High Line Width
input color LowColor = clrBlack; // Low Line Color
input string LowStyleStr = "Solid"; // Low Line Style (Solid, Dashed, Dotted)
input int LowWidth = 1; // Low Line Width
input bool EnableLabels = true; // Enable Labels
input string LabelLocation = "End"; // Label Location (Middle, End)
input group "SFP Core Logic & Filters"
input ENUM_EXECUTION_TYPE ExecutionType = AGGRESSIVE; // Execution type
input bool UseHTFPowerCandleFilter = true; // Filter trades based on Higher Timeframe trend
input ENUM_TIMEFRAMES HTFPowerCandleTimeframe = PERIOD_H4; // Timeframe for the HTF trend filter
input int LeftBars = 22; // Bars to the left for pivot detection
input int RightBars = 22; // Bars to the right for pivot detection
input int ReclaimLookbackCandles = 8; // Max bars for reclaim after breakout
input int ReclaimGraceCandles = 10; // Max bars for power candle after reclaim
input int LevelExpiryCandles = 15; // How many bars price can close beyond a level before it expires
input int SignalExpiryCandles = 30; // Candles before signal expires
input int MaxActiveSignals = 2; // Max active signals per direction
input double MaxSignalDistanceATR = 0.3; // Max ATR distance for signal generation
input group "Risk & Position Management"
input bool EnableHedge = false; // Allow simultaneous Buy and Sell positions
input int ATR_Period = 24; // Period for ATR calculation (on custom 35-min TF)
input double ATR_SL_Multiplier = 4; // Multiplier for ATR-based Stop Loss
input double RiskPercent = 3; // Percentage of account balance to risk per trade
input double RR_Ratio = 1.5; // Risk to Reward Ratio for Take Profit
input int MaxTradesPerDay = 50; // Maximum trades allowed in a single day
input int MaxTradesPerLevel = 1; // Maximum trades allowed at a single level
input int EA_MagicNumber = 174355; // Unique identifier for trades managed by this EA
input double MinTradeDistanceAtrMultiplier = 0.1; // Minimum distance between trades (ATR multiple)
input double MaxDistanceFromLevelATR = 0.2; // Max distance from level to trigger trade (ATR multiple)
input group "Advanced Trade Management"
input bool EnablePartialClose = true; // Enable partial closing of positions
input double PartialCloseAtrMultiplier= 1.7; // ATR multiple profit target for partial close
input double PartialClosePercent = 50; // Percentage of position to close
input bool EnableBreakeven = true; // Enable moving Stop Loss to breakeven
input double BreakevenTriggerReward = 0.5; // Reward/Risk ratio to trigger breakeven
input double BreakevenReward = 0.1; // Reward/Risk ratio for the new SL after breakeven
input bool EnableTradeExpiry = true; // Enable trade expiry feature
input int TradeExpiryCandles = 20; // Number of candles after which to check for retrace to entry
input bool EnableNewTradeExpiry = true; // Enable new trade expiry feature
input int NewTradeExpiryCandles = 100; // Number of candles for new expiry
input bool EnableTrailingSL = true; // Enable trailing SL
input double TrailingSLTriggerReward = 1.0; // Reward/Risk ratio to trigger trailing SL
input double TrailingSLDistanceReward = 0.5; // Trailing distance in Reward/Risk ratio
input group "Objective Target Management"
input bool EnableObjTarget = true; // Enable objective target management
input ENUM_TIMEFRAMES ObjTargetTimeframe = PERIOD_M5; // Timeframe for objective target
input double ObjPartialClosePercent = 80.0; // Percentage of position to close at objective target
input group "Chart & Visuals"
input int PowerCandlePeriods = 20; // Lookback period for calculating average candle body size
input double PowerCandleMultiplier = 1.7; // Multiplier to define a "Power Candle"
input color BullPowerColor = 3329330; // Color for bullish power candles
input color BearPowerColor = 255; // Color for bearish power candles
input int MaxPowerCandlesToDisplay = 1000; // Max Power Candle arrows on chart
input group "News Management"
input bool EnableNewsManagement = true; // Enable/Disable the news filter system
input int NewsCheckIntervalSeconds = 3600; // How often to check for new news events (1 hour)
input int MinsBefore = 10; // Do not trade X minutes before high-impact news
input int MinsAfter = 10; // Do not trade X minutes after high-impact news
input bool PartialCloseBeforeNews = false; // Partially close profitable trades before news
input group "MACD Trend Filter"
input bool EnableMacdFilter = true; // Enable/Disable the MACD Trend Filter
input bool MacdAllowNeutral = true; // If true, trades are allowed in neutral conditions
input int MacdFastLength = 50; // MACD Fast EMA Period
input int MacdSlowLength = 200; // MACD Slow EMA Period
input int MacdSignalSmoothing = 20; // MACD Signal Line Smoothing Period
input int MacdScalingLookback = 100; // Lookback for scaling histogram values
input int MacdNeutralThreshold = 25; // Threshold (0-100) for the neutral zone
input int MacdDisplayBars = 200; // Number of bars to display for MACD histogram
input color MacdBullColor = clrDarkGreen; // Color for bullish MACD histogram
input color MacdBearColor = clrDarkRed; // Color for bearish MACD histogram
input color MacdNeutralColor = clrGray; // Color for neutral MACD histogram
input double MacdHistHeightMultiplier = 0.5; // Multiplier for histogram height (relative to ATR)
input double MacdHistOffsetMultiplier = 1.0; // Multiplier for histogram offset below chart low
input group "Profit Keeper: Peak Drawdown"
input bool EnablePeakDrawdownExit = true; // Enable peak drawdown exit
input double PeakDrawdownStartPercent = 2.0; // Profit % of initial balance to start tracking drawdown
input double PeakProfitDrawdownPercent = 30.0; // Percent drawdown from peak to exit
input group "Additional Risk Management"
input bool EnableDailyLossLimit = true; // Enable daily loss limit
input double DailyLossPercent = 5.0; // Daily loss percentage to stop trading
input bool EnableWeeklyProfitTarget = true; // Enable weekly profit target
input double WeeklyProfitPercent = 10.0; // Weekly profit percentage target
input bool EnableDailyProfitTarget = true; // Enable daily profit target
input double DailyProfitPercent = 2.0; // Daily profit percentage target
input group "No Trade Zone"
input bool EnableNoTradeZone = true; // Enable/disable no trade zone
input int NoTradeStartHour = 23; // No trade zone start hour (GMT)
input int NoTradeStartMin = 30; // No trade zone start minute (GMT)
input int NoTradeEndHour = 0; // No trade zone end hour (GMT)
input int NoTradeEndMin = 30; // No trade zone end minute (GMT)
input group "Cooldown Management"
input bool EnableCooldown = true; // Enable cooldown after stop loss
input int CooldownH4Candles = 3; // H4 candles to wait after stop loss
input group "Trade Direction Control"
input ENUM_TRADE_DIRECTION TradeDirection = TradeBoth; // Allowed trade directions
// --- GLOBAL STRUCTURES & VARIABLES ---
// Structure to hold cached news event data for the Strategy Tester
struct CachedNewsEvent
  {
   datetime time;
   string country;
   int importance;
  };
CachedNewsEvent g_cached_news[];
string g_news_cache_filename = "CRT_NewsCache.csv";
// Structure for levels and state
struct LevelInfo
  {
   double price; // Price of the level
   ENUM_TIMEFRAMES timeframe; // Timeframe of the level
   datetime time; // Time of the CRT bar
   bool isResistance; // True if CRTH, false if CRTL
   bool breakoutDetected; // Price broke the level
   int breakoutCandleShift; // Shift of breakout candle
   bool reclaimDetected; // Price reclaimed the level
   int reclaimCandleShift; // Shift of reclaim candle
   bool reclaimPowerCandleConfirmed; // Power candle confirmed reclaim
   int reclaimPowerCandleShift; // Shift of reclaim power candle
   datetime reclaimPowerCandleTime; // Time of reclaim power candle
   int tradesTaken; // Counter for trades taken at this level
   int barsBeyondLevel; // Number of consecutive bars beyond the level
   bool expired; // Visually expired for plotting, but still tradeable
   bool confirmed; // True if CRT is confirmed
   string object_name; // Chart object name for line
   string label_name; // Chart label name
   datetime end_time; // End time for line when not ray
   int consecutiveClosesBeyond; // Counter for consecutive closes beyond level
   bool permanentlyInvalidated; // True if permanently invalidated
  };
LevelInfo levels[]; // CRT levels
// Structure for active signals
struct SignalInfo
  {
   bool isBuy;
   double entryLevel;
   datetime timeCreated;
   int triggerShift;
   double levelPrice;
   bool isResistance;
   ENUM_TIMEFRAMES timeframe;
   datetime pivotTime;
  };
SignalInfo activeSignals[];
// --- STRUCT FOR TRAILING SL MANAGEMENT ---
struct TrailingInfo
  {
   ulong ticket;
   bool active;
   double initial_risk;
  };
TrailingInfo trailingPositions[];
double buy_peak_profit = 0;
bool peakDrawdownActive_buy = false;
double sell_peak_profit = 0;
bool peakDrawdownActive_sell = false;
double initialBalance_buy = 0;
double initialBalance_sell = 0;
// Arrays for managing chart objects and trade states
string powerCandleObjects[];
ulong partialClosedTickets[];
ulong objPartialClosedTickets[];
// MQL5 Standard Library trading objects
CTrade Trade;
CPositionInfo PositionInfo;
COrderInfo OrderInfo;
CDealInfo DealInfo;
// Global state variables
int TradesToday = 0;
int LastTradeDay = 0;
datetime LastBarTime = 0;
int htfTrend = 0; // 1 for Bullish, -1 for Bearish, 0 for Neutral
// News and sleep mode variables
datetime nextNewsTime = 0;
datetime lastNewsCheck = 0;
datetime lastManagedNews = 0;
bool inSleepMode = false;
bool pendingSleep = false;
datetime sleepStart = 0;
datetime sleepEndTime = 0;
string base_currency = StringSubstr(_Symbol, 0, 3);
string quote_currency = StringSubstr(_Symbol, 3, 3);
// --- NEW MACD VARIABLES ---
int macdTrendState = 0; // 1 for Bullish, -1 for Bearish, 0 for Neutral
double macd_hist[]; // For display
datetime lastM1Time = 0;
// Additional globals for new features
datetime current_day_start = 0;
bool stopped_for_day = false;
datetime current_week_start = 0;
double week_start_equity = 0;
bool stopped_for_week = false;
double day_start_equity = 0;
// Global variables for session times in GMT minutes (0-1439)
int g_ny_start_gmt_min = -1, g_ny_end_gmt_min = -1;
int g_ln_start_gmt_min = -1, g_ln_end_gmt_min = -1;
int g_tk_start_gmt_min = -1, g_tk_end_gmt_min = -1;
int g_sy_start_gmt_min = -1, g_sy_end_gmt_min = -1;
// CRT globals
ENUM_TIMEFRAMES enabled_tfs[];
datetime last_tf_times[];
datetime detectedCrtTimes[];
// Cooldown globals
datetime g_buyCooldownEndTime = 0;
datetime g_sellCooldownEndTime = 0;
// Cleanup counter
int g_cleanup_counter = 0;
//+------------------------------------------------------------------+
//| NEWS SYSTEM FUNCTIONS |
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
      int i;
      for(i = 0; i < ArraySize(values); i++)
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
      int i;
      for(i = 0; i < ArraySize(g_cached_news); i++)
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
      int c;
      for(c = 0; c < 2; c++)
        {
         if(relevant_countries[c] == "") continue;
         if(CalendarValueHistory(values, now, to, relevant_countries[c]))
           {
            int i;
            for(i = 0; i < ArraySize(values); i++)
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
//| HELPER & INDICATOR FUNCTIONS |
//+------------------------------------------------------------------+
int line_style(string s)
  {
   if(s == "Dashed") return STYLE_DASH;
   if(s == "Dotted") return STYLE_DOT;
   return STYLE_SOLID;
  }
bool array_contains(const datetime &arr[], datetime val)
  {
   int i;
   for(i = 0; i < ArraySize(arr); i++)
     {
      if(arr[i] == val) return true;
     }
   return false;
  }
bool HasOpenBuyPositions()
  {
   int total = PositionsTotal();
   int i;
   for(i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
         return true;
        }
     }
   return false;
  }
bool HasOpenSellPositions()
  {
   int total = PositionsTotal();
   int i;
   for(i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
         return true;
        }
     }
   return false;
  }
bool AreAllBuyPositionsAtBreakeven()
  {
   bool all_at_be = true;
   int total = PositionsTotal();
   int i;
   for(i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);
         if(sl < openPrice)
           {
            all_at_be = false;
            break;
           }
        }
     }
   return all_at_be;
  }
bool AreAllSellPositionsAtBreakeven()
  {
   bool all_at_be = true;
   int total = PositionsTotal();
   int i;
   for(i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);
         if(sl > openPrice)
           {
            all_at_be = false;
            break;
           }
        }
     }
   return all_at_be;
  }
bool IsOpenTradeFromLevel(double level_price)
  {
   int total = PositionsTotal();
   int i;
   for(i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber)
        {
         string comment = PositionGetString(POSITION_COMMENT);
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
   return false;
  }
bool IsPowerCandleTF(int shift, bool isBullish, ENUM_TIMEFRAMES timeframe)
  {
   if(shift + PowerCandlePeriods >= iBars(_Symbol, timeframe)) return false;
   double sum_range = 0;
   int i;
   for(i = 0; i < PowerCandlePeriods; i++)
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
   int i;
   for(i = 1; i < 2000; i++)
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
// --- FIXED MACD Filter: Use current chart timeframe for consistent calculations ---
void UpdateMacdTrend()
  {
   if(!EnableMacdFilter)
     {
      macdTrendState = 0;
      return;
     }
   // Use current chart timeframe instead of synthetic 16-min bars
   int bars_needed = MacdSlowLength + MacdSignalSmoothing + MacdScalingLookback + 10;
   int total_bars = iBars(_Symbol, _Period);
   if(total_bars < bars_needed)
     {
      Print("MACD ERROR: Not enough bars on current timeframe for calculation.");
      return;
     }
   double close_prices[];
   ArraySetAsSeries(close_prices, true);
   if(CopyClose(_Symbol, _Period, 0, bars_needed, close_prices) < bars_needed)
     {
      Print("MACD ERROR: Failed to copy close prices.");
      return;
     }
   double fast_ema[];
   double slow_ema[];
   ArrayResize(fast_ema, bars_needed);
   ArrayResize(slow_ema, bars_needed);
   ArraySetAsSeries(fast_ema, true);
   ArraySetAsSeries(slow_ema, true);
   // Calculate EMAs using current chart data
   ExponentialMAOnBuffer(bars_needed, 0, 0, MacdFastLength, close_prices, fast_ema);
   ExponentialMAOnBuffer(bars_needed, 0, 0, MacdSlowLength, close_prices, slow_ema);
   double macd_line[];
   ArrayResize(macd_line, bars_needed);
   ArraySetAsSeries(macd_line, true);
   int i;
   for(i = 0; i < bars_needed; i++)
     {
      macd_line[i] = fast_ema[i] - slow_ema[i];
     }
   double signal_line[];
   ArrayResize(signal_line, bars_needed);
   ArraySetAsSeries(signal_line, true);
   ExponentialMAOnBuffer(bars_needed, 0, 0, MacdSignalSmoothing, macd_line, signal_line);
   double hist[];
   ArrayResize(hist, bars_needed);
   ArraySetAsSeries(hist, true);
   for(i = 0; i < bars_needed; i++)
     {
      hist[i] = macd_line[i] - signal_line[i];
     }
   // Find max absolute histogram value for scaling
   double max_abs_hist = 0;
   for(i = 2; i <= MacdScalingLookback + 1 && i < bars_needed; i++)
     {
      max_abs_hist = MathMax(max_abs_hist, MathAbs(hist[i]));
     }
   if(max_abs_hist == 0)
     {
      macdTrendState = 0;
      return;
     }
   // Use previous completed bar (index 1) for decision making
   double scaled_value = (MathAbs(hist[1]) / max_abs_hist) * 100;
   // Enhanced logging for debugging
   if(scaled_value <= MacdNeutralThreshold)
     {
      macdTrendState = 0;
     }
   else if(hist[1] > 0)
     {
      macdTrendState = 1;
     }
   else
     {
      macdTrendState = -1;
      Print("MACD: Trend set to BEARISH (scaled value: ", DoubleToString(scaled_value, 2), "%)");
     }
   // Update display array with completed data
   ArrayResize(macd_hist, MathMin(MacdDisplayBars, bars_needed - 1));
   for(i = 1; i < ArraySize(macd_hist) + 1; i++)
     {
      macd_hist[i-1] = hist[i];
     }
  }
// --- FIXED MACD Display: Use consistent data with trading logic ---
void DrawMacdIndicator()
  {
   if(!EnableMacdFilter) return;
   ObjectsDeleteAll(0, "Macd", 0);
   double atr = GetCustom35MinATR();
   if(atr <= 0) return;
   double max_hist_height = atr * MacdHistHeightMultiplier;
   int long_lookback = MacdDisplayBars * 2;
   double min_low = DBL_MAX;
   int s;
   for(s = 0; s <= long_lookback; s++)
     {
      if(s >= iBars(_Symbol, _Period)) break;
      min_low = MathMin(min_low, iLow(_Symbol, _Period, s));
     }
   double offset = atr * MacdHistOffsetMultiplier;
   double base_y = min_low - offset;
   string zero_name = "MacdZero";
   ObjectCreate(0, zero_name, OBJ_HLINE, 0, 0, base_y);
   ObjectSetInteger(0, zero_name, OBJPROP_COLOR, clrGray);
   ObjectSetInteger(0, zero_name, OBJPROP_STYLE, STYLE_DOT);
   int hist_size = ArraySize(macd_hist);
   double max_abs_hist = 0;
   int i;
   for(i = 0; i < hist_size; i++)
     {
      max_abs_hist = MathMax(max_abs_hist, MathAbs(macd_hist[i]));
     }
   if(max_abs_hist == 0) return;
   for(i = 0; i < MacdDisplayBars; i++)
     {
      if(i >= hist_size) break;
      double hist_val = macd_hist[i];
      double scaled = (MathAbs(hist_val) / max_abs_hist) * 100;
      color col;
      if(scaled <= MacdNeutralThreshold)
        {
         col = MacdNeutralColor;
        }
      else if(hist_val > 0)
        {
         col = MacdBullColor;
        }
      else
        {
         col = MacdBearColor;
        }
      double height = (scaled / 100.0) * max_hist_height * (hist_val > 0 ? 1 : -1);
      datetime t1 = iTime(_Symbol, _Period, i);
      datetime t2 = t1 + PeriodSeconds(_Period);
      double p1 = base_y;
      double p2 = base_y + height;
      if(p2 < p1)
        {
         double temp = p1;
         p1 = p2;
         p2 = temp;
        }
      string name = "MacdHist_" + IntegerToString(i);
      if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p2, t2, p1))
        {
         ObjectSetInteger(0, name, OBJPROP_COLOR, col);
         ObjectSetInteger(0, name, OBJPROP_FILL, true);
         ObjectSetInteger(0, name, OBJPROP_BACK, true);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
        }
     }
  }
//+------------------------------------------------------------------+
//| CORE TRADING LOGIC |
//+------------------------------------------------------------------+
double GetCorrespondingLow(datetime crt_time, ENUM_TIMEFRAMES tf)
{
    for(int i = 0; i < ArraySize(levels); i++)
    {
        if(levels[i].timeframe == tf && levels[i].time == crt_time && !levels[i].isResistance)
        {
            return levels[i].price;
        }
    }
    return 0;
}
void RemoveCRTPair(datetime crt_time, ENUM_TIMEFRAMES tf)
{
    for(int i = ArraySize(levels) - 1; i >= 0; i--)
    {
        if(levels[i].timeframe == tf && levels[i].time == crt_time)
        {
            // Remove from detectedCrtTimes array too
            for(int j = ArraySize(detectedCrtTimes) - 1; j >= 0; j--)
            {
                if(detectedCrtTimes[j] == crt_time)
                {
                    ArrayRemove(detectedCrtTimes, j, 1);
                    break;
                }
            }
          
            ObjectDelete(0, levels[i].object_name);
            ObjectDelete(0, levels[i].label_name);
            ArrayRemove(levels, i, 1);
        }
    }
}
// IMPROVED CRT COUNTING - COUNT COMPLETE PAIRS ONLY
int CountCRTsPerTF(ENUM_TIMEFRAMES tf)
{
    int count = 0;
    datetime processed_times[];
  
    for(int i = 0; i < ArraySize(levels); i++)
    {
        if(levels[i].timeframe == tf && levels[i].isResistance &&
           !levels[i].expired && !levels[i].permanentlyInvalidated)
        {
            bool already_counted = false;
            for(int j = 0; j < ArraySize(processed_times); j++)
            {
                if(processed_times[j] == levels[i].time)
                {
                    already_counted = true;
                    break;
                }
            }
          
            if(!already_counted)
            {
                // Verify this is a complete pair
                double corresponding_low = GetCorrespondingLow(levels[i].time, tf);
                if(corresponding_low > 0)
                {
                    count++;
                    ArrayResize(processed_times, count);
                    processed_times[count-1] = levels[i].time;
                }
            }
        }
    }
    return count;
}
// IMPROVED OLDEST CRT REMOVAL
void RemoveOldestCRT(ENUM_TIMEFRAMES tf)
{
    datetime oldest_time = LONG_MAX;
  
    // Find the oldest resistance level with a valid pair
    for(int i = 0; i < ArraySize(levels); i++)
    {
        if(levels[i].timeframe == tf && levels[i].isResistance &&
           !levels[i].expired && !levels[i].permanentlyInvalidated)
        {
            if(levels[i].time < oldest_time)
            {
                oldest_time = levels[i].time;
            }
        }
    }
  
    if(oldest_time != LONG_MAX)
    {
        Print("Removing Oldest CRT for ", EnumToString(tf), " from time: ", TimeToString(oldest_time));
        RemoveCRTPair(oldest_time, tf);
    }
    else
    {
        Print("WARNING: No valid CRT found to remove for ", EnumToString(tf));
    }
}
// Modified to allow narrower contained ranges
bool IsCRTLapped(double new_high, double new_low, ENUM_TIMEFRAMES tf, datetime new_time)
{
    for(int i = 0; i < ArraySize(levels); i++)
    {
        if(levels[i].timeframe == tf && !levels[i].permanentlyInvalidated && levels[i].isResistance)
        {
            double existing_low = GetCorrespondingLow(levels[i].time, tf);
          
            // Check if new CRT is completely inside existing CRT
            if(new_high <= levels[i].price && new_low >= existing_low)
            {
                double new_range = new_high - new_low;
                double exist_range = levels[i].price - existing_low;
                if(new_range < 0.5 * exist_range)
                {
                    Print("Allowed nested CRT as narrower: ", EnumToString(tf),
                          " New [", new_low, " - ", new_high, "] inside [", existing_low, " - ", levels[i].price, "]");
                    return false; // Allow if >50% narrower
                }
                else
                {
                    Print("CRT Contained - Skipping: New CRT inside existing ", EnumToString(tf),
                          " [", new_low, " - ", new_high, "] inside [", existing_low, " - ", levels[i].price, "]");
                    return true;
                }
            }
          
            // Check if new CRT completely contains existing CRT - REMOVE THE OLD ONE
            if(new_high >= levels[i].price && new_low <= existing_low)
            {
                Print("CRT Contains Existing - Removing old: ", EnumToString(tf),
                      " [", existing_low, " - ", levels[i].price, "] contained by new [", new_low, " - ", new_high, "]");
                RemoveCRTPair(levels[i].time, tf);
                return false; // Allow the new CRT to be added
            }
        }
    }
    return false;
}
// ADD THIS NEW FUNCTION - CLEANS UP INVALIDATED CRTs
void CleanupInvalidCRTs()
{
    int removed = 0;
    for(int i = ArraySize(levels) - 1; i >= 0; i--)
    {
        if(levels[i].permanentlyInvalidated)
        {
            ObjectDelete(0, levels[i].object_name);
            ObjectDelete(0, levels[i].label_name);
            ArrayRemove(levels, i, 1);
            removed++;
        }
    }
    if(removed > 0) Print("Cleaned up ", removed, " invalidated CRTs");
}
// New function to remove levels older than 30 days
void CleanOldLevels(ENUM_TIMEFRAMES tf)
{
   for(int i = ArraySize(levels) - 1; i >= 0; i--)
   {
      if(levels[i].timeframe == tf && levels[i].isResistance && (TimeCurrent() - levels[i].time) / 86400 > 30)
      {
         Print("Removing old CRT (>30 days): ", EnumToString(tf), " at time ", TimeToString(levels[i].time));
         RemoveCRTPair(levels[i].time, tf);
      }
   }
}
// New periodic cleanup function
void CleanupStaleCRTs()
{
   for(int t = 0; t < ArraySize(enabled_tfs); t++)
   {
      ENUM_TIMEFRAMES tf = enabled_tfs[t];
      for(int i = ArraySize(levels) - 1; i >= 0; i--)
      {
         if(levels[i].timeframe == tf && levels[i].isResistance)
         {
            int bars_since = iBarShift(_Symbol, _Period, levels[i].time);
            if(bars_since > 50 && !levels[i].breakoutDetected && levels[i].tradesTaken == 0)
            {
               Print("Removing stale CRT (no interaction in 50 bars): ", EnumToString(tf), " at time ", TimeToString(levels[i].time));
               RemoveCRTPair(levels[i].time, tf);
            }
         }
      }
   }
}
void DetectCRT(ENUM_TIMEFRAMES tf)
  {
   CleanupInvalidCRTs();
   CleanOldLevels(tf); // Remove old levels before count check
   int bars_needed = CRTLookback + 2;
   double high_arr[];
   double low_arr[];
   datetime time_arr[];
   ArraySetAsSeries(high_arr, true);
   ArraySetAsSeries(low_arr, true);
   ArraySetAsSeries(time_arr, true);
   if(CopyHigh(_Symbol, tf, 1, bars_needed, high_arr) < bars_needed) return;
   if(CopyLow(_Symbol, tf, 1, bars_needed, low_arr) < bars_needed) return;
   if(CopyTime(_Symbol, tf, 1, bars_needed, time_arr) < bars_needed) return;
   double crt_highs[];
   double crt_lows[];
   datetime crt_times[];
   int k;
   for(k = 1; k <= CRTLookback; k++)
     {
      if(high_arr[k] == 0) continue;
      double potH = high_arr[k];
      double potL = low_arr[k];
      double max_h = -DBL_MAX;
      double min_l = DBL_MAX;
      int j;
      for(j = 0; j < k; j++)
        {
         max_h = MathMax(max_h, high_arr[j]);
         min_l = MathMin(min_l, low_arr[j]);
        }
      bool within = max_h <= potH && min_l >= potL;
      bool unique = true;
      double hh = max_h;
      hh = MathMax(hh, potH);
      double ll = min_l;
      ll = MathMin(ll, potL);
      int i;
      for(i = 0; i < k; i++)
        {
         if(high_arr[i] == hh && low_arr[i] == ll)
           {
            unique = false;
            break;
           }
        }
      if(within && unique)
        {
         int size = ArraySize(crt_highs);
         ArrayResize(crt_highs, size + 1);
         crt_highs[size] = potH;
         ArrayResize(crt_lows, size + 1);
         crt_lows[size] = potL;
         ArrayResize(crt_times, size + 1);
         crt_times[size] = time_arr[k];
        }
     }
   int num = ArraySize(crt_highs);
   if(num > 0)
     {
      int m = num - 1;
      datetime c_time = crt_times[m];
      if(!array_contains(detectedCrtTimes, c_time))
        {
         Print("Potential CRT detected: [", DoubleToString(crt_lows[m], _Digits), " - ", DoubleToString(crt_highs[m], _Digits), "] on ", EnumToString(tf));
         if(IsCRTLapped(crt_highs[m], crt_lows[m], tf, c_time))
         {
            return; // Skip if contained, function already handles removal if new contains old
         }
         int current_crt_count = CountCRTsPerTF(tf);
         if(current_crt_count >= MaxActiveCRTsPerTF)
         {
            RemoveOldestCRT(tf);
         }
         LevelInfo high_level;
         high_level.price = crt_highs[m];
         high_level.timeframe = tf;
         high_level.time = c_time;
         high_level.isResistance = true;
         high_level.breakoutDetected = false;
         high_level.breakoutCandleShift = 0;
         high_level.reclaimDetected = false;
         high_level.reclaimCandleShift = 0;
         high_level.reclaimPowerCandleConfirmed = false;
         high_level.reclaimPowerCandleShift = 0;
         high_level.reclaimPowerCandleTime = 0;
         high_level.tradesTaken = 0;
         high_level.barsBeyondLevel = 0;
         high_level.expired = false;
         high_level.confirmed = !EnableCRTConfirmation;
         high_level.end_time = 0;
         high_level.consecutiveClosesBeyond = 0;
         high_level.permanentlyInvalidated = false;
         int l_size = ArraySize(levels);
         ArrayResize(levels, l_size + 1);
         levels[l_size] = high_level;
         LevelInfo low_level = high_level;
         low_level.price = crt_lows[m];
         low_level.isResistance = false;
         ArrayResize(levels, l_size + 2);
         levels[l_size + 1] = low_level;
         int d_size = ArraySize(detectedCrtTimes);
         ArrayResize(detectedCrtTimes, d_size + 1);
         detectedCrtTimes[d_size] = c_time;
         AddLevel(high_level);
         AddLevel(low_level);
         ManageMaxCRTDisplay();
        }
     }
  }
void ManageMaxCRTDisplay()
  {
   while(ArraySize(levels) > MaxCRTDisplay)
     {
      int oldest_idx = 0;
      datetime oldest_time = levels[0].time;
      for(int i = 1; i < ArraySize(levels); i++)
        {
         if(levels[i].time < oldest_time)
           {
            oldest_time = levels[i].time;
            oldest_idx = i;
           }
        }
      ObjectDelete(0, levels[oldest_idx].object_name);
      ObjectDelete(0, levels[oldest_idx].label_name);
      ArrayRemove(levels, oldest_idx, 1);
     }
  }
void ConfirmCRTs(ENUM_TIMEFRAMES tf)
  {
   double htf_close = iClose(_Symbol, tf, 1);
   int i;
   for(i = 0; i < ArraySize(levels); i++)
     {
      if(levels[i].timeframe == tf && !levels[i].confirmed && !levels[i].expired)
        {
         bool beyond = levels[i].isResistance ? htf_close > levels[i].price : htf_close < levels[i].price;
         if(beyond)
           {
            levels[i].expired = true;
           }
         else
           {
            levels[i].confirmed = true;
           }
        }
     }
  }
void UpdateLevelExpiry()
  {
   // Removed close-based expiry
  }
void UpdateInvalidation()
  {
   int shift = 1;
   double close = iClose(_Symbol, _Period, shift);
   for(int i = ArraySize(levels) - 1; i >= 0; i--)
   {
      if(levels[i].permanentlyInvalidated) continue;
      bool beyond = levels[i].isResistance ? close > levels[i].price : close < levels[i].price;
      if(beyond)
        {
         levels[i].consecutiveClosesBeyond++;
         if(levels[i].consecutiveClosesBeyond >= InvalidationCandleCount)
           {
            levels[i].permanentlyInvalidated = true;
            Print("CRT Permanently Invalidated: ", levels[i].isResistance ? "CRTH" : "CRTL", " at ",
                  DoubleToString(levels[i].price, _Digits), " after ", levels[i].consecutiveClosesBeyond, " consecutive closes beyond.");
            ObjectDelete(0, levels[i].object_name);
            ObjectDelete(0, levels[i].label_name);
            ArrayRemove(levels, i, 1);
           }
        }
      else
        {
         levels[i].consecutiveClosesBeyond = 0;
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
   int i;
   for(i = 0; i < ATR_Period; i++)
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
      int j;
      for(j = start_idx; j <= end_idx; j++)
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
   int total = PositionsTotal();
   int i;
   for(i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber)
        {
         double existingOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         if(MathAbs(newEntryPrice - existingOpenPrice) < minDistance)
           {
            Print("Trade Blocked: New trade at ", DoubleToString(newEntryPrice, _Digits),
                  " is too close to existing OPEN POSITION at ", DoubleToString(existingOpenPrice, _Digits),
                  ". Required distance: ", DoubleToString(minDistance, _Digits));
            return true;
           }
        }
     }
   return false;
  }
// --- FIXED MACD Filter: Enhanced logging and consistent timing ---
bool PlaceTrade(bool isBuy, double level, bool isResistance, ENUM_TIMEFRAMES tf, datetime pivotTime, int triggerCandleShift)
  {
   if(EnableNoTradeZone && IsNoTradeZone())
   {
      Print("Trade Blocked: Currently in No Trade Zone");
      return false;
   }
 
   if(EnableCooldown)
   {
      if(isBuy && TimeCurrent() < g_buyCooldownEndTime)
      {
         Print("Trade Blocked: Buy cooldown active until ", TimeToString(g_buyCooldownEndTime));
         return false;
      }
      if(!isBuy && TimeCurrent() < g_sellCooldownEndTime)
      {
         Print("Trade Blocked: Sell cooldown active until ", TimeToString(g_sellCooldownEndTime));
         return false;
      }
   }
 
   // Existing trade direction check
   if(TradeDirection == TradeBuyOnly && !isBuy) return false;
   if(TradeDirection == TradeSellOnly && isBuy) return false;
   if(stopped_for_day)
     {
      Print("Trade Blocked: Daily loss limit reached.");
      return false;
     }
   if(stopped_for_week)
     {
      Print("Trade Blocked: Weekly profit target reached.");
      return false;
     }
   if(TradesToday >= MaxTradesPerDay || !IsWithinSession()) return false;
   if(!EnableHedge)
     {
      if(isBuy && HasOpenSellPositions())
        {
         Print("Trade Blocked (Hedging OFF): Trying to open Buy, but Sell position open.");
         return false;
        }
      if(!isBuy && HasOpenBuyPositions())
        {
         Print("Trade Blocked (Hedging OFF): Trying to open Sell, but Buy position open.");
         return false;
        }
     }
   if(isBuy && HasOpenBuyPositions() && !AreAllBuyPositionsAtBreakeven())
     {
      Print("Trade Blocked: A Buy position is already open and not at breakeven.");
      return false;
     }
   if(!isBuy && HasOpenSellPositions() && !AreAllSellPositionsAtBreakeven())
     {
      Print("Trade Blocked: A Sell position is already open and not at breakeven.");
      return false;
     }
   double marketPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(IsTradeTooClose(marketPrice))
     {
      return false;
     }
   Print(" - Trade Spacing Filter: PASSED. New trade is a safe distance from existing positions/orders.");
   if(UseHTFPowerCandleFilter)
     {
      if(isBuy && htfTrend == -1)
        {
         Print("Trade Blocked: Attempting to BUY, but HTF trend is BEARISH. Signal ignored.");
         return false;
        }
      if(!isBuy && htfTrend == 1)
        {
         Print("Trade Blocked: Attempting to SELL, but HTF trend is BULLISH. Signal ignored.");
         return false;
        }
      Print(" - HTF Trend Filter: PASSED. Trade direction aligns with HTF trend.");
     }
   // FIXED MACD Filter: Update MACD RIGHT BEFORE trade decision with enhanced logging
   if(EnableMacdFilter)
     {
      UpdateMacdTrend(); // Ensure we have the latest MACD data
      PrintFormat("MACD TRADE CHECK: Attempting %s, MACD State=%d (1=Bullish, -1=Bearish, 0=Neutral), AllowNeutral=%s",
                  isBuy ? "BUY" : "SELL", macdTrendState, MacdAllowNeutral ? "true" : "false");
      if(isBuy)
        {
         if(macdTrendState == -1)
           {
            Print(">>> TRADE BLOCKED by MACD: Attempting to BUY, but MACD trend is BEARISH.");
            return false;
           }
         if(macdTrendState == 0 && !MacdAllowNeutral)
           {
            Print(">>> TRADE BLOCKED by MACD: Attempting to BUY, but MACD trend is NEUTRAL (and neutral trades are disabled).");
            return false;
           }
        }
      else
        {
         if(macdTrendState == 1)
           {
            Print(">>> TRADE BLOCKED by MACD: Attempting to SELL, but MACD trend is BULLISH.");
            return false;
           }
         if(macdTrendState == 0 && !MacdAllowNeutral)
           {
            Print(">>> TRADE BLOCKED by MACD: Attempting to SELL, but MACD trend is NEUTRAL (and neutral trades are disabled).");
            return false;
           }
        }
      Print(" - MACD Trend Filter: PASSED. Trade direction aligns with MACD trend.");
     }
   double atr_35m = GetCustom35MinATR();
   if(atr_35m <= 0)
     {
      Print("Failed to get custom 35-min ATR. Cannot place trade.");
      return false;
     }
   if(MathAbs(marketPrice - level) > atr_35m * MaxDistanceFromLevelATR)
     {
      Print("Trade Blocked: Current price too far from level (", DoubleToString(MathAbs(marketPrice - level) / atr_35m, 2), " ATR > ", MaxDistanceFromLevelATR, " ATR).");
      return false;
     }
   double slDistance = atr_35m * ATR_SL_Multiplier;
   double min_stop_points = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
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
   string comment = "CRT|" + shortTradeType + "|" + shortTfStr + "|CRT:" + TimeToString(pivotTime, TIME_DATE | TIME_MINUTES) + "|@ " + DoubleToString(level, _Digits);
   double sl = isBuy ? marketPrice - slDistance : marketPrice + slDistance;
   double tp = isBuy ? marketPrice + slDistance * RR_Ratio : marketPrice - slDistance * RR_Ratio;
   string tradeType = isBuy ? "Buy Market" : "Sell Market";
   bool order_sent = false;
   if(isBuy)
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
      if(isBuy) {
         if(initialBalance_buy == 0) initialBalance_buy = AccountInfoDouble(ACCOUNT_BALANCE);
      } else {
         if(initialBalance_sell == 0) initialBalance_sell = AccountInfoDouble(ACCOUNT_BALANCE);
      }
      TradesToday++;
      Print(">>> TRADE EXECUTED: ", tradeType, " at ", DoubleToString(marketPrice, _Digits),
            ". SL: ", DoubleToString(sl, _Digits), ", TP: ", DoubleToString(tp, _Digits),
            ". Time: ", TimeToString(TimeCurrent()));
      SaveEnhancedState();
      return true;
     }
   return false;
  }
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
bool ProcessResistanceLevel(int level_idx)
  {
   if(!levels[level_idx].confirmed || levels[level_idx].permanentlyInvalidated) return false;
   int current_bar_shift = 1;
   if(iBars(_Symbol, _Period) <= current_bar_shift) return false;
   double current_high = iHigh(_Symbol, _Period, current_bar_shift);
   double current_close = iClose(_Symbol, _Period, current_bar_shift);
   double level_price = levels[level_idx].price;
   if(current_high > level_price && current_close < level_price && !levels[level_idx].reclaimDetected)
     {
      levels[level_idx].breakoutDetected = true;
      levels[level_idx].breakoutCandleShift = current_bar_shift;
      levels[level_idx].reclaimDetected = true;
      levels[level_idx].reclaimCandleShift = current_bar_shift;
      Print("SFP State Update (CRTH ", DoubleToString(level_price, _Digits),"): Wick rejection detected.");
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
         Print("SFP State Update (CRTH ", DoubleToString(level_price, _Digits),"): Breakout detected.");
        }
      if(levels[level_idx].breakoutDetected)
        {
         if(current_close < level_price)
           {
            levels[level_idx].reclaimDetected = true;
            levels[level_idx].reclaimCandleShift = current_bar_shift;
            Print("SFP State Update (CRTH ", DoubleToString(level_price, _Digits),"): Reclaim detected. Now searching for power candle...");
           }
         else if(current_bar_shift - levels[level_idx].breakoutCandleShift > ReclaimLookbackCandles)
           {
            levels[level_idx].breakoutDetected = false;
           }
        }
     }
   if(levels[level_idx].reclaimDetected && !levels[level_idx].reclaimPowerCandleConfirmed)
     {
      int j;
      for(j = 0; j <= ReclaimGraceCandles; j++)
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
      double current_atr = GetCustom35MinATR();
      double trigger_close = iClose(_Symbol, _Period, levels[level_idx].reclaimPowerCandleShift);
      double distance_to_level = MathAbs(trigger_close - level_price);
    
      bool isBuy = false;
      if(ExecutionType == AGGRESSIVE)
        {
         if(PlaceTrade(isBuy, level_price, levels[level_idx].isResistance, levels[level_idx].timeframe, levels[level_idx].time, levels[level_idx].reclaimPowerCandleShift))
           {
            levels[level_idx].tradesTaken++;
            levels[level_idx].reclaimPowerCandleConfirmed = false;
            levels[level_idx].reclaimDetected = false;
            levels[level_idx].breakoutDetected = false;
            SaveEnhancedState();
            return true;
           }
        }
      else
        {
         if(EnableMacdFilter)
           {
            UpdateMacdTrend();
            PrintFormat("MACD PENDING SELL CHECK: macdTrendState=%d, AllowNeutral=%s",
                        macdTrendState, MacdAllowNeutral ? "true" : "false");
            if(macdTrendState == 1 || (macdTrendState == 0 && !MacdAllowNeutral))
              {
               Print(">>> MACD UNFAVORABLE: Blocking creation of pending SELL signal.");
               levels[level_idx].reclaimPowerCandleConfirmed = false;
               return false;
              }
           }
         int sellCount = 0;
         int k;
         for(k = 0; k < ArraySize(activeSignals); k++)
           {
            if(!activeSignals[k].isBuy) sellCount++;
           }
         if(sellCount >= MaxActiveSignals)
           {
            Print("Max active sell signals reached. Ignoring new signal.");
            levels[level_idx].reclaimPowerCandleConfirmed = false;
            return false;
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
            entry_level = MathMax(trig_high, level_price);
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
         levels[level_idx].tradesTaken++;
         levels[level_idx].reclaimPowerCandleConfirmed = false;
         levels[level_idx].reclaimDetected = false;
         levels[level_idx].breakoutDetected = false;
         SaveEnhancedState();
         return true;
        }
     }
   return false;
  }
bool ProcessSupportLevel(int level_idx)
  {
   if(!levels[level_idx].confirmed || levels[level_idx].permanentlyInvalidated) return false;
   int current_bar_shift = 1;
   if(iBars(_Symbol, _Period) <= current_bar_shift) return false;
   double current_low = iLow(_Symbol, _Period, current_bar_shift);
   double current_close = iClose(_Symbol, _Period, current_bar_shift);
   double level_price = levels[level_idx].price;
   if(current_low < level_price && current_close > level_price && !levels[level_idx].reclaimDetected)
     {
      levels[level_idx].breakoutDetected = true;
      levels[level_idx].breakoutCandleShift = current_bar_shift;
      levels[level_idx].reclaimDetected = true;
      levels[level_idx].reclaimCandleShift = current_bar_shift;
      Print("SFP State Update (CRTL ", DoubleToString(level_price, _Digits),"): Wick rejection detected.");
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
         Print("SFP State Update (CRTL ", DoubleToString(level_price, _Digits),"): Breakout detected.");
        }
      if(levels[level_idx].breakoutDetected)
        {
         if(current_close > level_price)
           {
            levels[level_idx].reclaimDetected = true;
            levels[level_idx].reclaimCandleShift = current_bar_shift;
            Print("SFP State Update (CRTL ", DoubleToString(level_price, _Digits),"): Reclaim detected. Now searching for power candle...");
           }
         else if(current_bar_shift - levels[level_idx].breakoutCandleShift > ReclaimLookbackCandles)
           {
            levels[level_idx].breakoutDetected = false;
           }
        }
     }
   if(levels[level_idx].reclaimDetected && !levels[level_idx].reclaimPowerCandleConfirmed)
     {
      int j;
      for(j = 0; j <= ReclaimGraceCandles; j++)
        {
         int check_shift = levels[level_idx].reclaimCandleShift - j;
         if(check_shift < 0 || check_shift >= iBars(_Symbol, _Period)) continue;
         if(iClose(_Symbol, _Period, check_shift) > level_price && IsPowerCandle(check_shift, true))
           {
            levels[level_idx].reclaimPowerCandleConfirmed = true;
            levels[level_idx].reclaimPowerCandleShift = check_shift;
            levels[level_idx].reclaimPowerCandleTime = iTime(_Symbol, _Period, check_shift);
            Print(" - CONFIRMATION: PASSED. Found Bullish Power Candle at bar shift ", check_shift);
            break;
           }
        }
     }
   if(levels[level_idx].reclaimPowerCandleConfirmed && levels[level_idx].tradesTaken < MaxTradesPerLevel && !IsOpenTradeFromLevel(level_price))
     {
      Print("--- Evaluating BUY Signal at ", DoubleToString(level_price, _Digits), " ---");
      double current_atr = GetCustom35MinATR();
      double trigger_close = iClose(_Symbol, _Period, levels[level_idx].reclaimPowerCandleShift);
      double distance_to_level = MathAbs(trigger_close - level_price);
      bool isBuy = true;
      if(ExecutionType == AGGRESSIVE)
        {
         if(PlaceTrade(isBuy, level_price, levels[level_idx].isResistance, levels[level_idx].timeframe, levels[level_idx].time, levels[level_idx].reclaimPowerCandleShift))
           {
            levels[level_idx].tradesTaken++;
            levels[level_idx].reclaimPowerCandleConfirmed = false;
            levels[level_idx].reclaimDetected = false;
            levels[level_idx].breakoutDetected = false;
            SaveEnhancedState();
            return true;
           }
        }
      else
        {
         if(EnableMacdFilter)
           {
            UpdateMacdTrend();
            PrintFormat("MACD PENDING BUY CHECK: macdTrendState=%d, AllowNeutral=%s",
                        macdTrendState, MacdAllowNeutral ? "true" : "false");
            if(macdTrendState == -1 || (macdTrendState == 0 && !MacdAllowNeutral))
              {
               Print(">>> MACD UNFAVORABLE: Blocking creation of pending BUY signal.");
               levels[level_idx].reclaimPowerCandleConfirmed = false;
               return false;
              }
           }
         int buyCount = 0;
         int k;
         for(k = 0; k < ArraySize(activeSignals); k++)
           {
            if(activeSignals[k].isBuy) buyCount++;
           }
         if(buyCount >= MaxActiveSignals)
           {
            Print("Max active buy signals reached. Ignoring new signal.");
            levels[level_idx].reclaimPowerCandleConfirmed = false;
            return false;
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
         levels[level_idx].tradesTaken++;
         levels[level_idx].reclaimPowerCandleConfirmed = false;
         levels[level_idx].reclaimDetected = false;
         levels[level_idx].breakoutDetected = false;
         SaveEnhancedState();
         return true;
        }
     }
   return false;
  }
//+------------------------------------------------------------------+
//| TRADE MANAGEMENT FUNCTIONS |
//+------------------------------------------------------------------+
bool IsWithinSession()
  {
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int current_gmt_minutes = dt.hour * 60 + dt.min;
   // Check New York
   if(g_ny_start_gmt_min != -1)
     {
      if(g_ny_start_gmt_min <= g_ny_end_gmt_min)
        {
         if(current_gmt_minutes >= g_ny_start_gmt_min && current_gmt_minutes < g_ny_end_gmt_min) return true;
        }
      else
        {
         if(current_gmt_minutes >= g_ny_start_gmt_min || current_gmt_minutes < g_ny_end_gmt_min) return true;
        }
     }
   // Check London
   if(g_ln_start_gmt_min != -1)
     {
      if(g_ln_start_gmt_min <= g_ln_end_gmt_min)
        {
         if(current_gmt_minutes >= g_ln_start_gmt_min && current_gmt_minutes < g_ln_end_gmt_min) return true;
        }
      else
        {
         if(current_gmt_minutes >= g_ln_start_gmt_min || current_gmt_minutes < g_ln_end_gmt_min) return true;
        }
     }
   // Check Tokyo
   if(g_tk_start_gmt_min != -1)
     {
      if(g_tk_start_gmt_min <= g_tk_end_gmt_min)
        {
         if(current_gmt_minutes >= g_tk_start_gmt_min && current_gmt_minutes < g_tk_end_gmt_min) return true;
        }
      else
        {
         if(current_gmt_minutes >= g_tk_start_gmt_min || current_gmt_minutes < g_tk_end_gmt_min) return true;
        }
     }
   // Check Sydney
   if(g_sy_start_gmt_min != -1)
     {
      if(g_sy_start_gmt_min <= g_sy_end_gmt_min)
        {
         if(current_gmt_minutes >= g_sy_start_gmt_min && current_gmt_minutes < g_sy_end_gmt_min) return true;
        }
      else
        {
         if(current_gmt_minutes >= g_sy_start_gmt_min || current_gmt_minutes < g_sy_end_gmt_min) return true;
        }
     }
   bool any_session_defined = g_ny_start_gmt_min != -1 || g_ln_start_gmt_min != -1 || g_tk_start_gmt_min != -1 || g_sy_start_gmt_min != -1;
   if(!any_session_defined) return true;
   return false;
  }
void CheckBreakeven()
  {
   if(!EnableBreakeven) return;
   int total = PositionsTotal();
   int i;
   for(i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
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
void CheckPartialClose()
  {
   if(!EnablePartialClose) return;
   double atr = GetCustom35MinATR();
   if(atr <= 0) return;
   double trigger_distance = atr * PartialCloseAtrMultiplier;
   int total = PositionsTotal();
   int i;
   for(i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber) continue;
      bool already_partial = false;
      int j;
      for(j = 0; j < ArraySize(partialClosedTickets); j++)
        {
         if(partialClosedTickets[j] == ticket)
           {
            already_partial = true;
            break;
           }
        }
      if(already_partial) continue;
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      MqlTick current_tick;
      if(!SymbolInfoTick(_Symbol, current_tick)) continue;
      double current_price = (posType == POSITION_TYPE_BUY) ? current_tick.bid : current_tick.ask;
      double profit_distance = (posType == POSITION_TYPE_BUY) ? (current_price - openPrice) : (openPrice - current_price);
      if(profit_distance >= trigger_distance)
        {
         double original_volume = PositionGetDouble(POSITION_VOLUME);
         double volume = original_volume;
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
               Print("Failed to take partial profit for position #", ticket, ": ", GetLastError());
           }
        }
     }
  }
void ManagePositionsBeforeNews()
  {
   Print("--- NEWS: Starting position management before high-impact news at ", TimeToString(nextNewsTime), ". ---");
   double atr = GetCustom35MinATR();
   if(atr <= 0)
     {
      Print("--- NEWS: Failed to get ATR. Skipping management. ---");
      return;
     }
   double be_offset = 0.1 * atr;
   int closed = 0, modified = 0, partial = 0;
   int total = PositionsTotal();
   int i;
   for(i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber)
        {
         double profit = PositionGetDouble(POSITION_PROFIT);
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
            double entry = PositionGetDouble(POSITION_PRICE_OPEN);
            double new_sl = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? entry + be_offset : entry - be_offset;
            new_sl = NormalizeDouble(new_sl, _Digits);
            MqlTick tick;
            SymbolInfoTick(_Symbol, tick);
            long stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
            bool valid = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && new_sl <= tick.bid - stops_level * _Point) ||
                         (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && new_sl >= tick.ask + stops_level * _Point);
            if(!valid)
              {
               new_sl = entry;
               new_sl = NormalizeDouble(new_sl, _Digits);
              }
            if(Trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP)))
              {
               Print("--- NEWS: Modified SL for #", ticket, " to ", DoubleToString(new_sl, _Digits), ". ---");
               modified++;
              }
            else
               Print("--- NEWS: Failed to modify SL for #", ticket, ": ", GetLastError(), " ---");
            if(PartialCloseBeforeNews)
              {
               double volume = PositionGetDouble(POSITION_VOLUME);
               double close_vol = volume * (PartialClosePercent / 100.0);
               double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
               close_vol = vol_step * MathRound(close_vol / vol_step);
               if(close_vol > 0 && close_vol < volume)
                 {
                  if(Trade.PositionClosePartial(ticket, close_vol))
                    {
                     Print("--- NEWS: Partial closed #", ticket, ": ", DoubleToString(close_vol, 2), " lots. ---");
                     partial++;
                    }
                  else
                     Print("--- NEWS: Failed partial close #", ticket, ": ", GetLastError(), " ---");
                 }
              }
           }
        }
     }
   Print("--- NEWS: Management complete. Closed: ", closed, ", Modified: ", modified, ", Partial: ", partial, " ---");
  }
double GetMostRecentResistance(ENUM_TIMEFRAMES tf)
  {
   datetime max_time = 0;
   double price = 0;
   int i;
   for(i = 0; i < ArraySize(levels); i++)
     {
      if(levels[i].timeframe == tf && levels[i].isResistance && !levels[i].expired && !levels[i].permanentlyInvalidated)
        {
         if(levels[i].time > max_time)
           {
            max_time = levels[i].time;
            price = levels[i].price;
           }
        }
     }
   return price;
  }
double GetMostRecentSupport(ENUM_TIMEFRAMES tf)
  {
   datetime max_time = 0;
   double price = 0;
   int i;
   for(i = 0; i < ArraySize(levels); i++)
     {
      if(levels[i].timeframe == tf && !levels[i].isResistance && !levels[i].expired && !levels[i].permanentlyInvalidated)
        {
         if(levels[i].time > max_time)
           {
            max_time = levels[i].time;
            price = levels[i].price;
           }
        }
     }
   return price;
  }
void CheckObjTarget()
  {
   if(!EnableObjTarget) return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   int total = PositionsTotal();
   int i;
   for(i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber) continue;
      bool already_handled = false;
      int j;
      for(j = 0; j < ArraySize(objPartialClosedTickets); j++)
        {
         if(objPartialClosedTickets[j] == ticket)
           {
            already_handled = true;
            break;
           }
        }
      if(already_handled) continue;
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double profit = PositionGetDouble(POSITION_PROFIT);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double target = 0;
      if(posType == POSITION_TYPE_BUY)
        {
         target = GetMostRecentResistance(ObjTargetTimeframe);
         if(target == 0) continue;
         bool hit = tick.bid >= target;
         if(!hit) continue;
        }
      else
        {
         target = GetMostRecentSupport(ObjTargetTimeframe);
         if(target == 0) continue;
         bool hit = tick.ask <= target;
         if(!hit) continue;
        }
      if(profit < 0)
        {
         if(Trade.PositionClose(ticket))
           {
            Print("Obj Target Hit in Loss: Closed full ", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"), " position #", ticket, " at target ", DoubleToString(target, _Digits));
           }
        }
      else
        {
         double volume = PositionGetDouble(POSITION_VOLUME);
         double close_vol = volume * (ObjPartialClosePercent / 100.0);
         double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
         close_vol = vol_step * MathRound(close_vol / vol_step);
         if(close_vol > 0 && close_vol <= volume)
           {
            if(Trade.PositionClosePartial(ticket, close_vol))
              {
               Print("Obj Target Hit in Profit: Partial closed ", DoubleToString(close_vol, 2), " lots of position #", ticket, " at target ", DoubleToString(target, _Digits));
               double risk = MathAbs(entry - sl);
               double new_sl = (posType == POSITION_TYPE_BUY) ? entry + risk * BreakevenReward : entry - risk * BreakevenReward;
               new_sl = NormalizeDouble(new_sl, _Digits);
               bool valid = (posType == POSITION_TYPE_BUY && new_sl <= tick.bid) || (posType == POSITION_TYPE_SELL && new_sl >= tick.ask);
               if(!valid) new_sl = entry;
               if(Trade.PositionModify(ticket, new_sl, tp))
                 {
                  Print("Obj Target: Moved SL to breakeven for remaining position #", ticket, " at ", DoubleToString(new_sl, _Digits));
                 }
               int size = ArraySize(objPartialClosedTickets);
               ArrayResize(objPartialClosedTickets, size + 1);
               objPartialClosedTickets[size] = ticket;
              }
           }
        }
     }
  }
void CheckTradeExpiry()
  {
   if(!EnableTradeExpiry) return;
   int total = PositionsTotal();
   int i;
   for(i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      int bars_since = iBarShift(_Symbol, _Period, open_time);
      if(bars_since <= TradeExpiryCandles) continue;
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double profit = PositionGetDouble(POSITION_PROFIT);
      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick)) continue;
      double current_price = (posType == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
      bool close_condition = false;
      if(profit > 0)
        {
         if(posType == POSITION_TYPE_BUY && current_price <= open_price) close_condition = true;
         if(posType == POSITION_TYPE_SELL && current_price >= open_price) close_condition = true;
        }
      else
        {
         if(posType == POSITION_TYPE_BUY && current_price >= open_price) close_condition = true;
         if(posType == POSITION_TYPE_SELL && current_price <= open_price) close_condition = true;
        }
      if(close_condition)
        {
         Trade.PositionClose(ticket);
         Print("Trade Expiry: Closed ", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"), " position #", ticket, " at approximately entry price after ", bars_since, " bars.");
        }
     }
  }
double GetNearestHigherResistance(double ref_price)
  {
   double nearest = DBL_MAX;
   bool found = false;
   int i;
   for(i = 0; i < ArraySize(levels); i++)
     {
      if(levels[i].isResistance && !levels[i].expired && !levels[i].permanentlyInvalidated && levels[i].price > ref_price)
        {
         if(!found || levels[i].price < nearest)
           {
            nearest = levels[i].price;
            found = true;
           }
        }
     }
   return found ? nearest : 0;
  }
double GetNearestLowerSupport(double ref_price)
  {
   double nearest = -DBL_MAX;
   bool found = false;
   int i;
   for(i = 0; i < ArraySize(levels); i++)
     {
      if(!levels[i].isResistance && !levels[i].expired && !levels[i].permanentlyInvalidated && levels[i].price < ref_price)
        {
         if(!found || levels[i].price > nearest)
           {
            nearest = levels[i].price;
            found = true;
           }
        }
     }
   return found ? nearest : 0;
  }
void CheckNewTradeExpiry()
  {
   if(!EnableNewTradeExpiry) return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   int total = PositionsTotal();
   int i;
   for(i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      int bars_since = iBarShift(_Symbol, _Period, open_time);
      if(bars_since <= NewTradeExpiryCandles) continue;
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(posType == POSITION_TYPE_BUY)
        {
         double res = GetNearestHigherResistance(open_price);
         if(res > 0 && tick.bid >= res)
           {
            Trade.PositionClose(ticket);
            Print("New Trade Expiry: Closed BUY position #", ticket, " at resistance ", DoubleToString(res, _Digits), " after ", bars_since, " bars.");
           }
        }
      else
        {
         double sup = GetNearestLowerSupport(open_price);
         if(sup > 0 && tick.ask <= sup)
           {
            Trade.PositionClose(ticket);
            Print("New Trade Expiry: Closed SELL position #", ticket, " at support ", DoubleToString(sup, _Digits), " after ", bars_since, " bars.");
           }
        }
     }
  }
void CheckTrailingSL()
  {
   if(!EnableTrailingSL) return;
   double close1 = iClose(_Symbol, _Period, 1);
   int total = PositionsTotal();
   int p;
   for(p = 0; p < total; p++)
     {
      ulong ticket = PositionGetTicket(p);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      bool found = false;
      int j;
      for(j = 0; j < ArraySize(trailingPositions); j++)
        {
         if(trailingPositions[j].ticket == ticket)
           {
            found = true;
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double open = PositionGetDouble(POSITION_PRICE_OPEN);
            double current_sl = PositionGetDouble(POSITION_SL);
            double tp = PositionGetDouble(POSITION_TP);
            double profit_points = (posType == POSITION_TYPE_BUY ? close1 - open : open - close1);
            double r = trailingPositions[j].initial_risk;
            if(r <= 0) continue;
            if(!trailingPositions[j].active && profit_points >= TrailingSLTriggerReward * r)
              {
               trailingPositions[j].active = true;
               Print("Trailing SL activated for position #", ticket);
              }
            if(trailingPositions[j].active)
              {
               double new_sl;
               if(posType == POSITION_TYPE_BUY)
                 {
                  new_sl = close1 - TrailingSLDistanceReward * r;
                  new_sl = NormalizeDouble(new_sl, _Digits);
                  if(new_sl > current_sl)
                    {
                     if(Trade.PositionModify(ticket, new_sl, tp))
                       Print("Trailing SL updated for BUY position #", ticket, " to ", DoubleToString(new_sl, _Digits));
                    }
                 }
               else
                 {
                  new_sl = close1 + TrailingSLDistanceReward * r;
                  new_sl = NormalizeDouble(new_sl, _Digits);
                  if(new_sl < current_sl || current_sl == 0)
                    {
                     if(Trade.PositionModify(ticket, new_sl, tp))
                       Print("Trailing SL updated for SELL position #", ticket, " to ", DoubleToString(new_sl, _Digits));
                    }
                 }
              }
            break;
           }
        }
      if(!found)
        {
         double sl = PositionGetDouble(POSITION_SL);
         double open = PositionGetDouble(POSITION_PRICE_OPEN);
         double initial_r = MathAbs(open - sl);
         if(initial_r > 0)
           {
            int size = ArraySize(trailingPositions);
            ArrayResize(trailingPositions, size + 1);
            trailingPositions[size].ticket = ticket;
            trailingPositions[size].active = false;
            trailingPositions[size].initial_risk = initial_r;
           }
        }
     }
   int j;
   for(j = ArraySize(trailingPositions) - 1; j >= 0; j--)
     {
      if(!PositionSelectByTicket(trailingPositions[j].ticket))
        ArrayRemove(trailingPositions, j, 1);
     }
  }
// --- FIXED MACD Filter: Update before checking active signals ---
void CheckActiveSignals()
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   int i;
   for(i = ArraySize(activeSignals) - 1; i >= 0; i--)
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
         if(IsLevelStillValid(activeSignals[i].levelPrice, activeSignals[i].isResistance))
           {
            if(EnableMacdFilter)
              {
               UpdateMacdTrend();
               PrintFormat("MACD ACTIVE SIGNAL CHECK: %s signal, macdTrendState=%d",
                           activeSignals[i].isBuy ? "BUY" : "SELL", macdTrendState);
              }
            if(PlaceTrade(activeSignals[i].isBuy, activeSignals[i].levelPrice, activeSignals[i].isResistance,
                          activeSignals[i].timeframe, activeSignals[i].pivotTime, activeSignals[i].triggerShift))
              {
               ArrayRemove(activeSignals, i, 1);
               SaveEnhancedState();
               break;
              }
           }
         else
           {
            Print("Signal at ", DoubleToString(activeSignals[i].entryLevel, _Digits), " cancelled because its source level has expired.");
            ArrayRemove(activeSignals, i, 1);
           }
        }
     }
  }
void CloseAllTrades()
  {
   int total = PositionsTotal();
   int i;
   for(i = total - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber)
        {
         Trade.PositionClose(ticket);
        }
     }
  }
void CheckDailyLossLimit()
  {
   if(!EnableDailyLossLimit || stopped_for_day) return;
   datetime now = TimeCurrent();
   MqlDateTime dts;
   TimeToStruct(now, dts);
   dts.hour = 0;
   dts.min = 0;
   dts.sec = 0;
   datetime day_start = StructToTime(dts);
   if(HistorySelect(day_start, now))
     {
      double dpl = 0;
      int j;
      for(j = 0; j < HistoryDealsTotal(); j++)
        {
         ulong dt = HistoryDealGetTicket(j);
         if(dt > 0 && HistoryDealGetString(dt, DEAL_SYMBOL) == _Symbol && HistoryDealGetInteger(dt, DEAL_MAGIC) == EA_MagicNumber)
           {
            dpl += HistoryDealGetDouble(dt, DEAL_PROFIT);
           }
        }
      double day_start_balance = AccountInfoDouble(ACCOUNT_BALANCE) - dpl;
      double max_loss = day_start_balance * (DailyLossPercent / 100.0);
      if(dpl <= -max_loss)
        {
         stopped_for_day = true;
         Print("Daily loss limit reached. Loss: ", DoubleToString(-dpl, 2), " >= ", DoubleToString(max_loss, 2), ". Stopping trading for the day.");
        }
     }
  }
void CheckDailyProfitTarget()
  {
   if(!EnableDailyProfitTarget || stopped_for_day) return;
   double curr_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double target_equity = day_start_equity * (1 + DailyProfitPercent / 100.0);
   if(curr_equity >= target_equity)
     {
      Print("Daily profit target reached. Closing all trades and stopping for the day.");
      CloseAllTrades();
      stopped_for_day = true;
     }
  }
//+------------------------------------------------------------------+
//| UPDATED CRT PLOTTING FUNCTIONS - MATCHING TRADINGVIEW BEHAVIOR |
//+------------------------------------------------------------------+
void AddLevel(LevelInfo &level)
{
   string tfStr = EnumToString(level.timeframe);
   StringReplace(tfStr, "PERIOD_", "");
   string typeStr = level.isResistance ? "CRTH" : "CRTL";
   string name = "Level_" + tfStr + "_" + typeStr + "_" + TimeToString(level.time);
   level.object_name = name;
   // Set end time to current time initially (will be updated on each bar)
   datetime end_t = TimeCurrent();
   level.end_time = end_t;
   if(ObjectCreate(0, name, OBJ_TREND, 0, level.time, level.price, end_t, level.price))
   {
      color col = level.isResistance ? HighColor : LowColor;
      string style_s = level.isResistance ? HighStyleStr : LowStyleStr;
      int width = level.isResistance ? HighWidth : LowWidth;
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetInteger(0, name, OBJPROP_STYLE, line_style(style_s));
      ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false); // NOT a ray - will stop at end_time
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, end_t); // Set end time
   }
   string label_name = name + "_Label";
   level.label_name = label_name;
   if(EnableLabels)
   {
      string lab_text = tfStr + " " + typeStr;
      datetime lab_t = LabelLocation == "Middle" ? (level.time + end_t) / 2 : end_t;
      if(ObjectCreate(0, label_name, OBJ_TEXT, 0, lab_t, level.price))
      {
         ObjectSetString(0, label_name, OBJPROP_TEXT, lab_text);
         ObjectSetInteger(0, label_name, OBJPROP_COLOR, level.isResistance ? HighColor : LowColor);
         ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, 8);
         ObjectSetInteger(0, label_name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, label_name, OBJPROP_HIDDEN, false);
         ObjectSetInteger(0, label_name, OBJPROP_ANCHOR, level.isResistance ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
      }
   }
}
void UpdateLines()
{
   datetime curr_t = TimeCurrent();
   for(int i = 0; i < ArraySize(levels); i++)
   {
      if(levels[i].expired || levels[i].permanentlyInvalidated)
      {
         // For expired levels, don't update - keep them at their break time
         continue;
      }
      // Update end time to current time for active levels
      levels[i].end_time = curr_t;
      ObjectSetInteger(0, levels[i].object_name, OBJPROP_TIME, 1, curr_t);
      datetime lab_t = LabelLocation == "Middle" ? (levels[i].time + curr_t) / 2 : curr_t;
      ObjectSetInteger(0, levels[i].label_name, OBJPROP_TIME, lab_t);
   }
}
// UPDATED: Check CRT expiry based on TF close, matching Pine Script exactly, with added time-based invalidation
void CheckCRTExpiry(ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
  {
   // Use shift 1 (previous completed bar) for the close check
   double htf_close = iClose(_Symbol, tf, 1);
   if(htf_close == 0) return;
   for(int j = ArraySize(levels) - 1; j >= 0; j--)
   {
      if(levels[j].timeframe == tf && levels[j].confirmed && !levels[j].permanentlyInvalidated)
        {
         // Check for age-based invalidation
         int bars_since = iBarShift(_Symbol, tf, levels[j].time, false);
         if(bars_since > 20 && !levels[j].breakoutDetected && levels[j].tradesTaken == 0)
         {
            levels[j].permanentlyInvalidated = true;
            Print("CRT Invalidated due to age no interaction: ", levels[j].isResistance ? "CRTH" : "CRTL", " at ",
                  DoubleToString(levels[j].price, _Digits), " on ", EnumToString(tf));
            if(levels[j].isResistance) RemoveCRTPair(levels[j].time, tf);
            continue;
         }
         
         // Standard expiry check
         if(!levels[j].expired)
         {
            bool beyond = (levels[j].isResistance && htf_close > levels[j].price) ||
                          (!levels[j].isResistance && htf_close < levels[j].price);
      
            if(beyond)
            {
               // Set the break time to the time of the bar that broke the level
               datetime break_time = iTime(_Symbol, tf, 1) + PeriodSeconds(tf) - 1;
               levels[j].expired = true;
               levels[j].end_time = break_time;
         
               // Update the line object to stop at break time
               ObjectSetInteger(0, levels[j].object_name, OBJPROP_TIME, 1, break_time);
         
               // Update label position
               datetime lab_t = LabelLocation == "Middle" ? (levels[j].time + break_time) / 2 : break_time;
               ObjectSetInteger(0, levels[j].label_name, OBJPROP_TIME, lab_t);
         
               Print("CRT Expired: ", levels[j].isResistance ? "CRTH" : "CRTL", " at ",
                     DoubleToString(levels[j].price, _Digits), " on ", EnumToString(tf),
                     " - Broken by close at ", DoubleToString(htf_close, _Digits));
            }
         }
        }
     }
  }
// --- Main MQL5 Functions ---
int OnInit()
  {
   Trade.SetExpertMagicNumber(EA_MagicNumber);
   ChartSetInteger(ChartID(), CHART_SHOW_GRID, false);
   UpdateHTFPowerCandleTrend();
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
   ArrayResize(macd_hist, MacdDisplayBars);
   if(TradeNewYork) { g_ny_start_gmt_min = 720; g_ny_end_gmt_min = 1260; }
   if(TradeLondon) { g_ln_start_gmt_min = 420; g_ln_end_gmt_min = 720; }
   if(TradeTokyo) { g_tk_start_gmt_min = 0; g_tk_end_gmt_min = 420; }
   if(TradeSydney) { g_sy_start_gmt_min = 1320; g_sy_end_gmt_min = 0; }
   // Initialize enabled_tfs
   int tf_count = 0;
   if(EnableM30_CRT) { ArrayResize(enabled_tfs, tf_count+1); enabled_tfs[tf_count++] = PERIOD_M30; }
   if(EnableH1_CRT) { ArrayResize(enabled_tfs, tf_count+1); enabled_tfs[tf_count++] = PERIOD_H1; }
   if(EnableH2_CRT) { ArrayResize(enabled_tfs, tf_count+1); enabled_tfs[tf_count++] = PERIOD_H2; }
   if(EnableH3_CRT) { ArrayResize(enabled_tfs, tf_count+1); enabled_tfs[tf_count++] = PERIOD_H3; }
   if(EnableH4_CRT) { ArrayResize(enabled_tfs, tf_count+1); enabled_tfs[tf_count++] = PERIOD_H4; }
   if(EnableH6_CRT) { ArrayResize(enabled_tfs, tf_count+1); enabled_tfs[tf_count++] = PERIOD_H6; }
   if(EnableH12_CRT) { ArrayResize(enabled_tfs, tf_count+1); enabled_tfs[tf_count++] = PERIOD_H12; }
   if(EnableD1_CRT) { ArrayResize(enabled_tfs, tf_count+1); enabled_tfs[tf_count++] = PERIOD_D1; }
   if(EnableW1_CRT) { ArrayResize(enabled_tfs, tf_count+1); enabled_tfs[tf_count++] = PERIOD_W1; }
   ArrayResize(last_tf_times, tf_count);
   ArrayFill(last_tf_times, 0, tf_count, 0);
   LoadEnhancedState();
   return(INIT_SUCCEEDED);
  }
void OnTick()
  {
   datetime ExpirationDate = StringToTime("2025.12.31 23:59:59");
   if(TimeCurrent() > ExpirationDate)
     {
      Print("EA expired. Trading disabled, please send an email to @ighodaloxauusd@gmail.com or contact @__ighodalo on X(twitter)");
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
         if(time_to_news <= MinsBefore * 60 && time_to_news > 0)
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
      g_cleanup_counter++;
      if(g_cleanup_counter % 100 == 0)
      {
         CleanupStaleCRTs();
      }
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      datetime this_day_start;
      TimeToStruct(TimeCurrent(), dt);
      dt.hour = 0;
      dt.min = 0;
      dt.sec = 0;
      this_day_start = StructToTime(dt);
      if(this_day_start > current_day_start)
        {
         current_day_start = this_day_start;
         day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
         stopped_for_day = false;
         TradesToday = 0;
         LastTradeDay = dt.day;
         Print("New day started. Day start equity: ", day_start_equity, ". Trading resumed.");
        }
      MqlDateTime wdt;
      TimeToStruct(TimeCurrent(), wdt);
      int dow = wdt.day_of_week;
      datetime this_week_start = TimeCurrent() - (datetime)((long)(dow - 1) * 86400);
      MqlDateTime wsdt;
      TimeToStruct(this_week_start, wsdt);
      wsdt.hour = 0;
      wsdt.min = 0;
      wsdt.sec = 0;
      this_week_start = StructToTime(wsdt);
      if(this_week_start > current_week_start)
        {
         current_week_start = this_week_start;
         week_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
         stopped_for_week = false;
         Print("Weekly reset: Trading resumed for new week. Week start equity: ", week_start_equity);
        }
      if(!inSleepMode)
        {
         UpdateHTFPowerCandleTrend();
         UpdateLines();
         UpdateMacdTrend();
         DrawMacdIndicator();
         int i;
         for(i = 0; i < ArraySize(enabled_tfs); i++)
           {
            ENUM_TIMEFRAMES tf = enabled_tfs[i];
            datetime curr = iTime(_Symbol, tf, 0);
            if(curr > last_tf_times[i])
              {
               last_tf_times[i] = curr;
               DetectCRT(tf);
               if(EnableCRTConfirmation) ConfirmCRTs(tf);
               CheckCRTExpiry(tf); // UPDATED: Check expiry on new TF bar, using TF close
              }
           }
         CheckCRTExpiry();
         UpdateInvalidation();
         for(i = ArraySize(levels) - 1; i >= 0; i--)
           {
            bool tradePlaced = false;
            if(levels[i].isResistance)
              {
               tradePlaced = ProcessResistanceLevel(i);
              }
            else
              {
               tradePlaced = ProcessSupportLevel(i);
              }
            if(tradePlaced) break;
           }
         UpdateIndicatorPlots();
        }
      CheckDailyLossLimit();
      CheckDailyProfitTarget();
      CheckTrailingSL();
      LastBarTime = currentBarTime;
     }
   CheckBreakeven();
   CheckPartialClose();
   CheckObjTarget();
   CheckTradeExpiry();
   CheckNewTradeExpiry();
   if(ExecutionType != AGGRESSIVE && !inSleepMode)
     {
      CheckActiveSignals();
     }
   if(EnablePeakDrawdownExit)
     {
      double buy_profit = 0;
      double sell_profit = 0;
      int total = PositionsTotal();
      int i;
      for(i = 0; i < total; i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket != 0)
           {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber)
              {
               double profit = PositionGetDouble(POSITION_PROFIT);
               ENUM_POSITION_TYPE typ = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
               if(typ == POSITION_TYPE_BUY) buy_profit += profit;
               else sell_profit += profit;
              }
           }
        }
      // Buys
      if(HasOpenBuyPositions())
        {
         double profit_percent = (buy_profit / initialBalance_buy) * 100.0;
         if(!peakDrawdownActive_buy && profit_percent >= PeakDrawdownStartPercent)
           {
            peakDrawdownActive_buy = true;
            buy_peak_profit = buy_profit;
            Print("Buy drawdown monitoring activated at profit % ", profit_percent);
           }
         if(peakDrawdownActive_buy)
           {
            if(buy_profit > buy_peak_profit) buy_peak_profit = buy_profit;
            double drawdown = buy_peak_profit - buy_profit;
            double dd_percent = (drawdown / buy_peak_profit) * 100;
            if(dd_percent >= PeakProfitDrawdownPercent)
              {
               CloseAllBuys();
               peakDrawdownActive_buy = false;
               buy_peak_profit = 0;
               Print("Closed all buys due to peak profit drawdown of ", dd_percent, "%");
              }
           }
        }
      else ResetBuyVars();
      // Sells
      if(HasOpenSellPositions())
        {
         double profit_percent = (sell_profit / initialBalance_sell) * 100.0;
         if(!peakDrawdownActive_sell && profit_percent >= PeakDrawdownStartPercent)
           {
            peakDrawdownActive_sell = true;
            sell_peak_profit = sell_profit;
            Print("Sell drawdown monitoring activated at profit % ", profit_percent);
           }
         if(peakDrawdownActive_sell)
           {
            if(sell_profit > sell_peak_profit) sell_peak_profit = sell_profit;
            double drawdown = sell_peak_profit - sell_profit;
            double dd_percent = (drawdown / sell_peak_profit) * 100;
            if(dd_percent >= PeakProfitDrawdownPercent)
              {
               CloseAllSells();
               peakDrawdownActive_sell = false;
               sell_peak_profit = 0;
               Print("Closed all sells due to peak profit drawdown of ", dd_percent, "%");
              }
           }
        }
      else ResetSellVars();
     }
   if(EnableWeeklyProfitTarget && !stopped_for_week)
     {
      double curr_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double target_equity = week_start_equity * (1 + WeeklyProfitPercent / 100.0);
      if(curr_equity >= target_equity)
        {
         Print("Weekly profit target reached. Closing all trades and stopping for the week.");
         CloseAllTrades();
         stopped_for_week = true;
        }
     }
   int i;
   for(i = ArraySize(partialClosedTickets) - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(partialClosedTickets[i]))
        {
         ArrayRemove(partialClosedTickets, i, 1);
        }
     }
   for(i = ArraySize(objPartialClosedTickets) - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(objPartialClosedTickets[i]))
        {
         ArrayRemove(objPartialClosedTickets, i, 1);
        }
     }
   if(EnableCooldown) CheckForStopLossHits();
  }
void CloseAllBuys()
  {
   int total = PositionsTotal();
   int i;
   for(i = total - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0)
        {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
           {
            Trade.PositionClose(ticket);
           }
        }
     }
  }
void CloseAllSells()
  {
   int total = PositionsTotal();
   int i;
   for(i = total - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0)
        {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
           {
            Trade.PositionClose(ticket);
           }
        }
     }
  }
void ResetBuyVars()
  {
   peakDrawdownActive_buy = false;
   buy_peak_profit = 0;
   initialBalance_buy = 0;
  }
void ResetSellVars()
  {
   peakDrawdownActive_sell = false;
   sell_peak_profit = 0;
   initialBalance_sell = 0;
  }
void OnDeinit(const int reason)
  {
  }
bool IsLevelStillValid(double price, bool is_resistance)
  {
   int i;
   for(i = 0; i < ArraySize(levels); i++)
     {
      if(levels[i].isResistance == is_resistance && MathAbs(levels[i].price - price) < _Point * 5 && !levels[i].expired && !levels[i].permanentlyInvalidated)
        {
         return true;
        }
     }
   return false;
  }
bool IsPivotHighTF(ENUM_TIMEFRAMES tf, int idx, int left, int right)
  {
   int total_bars_tf = iBars(_Symbol, tf);
   if(idx < right || idx + left >= total_bars_tf) return false;
   double value = iHigh(_Symbol, tf, idx);
   int i;
   for(i = idx - right; i <= idx + left; i++)
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
   int i;
   for(i = idx - right; i <= idx + left; i++)
     {
      if(i == idx) continue;
      if(iLow(_Symbol, tf, i) <= value) return false;
     }
   return true;
  }
bool IsNoTradeZone()
{
   if(!EnableNoTradeZone) return false;
 
   MqlDateTime now;
   TimeToStruct(TimeGMT(), now); // Use GMT time for consistency
 
   int currentMinutes = now.hour * 60 + now.min;
   int startMinutes = NoTradeStartHour * 60 + NoTradeStartMin;
   int endMinutes = NoTradeEndHour * 60 + NoTradeEndMin;
 
   if(startMinutes <= endMinutes)
   {
      return (currentMinutes >= startMinutes && currentMinutes < endMinutes);
   }
   else
   {
      return (currentMinutes >= startMinutes || currentMinutes < endMinutes);
   }
}
void CheckForStopLossHits()
  {
   if(HistorySelect(TimeCurrent() - 3600, TimeCurrent())) // Last hour
     {
      int deals = HistoryDealsTotal();
      for(int i = deals - 1; i >= 0; i--)
        {
         ulong deal_ticket = HistoryDealGetTicket(i);
         if(deal_ticket > 0)
           {
            if(HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) == EA_MagicNumber &&
               HistoryDealGetString(deal_ticket, DEAL_SYMBOL) == _Symbol &&
               HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
              {
               string comment = HistoryDealGetString(deal_ticket, DEAL_COMMENT);
               bool is_sl_hit = StringFind(comment, "sl") >= 0;
               if(is_sl_hit)
                {
                 long type = HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
                 bool is_buy = false; // Determine if it was buy or sell based on profit or other
                 double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
                 if(profit < 0) // Assume SL hit is negative profit
                   {
                    // To determine direction, need to check original position type
                    // For simplicity, assume recent SL is for direction
                    // Better: Check if buy or sell based on deal reason or comment
                    if(StringFind(comment, "Buy") >= 0) is_buy = true;
                    else is_buy = false;
                    if(is_buy)
                      {
                       g_buyCooldownEndTime = TimeCurrent() + CooldownH4Candles * 14400;
                       Print("SL Hit on BUY - Cooldown until ", TimeToString(g_buyCooldownEndTime));
                      }
                    else
                      {
                       g_sellCooldownEndTime = TimeCurrent() + CooldownH4Candles * 14400;
                       Print("SL Hit on SELL - Cooldown until ", TimeToString(g_sellCooldownEndTime));
                      }
                    SaveEnhancedState();
                   }
                }
              }
           }
        }
     }
  }
void SaveEnhancedState()
{
   // Save cooldown timers
   GlobalVariableSet(_Symbol + IntegerToString(EA_MagicNumber) + "_BuyCooldown", (double)g_buyCooldownEndTime);
   GlobalVariableSet(_Symbol + IntegerToString(EA_MagicNumber) + "_SellCooldown", (double)g_sellCooldownEndTime);
 
   // Save trade direction state
   GlobalVariableSet(_Symbol + IntegerToString(EA_MagicNumber) + "_TradeDirection", (double)TradeDirection);
 
   // Save active signals array
   GlobalVariableSet(_Symbol + IntegerToString(EA_MagicNumber) + "_SignalCount", (double)ArraySize(activeSignals));
   for(int i = 0; i < ArraySize(activeSignals); i++)
   {
      string prefix = _Symbol + IntegerToString(EA_MagicNumber) + "_Signal_" + IntegerToString(i) + "_";
      GlobalVariableSet(prefix + "isBuy", activeSignals[i].isBuy ? 1.0 : 0.0);
      GlobalVariableSet(prefix + "entryLevel", activeSignals[i].entryLevel);
      GlobalVariableSet(prefix + "timeCreated", (double)activeSignals[i].timeCreated);
      GlobalVariableSet(prefix + "triggerShift", (double)activeSignals[i].triggerShift);
      GlobalVariableSet(prefix + "levelPrice", activeSignals[i].levelPrice);
      GlobalVariableSet(prefix + "isResistance", activeSignals[i].isResistance ? 1.0 : 0.0);
      GlobalVariableSet(prefix + "timeframe", (double)activeSignals[i].timeframe);
      GlobalVariableSet(prefix + "pivotTime", (double)activeSignals[i].pivotTime);
   }
 
   // Save only active CRT levels
   int valid_count = 0;
   for(int i = 0; i < ArraySize(levels); i++)
   {
      if(!levels[i].expired && !levels[i].permanentlyInvalidated) valid_count++;
   }
   GlobalVariableSet(_Symbol + IntegerToString(EA_MagicNumber) + "_LevelCount", (double)valid_count);
   int valid_idx = 0;
   for(int i = 0; i < ArraySize(levels); i++)
   {
      if(!levels[i].expired && !levels[i].permanentlyInvalidated)
      {
         string prefix = _Symbol + IntegerToString(EA_MagicNumber) + "_Level_" + IntegerToString(valid_idx) + "_";
         GlobalVariableSet(prefix + "price", levels[i].price);
         GlobalVariableSet(prefix + "tradesTaken", (double)levels[i].tradesTaken);
         GlobalVariableSet(prefix + "expired", levels[i].expired ? 1.0 : 0.0);
         GlobalVariableSet(prefix + "timeframe", (double)levels[i].timeframe);
         GlobalVariableSet(prefix + "time", (double)levels[i].time);
         GlobalVariableSet(prefix + "isResistance", levels[i].isResistance ? 1.0 : 0.0);
         GlobalVariableSet(prefix + "permanentlyInvalidated", levels[i].permanentlyInvalidated ? 1.0 : 0.0);
         valid_idx++;
      }
   }
}
void LoadEnhancedState()
{
   // Load cooldown timers
   if(GlobalVariableCheck(_Symbol + IntegerToString(EA_MagicNumber) + "_BuyCooldown"))
      g_buyCooldownEndTime = (datetime)GlobalVariableGet(_Symbol + IntegerToString(EA_MagicNumber) + "_BuyCooldown");
 
   if(GlobalVariableCheck(_Symbol + IntegerToString(EA_MagicNumber) + "_SellCooldown"))
      g_sellCooldownEndTime = (datetime)GlobalVariableGet(_Symbol + IntegerToString(EA_MagicNumber) + "_SellCooldown");
 
   // Load active signals
   ArrayResize(activeSignals, 0);
   int signal_count = (int)GlobalVariableGet(_Symbol + IntegerToString(EA_MagicNumber) + "_SignalCount");
   for(int i = 0; i < signal_count; i++) // Load up to 50 signals
   {
      string prefix = _Symbol + IntegerToString(EA_MagicNumber) + "_Signal_" + IntegerToString(i) + "_";
      if(GlobalVariableCheck(prefix + "isBuy"))
      {
         int size = ArraySize(activeSignals);
         ArrayResize(activeSignals, size + 1);
         activeSignals[size].isBuy = GlobalVariableGet(prefix + "isBuy") == 1.0;
         activeSignals[size].entryLevel = GlobalVariableGet(prefix + "entryLevel");
         activeSignals[size].timeCreated = (datetime)GlobalVariableGet(prefix + "timeCreated");
         activeSignals[size].triggerShift = (int)GlobalVariableGet(prefix + "triggerShift");
         activeSignals[size].levelPrice = GlobalVariableGet(prefix + "levelPrice");
         activeSignals[size].isResistance = GlobalVariableGet(prefix + "isResistance") == 1.0;
         activeSignals[size].timeframe = (ENUM_TIMEFRAMES)GlobalVariableGet(prefix + "timeframe");
         activeSignals[size].pivotTime = (datetime)GlobalVariableGet(prefix + "pivotTime");
      }
   }
   // Load CRT levels
   ArrayResize(levels, 0);
   int level_count = (int)GlobalVariableGet(_Symbol + IntegerToString(EA_MagicNumber) + "_LevelCount");
   for(int i = 0; i < level_count; i++)
   {
      string prefix = _Symbol + IntegerToString(EA_MagicNumber) + "_Level_" + IntegerToString(i) + "_";
      if(GlobalVariableCheck(prefix + "price"))
      {
         int size = ArraySize(levels);
         ArrayResize(levels, size + 1);
         levels[size].price = GlobalVariableGet(prefix + "price");
         levels[size].tradesTaken = (int)GlobalVariableGet(prefix + "tradesTaken");
         levels[size].expired = GlobalVariableGet(prefix + "expired") == 1.0;
         levels[size].timeframe = (ENUM_TIMEFRAMES)GlobalVariableGet(prefix + "timeframe");
         levels[size].time = (datetime)GlobalVariableGet(prefix + "time");
         levels[size].isResistance = GlobalVariableGet(prefix + "isResistance") == 1.0;
         levels[size].permanentlyInvalidated = GlobalVariableGet(prefix + "permanentlyInvalidated") == 1.0;
         // Re-add to chart if not invalidated
         if(!levels[size].expired && !levels[size].permanentlyInvalidated) AddLevel(levels[size]);
      }
   }
}
