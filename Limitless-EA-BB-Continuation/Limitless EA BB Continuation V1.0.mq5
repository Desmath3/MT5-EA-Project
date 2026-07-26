//+------------------------------------------------------------------+
//|                    Limitless EA BB Continuation V1.0.mq5        |
//|                                  Copyright 2025, Ighodalo        |
//|                                        @--ighodalo on X         |
//+------------------------------------------------------------------+

#property copyright "Ighodalo"
#property link      "https://www.mql5.com"
#property version   "1.00" // BB Continuation EA: Break extreme BB for trend state, enter on retrace to middle BB.

#property description "Trades Bollinger Bands continuations with pullback to middle band entry and multi-timeframe filters."
#property description "News system uses a file cache with corrected data types for reliable backtesting."
#property description "ATR calculation now uses a synthetic 35-minute timeframe based on M5 data."
#property description "Exit logic now includes Dynamic SL, ATR-based partials, opposite BB partials/exits, and market structure shift exits."

// --- Crucial for enabling news filter in Strategy Tester ---
#property tester_file "Limitless_News_Cache.csv"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\HistoryOrderInfo.mqh>
#include <Trade\DealInfo.mqh>
#include <Trade\OrderInfo.mqh>

// --- ENUMERATIONS ---
enum ENUM_EXECUTION_MODE
  {
   AGGRESSIVE,
   CONSERVATIVE,
   SEMI_AGGRESSIVE
  };

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
// --- General Settings ---
input group "General Settings"
input ulong MagicNumber = 123456;      // Unique identifier for EA's orders
input int Slippage = 3;                // Slippage in points

// --- Session Management ---
input group "Session Management"
input bool TradeNewYork = true;        // Trade during New York session (12:00-21:00 GMT)
input bool TradeLondon = true;         // Trade during London session (07:00-16:00 GMT)
input bool TradeTokyo = true;          // Trade during Tokyo session (00:00-09:00 GMT)
input bool TradeSydney = true;         // Trade during Sydney session (21:00-06:00 GMT)
input bool UseManualTimeFilter = true; // Enable Manual Trading Times (Broker Time)
input string StartTradingTime = "08:00"; // Start Trading Time (HH:MM)
input string StopTradingTime = "22:00"; // Stop Trading Time (HH:MM)
input bool EnableNoTradeTime = false; // Enable No-Trade Window
input string NoTradeStart = "12:00";   // No-Trade Start Time (HH:MM)
input string NoTradeEnd = "14:00";     // No-Trade End Time (HH:MM)

// --- Bollinger Bands & Entry Logic ---
input group "Bollinger Bands & Entry Logic"
input int BollingerPeriod = 50;        // Bollinger Bands period
input double BollingerDeviation = 1.4; // Bollinger Bands deviation
input bool TradeWickRejections = true; // TRADE YOUR STRATEGY: false=Pullback to Middle, true=Wick Rejection at Middle
input bool CheckATRDistance = true;    // Check if entry is too far from BB Middle
input double MaxATRDistanceMultiplier = 1.4; // Max distance from Middle BB = ATR * Multiplier

// --- Execution Settings ---
input group "Execution Settings"
input ENUM_EXECUTION_MODE ExecutionMode = AGGRESSIVE; // Execution Mode
input int SignalExpiryCandles = 30;    // Signal Expiry Candles (for Conservative and Semi-Aggressive)

// --- Risk & Position Management ---
input group "Risk & Position Management"
input bool EnableHedge = true;         // Allow simultaneous Buy and Sell positions
input bool AllowMultipleAfterBreakeven = true; // Allow multiple positions after breakeven is set
input double RiskPerTrade = 50.0;      // Fixed risk per trade in USD
input bool UsePercentageRisk = false;  // If true, risk is % of account balance
input double RiskPercentage = 3.0;     // Risk percentage (if above is true)
input int ATRPeriod = 14;              // ATR period for SL/TP calculation
input double ATRSLMultiplier = 4.0;    // Stop loss = ATRSLMultiplier * ATR
input double RiskRewardRatio = 0.5;    // Final target = Entry +/- (risk * RRR)

// --- Trade Management ---
input group "Trade Management"
input bool   EnablePartialClose = true; // Enable partial closing of positions
input double PartialCloseRR = 1.5; // RR profit target for partial close
input double PartialClosePercent = 50.0; // Percentage of position to close
input bool   EnableBreakeven = true;   // Enable moving Stop Loss to breakeven
input double BreakevenTriggerReward = 0.5; // Reward/Risk ratio to trigger breakeven
input double BreakevenReward = 0.3; // Reward/Risk ratio for the new SL after breakeven
input bool   EnableTrailingProfit = true; // Enable trailing profit
input double TrailingStartRR = 2.0;    // Start trailing at this RR level
input double TrailingDistanceRR = 1.0; // Trailing step and distance in RR
input bool   EnableReversalExit = true; // Exit trades based on market structure shift
input int    LookbackHighLow = 70;     // Lookback for market structure shift
input bool   EnableDynamicSL = true;   // Enable trigger-candle based exit for losing trades
input int    DynamicSLLookback = 2; // Lookback from the trigger candle for Dynamic SL
input bool   EnableOppositeBBExit = true; // Enable exit/partial at opposite BB
input double OppositeBBPartialPercent = 80.0; // % to close at opposite BB if in profit

// --- Trend & Confirmation Filters ---
input group "Trend & Confirmation Filters"
input bool UseHTFPowerCandleFilter = true; // Enable Higher Timeframe Power Candle trend filter
input ENUM_TIMEFRAMES HTFPowerCandleTimeframe = PERIOD_H4; // Timeframe for the HTF trend filter
input bool UseADXFilter = false;       // Enable ADX Trend Filter
input ENUM_TIMEFRAMES ADXTimeframe = PERIOD_H4; // ADX Timeframe
input int ADXPeriod = 14;              // ADX Period
input int ADXThreshold = 25;           // ADX value to confirm trend
input bool UsePremiumDiscountFilter = false; // Only sell in premium, buy in discount
input int PDLookback = 1;              // Lookback period for premium/discount range
input bool UseLTPowerCandleFilter = true; // Enable execution timeframe Power Candle entry filter
input int PowerCandleWindow = 2;       // Window to search for Power Candle on entry (+/- N bars)
input int PowerCandlePeriods = 20;     // SMA Periods for power candles
input double PowerCandleMultiplier = 1.8; // Multiplier for power candles

// --- Trade & Loss Management ---
input group "Trade & Loss Management"
input int MaxTradesPerDay = 50;        // Maximum trades allowed per day
input bool AllowMultiplePositions = true; // If false, only one trade may be open at a time
input double MinTradeDistanceAtrMultiplier = 0.06; // Min ATR distance between trades if multiple are allowed
input double CloseAllFloatingPercent = 5.0; // % of account balance to trigger mass-close
input int MaxLossTradesPerDay = 5;     // Max loss trades per day
input int MaxLossForPowerCandle = 2;   // Max losses per session to trigger Power Candle confirmation

// --- News Management ---
input group "News Management"
input bool   EnableNewsManagement   = true;    // Enable/Disable the news filter system
input int    NewsCheckIntervalSeconds = 3600; // How often to check for new news events (1 hour)
input int    MinsBefore             = 5;    // Do not trade X minutes before high-impact news
input int    MinsAfter              = 5;    // Do not trade X minutes after high-impact news
input bool   PartialCloseBeforeNews = false; // Partially close profitable trades before news

// --- Chart & Visuals ---
input group "Chart & Visuals"
input bool PlotPowerCandles = true;    // Plot Power Candles on the chart
input color BullPowerColor = clrLimeGreen; // Color for bullish power candles
input color BearPowerColor = clrRed;   // Color for bearish power candles
input int MaxPowerCandlesToDisplay = 1000; // Max Power Candle arrows on chart

//+------------------------------------------------------------------+
//| CBBContinuationEA Class                                          |
//+------------------------------------------------------------------+
class CBBContinuationEA
  {
private:
   // --- All input parameters mirrored as member variables ---
   ulong             m_MagicNumber;
   int               m_Slippage;
   int               m_GmtOffset;
   bool              m_UseManualTimeFilter;
   int               m_StartTradingTime; // Stored as minutes from midnight
   int               m_StopTradingTime;  // Stored as minutes from midnight
   bool              m_EnableNoTradeTime;
   int               m_NoTradeStart;     // Stored as minutes from midnight
   int               m_NoTradeEnd;       // Stored as minutes from midnight
   bool              m_TradeNewYork;
   bool              m_TradeLondon;
   bool              m_TradeTokyo;
   bool              m_TradeSydney;
   int               m_BollingerPeriod;
   double            m_BollingerDeviation;
   bool              m_TradeWickRejections;
   bool              m_CheckATRDistance;
   double            m_MaxATRDistanceMultiplier;
   ENUM_EXECUTION_MODE m_ExecutionMode;
   bool              m_EnableHedge;
   bool              m_AllowMultipleAfterBreakeven;
   double            m_RiskPerTrade;
   bool              m_UsePercentageRisk;
   double            m_RiskPercentage;
   int               m_ATRPeriod;
   double            m_ATRSLMultiplier;
   double            m_RiskRewardRatio;
   
   // --- Trade Management Members ---
   bool              m_EnablePartialClose;
   double            m_PartialCloseRR;
   double            m_PartialClosePercent;
   bool              m_EnableBreakeven;
   double            m_BreakevenTriggerReward;
   double            m_BreakevenReward;
   bool              m_EnableTrailingProfit;
   double            m_TrailingStartRR;
   double            m_TrailingDistanceRR;
   bool              m_EnableReversalExit;
   int               m_LookbackHighLow;
   bool              m_EnableDynamicSL;
   int               m_DynamicSLLookback;
   bool              m_EnableOppositeBBExit;
   double            m_OppositeBBPartialPercent;
   
   bool              m_UseHTFPowerCandleFilter;
   ENUM_TIMEFRAMES   m_HTFPowerCandleTimeframe;
   bool              m_UseADXFilter;
   ENUM_TIMEFRAMES   m_ADXTimeframe;
   int               m_ADXPeriod;
   int               m_ADXThreshold;
   bool              m_UsePremiumDiscountFilter;
   int               m_PDLookback;
   bool              m_UseLTPowerCandleFilter;
   int               m_PowerCandleWindow;
   int               m_PowerCandlePeriods;
   double            m_PowerCandleMultiplier;
   int               m_MaxTradesPerDay;
   bool              m_AllowMultiplePositions;
   double            m_MinTradeDistanceAtrMultiplier;
   double            m_CloseAllFloatingPercent;
   int               m_MaxLossTradesPerDay;
   int               m_MaxLossForPowerCandle;
   bool              m_PlotPowerCandles;
   color             m_BullPowerColor;
   color             m_BearPowerColor;
   int               m_MaxPowerCandlesToDisplay;

   // --- News Filter Inputs ---
   bool              m_EnableNewsManagement;
   int               m_NewsCheckIntervalSeconds;
   int               m_MinsBefore;
   int               m_MinsAfter;
   bool              m_PartialCloseBeforeNews;
   
   // --- EA State & Internal Variables ---
   int               m_htfTrend; // 1 for Bull, -1 for Bear, 0 for None
   string            m_powerCandleObjects[];
   int               m_LossTradesNewYork;
   int               m_LossTradesLondon;
   int               m_LossTradesTokyo;
   int               m_LossTradesSydney;
   int               m_LossTradesPerDay;
   bool              m_waitForBullPower[4]; // NY, LON, TOK, SYD
   bool              m_waitForBearPower[4]; // NY, LON, TOK, SYD
   
   // --- Arrays to track which positions have been managed ---
   ulong             m_partialledTickets[];

   // --- Tracked Positions for Partial and Trailing ---
   struct TrackedPosition
     {
      ulong          ticket;
      double         original_risk;
      double         last_trail_sl;
     };
   TrackedPosition   m_trackedPositions[];

   enum BBState { BB_NONE, BB_BULLISH, BB_BEARISH } m_bbState;
   int               m_tradesToday;
   datetime          m_lastTradeDay;
   datetime          m_lastBarTime;

   // --- Handles & Buffers ---
   int               m_BandHandle;
   int               m_ADXHandle;
   double            m_upperBand[1];
   double            m_lowerBand[1];
   double            m_mainBand[1];

   // --- News Filter State ---
   struct CachedNewsEvent { datetime time; string country; int importance; };
   CachedNewsEvent   m_cached_news[];
   string            m_news_cache_filename;
   string            m_base_currency;
   string            m_quote_currency;
   datetime          m_nextNewsTime;
   datetime          m_lastNewsCheck;
   datetime          m_lastManagedNews;
   bool              m_inSleepMode;
   bool              m_pendingSleep;
   datetime          m_sleepStart;
   datetime          m_sleepEndTime;
   
   // --- Dynamic SL Management Structs & Arrays ---
   struct ManagedPositionInfo
     {
      ulong          position_ticket;
      double         dynamicSL_level;
     };
   ManagedPositionInfo m_managedPositions[];

   // --- MQL5 Objects ---
   CTrade            m_trade;
   CPositionInfo     m_position;
   CAccountInfo      m_account;
   COrderInfo        m_order;

   // --- Execution State ---
   bool              m_waitingExecution;
   ENUM_ORDER_TYPE   m_waitingSignal;
   datetime          m_signalTriggerTime;
   double            m_executionTargetLevel;
   double            m_pendingDynamicSLLevel;
   int               m_SignalExpiryCandles;

   // --- Additional for opposite BB close-based check ---
   datetime          m_lastOppositeBBCheck;

//+------------------------------------------------------------------+
//| HELPER & CALCULATION FUNCTIONS                                   |
//+------------------------------------------------------------------+
   
   int TimeStringToMinutes(string time_str)
     {
      string parts[];
      if(StringSplit(time_str, ':', parts) == 2)
        {
         int hour = (int)StringToInteger(parts[0]);
         int minute = (int)StringToInteger(parts[1]);
         if(hour >= 0 && hour < 24 && minute >= 0 && minute < 60)
           {
            return hour * 60 + minute;
           }
        }
      Print("Invalid time string format: ", time_str, ". Please use HH:MM.");
      return -1;
     }
   
   double CalculateLotSize(double slDistance)
     {
      double riskAmount = m_UsePercentageRisk ? m_account.Balance() * (m_RiskPercentage / 100.0) : m_RiskPerTrade;
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      
      if(tickSize <= 0 || tickValue <= 0 || slDistance <=0)
        {
         Print("Invalid symbol properties for lot size calculation. TickSize/TickValue/SL Distance is zero.");
         return 0.0;
        }
      
      double riskPerLot = (slDistance / tickSize) * tickValue;
      if(riskPerLot <= 0)
        {
         Print("Invalid risk per lot calculation. Check symbol info.");
         return 0.0;
        }
      
      double lotSize = riskAmount / riskPerLot;
      
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      
      lotSize = volStep * MathFloor(lotSize / volStep);
      
      if(lotSize < minLot) lotSize = minLot;
      if(lotSize > maxLot) lotSize = maxLot;
      
      return NormalizeDouble(lotSize, 2);
     }
   
   double GetCustom35MinATR()
     {
      int synthetic_bars_needed = m_ATRPeriod + 1;
      int m5_bars_needed = synthetic_bars_needed * 7;
      MqlRates m5_rates[];
      ArraySetAsSeries(m5_rates, true);
      
      if(CopyRates(_Symbol, PERIOD_M5, 0, m5_bars_needed, m5_rates) < m5_bars_needed)
        {
         Print("Not enough M5 history to calculate 35-min ATR.");
         return -1.0;
        }
      
      double sum_tr = 0;
      for(int i = 0; i < m_ATRPeriod; i++)
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
      
      return sum_tr / m_ATRPeriod;
     }

//+------------------------------------------------------------------+
//| NEWS FILTER FUNCTIONS                                            |
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
      ArrayFree(m_cached_news);
      int file_handle = FileOpen(m_news_cache_filename, FILE_READ|FILE_CSV|FILE_COMMON, ',');
      if(file_handle == INVALID_HANDLE)
        {
         Print("--- NEWS [TESTER MODE] ERROR: Could not find news file '", m_news_cache_filename, "'. Please run the EA on a live chart for 1 minute to create it. ---");
         return;
        }
      
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

         int size = ArraySize(m_cached_news);
         ArrayResize(m_cached_news, size + 1, 1000);
         m_cached_news[size].time = event_time;
         m_cached_news[size].country = country;
         m_cached_news[size].importance = importance;
         count++;
        }
      FileClose(file_handle);
      Print("--- NEWS [TESTER MODE]: Successfully loaded ", count, " news events into memory for this test run. ---");
     }

   void DownloadAndCacheNews()
     {
      Print("--- NEWS [LIVE MODE]: Initializing. Attempting to download and cache news history for tester use... ---");
      int file_handle = FileOpen(m_news_cache_filename, FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
      if(file_handle == INVALID_HANDLE)
        {
         Print("--- NEWS [LIVE MODE] ERROR: Could not create the cache file. Check terminal permissions. ---");
         return;
        }
      Print("--- NEWS [LIVE MODE]: Cache file '", m_news_cache_filename, "' opened for writing. ---");
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

   datetime GetNextHighImpactNewsTime()
     {
      datetime next_event_time = 0;
      datetime now = TimeGMT();
      string relevant_countries[2];
      relevant_countries[0] = CurrencyToCountryCode(m_base_currency);
      relevant_countries[1] = CurrencyToCountryCode(m_quote_currency);

      if(MQLInfoInteger(MQL_TESTER))
        {
         for(int i = 0; i < ArraySize(m_cached_news); i++)
           {
            if(m_cached_news[i].time > now && m_cached_news[i].importance == CALENDAR_IMPORTANCE_HIGH)
              {
               if(m_cached_news[i].country == relevant_countries[0] || m_cached_news[i].country == relevant_countries[1])
                 {
                  if(next_event_time == 0 || m_cached_news[i].time < next_event_time)
                    {
                     next_event_time = m_cached_news[i].time;
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

   void ManagePositionsBeforeNews()
     {
      Print("--- NEWS: Starting position management before high-impact news at ", TimeToString(m_nextNewsTime), ". ---");
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
         if(m_position.SelectByIndex(i) && m_position.Symbol() == _Symbol && m_position.Magic() == m_MagicNumber)
           {
            double profit = m_position.Profit();
            ulong ticket = m_position.Ticket();
            Print("--- NEWS: Checking position #", ticket, ": Profit=", DoubleToString(profit, 2), " ---");
            if(profit < 0)
              {
               if(m_trade.PositionClose(ticket))
                 {
                  Print("--- NEWS: Closed losing position #", ticket, ". ---");
                  closed++;
                 }
               else
                  Print("--- NEWS: Failed to close #", ticket, ": ", GetLastError(), " ---");
              }
            else
              {
               double entry = m_position.PriceOpen();
               double new_sl = (m_position.PositionType() == POSITION_TYPE_BUY) ? entry + be_offset : entry - be_offset;
               new_sl = NormalizeDouble(new_sl, _Digits);
               MqlTick tick;
               SymbolInfoTick(_Symbol, tick);
               long stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
               bool valid = (m_position.PositionType() == POSITION_TYPE_BUY && new_sl <= tick.bid - stops_level * _Point) ||
                            (m_position.PositionType() == POSITION_TYPE_SELL && new_sl >= tick.ask + stops_level * _Point);
               if(!valid)
                 {
                  new_sl = entry;
                  new_sl = NormalizeDouble(new_sl, _Digits);
                 }
               if(m_trade.PositionModify(ticket, new_sl, m_position.TakeProfit()))
                 {
                  Print("--- NEWS: Modified SL for #", ticket, " to ", DoubleToString(new_sl, _Digits), ". ---");
                  modified++;
                 }
               else
                  Print("--- NEWS: Failed to modify SL for #", ticket, ": ", GetLastError(), " ---");
               if(m_PartialCloseBeforeNews)
                 {
                  double volume = m_position.Volume();
                  double close_vol = volume * (m_PartialClosePercent / 100.0);
                  double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
                  close_vol = vol_step * MathRound(close_vol / vol_step);
                  if(close_vol > 0 && close_vol < volume)
                    {
                     if(m_trade.PositionClosePartial(ticket, close_vol))
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
   
   void CheckNewsEvents()
     {
      if(!m_EnableNewsManagement) return;

      datetime now_gmt = TimeGMT();

      if(m_pendingSleep && now_gmt >= m_sleepStart)
        {
         m_pendingSleep = false;
         m_inSleepMode = true;
         Print("--- NEWS: Entering sleep mode. ---");
        }
      if(m_inSleepMode && now_gmt >= m_sleepEndTime)
        {
         m_inSleepMode = false;
         Print("--- NEWS: Exiting sleep mode. ---");
        }

      if(now_gmt - m_lastNewsCheck >= m_NewsCheckIntervalSeconds)
        {
         m_lastNewsCheck = now_gmt;
         m_nextNewsTime = GetNextHighImpactNewsTime();
        }
      if(m_nextNewsTime > 0 && m_nextNewsTime != m_lastManagedNews)
        {
         long time_to_news = m_nextNewsTime - now_gmt;
         if(time_to_news <= m_MinsBefore * 60 && time_to_news > 0)
           {
            ManagePositionsBeforeNews();
            m_lastManagedNews = m_nextNewsTime;
            m_pendingSleep = true;
            m_sleepStart = now_gmt + 60;
            m_sleepEndTime = m_nextNewsTime + m_MinsAfter * 60 - 60;
           }
        }
     }

   bool HasOpenBuyPositions()
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(m_position.SelectByIndex(i))
           {
            if(m_position.Symbol() == _Symbol && m_position.Magic() == m_MagicNumber && m_position.PositionType() == POSITION_TYPE_BUY)
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
         if(m_position.SelectByIndex(i))
           {
            if(m_position.Symbol() == _Symbol && m_position.Magic() == m_MagicNumber && m_position.PositionType() == POSITION_TYPE_SELL)
              {
               return true;
              }
           }
        }
      return false;
     }

public:
//+------------------------------------------------------------------+
//| INITIALIZATION & DEINITIALIZATION                                |
//+------------------------------------------------------------------+

   CBBContinuationEA()
     {
      m_MagicNumber = MagicNumber;
      m_Slippage = Slippage;
      m_GmtOffset = 0;
      m_UseManualTimeFilter = UseManualTimeFilter;
      m_StartTradingTime = TimeStringToMinutes(StartTradingTime);
      m_StopTradingTime = TimeStringToMinutes(StopTradingTime);
      m_EnableNoTradeTime = EnableNoTradeTime;
      m_NoTradeStart = TimeStringToMinutes(NoTradeStart);
      m_NoTradeEnd = TimeStringToMinutes(NoTradeEnd);
      m_TradeNewYork = TradeNewYork;
      m_TradeLondon = TradeLondon;
      m_TradeTokyo = TradeTokyo;
      m_TradeSydney = TradeSydney;
      m_BollingerPeriod = BollingerPeriod;
      m_BollingerDeviation = BollingerDeviation;
      m_TradeWickRejections = TradeWickRejections;
      m_CheckATRDistance = CheckATRDistance;
      m_MaxATRDistanceMultiplier = MaxATRDistanceMultiplier;
      m_ExecutionMode = ExecutionMode;
      m_EnableHedge = EnableHedge;
      m_AllowMultipleAfterBreakeven = AllowMultipleAfterBreakeven;
      m_RiskPerTrade = RiskPerTrade;
      m_UsePercentageRisk = UsePercentageRisk;
      m_RiskPercentage = RiskPercentage;
      m_ATRPeriod = ATRPeriod;
      m_ATRSLMultiplier = ATRSLMultiplier;
      m_RiskRewardRatio = RiskRewardRatio;
      
      m_EnablePartialClose = EnablePartialClose;
      m_PartialCloseRR = PartialCloseRR;
      m_PartialClosePercent = PartialClosePercent;
      m_EnableBreakeven = EnableBreakeven;
      m_BreakevenTriggerReward = BreakevenTriggerReward;
      m_BreakevenReward = BreakevenReward;
      m_EnableTrailingProfit = EnableTrailingProfit;
      m_TrailingStartRR = TrailingStartRR;
      m_TrailingDistanceRR = TrailingDistanceRR;
      m_EnableReversalExit = EnableReversalExit;
      m_LookbackHighLow = LookbackHighLow;
      m_EnableDynamicSL = EnableDynamicSL;
      m_DynamicSLLookback = DynamicSLLookback;
      m_EnableOppositeBBExit = EnableOppositeBBExit;
      m_OppositeBBPartialPercent = OppositeBBPartialPercent;
      
      m_UseHTFPowerCandleFilter = UseHTFPowerCandleFilter;
      m_HTFPowerCandleTimeframe = HTFPowerCandleTimeframe;
      m_UseADXFilter = UseADXFilter;
      m_ADXTimeframe = ADXTimeframe;
      m_ADXPeriod = ADXPeriod;
      m_ADXThreshold = ADXThreshold;
      m_UsePremiumDiscountFilter = UsePremiumDiscountFilter;
      m_PDLookback = PDLookback;
      m_UseLTPowerCandleFilter = UseLTPowerCandleFilter;
      m_PowerCandleWindow = PowerCandleWindow;
      m_PowerCandlePeriods = PowerCandlePeriods;
      m_PowerCandleMultiplier = PowerCandleMultiplier;
      m_MaxTradesPerDay = MaxTradesPerDay;
      m_AllowMultiplePositions = AllowMultiplePositions;
      m_MinTradeDistanceAtrMultiplier = MinTradeDistanceAtrMultiplier;
      m_CloseAllFloatingPercent = CloseAllFloatingPercent;
      m_MaxLossTradesPerDay = MaxLossTradesPerDay;
      m_MaxLossForPowerCandle = MaxLossForPowerCandle;
      m_PlotPowerCandles = PlotPowerCandles;
      m_BullPowerColor = BullPowerColor;
      m_BearPowerColor = BearPowerColor;
      m_MaxPowerCandlesToDisplay = MaxPowerCandlesToDisplay;
      m_EnableNewsManagement = EnableNewsManagement;
      m_NewsCheckIntervalSeconds = NewsCheckIntervalSeconds;
      m_MinsBefore = MinsBefore;
      m_MinsAfter = MinsAfter;
      m_PartialCloseBeforeNews = PartialCloseBeforeNews;
      m_htfTrend = 0;
      ArrayResize(m_powerCandleObjects, 0);
      m_LossTradesNewYork = 0;
      m_LossTradesLondon = 0;
      m_LossTradesTokyo = 0;
      m_LossTradesSydney = 0;
      m_LossTradesPerDay = 0;
      ArrayInitialize(m_waitForBullPower, false);
      ArrayInitialize(m_waitForBearPower, false);
      ArrayResize(m_partialledTickets, 0);
      ArrayResize(m_trackedPositions, 0);
      m_bbState = BB_NONE;
      m_tradesToday = 0;
      m_lastTradeDay = 0;
      m_lastBarTime = 0;
      m_news_cache_filename = "Limitless_News_Cache.csv";
      ArrayResize(m_cached_news, 0);
      m_nextNewsTime = 0;
      m_lastNewsCheck = 0;
      m_lastManagedNews = 0;
      m_inSleepMode = false;
      m_pendingSleep = false;
      m_sleepStart = 0;
      m_sleepEndTime = 0;
      m_SignalExpiryCandles = SignalExpiryCandles;
      m_waitingExecution = false;
      m_signalTriggerTime = 0;
      m_executionTargetLevel = 0;
      m_pendingDynamicSLLevel = 0;
      m_lastOppositeBBCheck = 0;
     }

   void Initialize()
     {
      m_trade.SetExpertMagicNumber(m_MagicNumber);
      
      m_BandHandle = iBands(_Symbol, _Period, m_BollingerPeriod, 0, m_BollingerDeviation, PRICE_CLOSE);
      if(m_BandHandle == INVALID_HANDLE)
        Print("Failed to get handle for Bollinger Bands.");

      if(m_UseADXFilter)
        {
         m_ADXHandle = iADX(_Symbol, m_ADXTimeframe, m_ADXPeriod);
         if(m_ADXHandle == INVALID_HANDLE)
            Print("Failed to initialize ADX indicator.");
        }

      UpdateHTFPowerCandleTrend();
      
      if(m_EnableNewsManagement)
        {
         m_base_currency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
         m_quote_currency = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);

         if(MQLInfoInteger(MQL_TESTER))
           {
            LoadNewsFromCache();
           }
         else
           {
            DownloadAndCacheNews();
           }
         m_nextNewsTime = GetNextHighImpactNewsTime();
         m_lastNewsCheck = TimeGMT();
        }
     }
   
   void Deinit()
     {
      for(int i = ArraySize(m_powerCandleObjects) - 1; i >= 0; i--)
        {
         ObjectDelete(0, m_powerCandleObjects[i]);
        }
      ArrayResize(m_powerCandleObjects, 0);
     }

//+------------------------------------------------------------------+
//| CORE TRADING & SIGNAL LOGIC                                      |
//+------------------------------------------------------------------+

   
   void UpdateBBState()
     {
      double lastClose = iClose(_Symbol, _Period, 1);
      
      if(CopyBuffer(m_BandHandle, 0, 1, 1, m_mainBand) <= 0)
        Print("Error copying main band data: ", GetLastError());
      if(CopyBuffer(m_BandHandle, 1, 1, 1, m_upperBand) <= 0)
        Print("Error copying upper band data: ", GetLastError());
      if(CopyBuffer(m_BandHandle, 2, 1, 1, m_lowerBand) <= 0)
        Print("Error copying lower band data: ", GetLastError());

      if(lastClose < m_lowerBand[0])
        {
         m_bbState = BB_BEARISH;
        }
      else if(lastClose > m_upperBand[0])
        {
         m_bbState = BB_BULLISH;
        }
      // State persists until opposite break
     }
   
   ENUM_ORDER_TYPE GetTradeSignal()
     {
      if(m_TradeWickRejections)
        return GetWickRejectionSignal();
      else
        return GetBBContinuationSignal();
     }

   ENUM_ORDER_TYPE GetBBContinuationSignal()
     {
      ENUM_ORDER_TYPE signal = (ENUM_ORDER_TYPE)-1;
      double lastClose = iClose(_Symbol, _Period, 1);
      if(CopyBuffer(m_BandHandle, 0, 1, 1, m_mainBand) <= 0) return signal;
      if(CopyBuffer(m_BandHandle, 1, 1, 1, m_upperBand) <= 0) return signal;
      if(CopyBuffer(m_BandHandle, 2, 1, 1, m_lowerBand) <= 0) return signal;

      if(m_bbState == BB_BULLISH && lastClose <= m_mainBand[0])
        {
         Print("Signal Trigger: BB Pullback BUY. Close (", DoubleToString(lastClose, _Digits), ") retraced to Middle Band (", DoubleToString(m_mainBand[0], _Digits), ") in bullish state.");
         signal = ORDER_TYPE_BUY;
         // Do not reset state for continuation
        }
      else if(m_bbState == BB_BEARISH && lastClose >= m_mainBand[0])
        {
         Print("Signal Trigger: BB Pullback SELL. Close (", DoubleToString(lastClose, _Digits), ") retraced to Middle Band (", DoubleToString(m_mainBand[0], _Digits), ") in bearish state.");
         signal = ORDER_TYPE_SELL;
         // Do not reset state for continuation
        }

      return signal;
     }
     
   ENUM_ORDER_TYPE GetWickRejectionSignal()
     {
      ENUM_ORDER_TYPE signal = (ENUM_ORDER_TYPE)-1;
      double high1 = iHigh(_Symbol, _Period, 1);
      double low1 = iLow(_Symbol, _Period, 1);
      double close1 = iClose(_Symbol, _Period, 1);
      
      if(CopyBuffer(m_BandHandle, 0, 1, 1, m_mainBand) <= 0) return signal;
      
      if(m_bbState == BB_BULLISH && low1 < m_mainBand[0] && close1 > m_mainBand[0])
        {
         Print("Signal Trigger: BB Wick Rejection BUY at Middle. Low (", DoubleToString(low1, _Digits), ") pierced Middle Band (", DoubleToString(m_mainBand[0], _Digits), ") but Close (", DoubleToString(close1, _Digits), ") was above it in bullish state.");
         signal = ORDER_TYPE_BUY;
        }
      else if(m_bbState == BB_BEARISH && high1 > m_mainBand[0] && close1 < m_mainBand[0])
        {
         Print("Signal Trigger: BB Wick Rejection SELL at Middle. High (", DoubleToString(high1, _Digits), ") pierced Middle Band (", DoubleToString(m_mainBand[0], _Digits), ") but Close (", DoubleToString(close1, _Digits), ") was below it in bearish state.");
         signal = ORDER_TYPE_SELL;
        }
      
      return signal;
     }

   bool IsPowerCandle(int shift, bool isBullish, ENUM_TIMEFRAMES timeframe)
     {
      if(shift + m_PowerCandlePeriods >= iBars(_Symbol, timeframe)) return false;
      
      double sum_range = 0;
      for(int i = 1; i <= m_PowerCandlePeriods; i++)
        {
         if(shift + i >= iBars(_Symbol, timeframe)) return false;
         double open_i = iOpen(_Symbol, timeframe, shift + i);
         double close_i = iClose(_Symbol, timeframe, shift + i);
         sum_range += MathAbs(close_i - open_i);
        }
      double avg_range = sum_range / m_PowerCandlePeriods;
      
      double open_curr = iOpen(_Symbol, timeframe, shift);
      double close_curr = iClose(_Symbol, timeframe, shift);
      double body_curr = MathAbs(close_curr - open_curr);
      
      bool is_large = body_curr > avg_range * m_PowerCandleMultiplier;
      bool is_correct_direction = (isBullish && close_curr > open_curr) || (!isBullish && close_curr < open_curr);
      
      if(is_large && is_correct_direction)
        {
         int sessionIndex = GetCurrentSessionIndex();
         if(sessionIndex != -1)
           {
            if(isBullish && m_waitForBullPower[sessionIndex])
              {
               Print("Bullish power candle found. Resuming buy trades for this session.");
               m_waitForBullPower[sessionIndex] = false;
              }
            if(!isBullish && m_waitForBearPower[sessionIndex])
              {
               Print("Bearish power candle found. Resuming sell trades for this session.");
               m_waitForBearPower[sessionIndex] = false;
              }
           }
        }
      return is_large && is_correct_direction;
     }

   void UpdateHTFPowerCandleTrend()
     {
      if(!m_UseHTFPowerCandleFilter)
        {
         m_htfTrend = 0;
         return;
        }
      for(int i = 1; i < 2000; i++)
        {
         if (i >= iBars(_Symbol, m_HTFPowerCandleTimeframe)) break;
         
         if(IsPowerCandle(i, true, m_HTFPowerCandleTimeframe))
           {
            m_htfTrend = 1;
            return;
           }
         if(IsPowerCandle(i, false, m_HTFPowerCandleTimeframe))
           {
            m_htfTrend = -1;
            return;
           }
        }
     }

   bool CheckPastPowerCandle(int signalBarShift, bool isBullish)
     {
      int start = MathMax(signalBarShift - m_PowerCandleWindow, 1);
      int end = signalBarShift + m_PowerCandleWindow;
      for(int i = start; i <= end; i++)
        {
         if(IsPowerCandle(i, isBullish, _Period))
           {
            return true;
           }
        }
      return false;
     }

//+------------------------------------------------------------------+
//| CHARTING & VISUALS                                               |
//+------------------------------------------------------------------+

   void PlotPowerCandle(int shift, bool isBullish)
     {
      if(!m_PlotPowerCandles || shift >= iBars(_Symbol, _Period)) return;

      datetime t = iTime(_Symbol, _Period, shift);
      double price = isBullish ? iLow(_Symbol, _Period, shift) : iHigh(_Symbol, _Period, shift);
      color paint = isBullish ? m_BullPowerColor : m_BearPowerColor;
      int arrow_code = isBullish ? 233 : 234;
      string name = "PowerCandle_" + TimeToString(t) + "_" + IntegerToString(shift);

      if(ObjectFind(0, name) == -1)
        {
         if(ObjectCreate(0, name, OBJ_ARROW, 0, t, price))
           {
            ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrow_code);
            ObjectSetInteger(0, name, OBJPROP_COLOR, paint);
            ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);

            int size = ArraySize(m_powerCandleObjects);
            ArrayResize(m_powerCandleObjects, size + 1);
            m_powerCandleObjects[size] = name;

            if(ArraySize(m_powerCandleObjects) > m_MaxPowerCandlesToDisplay)
              {
               string old_name = m_powerCandleObjects[0];
               ObjectDelete(0, old_name);
               ArrayRemove(m_powerCandleObjects, 0, 1);
              }
           }
        }
     }

   void UpdateIndicatorPlots()
     {
      if(!m_PlotPowerCandles) return;
      int prev_completed_bar_shift = 1;
      if(iBars(_Symbol, _Period) <= prev_completed_bar_shift) return;

      if(IsPowerCandle(prev_completed_bar_shift, true, _Period))
        PlotPowerCandle(prev_completed_bar_shift, true);
      if(IsPowerCandle(prev_completed_bar_shift, false, _Period))
        PlotPowerCandle(prev_completed_bar_shift, false);
     }

//+------------------------------------------------------------------+
//| FILTER & CONDITION CHECKS                                         |
//+------------------------------------------------------------------+

   void GetSessionsAtTime(datetime time, bool &sessions[])
     {
      MqlDateTime dt;
      TimeToStruct(time, dt);
      
      datetime gmtTime = time - (m_GmtOffset * 3600);
      MqlDateTime gmt_dt;
      TimeToStruct(gmtTime, gmt_dt);
      int gmt_minutes = gmt_dt.hour * 60 + gmt_dt.min;

      ArrayResize(sessions, 4);
      sessions[0] = m_TradeNewYork && (gmt_minutes >= 12 * 60 && gmt_minutes < 21 * 60);
      sessions[1] = m_TradeLondon  && (gmt_minutes >= 7 * 60 && gmt_minutes < 16 * 60);
      sessions[2] = m_TradeTokyo   && (gmt_minutes >= 0 * 60 && gmt_minutes < 9 * 60);
      sessions[3] = m_TradeSydney  && (gmt_minutes >= 21 * 60 || gmt_minutes < 6 * 60);
     }
   
   int GetCurrentSessionIndex()
     {
      bool sessions[4];
      GetSessionsAtTime(TimeCurrent(), sessions);
      if(sessions[0]) return 0;
      if(sessions[1]) return 1;
      if(sessions[2]) return 2;
      if(sessions[3]) return 3;
      return -1;
     }

   bool IsWithinTradingHours()
     {
      if(m_EnableNoTradeTime)
        {
         MqlDateTime dt;
         TimeToStruct(TimeCurrent(), dt);
         int current_minutes = dt.hour * 60 + dt.min;
         
         if(m_NoTradeStart > m_NoTradeEnd)
           {
            if(current_minutes >= m_NoTradeStart || current_minutes < m_NoTradeEnd)
               return false;
           }
         else
           {
            if(current_minutes >= m_NoTradeStart && current_minutes < m_NoTradeEnd)
               return false;
           }
        }

      if(m_UseManualTimeFilter)
        {
         MqlDateTime dt;
         TimeToStruct(TimeCurrent(), dt);
         int current_minutes = dt.hour * 60 + dt.min;
         
         if(m_StartTradingTime > m_StopTradingTime)
           {
            return (current_minutes >= m_StartTradingTime || current_minutes < m_StopTradingTime);
           }
         else
           {
            return (current_minutes >= m_StartTradingTime && current_minutes < m_StopTradingTime);
           }
        }
       
      bool sessions[4];
      GetSessionsAtTime(TimeCurrent(), sessions);
      for(int i=0; i<4; i++)
        {
         if(sessions[i]) return true;
        }

      return false;
     }
   
   bool IsNewsTime()
     {
      if(!m_EnableNewsManagement) return false;
      return m_inSleepMode;
     }
   
   bool CheckADXTrend(ENUM_ORDER_TYPE signal)
{
    // If the filter is disabled in the inputs, always allow the trade.
    if (!m_UseADXFilter) return true;

    double adx_main[1];
    // Check if the ADX buffer can be copied successfully.
    if (CopyBuffer(m_ADXHandle, 0, 1, 1, adx_main) <= 0)
    {
        Print("ADX Filter Error: Could not copy ADX main buffer. Allowing trade as a failsafe.");
        return true; // Failsafe: if indicator fails, don't block trades.
    }

    // We check if the ADX value is above the threshold.
    // This means we only trade in what the ADX considers a strong-trending or continuation market.
    if (adx_main[0] > m_ADXThreshold)
    {
        // ADX is high, indicating a strong trend suitable for continuation.
        // The trade is allowed.
        Print("ADX Filter: PASSED. ADX value (", DoubleToString(adx_main[0], 2), ") is above threshold (", m_ADXThreshold, ").");
        return true;
    }
    else
    {
        //ADX is too low, indicating a weak trend, and the trade is being blocked.
        Print("ADX Filter: BLOCKED. ADX value (", DoubleToString(adx_main[0], 2), ") is below threshold (", m_ADXThreshold, "), indicating a weak trend unsuitable for continuations.");
        return false;
    }
}

   bool IsInPremiumDiscountZone(ENUM_ORDER_TYPE signal)
     {
      if(!m_UsePremiumDiscountFilter) return true;
       
      if(iBars(_Symbol, m_HTFPowerCandleTimeframe) < m_PDLookback + 1)
        {
         Print("Not enough HTF bars for premium/discount filter. Skipping check.");
         return false;
        }
      int high_shift = iHighest(_Symbol, m_HTFPowerCandleTimeframe, MODE_HIGH, m_PDLookback, 1);
      int low_shift = iLowest(_Symbol, m_HTFPowerCandleTimeframe, MODE_LOW, m_PDLookback, 1);
      double htf_high = iHigh(_Symbol, m_HTFPowerCandleTimeframe, high_shift);
      double htf_low = iLow(_Symbol, m_HTFPowerCandleTimeframe, low_shift);
      double midpoint = htf_low + (htf_high - htf_low) / 2.0;
      double current_price = iClose(_Symbol, _Period, 0);
       
      if(signal == ORDER_TYPE_BUY && current_price < midpoint) return true;
      if(signal == ORDER_TYPE_SELL && current_price > midpoint) return true;
       
      return false;
     }
     
   bool CheckATRDistanceFromBB(ENUM_ORDER_TYPE signal)
     {
      if(!m_CheckATRDistance) return true;
       
      double atrValue = GetCustom35MinATR();
      if(atrValue <= 0) 
        {
         Print("Failed to get 35-min ATR for distance check. Skipping filter.");
         return true;
        }
       
      if(CopyBuffer(m_BandHandle, 0, 1, 1, m_mainBand) <= 0) return false;
       
      double maxDist = atrValue * m_MaxATRDistanceMultiplier;
       
      double entryPrice = (signal == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double distance = MathAbs(entryPrice - m_mainBand[0]);
      if(distance > maxDist)
        {
         Print((signal == ORDER_TYPE_BUY ? "BUY" : "SELL"), " Blocked: Distance from Middle BB (", DoubleToString(distance, _Digits), ") is greater than Max Allowed (", DoubleToString(maxDist, _Digits), ").");
         return false;
        }
       
      return true;
     }

   bool CanTrade()
     {
      if(m_LossTradesPerDay >= m_MaxLossTradesPerDay) return false;
      if(m_tradesToday >= m_MaxTradesPerDay) return false;
      if(IsNewsTime()) return false;
       
      return true;
     }
     
   bool IsTradeAllowedByPowerCandleLossFilter(ENUM_ORDER_TYPE signal)
     {
      int sessionIndex = GetCurrentSessionIndex();
      if(sessionIndex != -1)
        {
         if(signal == ORDER_TYPE_BUY && m_waitForBullPower[sessionIndex])
           {
            return false;
           }
         if(signal == ORDER_TYPE_SELL && m_waitForBearPower[sessionIndex])
           {
            return false;
           }
        }
      return true;
     }

   bool IsAnyTradeOpenAndNotAtBreakeven()
     {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(m_position.SelectByIndex(i))
           {
            if(m_position.Symbol() == _Symbol && m_position.Magic() == m_MagicNumber)
              {
               double sl = m_position.StopLoss();
               double open = m_position.PriceOpen();
               if(m_position.PositionType() == POSITION_TYPE_BUY && sl <= open)
                  return true;
               if(m_position.PositionType() == POSITION_TYPE_SELL && (sl >= open || sl == 0))
                  return true;
              }
           }
        }
      return false;
     }
     
   bool HasOpenSameDirectionNotAtBE(ENUM_ORDER_TYPE orderType)
     {
      ENUM_POSITION_TYPE pos_type = (orderType == ORDER_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(m_position.SelectByIndex(i) && m_position.Symbol() == _Symbol && m_position.Magic() == m_MagicNumber && m_position.PositionType() == pos_type)
           {
            double sl = m_position.StopLoss();
            double open = m_position.PriceOpen();
            if(pos_type == POSITION_TYPE_BUY)
              {
               if(sl <= open) return true;
              }
            else
              {
               if(sl >= open || sl == 0) return true;
              }
           }
        }
      return false;
     }

   bool HasAnyOpenSameDirection(ENUM_ORDER_TYPE orderType)
     {
      ENUM_POSITION_TYPE pos_type = (orderType == ORDER_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(m_position.SelectByIndex(i) && m_position.Symbol() == _Symbol && m_position.Magic() == m_MagicNumber && m_position.PositionType() == pos_type)
           {
            return true;
           }
        }
      return false;
     }

   bool HasOpenOppositeDirectionNotAtBE(ENUM_ORDER_TYPE orderType)
     {
      ENUM_POSITION_TYPE pos_type = (orderType == ORDER_TYPE_BUY) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(m_position.SelectByIndex(i) && m_position.Symbol() == _Symbol && m_position.Magic() == m_MagicNumber && m_position.PositionType() == pos_type)
           {
            double sl = m_position.StopLoss();
            double open = m_position.PriceOpen();
            if(pos_type == POSITION_TYPE_BUY)
              {
               if(sl <= open) return true;
              }
            else
              {
               if(sl >= open || sl == 0) return true;
              }
           }
        }
      return false;
     }

   bool HasAnyOpenOppositeDirection(ENUM_ORDER_TYPE orderType)
     {
      ENUM_POSITION_TYPE pos_type = (orderType == ORDER_TYPE_BUY) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(m_position.SelectByIndex(i) && m_position.Symbol() == _Symbol && m_position.Magic() == m_MagicNumber && m_position.PositionType() == pos_type)
           {
            return true;
           }
        }
      return false;
     }
     
   bool IsNewTradeTooClose(ENUM_ORDER_TYPE orderType)
     {
      if(m_MinTradeDistanceAtrMultiplier <= 0) return false;

      double atr = GetCustom35MinATR();
      if (atr <= 0) {
         Print("Could not get ATR for trade distance check. Allowing trade as a failsafe.");
         return false;
      }

      double minDistance = atr * m_MinTradeDistanceAtrMultiplier;
      double currentPrice = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // Check open positions
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(m_position.SelectByIndex(i) && m_position.Symbol() == _Symbol && m_position.Magic() == m_MagicNumber)
           {
            ENUM_POSITION_TYPE posType = m_position.PositionType();
            bool isBuyPos = (posType == POSITION_TYPE_BUY);
            bool isSellPos = (posType == POSITION_TYPE_SELL);

            if ((orderType == ORDER_TYPE_BUY && isBuyPos) || (orderType == ORDER_TYPE_SELL && isSellPos))
              {
               double sl = m_position.StopLoss();
               double open = m_position.PriceOpen();
               if ((isBuyPos && sl >= open) || (isSellPos && sl <= open && sl != 0)) {
                  continue;
               }

               double distance = MathAbs(currentPrice - open);
               if (distance < minDistance)
                 {
                  Print("Trade Blocked: New ", (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"), " signal is too close to open position #", m_position.Ticket(),
                        ". Current distance: ", DoubleToString(distance, _Digits),
                        ", Required distance: ", DoubleToString(minDistance, _Digits));
                  return true;
                 }
              }
           }
        }

      return false;
     }

//+------------------------------------------------------------------+
//| TRADE MANAGEMENT FUNCTIONS                                       |
//+------------------------------------------------------------------+

   void UpdateTrackedPositions()
     {
      for(int i = ArraySize(m_trackedPositions) - 1; i >= 0; i--)
        {
         if(!m_position.SelectByTicket(m_trackedPositions[i].ticket))
           {
            ArrayRemove(m_trackedPositions, i, 1);
           }
        }
     }

   ENUM_ORDER_TYPE_FILLING GetAllowedFillingMode()
     {
      long allowed_modes = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);

      if((allowed_modes & SYMBOL_FILLING_FOK) != 0)
        {
         return ORDER_FILLING_FOK;
        }
      if((allowed_modes & SYMBOL_FILLING_IOC) != 0)
        {
         return ORDER_FILLING_IOC;
        }
      
      return ORDER_FILLING_RETURN;
     }

   void CheckBreakeven()
     {
      if(!m_EnableBreakeven) return;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(m_position.SelectByIndex(i) && m_position.Magic() == m_MagicNumber && m_position.Symbol() == _Symbol)
           {
            double openPrice = m_position.PriceOpen();
            double sl = m_position.StopLoss();
            double tp = m_position.TakeProfit();
            ENUM_POSITION_TYPE posType = m_position.PositionType();

            if(sl == 0) continue;
            double risk = MathAbs(openPrice - sl);
            if(risk == 0) continue;
            
            MqlTick current_tick;
            if(!SymbolInfoTick(_Symbol, current_tick)) continue;

            if(posType == POSITION_TYPE_BUY)
              {
               double triggerPrice = openPrice + risk * m_BreakevenTriggerReward;
               double newSL = openPrice + risk * m_BreakevenReward;
               if(sl >= newSL) continue; 
               if(current_tick.bid >= triggerPrice)
                  if(newSL < current_tick.bid)
                     if(m_trade.PositionModify(m_position.Ticket(), newSL, tp))
                        Print("Breakeven triggered for BUY position #", m_position.Ticket(), ". New SL set to ", DoubleToString(newSL, _Digits));
              }
            else if(posType == POSITION_TYPE_SELL)
              {
               double triggerPrice = openPrice - risk * m_BreakevenTriggerReward;
               double newSL = openPrice - risk * m_BreakevenReward;
               if(sl <= newSL && sl != 0) continue;
               if(current_tick.ask <= triggerPrice)
                  if(newSL > current_tick.ask)
                     if(m_trade.PositionModify(m_position.Ticket(), newSL, tp))
                        Print("Breakeven triggered for SELL position #", m_position.Ticket(), ". New SL set to ", DoubleToString(newSL, _Digits));
              }
           }
        }
     }

   void CheckPartialClose()
     {
      if(!m_EnablePartialClose) return;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(m_position.SelectByIndex(i) && m_position.Symbol() == _Symbol && m_position.Magic() == m_MagicNumber)
           {
            ulong ticket = m_position.Ticket();
            
            bool already_partial = false;
            for(int j = 0; j < ArraySize(m_partialledTickets); j++)
              {
               if(m_partialledTickets[j] == ticket)
                 {
                  already_partial = true;
                  break;
                 }
              }
            if(already_partial) continue;

            double openPrice = m_position.PriceOpen();
            ENUM_POSITION_TYPE posType = m_position.PositionType();
            MqlTick current_tick;
            if(!SymbolInfoTick(_Symbol, current_tick)) continue;

            double current_price = (posType == POSITION_TYPE_BUY) ? current_tick.bid : current_tick.ask;
            double profit_distance = (posType == POSITION_TYPE_BUY) ? (current_price - openPrice) : (openPrice - current_price);

            double original_risk = 0.0;
            for(int k = 0; k < ArraySize(m_trackedPositions); k++)
              {
               if(m_trackedPositions[k].ticket == ticket)
                 {
                  original_risk = m_trackedPositions[k].original_risk;
                  break;
                 }
              }
            if(original_risk <= 0) continue;

            double trigger_distance = original_risk * m_PartialCloseRR;

            if(profit_distance >= trigger_distance)
              {
               double volume = m_position.Volume();
               double close_volume = volume * (m_PartialClosePercent / 100.0);
               double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
               close_volume = vol_step * MathRound(close_volume / vol_step);
               
               if(close_volume > 0 && (volume - close_volume) >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
                 {
                  Print("Partial Close Check for #", ticket, ": ProfitDist=", DoubleToString(profit_distance, _Digits), ", TriggerDist=", DoubleToString(trigger_distance, _Digits), ", VolToClose=", DoubleToString(close_volume,2));

                  MqlTradeRequest request;
                  MqlTradeResult  result;
                  ZeroMemory(request);
                  ZeroMemory(result);

                  request.action       = TRADE_ACTION_DEAL;
                  request.position     = ticket; // Specify the position to close against
                  request.symbol       = _Symbol;
                  request.volume       = close_volume;
                  request.type         = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
                  request.price        = current_price;
                  request.deviation    = (ulong)m_Slippage;
                  request.magic        = m_MagicNumber;
                  request.comment      = "Partial Close";
                  request.type_filling = GetAllowedFillingMode();
                  request.type_time    = ORDER_TIME_GTC;

                  if(OrderSend(request, result))
                    {
                     if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED)
                       {
                        Print("Partial profit taken for position #", ticket, ". Closed ", DoubleToString(close_volume, 2), " lots.");
                        int size = ArraySize(m_partialledTickets);
                        ArrayResize(m_partialledTickets, size + 1);
                        m_partialledTickets[size] = ticket;
                       }
                     else
                       {
                        Print("OrderSend failed for partial close. Retcode: ", result.retcode, " - ", result.comment);
                       }
                    }
                  else
                    {
                     Print("OrderSend failed for partial close. Error: ", GetLastError());
                    }
                 }
              }
           }
        }
     }

   void CheckTrailingProfit()
     {
      if(!m_EnableTrailingProfit) return;

      for(int i = 0; i < ArraySize(m_trackedPositions); i++)
        {
         if(m_position.SelectByTicket(m_trackedPositions[i].ticket))
           {
            double openPrice = m_position.PriceOpen();
            ENUM_POSITION_TYPE posType = m_position.PositionType();
            MqlTick current_tick;
            if(!SymbolInfoTick(_Symbol, current_tick)) continue;

            double current_price = (posType == POSITION_TYPE_BUY) ? current_tick.bid : current_tick.ask;
            double profit_distance = (posType == POSITION_TYPE_BUY) ? (current_price - openPrice) : (openPrice - current_price);
            double current_rr = (m_trackedPositions[i].original_risk > 0) ? profit_distance / m_trackedPositions[i].original_risk : 0.0;
            double current_sl = m_position.StopLoss();

            if(current_rr >= m_TrailingStartRR)
              {
               double rr_since_start = current_rr - m_TrailingStartRR;
               double steps = MathFloor(rr_since_start / m_TrailingDistanceRR);
               double new_sl_rr = m_TrailingStartRR - m_TrailingDistanceRR + steps * m_TrailingDistanceRR;
               double new_sl_price = 0.0;

               if(posType == POSITION_TYPE_BUY)
                 {
                  new_sl_price = openPrice + new_sl_rr * m_trackedPositions[i].original_risk;
                  if(new_sl_price > current_sl)
                    {
                     double tp = m_position.TakeProfit();
                     if(m_trade.PositionModify(m_trackedPositions[i].ticket, new_sl_price, tp))
                       {
                        Print("Trailing SL updated for BUY position #", m_trackedPositions[i].ticket, " to ", DoubleToString(new_sl_price, _Digits));
                       }
                     else
                       {
                        Print("Failed to update trailing SL for BUY #", m_trackedPositions[i].ticket, ": ", m_trade.ResultRetcode());
                       }
                    }
                 }
               else // POSITION_TYPE_SELL
                 {
                  new_sl_price = openPrice - new_sl_rr * m_trackedPositions[i].original_risk;
                  if(new_sl_price < current_sl || current_sl == 0)
                    {
                     double tp = m_position.TakeProfit();
                     if(m_trade.PositionModify(m_trackedPositions[i].ticket, new_sl_price, tp))
                       {
                        Print("Trailing SL updated for SELL position #", m_trackedPositions[i].ticket, " to ", DoubleToString(new_sl_price, _Digits));
                       }
                     else
                       {
                        Print("Failed to update trailing SL for SELL #", m_trackedPositions[i].ticket, ": ", m_trade.ResultRetcode());
                       }
                    }
                 }
              }
           }
        }
     }

   void CheckReversalExit()
     {
      if(!m_EnableReversalExit) return;

      int hiIdx = iHighest(_Symbol, _Period, MODE_HIGH, m_LookbackHighLow, 2);
      int loIdx = iLowest(_Symbol, _Period, MODE_LOW, m_LookbackHighLow, 2);
      if(hiIdx < 0 || loIdx < 0) return;
       
      double highestHigh = iHigh(_Symbol, _Period, hiIdx);
      double lowestLow = iLow(_Symbol, _Period, loIdx);
      double close1 = iClose(_Symbol, _Period, 1);

      bool revBuy = (close1 > highestHigh);
      bool revSell = (close1 < lowestLow);

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(m_position.SelectByIndex(i) && m_position.Magic() == m_MagicNumber && m_position.Symbol() == _Symbol)
           {
            ENUM_POSITION_TYPE posType = m_position.PositionType();
            if(revBuy && posType == POSITION_TYPE_SELL)
              {
               Print("Reversal Exit: Closing SELL position #", m_position.Ticket(), " due to market structure shift up.");
               m_trade.PositionClose(m_position.Ticket());
              }
            if(revSell && posType == POSITION_TYPE_BUY)
              {
               Print("Reversal Exit: Closing BUY position #", m_position.Ticket(), " due to market structure shift down.");
               m_trade.PositionClose(m_position.Ticket());
              }
           }
        }
     }

   void CheckDynamicSL()
     {
      if(!m_EnableDynamicSL) return;

      double close1 = iClose(_Symbol, _Period, 1);

      for(int i = ArraySize(m_managedPositions) - 1; i >= 0; i--)
        {
         if(m_position.SelectByTicket(m_managedPositions[i].position_ticket))
           {
            if(m_position.Profit() < 0)
              {
               ENUM_POSITION_TYPE posType = m_position.PositionType();
               double sl_level = m_managedPositions[i].dynamicSL_level;

               if(sl_level == 0) continue;

               if(posType == POSITION_TYPE_BUY && close1 < sl_level)
                 {
                  Print("Dynamic SL Exit: Closing losing BUY position #", m_managedPositions[i].position_ticket, " because price closed at ",
                        DoubleToString(close1, _Digits), " below trigger level of ", DoubleToString(sl_level, _Digits));
                  m_trade.PositionClose(m_managedPositions[i].position_ticket);
                 }
               if(posType == POSITION_TYPE_SELL && close1 > sl_level)
                 {
                  Print("Dynamic SL Exit: Closing losing SELL position #", m_managedPositions[i].position_ticket, " because price closed at ",
                        DoubleToString(close1, _Digits), " above trigger level of ", DoubleToString(sl_level, _Digits));
                  m_trade.PositionClose(m_managedPositions[i].position_ticket);
                 }
              }
           }
        }
     }
     
   void UpdateManagedTrades()
     {
      if(!m_EnableDynamicSL) return;

      for(int i = ArraySize(m_managedPositions) - 1; i >= 0; i--)
        {
         if(!m_position.SelectByTicket(m_managedPositions[i].position_ticket))
           {
            ArrayRemove(m_managedPositions, i, 1);
           }
        }
     }

   void CheckCloseOnFloatingProfit()
     {
      if(m_CloseAllFloatingPercent <= 0) return;
      double totalProfit = 0;
      for(int i = PositionsTotal()-1; i >= 0; i--)
        {
         if(m_position.SelectByIndex(i) && m_position.Magic() == m_MagicNumber)
           {
            totalProfit += m_position.Profit();
           }
        }
       
      if(!m_account.InfoInteger(ACCOUNT_LEVERAGE)) return;
      double threshold = m_account.Balance() * (m_CloseAllFloatingPercent / 100.0);
       
      if(totalProfit >= threshold)
        {
         Print("Floating profit target of ", DoubleToString(m_CloseAllFloatingPercent, 2), "% reached. Closing all trades.");
         for(int i = PositionsTotal()-1; i >= 0; i--)
           {
            if(m_position.SelectByIndex(i) && m_position.Magic() == m_MagicNumber)
              m_trade.PositionClose(m_position.Ticket());
           }
        }
     }
     
   void CheckOppositeBBExit()
     {
      if(!m_EnableOppositeBBExit) return;

      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick)) return;

      double upper[1], lower[1];
      if(CopyBuffer(m_BandHandle, 1, 0, 1, upper) <= 0) return;
      if(CopyBuffer(m_BandHandle, 2, 0, 1, lower) <= 0) return;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(m_position.SelectByIndex(i) && m_position.Symbol() == _Symbol && m_position.Magic() == m_MagicNumber)
           {
            ulong ticket = m_position.Ticket();
            double profit = m_position.Profit();
            ENUM_POSITION_TYPE type = m_position.PositionType();
            bool hit = false;

            if(type == POSITION_TYPE_BUY && tick.bid <= lower[0]) hit = true;
            else if(type == POSITION_TYPE_SELL && tick.ask >= upper[0]) hit = true;

            if(hit)
              {
               if(profit < 0)
                 {
                  Print("Opposite BB Exit: Closing full losing ", (type == POSITION_TYPE_BUY ? "BUY" : "SELL"), " position #", ticket, " at opposite BB.");
                  m_trade.PositionClose(ticket);
                 }
               else
                 {
                  bool already_partial = false;
                  for(int j = 0; j < ArraySize(m_partialledTickets); j++)
                    {
                     if(m_partialledTickets[j] == ticket)
                       {
                        already_partial = true;
                        break;
                       }
                    }
                  if(already_partial) continue;

                  double volume = m_position.Volume();
                  double close_vol = volume * (m_OppositeBBPartialPercent / 100.0);
                  double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
                  close_vol = vol_step * MathRound(close_vol / vol_step);

                  if(close_vol > 0 && close_vol < volume)
                    {
                     if(m_trade.PositionClosePartial(ticket, close_vol))
                       {
                        Print("Opposite BB Partial: Closed ", DoubleToString(close_vol, 2), " lots of position #", ticket);
                        int size = ArraySize(m_partialledTickets);
                        ArrayResize(m_partialledTickets, size + 1);
                        m_partialledTickets[size] = ticket;
                       }
                     else
                       {
                        Print("Failed partial close at BB: ", GetLastError());
                       }
                    }

                  // Set breakeven for the remaining position
                  double open = m_position.PriceOpen();
                  double sl = m_position.StopLoss();
                  if(sl == 0) continue;
                  double risk = MathAbs(open - sl);
                  double new_sl;
                  if(type == POSITION_TYPE_BUY)
                    {
                     new_sl = open + risk * m_BreakevenReward;
                    }
                  else
                    {
                     new_sl = open - risk * m_BreakevenReward;
                    }
                  new_sl = NormalizeDouble(new_sl, _Digits);

                  long stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
                  bool valid;
                  if(type == POSITION_TYPE_BUY)
                    {
                     valid = new_sl <= tick.bid - stops_level * _Point;
                    }
                  else
                    {
                     valid = new_sl >= tick.ask + stops_level * _Point;
                    }
                  if(!valid)
                    {
                     new_sl = open;
                     new_sl = NormalizeDouble(new_sl, _Digits);
                    }

                  if(m_trade.PositionModify(ticket, new_sl, m_position.TakeProfit()))
                    {
                     Print("Set breakeven after partial at opposite BB for position #", ticket, ". New SL: ", DoubleToString(new_sl, _Digits));
                    }
                  else
                    {
                     Print("Failed to set breakeven after partial: ", GetLastError());
                    }
                 }
              }
           }
        }
     }

//+------------------------------------------------------------------+
//| TRADE EXECUTION                                                  |
//+------------------------------------------------------------------+

   void PlaceTrade(ENUM_ORDER_TYPE orderType)
     {
      Print("--- Evaluating Filters for confirmed ", (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"), " Signal ---");
    
      if (HasOpenSameDirectionNotAtBE(orderType)) 
        {
         Print("   - Trade Blocked: Existing same direction positions not at breakeven.");
         return;
        }

      if (!m_AllowMultipleAfterBreakeven && HasAnyOpenSameDirection(orderType)) 
        {
         Print("   - Trade Blocked: Multiple positions after breakeven disabled.");
         return;
        }

      if (!m_EnableHedge && HasAnyOpenOppositeDirection(orderType)) 
        {
         Print("   - Trade Blocked: Hedging disabled and existing opposite positions open.");
         return;
        }

      if (m_AllowMultiplePositions && IsNewTradeTooClose(orderType))
        {
         return;
        }
      Print("   - Position Management Filter: PASSED");

      if(!IsTradeAllowedByPowerCandleLossFilter(orderType))
        {
         Print("   - Trade Blocked: Paused due to session losses. Waiting for Power Candle reset.");
         return;
        }
      Print("   - Session Loss Filter: PASSED");

      if(m_UseHTFPowerCandleFilter && ((orderType == ORDER_TYPE_BUY && m_htfTrend == -1) || (orderType == ORDER_TYPE_SELL && m_htfTrend == 1))) 
        {
         Print("   - Trade Blocked: Signal opposes HTF Power Candle trend.");
         return;
        }
      Print("   - HTF Trend Filter: PASSED");

      if(!CheckADXTrend(orderType))
        {
         Print("   - Trade Blocked: ADX filter indicates no trend or opposing trend.");
         return;
        }
      Print("   - ADX Filter: PASSED");

      if(!IsInPremiumDiscountZone(orderType))
        {
         Print("   - Trade Blocked: Price is not in a valid Premium/Discount zone.");
         return;
        }
       Print("   - Premium/Discount Filter: PASSED");

      if(!CheckATRDistanceFromBB(orderType))
        {
         return;
        }
      Print("   - ATR Distance Filter: PASSED");

      if(m_UseLTPowerCandleFilter && !CheckPastPowerCandle(1, orderType == ORDER_TYPE_BUY))
        {
         Print("   - Trade Blocked: No LT Power Candle found near the signal bar.");
         return;
        }
      Print("   - LT Power Candle Filter: PASSED");
       
      Print("--- ALL FILTERS PASSED. EXECUTING TRADE ---");

      double atrValue = GetCustom35MinATR();
      if(atrValue <= 0)
        {
         Print("Failed to calculate 35-min ATR. Cannot execute trade.");
         return;
        }
       
      double stopLossDistance = atrValue * m_ATRSLMultiplier;
      double takeProfitDistance = stopLossDistance * m_RiskRewardRatio;

      double entryPrice, slPrice, tpPrice;
      if(orderType == ORDER_TYPE_BUY)
        {
         entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         slPrice = entryPrice - stopLossDistance;
         tpPrice = entryPrice + takeProfitDistance;
        }
      else
        {
         entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         slPrice = entryPrice + stopLossDistance;
         tpPrice = entryPrice - takeProfitDistance;
        }
       
      double lotSize = CalculateLotSize(stopLossDistance);
      if (lotSize <= 0)
        {
         Print("Trade failed: Calculated lot size is 0.");
         return;
        }
       
      double dynamic_sl_level = 0;
      if(m_EnableDynamicSL)
        {
         if(m_ExecutionMode == AGGRESSIVE)
           {
            int triggerCandleShift = 1;
            if(orderType == ORDER_TYPE_BUY)
              {
               int low_idx = iLowest(_Symbol, _Period, MODE_LOW, m_DynamicSLLookback + 1, triggerCandleShift);
               dynamic_sl_level = iLow(_Symbol, _Period, low_idx);
              }
            else
              {
               int high_idx = iHighest(_Symbol, _Period, MODE_HIGH, m_DynamicSLLookback + 1, triggerCandleShift);
               dynamic_sl_level = iHigh(_Symbol, _Period, high_idx);
              }
           }
         else
           {
            dynamic_sl_level = m_pendingDynamicSLLevel;
           }
         Print("   - Dynamic SL Exit Level: ", DoubleToString(dynamic_sl_level, _Digits));
        }

      if(orderType == ORDER_TYPE_BUY)
         m_trade.Buy(lotSize, _Symbol, 0, slPrice, tpPrice);
      else
         m_trade.Sell(lotSize, _Symbol, 0, slPrice, tpPrice);
       
      if(m_trade.ResultRetcode() == TRADE_RETCODE_DONE || m_trade.ResultRetcode() == TRADE_RETCODE_PLACED)
        {
         datetime now = TimeCurrent();
         ENUM_POSITION_TYPE pos_type = (orderType == ORDER_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
         ulong position_ticket = 0;
         if(m_trade.ResultDeal() > 0)
           {
            long pos_id = HistoryDealGetInteger(m_trade.ResultDeal(), DEAL_POSITION_ID);
            if(pos_id > 0)
              {
               position_ticket = (ulong)pos_id;
              }
           }
         if(position_ticket == 0)
           {
            for(int k = PositionsTotal() - 1; k >= 0; k--)
              {
               if(m_position.SelectByIndex(k) && m_position.Symbol() == _Symbol && m_position.Magic() == m_MagicNumber && m_position.PositionType() == pos_type && m_position.Time() >= now - 60)
                 {
                  position_ticket = m_position.Ticket();
                  Print("Fallback: Found position #", position_ticket, ".");
                  break;
                 }
              }
           }
         if(position_ticket > 0)
           {
            m_tradesToday++;
            
            // Add to tracked positions
            int tsize = ArraySize(m_trackedPositions);
            ArrayResize(m_trackedPositions, tsize + 1);
            m_trackedPositions[tsize].ticket = position_ticket;
            m_trackedPositions[tsize].original_risk = stopLossDistance;
            m_trackedPositions[tsize].last_trail_sl = slPrice;
            
            // Add to managed if dynamic SL
            if(m_EnableDynamicSL && dynamic_sl_level > 0)
              {
               int msize = ArraySize(m_managedPositions);
               ArrayResize(m_managedPositions, msize + 1);
               m_managedPositions[msize].position_ticket = position_ticket;
               m_managedPositions[msize].dynamicSL_level = dynamic_sl_level;
               Print("Dynamic SL: Managing position #", position_ticket);
              }
            Print("Trade Executed Successfully.");
           }
         else
           {
            Print("Trade executed but could not identify position ticket.");
           }
        }
      else
        {
         Print("Trade Execution Failed. Retcode: ", m_trade.ResultRetcode());
        }
     }
     

//+------------------------------------------------------------------+
//| EA EVENT HANDLERS                                                |
//+------------------------------------------------------------------>


   void OnNewBar()

     {

      UpdateIndicatorPlots();

      UpdateHTFPowerCandleTrend();

      UpdateBBState();

       

      CheckDynamicSL();

      CheckReversalExit();

       

      if(m_waitingExecution && m_ExecutionMode != AGGRESSIVE)
        {
         int bars_since_signal = iBarShift(_Symbol, _Period, m_signalTriggerTime);
         if(bars_since_signal > m_SignalExpiryCandles)
           {
            m_waitingExecution = false;
            Print("Signal expired.");
           }
        }
      
      if(!CanTrade() || !IsWithinTradingHours())

        return;


      ENUM_ORDER_TYPE signal = GetTradeSignal();

      if(signal == (ENUM_ORDER_TYPE)-1)

        return;


      if(m_ExecutionMode == AGGRESSIVE)
        {
         PlaceTrade(signal);
        }
      else
        {
         m_waitingExecution = true;
         m_waitingSignal = signal;
         m_signalTriggerTime = iTime(_Symbol, _Period, 1);
         if(m_ExecutionMode == CONSERVATIVE)
           {
            m_executionTargetLevel = m_mainBand[0];
           }
         else // SEMI_AGGRESSIVE
           {
            double high1 = iHigh(_Symbol, _Period, 1);
            double low1 = iLow(_Symbol, _Period, 1);
            m_executionTargetLevel = (high1 + low1) / 2.0;
           }
         if(m_EnableDynamicSL)
           {
            int triggerCandleShift = 1;
            if(signal == ORDER_TYPE_BUY)
              {
               int low_idx = iLowest(_Symbol, _Period, MODE_LOW, m_DynamicSLLookback + 1, triggerCandleShift);
               m_pendingDynamicSLLevel = iLow(_Symbol, _Period, low_idx);
              }
            else
              {
               int high_idx = iHighest(_Symbol, _Period, MODE_HIGH, m_DynamicSLLookback + 1, triggerCandleShift);
               m_pendingDynamicSLLevel = iHigh(_Symbol, _Period, high_idx);
              }
            Print("   - Dynamic SL Exit Level calculated at: ", DoubleToString(m_pendingDynamicSLLevel, _Digits));
           }
        }

     }


   void OnTick()

     {

      datetime currentTime = TimeCurrent();

      datetime currentDay = StringToTime(TimeToString(currentTime, TIME_DATE));

       

      if(m_lastTradeDay != currentDay)

        {

         m_tradesToday = 0;

         m_LossTradesNewYork = 0;

         m_LossTradesLondon  = 0;

         m_LossTradesTokyo   = 0;

         m_LossTradesSydney  = 0;

         m_LossTradesPerDay  = 0;

         ArrayInitialize(m_waitForBullPower, false);

         ArrayInitialize(m_waitForBearPower, false);

         ArrayResize(m_partialledTickets, 0);

         m_lastTradeDay = currentDay;

         Print("--- New Trading Day Started ---");

        }


      CheckNewsEvents();


      datetime currentBarTime = (datetime)SeriesInfoInteger(_Symbol, _Period, SERIES_LASTBAR_DATE);

      if(currentBarTime != m_lastBarTime)

        {

         OnNewBar();

         m_lastBarTime = currentBarTime;

        }

       

      UpdateManagedTrades();

      UpdateTrackedPositions();

      CheckBreakeven();

      CheckPartialClose();

      CheckTrailingProfit();

      CheckOppositeBBExit();

      CheckCloseOnFloatingProfit();


      if(m_waitingExecution && m_ExecutionMode != AGGRESSIVE)
        {
         MqlTick tick;
         if(SymbolInfoTick(_Symbol, tick))
           {
            if(m_waitingSignal == ORDER_TYPE_BUY)
              {
               if(tick.bid <= m_executionTargetLevel)
                 {
                  PlaceTrade(ORDER_TYPE_BUY);
                  m_waitingExecution = false;
                 }
              }
            else if(m_waitingSignal == ORDER_TYPE_SELL)
              {
               if(tick.ask >= m_executionTargetLevel)
                 {
                  PlaceTrade(ORDER_TYPE_SELL);
                  m_waitingExecution = false;
                 }
              }
           }
        }

     }


   void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)

     {

      if(trans.type == TRADE_TRANSACTION_DEAL_ADD)

        {

         if(HistoryDealSelect(trans.deal))

           {

            long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);

            if((ulong)magic == m_MagicNumber)

              {

               long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

               double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);

                

               if(entry == DEAL_ENTRY_OUT && profit < 0)

                 {

                  m_LossTradesPerDay++;

                  int sessionIndex = GetCurrentSessionIndex();

                  if(sessionIndex != -1)

                    {

                     if(sessionIndex == 0) m_LossTradesNewYork++;

                     else if(sessionIndex == 1) m_LossTradesLondon++;

                     else if(sessionIndex == 2) m_LossTradesTokyo++;

                     else if(sessionIndex == 3) m_LossTradesSydney++;

                     

                     int sessionLosses = (sessionIndex == 0 ? m_LossTradesNewYork : (sessionIndex == 1 ? m_LossTradesLondon : (sessionIndex == 2 ? m_LossTradesTokyo : m_LossTradesSydney)));

                     if(sessionLosses >= m_MaxLossForPowerCandle)

                       {

                        if(!m_waitForBullPower[sessionIndex])

                          {

                           m_waitForBullPower[sessionIndex] = true;

                           Print("Max losses for session reached. Waiting for a Bullish Power Candle before buying again.");

                          }

                        if(!m_waitForBearPower[sessionIndex])

                          {

                           m_waitForBearPower[sessionIndex] = true;

                           Print("Max losses for session reached. Waiting for a Bearish Power Candle before selling again.");

                          }

                       }

                    }

                 }

              }

           }

        }

     }

  };


//+------------------------------------------------------------------+
//| MQL5 Standard Functions                                          |
//+------------------------------------------------------------------+
CBBContinuationEA eaInstance;


int OnInit()

  {

   datetime ExpirationDate = D'2025.11.17 23:59:59';

   if(TimeCurrent() > ExpirationDate)

     {

      Print("EA expired. Please contact developer.");

      return(INIT_FAILED);

     }

   eaInstance.Initialize();

   ChartSetInteger(0, CHART_SHOW_GRID, false);

   return(INIT_SUCCEEDED);

  }


void OnTick()

  {

   eaInstance.OnTick();

  }


void OnDeinit(const int reason)

  {

   eaInstance.Deinit();

  }


void OnTradeTransaction(const MqlTradeTransaction &trans,

                        const MqlTradeRequest &request,

                        const MqlTradeResult &result)

  {

   eaInstance.OnTradeTransaction(trans, request, result);

  }
 
//+------------------------------------------------------------------+