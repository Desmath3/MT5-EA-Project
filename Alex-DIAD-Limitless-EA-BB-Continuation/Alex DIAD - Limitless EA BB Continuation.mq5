//+------------------------------------------------------------------+
//|           Belema BB Continuation Scalper v1.0 (Hybrid)           |
//|------------------------------------------------------------------|
//| Description: This EA combines Bollinger Band continuation entries|
//|              (breakout and pullback to the middle band) with the |
//|              advanced scaling and trade management engine from   |
//|              the Belema SFP series.                              |
//|                                                                  |
//|              - Entry Logic: Bollinger Bands Continuation         |
//|              - Trade Management: SFP Scaling Engine v2.7         |
//+------------------------------------------------------------------+
#property copyright "Belema & Ighodalo"
#property link      "https://www.mql5.com"
#property version   "1.0"
#property description "Hybrid EA: BB continuation entries with SFP scaling & management."

// --- Includes ---
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>
#include <Trade/DealInfo.mqh>

#property tester_file "Hybrid_BB_Continuation_NewsCache.csv"

// --- ENUMERATIONS ---
enum ENUM_ENTRY_STRATEGY
  {
   PULLBACK_TO_MIDDLE, // Entry on a pullback to the middle BB
   WICK_REJECTION_AT_MIDDLE    // Entry on a wick rejection at the middle BB
  };

// --- INPUT PARAMETERS ---
input group "Session Management"
input bool   TradeNewYork = true; // Trade during New York session (12:00-21:00 GMT)
input bool   TradeLondon = true;  // Trade during London session (7:00-12:00 GMT)
input bool   TradeTokyo = true;   // Trade during Tokyo session (0:00-7:00 GMT)
input bool   TradeSydney = true;  // Trade during Sydney session (22:00-0:00 GMT)

input group "Bollinger Bands & Entry Logic"
input int    BollingerPeriod = 50;     // Bollinger Bands period
input double BollingerDeviation = 1.4; // Bollinger Bands deviation
input ENUM_ENTRY_STRATEGY EntryStrategy = PULLBACK_TO_MIDDLE; // Entry Strategy

input group "Entry Filters"
input bool   UseHTFPowerCandleFilter = true; // Filter trades based on Higher Timeframe trend
input ENUM_TIMEFRAMES HTFPowerCandleTimeframe = PERIOD_H4; // Timeframe for the HTF trend filter
input int    PowerCandlePeriods = 20; // Lookback period for calculating average candle body size
input double PowerCandleMultiplier = 1.7; // Multiplier to define a "Power Candle"

input group "Risk & Position Management"
input int    ATR_Period = 14;          // Period for ATR calculation
input int    MaxTradesPerDay = 50;     // Maximum trades allowed in a single day
input int    EA_MagicNumber = 174357;  // Unique identifier for trades managed by this EA
input bool   EnableHedge = false;      // Allow simultaneous Buy and Sell trades

input group "Strategy Settings"
input double InitialRiskPercent = 5.0;
input double InitialRiskDollar = 0;
input double ProfitTargetPercent = 100.0;
input double ProfitTargetDollar = 0;
input double SL_Multiplier = 1.5;
input double Add_Multiplier = 1.0;
input double Add_Lot_Multiplier = 1.0; // Lot size multiplier for LINEAR scaling
input int    MaxPositions = 5;
input int    BreakevenOffsetPips = 0; // Pips to add to BE price to cover costs
input int    Slippage = 3;

input group "Scaling Strategy"
input bool   EnableExponentialScaling = false; // Enable exponential lot sizing from 3rd position
input double AggressionFactor = 1.5;         // Multiplier for exponential scaling (>1.0)

input group "Trailing Stop"
input bool   EnableTrailingStop = true;   // Enable/Disable Trailing Stop
input double TrailingStartATR = 2.0;    // ATR multiple to start trailing
input double TrailingStopATR = 1.5;     // ATR multiple for trailing distance

input group "Profit Keeper: SL Management"
input bool   EnableProgressiveBE = true; // True: Progressive Reward Lock | False: Basket Breakeven

input group "Profit Keeper: Peak Drawdown"
input bool   EnablePeakDrawdownExit = true;    // Enable Peak Profit Drawdown Exit
input double PeakDrawdownStartRR = 2.0;      // RR multiple to start monitoring for drawdown
input double PeakProfitDrawdownPercent = 30.0; // Exit if profit retraces by X% from its peak

input group "Profit Keeper: Stale Trade"
input bool   EnableStaleTradeExit = true;  // Enable Stale Trade Exit
input int    StaleTradeBars = 24;          // Bars before a trade is considered stale (e.g., 24 H1 bars = 1 day)

input group "Chart & Visuals"
input color  BullPowerColor = clrLimeGreen; // Color for bullish power candles
input color  BearPowerColor = clrRed;     // Color for bearish power candles
input int    MaxPowerCandlesToDisplay = 1000; // Max Power Candle arrows on chart

input group "News Management"
input bool   EnableNewsManagement = true;     // Enable/Disable the news filter system
input int    NewsCheckIntervalSeconds = 3600; // How often to check for new news events (1 hour)
input int    MinsBefore = 10;                 // Do not trade X minutes before high-impact news
input int    MinsAfter = 10;                  // Do not trade X minutes after high-impact news

// --- GLOBAL STRUCTURES & VARIABLES ---
struct CachedNewsEvent
  {
   datetime time;
   string   country;
   int      importance;
  };
CachedNewsEvent g_cached_news[];
string g_news_cache_filename = "Hybrid_BB_Continuation_NewsCache.csv";

string powerCandleObjects[];

CTrade        Trade;
CPositionInfo PositionInfo;
COrderInfo    OrderInfo;
CDealInfo     DealInfo;

int      TradesToday = 0;
int      LastTradeDay = 0;
datetime LastBarTime = 0;
int      htfTrend = 0; // 1 for Bull, -1 for Bear, 0 for None

datetime nextNewsTime = 0;
datetime lastNewsCheck = 0;
datetime lastManagedNews = 0;
bool     inSleepMode = false;
bool     pendingSleep = false;
datetime sleepStart = 0;
datetime sleepEndTime = 0;
string   base_currency;
string   quote_currency;

// --- Bollinger Bands State ---
enum BBState { BB_NONE, BB_BULLISH, BB_BEARISH };
BBState  g_bbState = BB_NONE;
int      g_bandHandle = INVALID_HANDLE;

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

// --- New Exponential Scaling Variables ---
double   currentMultiplier_buy = 0;
double   currentMultiplier_sell = 0;

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
   FileReadString(file_handle); // Skip header
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
   FileWrite(file_handle, "time_as_string,country,importance");
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
bool IsPowerCandleTF(int shift, bool isBullish, ENUM_TIMEFRAMES timeframe)
  {
   if(shift + PowerCandlePeriods >= iBars(_Symbol, timeframe)) return false;
   double sum_range = 0;
   for(int i = 1; i <= PowerCandlePeriods; i++) // Lookback from the bar before the shift
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
   double price = isBullish ? iLow(_Symbol, _Period, shift) - GetATR()*0.1 : iHigh(_Symbol, _Period, shift) + GetATR()*0.1;
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
           Print("HTF Trend Update: Last power candle on ", EnumToString(HTFPowerCandleTimeframe), " was BULLISH. Only BUY trades will be considered.");
         htfTrend = 1;
         return;
        }
      if(IsPowerCandleTF(i, false, HTFPowerCandleTimeframe))
        {
         if(htfTrend != -1)
           Print("HTF Trend Update: Last power candle on ", EnumToString(HTFPowerCandleTimeframe), " was BEARISH. Only SELL trades will be considered.");
         htfTrend = -1;
         return;
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

//+------------------------------------------------------------------+
//| CORE ENTRY LOGIC (from BB Continuation EA)                       |
//+------------------------------------------------------------------+
void UpdateBBState()
  {
   double lastClose = iClose(_Symbol, _Period, 1);
   double upperBand[1], lowerBand[1];

   if(CopyBuffer(g_bandHandle, 1, 1, 1, upperBand) <= 0)
     {
      Print("Error copying upper band data: ", GetLastError());
      return;
     }
   if(CopyBuffer(g_bandHandle, 2, 1, 1, lowerBand) <= 0)
     {
      Print("Error copying lower band data: ", GetLastError());
      return;
     }

   if(lastClose > upperBand[0])
     {
      g_bbState = BB_BULLISH;
     }
   else if(lastClose < lowerBand[0])
     {
      g_bbState = BB_BEARISH;
     }
   // Note: State persists until an opposite break occurs.
  }

bool GetTradeSignal(bool &isBuy)
  {
   double high1 = iHigh(_Symbol, _Period, 1);
   double low1 = iLow(_Symbol, _Period, 1);
   double close1 = iClose(_Symbol, _Period, 1);
   double mainBand[1];

   if(CopyBuffer(g_bandHandle, 0, 1, 1, mainBand) <= 0) return false;

   if(EntryStrategy == WICK_REJECTION_AT_MIDDLE)
     {
      if(g_bbState == BB_BULLISH && low1 < mainBand[0] && close1 > mainBand[0])
        {
         Print("Signal Trigger: BB Wick Rejection BUY at Middle.");
         isBuy = true;
         return true;
        }
      else if(g_bbState == BB_BEARISH && high1 > mainBand[0] && close1 < mainBand[0])
        {
         Print("Signal Trigger: BB Wick Rejection SELL at Middle.");
         isBuy = false;
         return true;
        }
     }
   else // PULLBACK_TO_MIDDLE
     {
      if(g_bbState == BB_BULLISH && close1 <= mainBand[0] && iClose(_Symbol, _Period, 2) > mainBand[0])
        {
         Print("Signal Trigger: BB Pullback BUY to Middle Band.");
         isBuy = true;
         return true;
        }
      else if(g_bbState == BB_BEARISH && close1 >= mainBand[0] && iClose(_Symbol, _Period, 2) < mainBand[0])
        {
         Print("Signal Trigger: BB Pullback SELL to Middle Band.");
         isBuy = false;
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| TRADE EXECUTION                                                  |
//+------------------------------------------------------------------+
bool PlaceInitialTrade(bool isBuy)
  {
   if(TradesToday >= MaxTradesPerDay || !IsWithinSession()) return false;
   if((isBuy && HasOpenBuyPositions()) || (!isBuy && HasOpenSellPositions())) return false;
   if(!EnableHedge && ((isBuy && HasOpenSellPositions()) || (!isBuy && HasOpenBuyPositions()))) return false;

   // --- Run Filters ---
   if(UseHTFPowerCandleFilter && ((isBuy && htfTrend == -1) || (!isBuy && htfTrend == 1)))
     {
      Print("Trade Blocked: Signal opposes HTF Power Candle trend.");
      return false;
     }
   Print("HTF Trend Filter: PASSED");
   // --- End Filters ---

   double marketPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double atr = GetATR();
   if(atr <= 0)
     {
      Print("Failed to get ATR. Cannot place trade.");
      return false;
     }
   double slDistance = atr * SL_Multiplier;
   double min_stop_distance = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(slDistance < min_stop_distance) slDistance = min_stop_distance;

   double lotSize = CalculateLotSize(slDistance);
   if(lotSize <= 0)
     {
      Print("Calculated lot size is zero or negative.");
      return false;
     }

   Trade.SetExpertMagicNumber(EA_MagicNumber);
   string comment = "BB_Cont|" + (isBuy ? "BUY" : "SELL") + "|Initial";
   double sl = isBuy ? marketPrice - slDistance : marketPrice + slDistance;

   MqlTick tick;
   SymbolInfoTick(_Symbol, tick);
   double stops_level = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   bool sl_valid = isBuy ? (tick.bid - sl >= stops_level) : (sl - tick.ask >= stops_level);

   if(!sl_valid)
     {
      Print((isBuy ? "BUY" : "SELL"), " SL is too close to the current price. Trade aborted.");
      return false;
     }

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
      Print(">>> INITIAL TRADE EXECUTED: ", isBuy ? "Buy Market" : "Sell Market", " at ", DoubleToString(marketPrice, _Digits),
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
   if(slDistance <= 0 || tickValue <= 0 || tickSize <= 0) return 0.0;
   double riskAmount = InitialRiskDollar > 0 ? InitialRiskDollar : accountBalance * (InitialRiskPercent / 100.0);
   double slPoints = slDistance / tickSize;
   double lotSize = riskAmount / (slPoints * tickValue);

   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lotSize = lotStep > 0 ? MathFloor(lotSize / lotStep) * lotStep : lotSize;

   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   return NormalizeDouble(lotSize, 2);
  }

//+------------------------------------------------------------------+
//| TRADE MANAGEMENT FUNCTIONS (from SFP EA)                         |
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
   if(TradeSydney && (minutes >= 22 * 60)) ok = true;
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
            if(PositionInfo.PositionType() == POSITION_TYPE_BUY)
              {
               if(new_sl > currentSL && (tick.bid - new_sl) > stops_level)
                 {
                  if(Trade.PositionModify(ticket, new_sl, PositionInfo.TakeProfit()))
                    {
                     Print("--- NEWS: Modified SL for #", ticket, " to ", DoubleToString(new_sl, _Digits), ". ---");
                     modified++;
                    }
                  else
                    Print("--- NEWS: Failed to modify SL for #", ticket, ": ", GetLastError(), " ---");
                 }
              }
            else if(PositionInfo.PositionType() == POSITION_TYPE_SELL)
              {
               if((new_sl < currentSL || currentSL == 0) && (new_sl - tick.ask) > stops_level)
                 {
                  if(Trade.PositionModify(ticket, new_sl, PositionInfo.TakeProfit()))
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
   currentMultiplier_buy = 0;
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
   currentMultiplier_sell = 0;
  }
void AddBuyPosition()
  {
   double current_sl = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i) && PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber && PositionInfo.PositionType() == POSITION_TYPE_BUY)
        {
         current_sl = PositionInfo.StopLoss();
         break;
        }
     }
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
   if((tick.ask - current_sl) < (currentATR * 0.1))
     {
      Print("AddBuyPosition skipped: Current SL is too close. Price-SL distance ", DoubleToString(tick.ask - current_sl, _Digits), " is less than 0.1 ATR (", DoubleToString(currentATR * 0.1, _Digits), ").");
      return;
     }

   double newLot = 0;
   if(EnableExponentialScaling)
     {
      double local_aggression_factor = AggressionFactor;
      if(local_aggression_factor <= 1.0) local_aggression_factor = 1.01;

      if(positionsCount_buy == 1)
        {
         newLot = initialLot_buy * Add_Lot_Multiplier;
         currentMultiplier_buy = local_aggression_factor;
        }
      else
        {
         newLot = initialLot_buy * currentMultiplier_buy;
         double dampingFactor = 1.0 / MathSqrt(local_aggression_factor);
         currentMultiplier_buy *= dampingFactor;
        }
     }
   else
     {
      newLot = initialLot_buy * Add_Lot_Multiplier;
     }

   newLot = NormalizeDouble(newLot, 2);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(newLot < minLot) newLot = minLot;
   if(newLot > maxLot) newLot = maxLot;
   string comment = "Add Buy " + IntegerToString(positionsCount_buy + 1);

   if(Trade.Buy(newLot, _Symbol, 0, current_sl, 0, comment))
     {
      lastEntry_buy = Trade.ResultPrice();
      positionsCount_buy++;
     }
  }
void AddSellPosition()
  {
   double current_sl = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i) && PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber && PositionInfo.PositionType() == POSITION_TYPE_SELL)
        {
         current_sl = PositionInfo.StopLoss();
         break;
        }
     }
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
   if((current_sl - tick.bid) < (currentATR * 0.1))
     {
      Print("AddSellPosition skipped: Current SL is too close. SL-Price distance ", DoubleToString(current_sl - tick.bid, _Digits), " is less than 0.1 ATR (", DoubleToString(currentATR * 0.1, _Digits), ").");
      return;
     }

   double newLot = 0;
   if(EnableExponentialScaling)
     {
      double local_aggression_factor = AggressionFactor;
      if(local_aggression_factor <= 1.0) local_aggression_factor = 1.01;

      if(positionsCount_sell == 1)
        {
         newLot = initialLot_sell * Add_Lot_Multiplier;
         currentMultiplier_sell = local_aggression_factor;
        }
      else
        {
         newLot = initialLot_sell * currentMultiplier_sell;
         double dampingFactor = 1.0 / MathSqrt(local_aggression_factor);
         currentMultiplier_sell *= dampingFactor;
        }
     }
   else
     {
      newLot = initialLot_sell * Add_Lot_Multiplier;
     }

   newLot = NormalizeDouble(newLot, 2);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(newLot < minLot) newLot = minLot;
   if(newLot > maxLot) newLot = maxLot;
   string comment = "Add Sell " + IntegerToString(positionsCount_sell + 1);

   if(Trade.Sell(newLot, _Symbol, 0, current_sl, 0, comment))
     {
      lastEntry_sell = Trade.ResultPrice();
      positionsCount_sell++;
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
      bool isSkipped = false;
      for(int i = 0; i < ArraySize(skippedBuyLevels); i++)
        {
         if(MathAbs(currentPrice - skippedBuyLevels[i]) < (addThreshold * 0.1))
           {
            isSkipped = true;
            break;
           }
        }
      if(!isSkipped)
        {
         AddBuyPosition();
        }
      else
        {
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
      bool isSkipped = false;
      for(int i = 0; i < ArraySize(skippedSellLevels); i++)
        {
         if(MathAbs(currentPrice - skippedSellLevels[i]) < (addThreshold * 0.1))
           {
            isSkipped = true;
            break;
           }
        }
      if(!isSkipped)
        {
         AddSellPosition();
        }
      else
        {
         Print("Scale-in for SELL at ", DoubleToString(currentPrice, _Digits), " skipped as it's a previously closed stale level.");
         lastEntry_sell = currentPrice;
        }
     }
  }
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
void ManageBasketStopLoss(bool isBuy)
  {
   int posCount = isBuy ? CountBuyPositions() : CountSellPositions();
   if(posCount < 2) return;

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
   if(EnableProgressiveBE)
     {
      double initialRisk = isBuy ? initialRiskAmount_buy : initialRiskAmount_sell;
      if(initialRisk <= 0) return;
      double profitToLock = (posCount - 1) * initialRisk;
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickValue <= 0) return;
      double profitInPoints = (profitToLock / totalLot) / tickValue * _Point;
      newSL = isBuy ? bePrice + profitInPoints : bePrice - profitInPoints;
     }
   else
     {
      double offset = BreakevenOffsetPips * _Point;
      newSL = isBuy ? bePrice + offset : bePrice - offset;
     }
   newSL = NormalizeDouble(newSL, _Digits);

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
   if(initialRisk <= 0) return;

   if(currentProfit >= initialRisk * PeakDrawdownStartRR)
     {
      if(currentProfit > peakProfit)
        {
         peakProfit = currentProfit;
         if(isBuy) peakProfit_buy = peakProfit;
         else peakProfit_sell = peakProfit;
        }
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
   if(!EnableStaleTradeExit) return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i) && PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber)
        {
         datetime openTime = PositionInfo.Time();
         int barsOpen = iBarShift(_Symbol, _Period, openTime);

         if(barsOpen > StaleTradeBars)
           {
            double entryPrice = PositionInfo.PriceOpen();
            ulong ticket = PositionInfo.Ticket();

            if(PositionInfo.PositionType() == POSITION_TYPE_BUY)
              {
               if(tick.bid <= entryPrice)
                 {
                  if(CountBuyPositions() <= 1)
                    {
                     Print("STALE TRADE EXIT: Initial/last BUY trade #", ticket, " retraced to entry after ", barsOpen, " bars. Closing basket.");
                     CloseBuyPositions();
                    }
                  else
                    {
                     Print("STALE TRADE EXIT: Scaled-in BUY trade #", ticket, " retraced to entry after ", barsOpen, " bars. Closing only this position and skipping level ", DoubleToString(entryPrice, _Digits), ".");
                     int size = ArraySize(skippedBuyLevels);
                     ArrayResize(skippedBuyLevels, size + 1);
                     skippedBuyLevels[size] = entryPrice;
                     Trade.PositionClose(ticket);
                    }
                  break;
                 }
              }
            else if(PositionInfo.PositionType() == POSITION_TYPE_SELL)
              {
               if(tick.ask >= entryPrice)
                 {
                  if(CountSellPositions() <= 1)
                    {
                     Print("STALE TRADE EXIT: Initial/last SELL trade #", ticket, " retraced to entry after ", barsOpen, " bars. Closing basket.");
                     CloseSellPositions();
                    }
                  else
                    {
                     Print("STALE TRADE EXIT: Scaled-in SELL trade #", ticket, " retraced to entry after ", barsOpen, " bars. Closing only this position and skipping level ", DoubleToString(entryPrice, _Digits), ".");
                     int size = ArraySize(skippedSellLevels);
                     ArrayResize(skippedSellLevels, size + 1);
                     skippedSellLevels[size] = entryPrice;
                     Trade.PositionClose(ticket);
                    }
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
   
   base_currency = StringSubstr(_Symbol, 0, 3);
   quote_currency = StringSubstr(_Symbol, 3, 3);

   g_bandHandle = iBands(_Symbol, _Period, BollingerPeriod, 0, BollingerDeviation, PRICE_CLOSE);
   if(g_bandHandle == INVALID_HANDLE)
     {
      Print("Failed to initialize Bollinger Bands indicator. EA will not work.");
      return(INIT_FAILED);
     }
   
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
   datetime ExpirationDate = StringToTime("2025.12.31 23:59:59");
   if(TimeCurrent() > ExpirationDate)
     {
      Print("EA expired. Please contact developer.");
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
         UpdateIndicatorPlots();
         UpdateBBState();
         
         // --- NEW ENTRY LOGIC ---
         if(!HasOpenBuyPositions() && !HasOpenSellPositions())
           {
            bool is_buy = false;
            if(GetTradeSignal(is_buy))
              {
               PlaceInitialTrade(is_buy);
              }
           }
        }
      LastBarTime = currentBarTime;
     }

   // --- MANAGE ALL OPEN POSITION LOGIC ---
   if(PositionsTotal() > 0)
     {
      if(!HasOpenBuyPositions()) ResetBuyVars();
      if(!HasOpenSellPositions()) ResetSellVars();
      CheckVirtualStops();
      CheckIndividualStaleTrades();
      ManageBuyScaling();
      ManageSellScaling();
      if(HasOpenBuyPositions())
        {
         ManageTrailingStop(true);
         ManagePeakProfitDrawdown(true);
         ManageBasketStopLoss(true);
        }
      if(HasOpenSellPositions())
        {
         ManageTrailingStop(false);
         ManagePeakProfitDrawdown(false);
         ManageBasketStopLoss(false);
        }
     }
   else
     {
      ResetBuyVars();
      ResetSellVars();
     }
  }

void OnDeinit(const int reason)
  {
   for(int i = ArraySize(powerCandleObjects) - 1; i >= 0; i--)
     {
      ObjectDelete(0, powerCandleObjects[i]);
     }
   ArrayFree(powerCandleObjects);
   
   if(g_bandHandle != INVALID_HANDLE)
      IndicatorRelease(g_bandHandle);
  }
