//+------------------------------------------------------------------+
//|                 Belema SFP EA (Enhanced) - v2.0                  |
//|         Swing Failure Pattern with Advanced Trade Management     |
//|      Built with features from Power Pivot EA v3.6 by Belema      |
//+------------------------------------------------------------------+
#property copyright "Belema"
#property link      "https://www.mql5.com"
#property version   "2.0"
#property description "Combines SFP logic with Dynamic SL, Partial Closing, and a News Filter."
#property description "This version integrates the best trade management features from the Power Pivot EA."

// --- Includes ---
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>
#include <Trade/DealInfo.mqh>

// This file is used by the Strategy Tester to simulate news events.
// The EA will create this file automatically when run on a live chart.
#property tester_file "SFP_NewsCache.csv"

// --- ENUMERATIONS ---
enum ENUM_ORDER_EXECUTION_TYPE
  {
   EXECUTION_TYPE_LIMIT,   // Place a Limit Order
   EXECUTION_TYPE_MARKET   // Place a Market Order
  };

// --- INPUT PARAMETERS ---

input group "Session Management"
input bool   TradeNewYork = true;    // Trade during New York session (12:00-21:00 GMT)
input bool   TradeLondon  = true;    // Trade during London session (07:00-12:00 GMT)
input bool   TradeTokyo   = false;   // Trade during Tokyo session (00:00-07:00 GMT)
input bool   TradeSydney  = false;   // Trade during Sydney session (22:00-00:00 GMT)

input group "Point of Interest (POI) Settings"
input bool   EnableM5_POI  = true;    // Detect Pivots on M5 timeframe
input bool   EnableM15_POI = true;    // Detect Pivots on M15 timeframe
input bool   EnableM30_POI = true;    // Detect Pivots on M30 timeframe
input bool   EnableH1_POI  = true;    // Detect Pivots on H1 timeframe
input bool   EnableH4_POI  = true;    // Detect Pivots on H4 timeframe
input bool   EnableD1_POI  = false;   // Detect Pivots on D1 timeframe
input int    MaxPOIPerTF   = 1;       // Maximum number of Support/Resistance levels per timeframe

input group "SFP Core Logic & Filters"
input ENUM_ORDER_EXECUTION_TYPE OrderExecutionType = EXECUTION_TYPE_LIMIT; // How to enter trades
input bool   UseHTFPowerCandleFilter = true; // Filter trades based on Higher Timeframe trend
input ENUM_TIMEFRAMES HTFPowerCandleTimeframe = PERIOD_H4; // Timeframe for the HTF trend filter
input int    LeftBars               = 15;   // Bars to the left for pivot detection
input int    RightBars              = 15;   // Bars to the right for pivot detection
input int    ReclaimLookbackCandles = 5;    // Max bars for reclaim after breakout
input int    ReclaimGraceCandles    = 3;    // Max bars for power candle after reclaim
input int    PendingOrderExpiryCandles = 10; // How many bars a pending order can exist before being deleted
input int    LevelExpiryCandles     = 50;   // How many bars price can close beyond a level before it expires
input bool   EnablePremiumDiscountFilter = true; // Only sell in premium, buy in discount
input int    RangeLookback          = 20;   // Lookback period for premium/discount range
input bool   UseFVGConfirmation     = true; // Require a Fair Value Gap for entry confirmation
input int    FindFVGLimit           = 10;   // How many bars to look for an FVG after the power candle

input group "Risk & Position Management"
input bool   EnableHedge            = true;    // Allow simultaneous Buy and Sell positions
input int    ATR_Period             = 14;      // Period for ATR calculation (on custom 35-min TF)
input double ATR_SL_Multiplier      = 2.0;     // Multiplier for ATR-based Stop Loss
input double RiskPercent            = 1.0;     // Percentage of account balance to risk per trade
input double RR_Ratio               = 2.0;     // Risk to Reward Ratio for Take Profit
input int    MaxTradesPerDay        = 2;       // Maximum trades allowed in a single day
input int    MaxTradesPerLevel      = 1;       // Maximum trades allowed at a single POI level
input int    EA_MagicNumber         = 54321;   // Unique identifier for trades managed by this EA
input double MinTradeDistanceAtrMultiplier = 0.5; // Minimum distance between trades (ATR multiple)

input group "Advanced Trade Management"
input bool   EnablePartialClose       = true;  // Enable partial closing of positions
input double PartialCloseAtrMultiplier= 1.0;  // ATR multiple profit target for partial close
input double PartialClosePercent      = 50.0;  // Percentage of position to close
input bool   EnableBreakeven          = true;  // Enable moving Stop Loss to breakeven
input double BreakevenTriggerReward   = 1.0;   // Reward/Risk ratio to trigger breakeven
input double BreakevenReward          = 0.1;   // Reward/Risk ratio for the new SL after breakeven
input bool   EnableDynamicSL          = true;  // Enable trigger-candle based exit for losing trades
input int    DynamicSLLookback        = 5;     // Lookback from the trigger candle for Dynamic SL
input bool   EnableReversalExit       = true;  // Exit trades based on market structure shift
input int    LookbackHighLow          = 5;     // Lookback for market structure shift
input bool   EnableLossReversalExit   = true;  // Enable reversal exit only when in loss
input int    LossLookbackHighLow      = 5;     // Lookback period for loss reversal exit

input group "Chart & Visuals"
input int    PowerCandlePeriods       = 14;    // Lookback period for calculating average candle body size
input double PowerCandleMultiplier    = 1.5;   // Multiplier to define a "Power Candle"
input color  BullPowerColor           = clrLimeGreen; // Color for bullish power candles
input color  BearPowerColor           = clrRed;       // Color for bearish power candles
input color  BullFvgColor             = clrDarkGreen; // Color for bullish FVG boxes
input color  BearFvgColor             = clrDarkRed;   // Color for bearish FVG boxes
input int    MaxFvgsToDisplay         = 5000;  // Max FVG objects on chart
input int    MaxPowerCandlesToDisplay = 1000;  // Max Power Candle arrows on chart

input group "News Management"
input bool   EnableNewsManagement   = true;    // Enable/Disable the news filter system
input int    NewsCheckIntervalSeconds = 3600; // How often to check for new news events (1 hour)
input int    MinsBefore             = 5;    // Do not trade X minutes before high-impact news
input int    MinsAfter              = 5;    // Do not trade X minutes after high-impact news
input bool   PartialCloseBeforeNews = false; // Partially close profitable trades before news

// --- GLOBAL STRUCTURES & VARIABLES ---

// Structure to hold cached news event data for the Strategy Tester
struct CachedNewsEvent
  {
   datetime time;
   string   country;
   int      importance;
  };
CachedNewsEvent g_cached_news[];
string g_news_cache_filename = "SFP_NewsCache.csv";

// Structure for SFP levels and state
struct LevelInfo
  {
   double          price;                     // Price of the level
   ENUM_TIMEFRAMES timeframe;                 // Timeframe of the level
   datetime        time;                      // Time of the pivot bar
   bool            isResistance;              // True if resistance, false if support
   bool            breakoutDetected;          // Price broke the level
   int             breakoutCandleShift;       // Shift of breakout candle
   bool            reclaimDetected;           // Price reclaimed the level
   int             reclaimCandleShift;        // Shift of reclaim candle
   bool            reclaimPowerCandleConfirmed; // Power candle confirmed reclaim
   int             reclaimPowerCandleShift;   // Shift of reclaim power candle
   datetime        reclaimPowerCandleTime;    // Time of reclaim power candle
   int             tradesTaken;               // Counter for trades taken at this level
   int             barsBeyondLevel;           // Number of consecutive bars beyond the level
   bool            expired;                   // True if level is expired
  };
LevelInfo levels[];

// Structure for tracking pending orders for expiration
struct PendingOrderInfo
  {
   ulong    ticket;    // Order ticket
   datetime setupTime; // Time order was placed
  };
PendingOrderInfo pendingOrders[];

// Structure for FVG chart objects
struct FVGObject
  {
   string   name;      // Object name
   double   high;      // High of FVG
   double   low;       // Low of FVG
   datetime startTime; // Start time of FVG
  };
FVGObject bullFvgs[];
FVGObject bearFvgs[];

// --- STRUCTS FOR DYNAMIC SL MANAGEMENT ---
// Holds info for an active position being managed by the Dynamic SL.
struct ManagedPositionInfo
  {
   ulong  position_ticket;
   double dynamicSL_level;
  };
ManagedPositionInfo managedPositions[];

// Temporarily holds info for a pending order that will be managed by Dynamic SL once filled.
struct PendingOrderSLInfo
  {
   ulong  order_ticket;
   double dynamicSL_level;
  };
PendingOrderSLInfo pendingSLs[];
// --- END OF DYNAMIC SL STRUCTS ---

// Arrays for managing chart objects and trade states
string powerCandleObjects[];
ulong  partialClosedTickets[];

// MQL5 Standard Library trading objects
CTrade        Trade;
CPositionInfo PositionInfo;
COrderInfo    OrderInfo;
CDealInfo     DealInfo;

// Global state variables
int      TradesToday   = 0;
int      LastTradeDay  = 0;
datetime LastBarTime   = 0;
int      htfTrend      = 0; // 1 for Bullish, -1 for Bearish, 0 for Neutral

// News and sleep mode variables
datetime nextNewsTime    = 0;
datetime lastNewsCheck   = 0;
datetime lastManagedNews = 0;
bool     inSleepMode     = false;
bool     pendingSleep    = false;
datetime sleepStart      = 0;
datetime sleepEndTime    = 0;
string   base_currency   = StringSubstr(_Symbol, 0, 3);
string   quote_currency  = StringSubstr(_Symbol, 3, 3);

//+------------------------------------------------------------------+
//| NEWS SYSTEM FUNCTIONS                                            |
//+------------------------------------------------------------------+

// Converts a currency code (e.g., "USD") to a country code (e.g., "US") for news filtering.
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

// Loads news events from the cache file for use in the Strategy Tester.
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

   // Skip the header row
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

// Downloads news from the server and saves it to a cache file. Only runs on a live chart.
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
   datetime to   = TimeCurrent() + (86400 * 90); // One year into the future

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

// Gets the time of the next high-impact news event for the current symbol.
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
      datetime to = now + 86400 * 7; // Check for news up to 7 days ahead
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
   levels[n].breakoutDetected = false;
   levels[n].reclaimDetected = false;
   levels[n].reclaimPowerCandleConfirmed = false;
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

// Checks if a new trade is too close to existing trades or pending orders.
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

   // Check open positions
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

   // Check pending orders
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

// Main function to validate and place a trade.
bool PlaceTrade(ENUM_ORDER_TYPE type, double entryPrice, double level, bool isResistance, ENUM_TIMEFRAMES tf, datetime pivotTime, int triggerCandleShift)
  {
   // --- TRADE GATEKEEPER ---
   if(TradesToday >= MaxTradesPerDay || !IsWithinSession()) return false;

   // --- CONCURRENT TRADE AND DISTANCE CHECKS ---
   bool isBuyOrder = (type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT);
   bool isSellOrder = (type == ORDER_TYPE_SELL || type == ORDER_TYPE_SELL_LIMIT);

   if(EnableHedge)
     {
      if(isBuyOrder && HasOpenBuyPositions())
        {
         Print("Trade Blocked (Hedging ON): A Buy position is already open.");
         return false;
        }
      if(isSellOrder && HasOpenSellPositions())
        {
         Print("Trade Blocked (Hedging ON): A Sell position is already open.");
         return false;
        }
     }
   else
     {
      if(PositionsTotal() > 0 && (HasOpenBuyPositions() || HasOpenSellPositions()))
        {
         Print("Trade Blocked (Hedging OFF): A position is already open.");
         return false;
        }
     }

   double potentialEntryPrice = (OrderExecutionType == EXECUTION_TYPE_LIMIT) ? entryPrice : SymbolInfoDouble(_Symbol, isBuyOrder ? SYMBOL_ASK : SYMBOL_BID);
   if(IsTradeTooClose(potentialEntryPrice))
     {
      return false;
     }
   Print("    - Trade Spacing Filter: PASSED. New trade is a safe distance from existing positions/orders.");

   // --- HTF TREND FILTER ---
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
      Print("    - HTF Trend Filter: PASSED. Trade direction aligns with HTF trend.");
     }

   // --- PREMIUM/DISCOUNT FILTER ---
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
      double current_price = iClose(_Symbol, _Period, 0); // Use current close for filter
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
      Print("    - Premium/Discount Filter: PASSED.");
     }

   // --- ATR AND LOT SIZE CALCULATION ---
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

   // --- DYNAMIC SL CALCULATION ---
   double dynamic_sl_level = 0;
   if(EnableDynamicSL)
     {
      if(isBuyOrder)
        {
         int low_idx = iLowest(_Symbol, _Period, MODE_LOW, DynamicSLLookback, triggerCandleShift);
         dynamic_sl_level = iLow(_Symbol, _Period, low_idx);
        }
      else // isSellOrder
        {
         int high_idx = iHighest(_Symbol, _Period, MODE_HIGH, DynamicSLLookback, triggerCandleShift);
         dynamic_sl_level = iHigh(_Symbol, _Period, high_idx);
        }
      Print("    - Dynamic SL Exit Level calculated at: ", DoubleToString(dynamic_sl_level, _Digits));
     }

   // --- ORDER PREPARATION ---
   Trade.SetExpertMagicNumber(EA_MagicNumber);

   string shortTradeType;
   if(type == ORDER_TYPE_BUY_LIMIT) shortTradeType = "BL";
   else if(type == ORDER_TYPE_SELL_LIMIT) shortTradeType = "SL";
   else if(type == ORDER_TYPE_BUY) shortTradeType = "BM";
   else if(type == ORDER_TYPE_SELL) shortTradeType = "SM";

   string shortTfStr = EnumToString(tf);
   StringReplace(shortTfStr, "PERIOD_", "");

   string comment = "SFP|" + shortTradeType + "|" + shortTfStr + "|POI:" + TimeToString(pivotTime, TIME_DATE | TIME_MINUTES) + "|@ " + DoubleToString(level, _Digits);

   // --- EXECUTION LOGIC ---
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
         return PlaceTrade(ORDER_TYPE_BUY, 0, level, isResistance, tf, pivotTime, triggerCandleShift);
        }
      if(type == ORDER_TYPE_SELL_LIMIT && normalized_entry <= tick.bid)
        {
         Print("Sell Limit price ", DoubleToString(normalized_entry, _Digits), " is invalid. Executing at Market.");
         return PlaceTrade(ORDER_TYPE_SELL, 0, level, isResistance, tf, pivotTime, triggerCandleShift);
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
            // Add to pending order tracker for expiration
            int size = ArraySize(pendingOrders);
            ArrayResize(pendingOrders, size + 1);
            pendingOrders[size].ticket = ticket;
            pendingOrders[size].setupTime = iTime(_Symbol, _Period, 0);
            
            // If Dynamic SL is enabled, add it to the pending management list
            if(EnableDynamicSL && dynamic_sl_level > 0)
            {
                int sl_size = ArraySize(pendingSLs);
                ArrayResize(pendingSLs, sl_size + 1);
                pendingSLs[sl_size].order_ticket = ticket;
                pendingSLs[sl_size].dynamicSL_level = dynamic_sl_level;
            }

            Print(">>> TRADE PLACED: ", tradeType, " at ", DoubleToString(normalized_entry, _Digits),
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
         ulong deal_ticket = Trade.ResultDeal();
         if(deal_ticket > 0)
           {
            long pos_ticket_long = HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
            if(pos_ticket_long > 0 && EnableDynamicSL && dynamic_sl_level > 0)
              {
               ulong position_ticket = (ulong)pos_ticket_long;
               int size = ArraySize(managedPositions);
               ArrayResize(managedPositions, size + 1);
               managedPositions[size].position_ticket = position_ticket;
               managedPositions[size].dynamicSL_level = dynamic_sl_level;
              }
           }
         Print(">>> TRADE EXECUTED: ", tradeType, " at ", DoubleToString(marketPrice, _Digits),
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

// Process resistance level with SFP logic
void ProcessResistanceLevel(int level_idx)
  {
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
         Print("Level Expired: Resistance at ", DoubleToString(levels[level_idx].price, _Digits), " expired after ", IntegerToString(LevelExpiryCandles), " bars beyond.");
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
         Print("    - CONFIRMATION: PASSED. Wick rejection was a power candle.");
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
            Print("    - CONFIRMATION: PASSED. Found Bearish Power Candle at bar shift ", check_shift);
            break;
           }
        }
     }

   if(levels[level_idx].reclaimPowerCandleConfirmed && levels[level_idx].tradesTaken < MaxTradesPerLevel && !IsOpenTradeFromLevel(level_price))
     {
      Print("--- Evaluating SELL Signal at ", DoubleToString(level_price, _Digits), " ---");
      double entry_price = 0;
      if(UseFVGConfirmation)
        {
         Print("    - FVG Filter: ENABLED. Searching for Bearish FVG...");
         int fvg_check_shift = levels[level_idx].reclaimPowerCandleShift;
         bool fvg_found = false;
         for(int i = 0; i < FindFVGLimit; i++)
           {
            int check_shift = fvg_check_shift - i;
            if(check_shift < 0) break;
            if(HasFVG(check_shift, false))
              {
               int middle_shift = check_shift + 1;
               if(middle_shift < iBars(_Symbol, _Period))
                 {
                  entry_price = (iHigh(_Symbol, _Period, middle_shift) + iLow(_Symbol, _Period, middle_shift)) / 2.0;
                  fvg_found = true;
                  Print("    - FVG Filter: PASSED. Found FVG, entry price set to ", DoubleToString(entry_price, _Digits));
                  break;
                 }
              }
           }
         if(!fvg_found)
           {
            Print("    - FVG Filter: FAILED. No Bearish FVG found. Signal ignored.");
            levels[level_idx].reclaimPowerCandleConfirmed = false;
            return;
           }
        }
      else
        {
         Print("    - FVG Filter: DISABLED. Using Power Candle for entry.");
         int power_shift = levels[level_idx].reclaimPowerCandleShift;
         entry_price = (iHigh(_Symbol, _Period, power_shift) + iLow(_Symbol, _Period, power_shift)) / 2.0;
        }

      if(entry_price > 0 || OrderExecutionType == EXECUTION_TYPE_MARKET)
        {
         ENUM_ORDER_TYPE order_type_to_place = (OrderExecutionType == EXECUTION_TYPE_MARKET) ? ORDER_TYPE_SELL : ORDER_TYPE_SELL_LIMIT;
         if(PlaceTrade(order_type_to_place, entry_price, level_price, levels[level_idx].isResistance, levels[level_idx].timeframe, levels[level_idx].time, levels[level_idx].reclaimPowerCandleShift))
           {
            levels[level_idx].tradesTaken++;
           }
         levels[level_idx].reclaimPowerCandleConfirmed = false;
         levels[level_idx].reclaimDetected = false;
         levels[level_idx].breakoutDetected = false;
        }
     }
  }

// Process support level with SFP logic
void ProcessSupportLevel(int level_idx)
  {
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
         Print("    - CONFIRMATION: PASSED. Wick rejection was a power candle.");
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
            Print("    - CONFIRMATION: PASSED. Found Bullish Power Candle at bar shift ", check_shift);
            break;
           }
        }
     }

   if(levels[level_idx].reclaimPowerCandleConfirmed && levels[level_idx].tradesTaken < MaxTradesPerLevel && !IsOpenTradeFromLevel(level_price))
     {
      Print("--- Evaluating BUY Signal at ", DoubleToString(level_price, _Digits), " ---");
      double entry_price = 0;

      if(UseFVGConfirmation)
        {
         Print("    - FVG Filter: ENABLED. Searching for Bullish FVG...");
         int fvg_check_shift = levels[level_idx].reclaimPowerCandleShift;
         bool fvg_found = false;
         for(int i = 0; i < FindFVGLimit; i++)
           {
            int check_shift = fvg_check_shift - i;
            if(check_shift < 0) break;
            if(HasFVG(check_shift, true))
              {
               int middle_shift = check_shift + 1;
               if(middle_shift < iBars(_Symbol, _Period))
                 {
                  entry_price = (iHigh(_Symbol, _Period, middle_shift) + iLow(_Symbol, _Period, middle_shift)) / 2.0;
                  fvg_found = true;
                  Print("    - FVG Filter: PASSED. Found FVG, entry price set to ", DoubleToString(entry_price, _Digits));
                  break;
                 }
              }
           }
         if(!fvg_found)
           {
            Print("    - FVG Filter: FAILED. No Bullish FVG found. Signal ignored.");
            levels[level_idx].reclaimPowerCandleConfirmed = false;
            return;
           }
        }
      else
        {
         Print("    - FVG Filter: DISABLED. Using Power Candle for entry.");
         int power_shift = levels[level_idx].reclaimPowerCandleShift;
         entry_price = (iHigh(_Symbol, _Period, power_shift) + iLow(_Symbol, _Period, power_shift)) / 2.0;
        }

      if(entry_price > 0 || OrderExecutionType == EXECUTION_TYPE_MARKET)
        {
         ENUM_ORDER_TYPE order_type_to_place = (OrderExecutionType == EXECUTION_TYPE_MARKET) ? ORDER_TYPE_BUY : ORDER_TYPE_BUY_LIMIT;
         if(PlaceTrade(order_type_to_place, entry_price, level_price, levels[level_idx].isResistance, levels[level_idx].timeframe, levels[level_idx].time, levels[level_idx].reclaimPowerCandleShift))
           {
            levels[level_idx].tradesTaken++;
           }
         levels[level_idx].reclaimPowerCandleConfirmed = false;
         levels[level_idx].reclaimDetected = false;
         levels[level_idx].breakoutDetected = false;
        }
     }
  }

//+------------------------------------------------------------------+
//| TRADE MANAGEMENT FUNCTIONS                                       |
//+------------------------------------------------------------------+

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

// Closes a percentage of the position when a certain profit target is reached.
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
                  Print("Failed to take partial profit for position #", ticket, ": ", GetLastError());
              }
           }
        }
     }
  }

// Exits a losing trade if price closes beyond the high/low of the trigger candle's lookback range.
void CheckDynamicSL()
  {
   if(!EnableDynamicSL) return;

   // This check runs once per bar, using the confirmed close of the previous bar.
   double close1 = iClose(_Symbol, _Period, 1);

   // Iterate through our internally managed list of positions.
   for(int i = ArraySize(managedPositions) - 1; i >= 0; i--)
     {
      if(PositionSelectByTicket(managedPositions[i].position_ticket))
        {
         // This logic only applies to trades that are currently in a loss.
         if(PositionGetDouble(POSITION_PROFIT) < 0)
           {
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double sl_level = managedPositions[i].dynamicSL_level;

            if(sl_level == 0) continue; // Safeguard

            // For a BUY trade, close if price closes below the trigger candle's low.
            if(posType == POSITION_TYPE_BUY && close1 < sl_level)
              {
               Print("Dynamic SL Exit: Closing losing BUY position #", managedPositions[i].position_ticket, " because price closed at ",
                     DoubleToString(close1, _Digits), " below trigger level of ", DoubleToString(sl_level, _Digits));
               Trade.PositionClose(managedPositions[i].position_ticket);
              }

            // For a SELL trade, close if price closes above the trigger candle's high.
            if(posType == POSITION_TYPE_SELL && close1 > sl_level)
              {
               Print("Dynamic SL Exit: Closing losing SELL position #", managedPositions[i].position_ticket, " because price closed at ",
                     DoubleToString(close1, _Digits), " above trigger level of ", DoubleToString(sl_level, _Digits));
               Trade.PositionClose(managedPositions[i].position_ticket);
              }
           }
        }
     }
  }

// Manages the internal lists for the Dynamic SL feature.
void UpdateManagedTrades()
  {
   // 1. Check pending orders that might have been filled and move them to the active list.
   for(int i = ArraySize(pendingSLs) - 1; i >= 0; i--)
     {
      // If the order no longer exists in the terminal's list of open orders...
      if(!OrderSelect(pendingSLs[i].order_ticket))
        {
         // It was likely filled or canceled. Find the deal associated with it.
         if(HistorySelect(0, TimeCurrent()))
           {
            int deals_total = HistoryDealsTotal();
            for(int j = deals_total - 1; j >= 0; j--)
              {
               ulong deal_ticket = HistoryDealGetTicket(j);
               if(deal_ticket == 0) continue;

               // Check if this deal resulted from our pending order.
               if((ulong)HistoryDealGetInteger(deal_ticket, DEAL_ORDER) == pendingSLs[i].order_ticket)
                 {
                  // Was this an "entry" deal that created a position?
                  if(HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
                    {
                     long pos_ticket_long = HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
                     if(pos_ticket_long > 0)
                       {
                        ulong position_ticket = (ulong)pos_ticket_long;
                        // Add it to our active management list.
                        int size = ArraySize(managedPositions);
                        ArrayResize(managedPositions, size + 1);
                        managedPositions[size].position_ticket = position_ticket;
                        managedPositions[size].dynamicSL_level = pendingSLs[i].dynamicSL_level;
                        Print("Dynamic SL: Pending order ", pendingSLs[i].order_ticket, " filled. Now managing position #", position_ticket);
                        break; // Found the deal, no need to look further.
                       }
                    }
                 }
              }
           }
         // The pending order is gone, so remove it from the pending list.
         ArrayRemove(pendingSLs, i, 1);
        }
     }

   // 2. Clean up closed positions from our managed list.
   for(int i = ArraySize(managedPositions) - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(managedPositions[i].position_ticket))
        {
         ArrayRemove(managedPositions, i, 1);
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

// Closes losing positions and secures profitable ones before high-impact news.
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
            double new_sl = (PositionInfo.PositionType() == POSITION_TYPE_BUY) ? entry + be_offset : entry - be_offset;
            new_sl = NormalizeDouble(new_sl, _Digits);
            MqlTick tick;
            SymbolInfoTick(_Symbol, tick);
            long stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
            bool valid = (PositionInfo.PositionType() == POSITION_TYPE_BUY && new_sl <= tick.bid - stops_level * _Point) ||
                         (PositionInfo.PositionType() == POSITION_TYPE_SELL && new_sl >= tick.ask + stops_level * _Point);
            if(!valid)
              {
               new_sl = entry;
               new_sl = NormalizeDouble(new_sl, _Digits);
              }
            if(Trade.PositionModify(ticket, new_sl, PositionInfo.TakeProfit()))
              {
               Print("--- NEWS: Modified SL for #", ticket, " to ", DoubleToString(new_sl, _Digits), ". ---");
               modified++;
              }
            else
               Print("--- NEWS: Failed to modify SL for #", ticket, ": ", GetLastError(), " ---");
            if(PartialCloseBeforeNews)
              {
               double volume = PositionInfo.Volume();
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

   return INIT_SUCCEEDED;
  }

void OnTick()
  {
   // Expiration date: July 17th, 2025 23:59:59 GMT
   datetime ExpirationDate = StringToTime("2025.11.17 23:59:59");
   if(TimeCurrent() > ExpirationDate)
     {
      Print("EA expired. Trading disabled, please send an email to @ighodaloxauusd@gmail.com or contact @__ighodalo on X(twitter");
      return;
     }

   // --- NEWS MANAGEMENT & SLEEP MODE ---
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

   // --- NEW BAR LOGIC ---
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
        }

      // Bar-based management
      ManagePendingOrders();
      CheckDynamicSL();
      CheckReversalExit();
      CheckLossReversalExit();

      LastBarTime = currentBarTime;
     }

   // --- TICK-BASED LOGIC ---
   if(EnableDynamicSL)
     {
      UpdateManagedTrades(); // Check for filled limit orders
     }
   CheckBreakeven();
   CheckPartialClose();
   EnforceHedgeRule();
   
   // Clean up the partial closed tickets array
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
   Print("Belema SFP EA Deinitialized. All chart objects removed.");
  }
