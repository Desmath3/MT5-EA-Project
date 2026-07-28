#property copyright "Belema"
#property link "https://www.mql5.com"
#property version "14.0"
#property description "Combines SFP logic with Dynamic SL, Partial Closing, and a News Filter."
#property description "This version integrates the best trade management features from the Power Pivot EA."
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>
#include <Trade/DealInfo.mqh>
#include <MovingAverages.mqh>
#property tester_file "SFP_NewsCache.csv"
enum ENUM_EXECUTION_TYPE
  {
   AGGRESSIVE,
   SEMI_AGGRESSIVE,
   CONSERVATIVE
  };
input group "Session Management"
input bool TradeNewYork = true;
input bool TradeLondon = true;
input bool TradeTokyo = true;
input bool TradeSydney = true;
input group "Point of Interest (POI) Settings"
input bool EnableM5_POI = true;
input bool EnableM15_POI = true;
input bool EnableM30_POI = true;
input bool EnableH1_POI = true;
input bool EnableH4_POI = true;
input bool EnableD1_POI = false;
input int MaxPOIPerTF = 7;
input group "SFP Core Logic & Filters"
input ENUM_EXECUTION_TYPE ExecutionType = AGGRESSIVE;
input bool UseHTFPowerCandleFilter = true;
input ENUM_TIMEFRAMES HTFPowerCandleTimeframe = PERIOD_H4;
input int LeftBars = 22;
input int RightBars = 22;
input int ReclaimLookbackCandles = 8;
input int ReclaimGraceCandles = 10;
input int LevelExpiryCandles = 15;
input int SignalExpiryCandles = 30;
input int MaxActiveSignals = 2;
input group "Risk & Position Management"
input bool EnableHedge = false;
input int ATR_Period = 24;
input double ATR_SL_Multiplier = 4;
input double RiskPercent = 3;
input double RR_Ratio = 1.5;
input int MaxTradesPerDay = 50;
input int MaxTradesPerLevel = 1;
input int EA_MagicNumber = 174355;
input double MinTradeDistanceAtrMultiplier = 0.1;
input double MaxDistanceFromLevelATR = 0.2;
input group "Advanced Trade Management"
input bool EnablePartialClose = true;
input double PartialCloseAtrMultiplier= 1.7;
input double PartialClosePercent = 50;
input bool EnableBreakeven = true;
input double BreakevenTriggerReward = 0.5;
input double BreakevenReward = 0.1;
input bool EnableTradeExpiry = true;
input int TradeExpiryCandles = 20;
input bool EnableDynamicTarget = true;
input int DynamicTargetCandles = 100;
input bool EnableTrailingSL = true;
input double TrailingSLTriggerReward = 1.0;
input double TrailingSLDistanceReward = 0.5;
input group "Objective Target Management"
input bool EnableObjTarget = true;
input ENUM_TIMEFRAMES ObjTargetTimeframe = PERIOD_M5;
input double ObjPartialClosePercent = 80.0;
input group "Chart & Visuals"
input int PowerCandlePeriods = 20;
input double PowerCandleMultiplier = 1.7;
input color BullPowerColor = 3329330;
input color BearPowerColor = 255;
input int MaxPowerCandlesToDisplay = 1000;
input group "News Management"
input bool EnableNewsManagement = true;
input int NewsCheckIntervalSeconds = 3600;
input int MinsBefore = 10;
input int MinsAfter = 10;
input bool PartialCloseBeforeNews = false;
input group "MACD Trend Filter"
input bool EnableMacdFilter = true;
input bool MacdAllowNeutral = true;
input int MacdFastLength = 50;
input int MacdSlowLength = 200;
input int MacdSignalSmoothing = 20;
input int MacdScalingLookback = 100;
input int MacdNeutralThreshold = 25;
input int MacdDisplayBars = 200;
input color MacdBullColor = clrDarkGreen;
input color MacdBearColor = clrDarkRed;
input color MacdNeutralColor = clrGray;
input double MacdHistHeightMultiplier = 0.5;
input double MacdHistOffsetMultiplier = 1.0;
input group "Profit Keeper: Peak Drawdown"
input bool EnablePeakDrawdownExit = true;
input double PeakDrawdownStartPercent = 2.0;
input double PeakProfitDrawdownPercent = 30.0;
input group "Additional Risk Management"
input bool EnableDailyLossLimit = true;
input double DailyLossPercent = 5.0;
input bool EnableWeeklyProfitTarget = true;
input double WeeklyProfitPercent = 10.0;
struct CachedNewsEvent
  {
   datetime time;
   string country;
   int importance;
  };
CachedNewsEvent g_cached_news[];
string g_news_cache_filename = "SFP_NewsCache.csv";
struct LevelInfo
  {
   double price;
   ENUM_TIMEFRAMES timeframe;
   datetime time;
   bool isResistance;
   bool breakoutDetected;
   datetime breakoutTime;
   bool reclaimDetected;
   datetime reclaimTime;
   bool reclaimPowerCandleConfirmed;
   datetime reclaimPowerCandleTime;
   int tradesTaken;
   int barsBeyondLevel;
   bool expired;
  };
LevelInfo levels[];
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
string powerCandleObjects[];
ulong partialClosedTickets[];
ulong objPartialClosedTickets[];
CTrade Trade;
CPositionInfo PositionInfo;
COrderInfo OrderInfo;
CDealInfo DealInfo;
int TradesToday = 0;
int LastTradeDay = 0;
datetime LastBarTime = 0;
int htfTrend = 0;
datetime nextNewsTime = 0;
datetime lastNewsCheck = 0;
datetime lastManagedNews = 0;
bool inSleepMode = false;
bool pendingSleep = false;
datetime sleepStart = 0;
datetime sleepEndTime = 0;
string base_currency = StringSubstr(_Symbol, 0, 3);
string quote_currency = StringSubstr(_Symbol, 3, 3);
int macdTrendState = 0;
double macd_hist[];
datetime lastM1Time = 0;
datetime current_day_start = 0;
bool stopped_for_day = false;
datetime current_week_start = 0;
double week_start_equity = 0;
bool stopped_for_week = false;
int g_ny_start_gmt_min = -1, g_ny_end_gmt_min = -1;
int g_ln_start_gmt_min = -1, g_ln_end_gmt_min = -1;
int g_tk_start_gmt_min = -1, g_tk_end_gmt_min = -1;
int g_sy_start_gmt_min = -1, g_sy_end_gmt_min = -1;
double g_atr_35m = 0;
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
   ArrayFree(g_cached_news);
   int file_handle = FileOpen(g_news_cache_filename, FILE_READ | FILE_CSV | FILE_COMMON, ',');
   if(file_handle == INVALID_HANDLE)
     {
      return;
     }
   FileReadString(file_handle);
   FileReadString(file_handle);
   FileReadString(file_handle);
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
     }
   FileClose(file_handle);
  }
void DownloadAndCacheNews()
  {
   int file_handle = FileOpen(g_news_cache_filename, FILE_WRITE | FILE_CSV | FILE_COMMON, ',');
   if(file_handle == INVALID_HANDLE)
     {
      return;
     }
   FileWrite(file_handle, "time_as_string", "country", "importance");
   datetime from = TimeCurrent() - (86400 * 90);
   datetime to = TimeCurrent() + (86400 * 90);
   MqlCalendarValue values[];
   int total_saved = 0;
   if(CalendarValueHistory(values, from, to))
     {
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
   FileClose(file_handle);
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
   return next_event_time;
  }
bool HasOpenBuyPositions()
  {
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
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
   for(int i = 0; i < total; i++)
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
   for(int i = 0; i < total; i++)
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
   for(int i = 0; i < total; i++)
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
   for(int i = 0; i < total; i++)
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
         htfTrend = 1;
         return;
        }
      if(IsPowerCandleTF(i, false, HTFPowerCandleTimeframe))
        {
         htfTrend = -1;
         return;
        }
     }
  }
void UpdateMacdTrend()
  {
   if(!EnableMacdFilter)
     {
      macdTrendState = 0;
      return;
     }
   int bars_needed = MacdSlowLength + MacdSignalSmoothing + MacdScalingLookback + 10;
   int total_bars = iBars(_Symbol, _Period);
   if(total_bars < bars_needed)
     {
      return;
     }
   double close_prices[];
   ArraySetAsSeries(close_prices, true);
   if(CopyClose(_Symbol, _Period, 0, bars_needed, close_prices) < bars_needed)
     {
      return;
     }
   double fast_ema[];
   double slow_ema[];
   ArrayResize(fast_ema, bars_needed);
   ArrayResize(slow_ema, bars_needed);
   ArraySetAsSeries(fast_ema, true);
   ArraySetAsSeries(slow_ema, true);
   ExponentialMAOnBuffer(bars_needed, 0, 0, MacdFastLength, close_prices, fast_ema);
   ExponentialMAOnBuffer(bars_needed, 0, 0, MacdSlowLength, close_prices, slow_ema);
   double macd_line[];
   ArrayResize(macd_line, bars_needed);
   ArraySetAsSeries(macd_line, true);
   for(int i = 0; i < bars_needed; i++)
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
   for(int i = 0; i < bars_needed; i++)
     {
      hist[i] = macd_line[i] - signal_line[i];
     }
   double max_abs_hist = 0;
   for(int i = 1; i <= MacdScalingLookback && i < bars_needed; i++)
     {
      max_abs_hist = MathMax(max_abs_hist, MathAbs(hist[i]));
     }
   if(max_abs_hist == 0)
     {
      macdTrendState = 0;
      return;
     }
   double scaled_value = (MathAbs(hist[0]) / max_abs_hist) * 100;
   if(scaled_value <= MacdNeutralThreshold)
     {
      macdTrendState = 0;
     }
   else if(hist[0] > 0)
     {
      macdTrendState = 1;
     }
   else
     {
      macdTrendState = -1;
     }
   ArrayResize(macd_hist, MathMin(MacdDisplayBars, bars_needed));
   for(int i = 0; i < ArraySize(macd_hist); i++)
     {
      macd_hist[i] = hist[i];
     }
  }
void DrawMacdIndicator()
  {
   if(!EnableMacdFilter) return;
   double atr = g_atr_35m;
   if(atr <= 0) return;
   double max_hist_height = atr * MacdHistHeightMultiplier;
   int long_lookback = MacdDisplayBars * 2;
   double min_low = DBL_MAX;
   for(int s = 0; s <= long_lookback; s++)
     {
      if(s >= iBars(_Symbol, _Period)) break;
      min_low = MathMin(min_low, iLow(_Symbol, _Period, s));
     }
   double offset = atr * MacdHistOffsetMultiplier;
   double base_y = min_low - offset;
   string zero_name = "MacdZero";
   if(ObjectFind(0, zero_name) == -1)
     {
      ObjectCreate(0, zero_name, OBJ_HLINE, 0, 0, base_y);
      ObjectSetInteger(0, zero_name, OBJPROP_COLOR, clrGray);
      ObjectSetInteger(0, zero_name, OBJPROP_STYLE, STYLE_DOT);
     }
   else
     {
      ObjectSetDouble(0, zero_name, OBJPROP_PRICE, base_y);
     }
   int hist_size = ArraySize(macd_hist);
   double max_abs_hist = 0;
   for(int i = 1; i <= long_lookback && i < hist_size; i++)
     {
      max_abs_hist = MathMax(max_abs_hist, MathAbs(macd_hist[i]));
     }
   if(max_abs_hist == 0) return;
   for(int shift = 0; shift < MacdDisplayBars; shift++)
     {
      if(shift >= hist_size)
        {
         string name = "MacdHist_" + IntegerToString(shift);
         if(ObjectFind(0, name) != -1) ObjectDelete(0, name);
         continue;
        }
      double hist_val = macd_hist[shift];
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
      datetime t1 = iTime(_Symbol, _Period, shift);
      datetime t2 = t1 + PeriodSeconds(_Period);
      double p1 = base_y;
      double p2 = base_y + height;
      if(p2 < p1)
        {
         double temp = p1;
         p1 = p2;
         p2 = temp;
        }
      string name = "MacdHist_" + IntegerToString(shift);
      if(ObjectFind(0, name) == -1)
        {
         if(ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p2, t2, p1))
           {
            ObjectSetInteger(0, name, OBJPROP_COLOR, col);
            ObjectSetInteger(0, name, OBJPROP_FILL, true);
            ObjectSetInteger(0, name, OBJPROP_BACK, true);
            ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
           }
        }
      else
        {
         ObjectSetInteger(0, name, OBJPROP_COLOR, col);
         ObjectMove(0, name, 0, t1, p2);
         ObjectMove(0, name, 1, t2, p1);
        }
     }
  }
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
   levels[n].breakoutTime = 0;
   levels[n].reclaimDetected = false;
   levels[n].reclaimTime = 0;
   levels[n].reclaimPowerCandleConfirmed = false;
   levels[n].reclaimPowerCandleTime = 0;
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
void UpdateLevels()
  {
   ENUM_TIMEFRAMES enabledTFs[] = {PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1};
   bool enables[] = {EnableM5_POI, EnableM15_POI, EnableM30_POI, EnableH1_POI, EnableH4_POI, EnableD1_POI};
   for(int i = 0; i < ArraySize(enabledTFs); i++)
     {
      if(enables[i]) DetectPivots(enabledTFs[i]);
     }
  }
void UpdateLevelExpiry()
  {
   int shift = 1;
   double current_close = iClose(_Symbol, _Period, shift);
   for(int i = ArraySize(levels) - 1; i >= 0; i--)
     {
      double level_price = levels[i].price;
      bool beyond = levels[i].isResistance ? current_close > level_price : current_close < level_price;
      if(beyond)
       {
        levels[i].barsBeyondLevel++;
        if(levels[i].barsBeyondLevel > LevelExpiryCandles)
         {
          levels[i].expired = true;
          string tfStr = EnumToString(levels[i].timeframe);
          string typeStr = levels[i].isResistance ? "Resistance" : "Support";
          string name = "Level_" + tfStr + "_" + typeStr + "_" + TimeToString(levels[i].time);
          ObjectDelete(0, name);
          ObjectDelete(0, name + "_Label");
          ArrayRemove(levels, i, 1);
         }
       }
      else
       {
        levels[i].barsBeyondLevel = 0;
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
bool IsTradeTooClose(double newEntryPrice)
  {
   if(MinTradeDistanceAtrMultiplier <= 0) return false;
   double atr = g_atr_35m;
   if(atr <= 0)
     {
      return false;
     }
   double minDistance = atr * MinTradeDistanceAtrMultiplier;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber)
        {
         double existingOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         if(MathAbs(newEntryPrice - existingOpenPrice) < minDistance)
           {
            return true;
           }
        }
     }
   return false;
  }
bool PlaceTrade(bool isBuy, double level, bool isResistance, ENUM_TIMEFRAMES tf, datetime pivotTime, int triggerCandleShift)
  {
   if(stopped_for_day)
     {
      return false;
     }
   if(stopped_for_week)
     {
      return false;
     }
   if(TradesToday >= MaxTradesPerDay || !IsWithinSession()) return false;
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
   if(isBuy && HasOpenBuyPositions() && !AreAllBuyPositionsAtBreakeven())
     {
      return false;
     }
   if(!isBuy && HasOpenSellPositions() && !AreAllSellPositionsAtBreakeven())
     {
      return false;
     }
   double marketPrice = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(IsTradeTooClose(marketPrice))
     {
      return false;
     }

   if(UseHTFPowerCandleFilter)
     {
      if(isBuy && htfTrend == -1)
        {
         return false;
        }
      if(!isBuy && htfTrend == 1)
        {
         return false;
        }
      
     }
   if(EnableMacdFilter)
     {
      if(isBuy)
        {
         if(macdTrendState == -1)
           {
            return false;
           }
         if(macdTrendState == 0 && !MacdAllowNeutral)
           {
            return false;
           }
        }
      else
        {
         if(macdTrendState == 1)
           {
            return false;
           }
         if(macdTrendState == 0 && !MacdAllowNeutral)
           {
            return false;
           }
        }

     }
   double atr_35m = g_atr_35m;
   if(atr_35m <= 0)
     {
      return false;
     }
   if(MathAbs(marketPrice - level) > atr_35m * MaxDistanceFromLevelATR)
     {
      return false;
     }
   double slDistance = atr_35m * ATR_SL_Multiplier;
   double min_stop_points = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_stop_distance = min_stop_points * _Point;
   if(slDistance < min_stop_distance) slDistance = min_stop_distance;
   double lotSize = CalculateLotSize(slDistance);
   if(lotSize <= 0)
     {
      return false;
     }
   Trade.SetExpertMagicNumber(EA_MagicNumber);
   string shortTradeType = isBuy ? "BM" : "SM";
   string shortTfStr = EnumToString(tf);
   StringReplace(shortTfStr, "PERIOD_", "");
   string comment = "SFP|" + shortTradeType + "|" + shortTfStr + "|POI:" + TimeToString(pivotTime, TIME_DATE | TIME_MINUTES) + "|@ " + DoubleToString(level, _Digits);
   double sl = isBuy ? marketPrice - slDistance : marketPrice + slDistance;
   double tp = isBuy ? marketPrice + slDistance * RR_Ratio : marketPrice - slDistance * RR_Ratio;
   string tradeType = isBuy ? "Buy Market" : "Sell Market";
   bool order_sent = false;
   if(isBuy)
     {
      if(Trade.Buy(lotSize, _Symbol, marketPrice, sl, tp, comment)) order_sent = true;
      else { return false; }
     }
   else
     {
      if(Trade.Sell(lotSize, _Symbol, marketPrice, sl, tp, comment)) order_sent = true;
      else { return false; }
     }
   if(order_sent)
     {
      if(isBuy) {
         if(initialBalance_buy == 0) initialBalance_buy = AccountInfoDouble(ACCOUNT_BALANCE);
      } else {
         if(initialBalance_sell == 0) initialBalance_sell = AccountInfoDouble(ACCOUNT_BALANCE);
      }
      TradesToday++;
      ulong deal_ticket = Trade.ResultDeal();
      ulong pos_ticket = 0;
      if(deal_ticket > 0)
        {
         long pos_id = HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
         pos_ticket = (ulong)pos_id;
        }
      Print(">>> TRADE EXECUTED: ", tradeType, " at ", DoubleToString(marketPrice, _Digits),
            ". SL: ", DoubleToString(sl, _Digits), ", TP: ", DoubleToString(tp, _Digits),
            ". Time: ", TimeToString(TimeCurrent()));
      Print("Trade placed due to SFP signal at level ", DoubleToString(level, _Digits), ", timeframe ", EnumToString(tf), ", pivot time ", TimeToString(pivotTime),
            ", direction ", (isBuy ? "Buy" : "Sell"), ", execution type ", EnumToString(ExecutionType), ", HTF trend ", htfTrend, ", MACD state ", macdTrendState);
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
   int current_bar_shift = 1;
   if(iBars(_Symbol, _Period) <= current_bar_shift) return false;
   datetime current_time = iTime(_Symbol, _Period, current_bar_shift);
   double current_high = iHigh(_Symbol, _Period, current_bar_shift);
   double current_close = iClose(_Symbol, _Period, current_bar_shift);
   double level_price = levels[level_idx].price;
   if(levels[level_idx].expired) return false;
   if(current_close > level_price)
     {
      levels[level_idx].barsBeyondLevel++;
      if(levels[level_idx].barsBeyondLevel > LevelExpiryCandles)
        {
         levels[level_idx].expired = true;
         return false;
        }
     }
   else
     {
      levels[level_idx].barsBeyondLevel = 0;
     }
   if(current_high > level_price && current_close < level_price && levels[level_idx].reclaimTime == 0)
     {
      levels[level_idx].breakoutDetected = true;
      levels[level_idx].breakoutTime = current_time;
      levels[level_idx].reclaimDetected = true;
      levels[level_idx].reclaimTime = current_time;
      Print("SFP State Update (Resistance ", DoubleToString(level_price, _Digits),"): Wick rejection detected.");
     }
   if(!levels[level_idx].reclaimDetected)
     {
      if(!levels[level_idx].breakoutDetected && current_close > level_price)
        {
         levels[level_idx].breakoutDetected = true;
         levels[level_idx].breakoutTime = current_time;
          }
      if(levels[level_idx].breakoutDetected)
        {
         int breakout_shift = iBarShift(_Symbol, _Period, levels[level_idx].breakoutTime);
         int bars_after_breakout = breakout_shift - current_bar_shift;
         if(bars_after_breakout > ReclaimLookbackCandles)
           {
            levels[level_idx].breakoutDetected = false;
           }
         if(current_close < level_price)
           {
            levels[level_idx].reclaimDetected = true;
            levels[level_idx].reclaimTime = current_time;
            Print("SFP State Update (Resistance ", DoubleToString(level_price, _Digits),"): Reclaim detected. Now searching for power candle...");
           }
        }
     }
   if(levels[level_idx].reclaimDetected && !levels[level_idx].reclaimPowerCandleConfirmed)
     {
      int reclaim_shift = iBarShift(_Symbol, _Period, levels[level_idx].reclaimTime);
      int bars_after_reclaim = reclaim_shift - current_bar_shift;
      if(bars_after_reclaim > ReclaimGraceCandles)
        {
         levels[level_idx].reclaimPowerCandleConfirmed = false;
         levels[level_idx].reclaimDetected = false;
         levels[level_idx].breakoutDetected = false;
         return false;
        }
      double atr = g_atr_35m;
      if(atr <= 0) return false;
      double max_dist = atr * MaxDistanceFromLevelATR;
      for(int j = reclaim_shift - 1; j >= current_bar_shift; j--)
        {
         double close_j = iClose(_Symbol, _Period, j);
         double high_j = iHigh(_Symbol, _Period, j);
         if(close_j < level_price && IsPowerCandle(j, false) && MathAbs(high_j - level_price) <= max_dist)
           {
            levels[level_idx].reclaimPowerCandleConfirmed = true;
            levels[level_idx].reclaimPowerCandleTime = iTime(_Symbol, _Period, j);
            Print(" - CONFIRMATION: PASSED. Found Bearish Power Candle at bar shift ", j);
            break;
           }
        }
     }
   if(levels[level_idx].reclaimPowerCandleConfirmed && levels[level_idx].tradesTaken < MaxTradesPerLevel && !IsOpenTradeFromLevel(level_price))
     {
      Print("--- Evaluating SELL Signal at ", DoubleToString(level_price, _Digits), " ---");
      bool isBuy = false;
      int power_shift = iBarShift(_Symbol, _Period, levels[level_idx].reclaimPowerCandleTime);
      if(ExecutionType == AGGRESSIVE)
        {
         if(PlaceTrade(isBuy, level_price, levels[level_idx].isResistance, levels[level_idx].timeframe, levels[level_idx].time, power_shift))
           {
            levels[level_idx].tradesTaken++;
            levels[level_idx].reclaimPowerCandleConfirmed = false;
            levels[level_idx].reclaimDetected = false;
            levels[level_idx].breakoutDetected = false;
            return true;
           }
        }
      else
        {
         UpdateMacdTrend();
         if(EnableMacdFilter)
           {
            if(macdTrendState == 1 || (macdTrendState == 0 && !MacdAllowNeutral))
              {
               levels[level_idx].reclaimPowerCandleConfirmed = false;
               return false;
              }
           }
         int sellCount = 0;
         for(int k = 0; k < ArraySize(activeSignals); k++)
           {
            if(!activeSignals[k].isBuy) sellCount++;
           }
         if(sellCount >= MaxActiveSignals)
           {
            levels[level_idx].reclaimPowerCandleConfirmed = false;
            return false;
           }
         double entry_level = 0;
         double trig_high = iHigh(_Symbol, _Period, power_shift);
         double trig_low = iLow(_Symbol, _Period, power_shift);
         if(ExecutionType == SEMI_AGGRESSIVE)
           {
            entry_level = (trig_high + trig_low) / 2.0;
           }
         else
           {
            entry_level = MathMax(trig_high, level_price);
           }
         int n = ArraySize(activeSignals);
         ArrayResize(activeSignals, n + 1);
         activeSignals[n].isBuy = isBuy;
         activeSignals[n].entryLevel = entry_level;
         activeSignals[n].timeCreated = iTime(_Symbol, _Period, 0);
         activeSignals[n].triggerShift = power_shift;
         activeSignals[n].levelPrice = level_price;
         activeSignals[n].isResistance = levels[level_idx].isResistance;
         activeSignals[n].timeframe = levels[level_idx].timeframe;
         activeSignals[n].pivotTime = levels[level_idx].time;
         levels[level_idx].tradesTaken++;
         levels[level_idx].reclaimPowerCandleConfirmed = false;
         levels[level_idx].reclaimDetected = false;
         levels[level_idx].breakoutDetected = false;
         return true;
        }
     }
   return false;
  }
bool ProcessSupportLevel(int level_idx)
  {
   int current_bar_shift = 1;
   if(iBars(_Symbol, _Period) <= current_bar_shift) return false;
   datetime current_time = iTime(_Symbol, _Period, current_bar_shift);
   double current_low = iLow(_Symbol, _Period, current_bar_shift);
   double current_close = iClose(_Symbol, _Period, current_bar_shift);
   double level_price = levels[level_idx].price;
   if(levels[level_idx].expired) return false;
   if(current_close < level_price)
     {
      levels[level_idx].barsBeyondLevel++;
      if(levels[level_idx].barsBeyondLevel > LevelExpiryCandles)
        {
         levels[level_idx].expired = true;
         return false;
        }
     }
   else
     {
      levels[level_idx].barsBeyondLevel = 0;
     }
   if(current_low < level_price && current_close > level_price && levels[level_idx].reclaimTime == 0)
     {
      levels[level_idx].breakoutDetected = true;
      levels[level_idx].breakoutTime = current_time;
      levels[level_idx].reclaimDetected = true;
      levels[level_idx].reclaimTime = current_time;
      Print("SFP State Update (Support ", DoubleToString(level_price, _Digits),"): Wick rejection detected.");
     }
   if(!levels[level_idx].reclaimDetected)
     {
      if(!levels[level_idx].breakoutDetected && current_close < level_price)
        {
         levels[level_idx].breakoutDetected = true;
         levels[level_idx].breakoutTime = current_time;
         Print("SFP State Update (Support ", DoubleToString(level_price, _Digits),"): Breakout detected.");
        }
      if(levels[level_idx].breakoutDetected)
        {
         int breakout_shift = iBarShift(_Symbol, _Period, levels[level_idx].breakoutTime);
         int bars_after_breakout = breakout_shift - current_bar_shift;
         if(bars_after_breakout > ReclaimLookbackCandles)
           {
            levels[level_idx].breakoutDetected = false;
           }
         if(current_close > level_price)
           {
            levels[level_idx].reclaimDetected = true;
            levels[level_idx].reclaimTime = current_time;
            Print("SFP State Update (Support ", DoubleToString(level_price, _Digits),"): Reclaim detected. Now searching for power candle...");
           }
        }
     }
   if(levels[level_idx].reclaimDetected && !levels[level_idx].reclaimPowerCandleConfirmed)
     {
      int reclaim_shift = iBarShift(_Symbol, _Period, levels[level_idx].reclaimTime);
      int bars_after_reclaim = reclaim_shift - current_bar_shift;
      if(bars_after_reclaim > ReclaimGraceCandles)
        {
         levels[level_idx].reclaimPowerCandleConfirmed = false;
         levels[level_idx].reclaimDetected = false;
         levels[level_idx].breakoutDetected = false;
         return false;
        }
      double atr = g_atr_35m;
      if(atr <= 0) return false;
      double max_dist = atr * MaxDistanceFromLevelATR;
      for(int j = reclaim_shift - 1; j >= current_bar_shift; j--)
        {
         double close_j = iClose(_Symbol, _Period, j);
         double low_j = iLow(_Symbol, _Period, j);
         if(close_j > level_price && IsPowerCandle(j, true) && MathAbs(low_j - level_price) <= max_dist)
           {
            levels[level_idx].reclaimPowerCandleConfirmed = true;
            levels[level_idx].reclaimPowerCandleTime = iTime(_Symbol, _Period, j);
            Print(" - CONFIRMATION: PASSED. Found Bullish Power Candle at bar shift ", j);
            break;
           }
        }
     }
   if(levels[level_idx].reclaimPowerCandleConfirmed && levels[level_idx].tradesTaken < MaxTradesPerLevel && !IsOpenTradeFromLevel(level_price))
     {
      Print("--- Evaluating BUY Signal at ", DoubleToString(level_price, _Digits), " ---");
      bool isBuy = true;
      int power_shift = iBarShift(_Symbol, _Period, levels[level_idx].reclaimPowerCandleTime);
      if(ExecutionType == AGGRESSIVE)
        {
         if(PlaceTrade(isBuy, level_price, levels[level_idx].isResistance, levels[level_idx].timeframe, levels[level_idx].time, power_shift))
           {
            levels[level_idx].tradesTaken++;
            levels[level_idx].reclaimPowerCandleConfirmed = false;
            levels[level_idx].reclaimDetected = false;
            levels[level_idx].breakoutDetected = false;
            return true;
           }
        }
      else
        {
         UpdateMacdTrend();
         if(EnableMacdFilter)
           {
            if(macdTrendState == -1 || (macdTrendState == 0 && !MacdAllowNeutral))
              {
               levels[level_idx].reclaimPowerCandleConfirmed = false;
               return false;
              }
           }
         int buyCount = 0;
         for(int k = 0; k < ArraySize(activeSignals); k++)
           {
            if(activeSignals[k].isBuy) buyCount++;
           }
         if(buyCount >= MaxActiveSignals)
           {
            levels[level_idx].reclaimPowerCandleConfirmed = false;
            return false;
           }
         double entry_level = 0;
         double trig_high = iHigh(_Symbol, _Period, power_shift);
         double trig_low = iLow(_Symbol, _Period, power_shift);
         if(ExecutionType == SEMI_AGGRESSIVE)
           {
            entry_level = (trig_high + trig_low) / 2.0;
           }
         else
           {
            entry_level = MathMin(trig_low, level_price);
           }
         int n = ArraySize(activeSignals);
         ArrayResize(activeSignals, n + 1);
         activeSignals[n].isBuy = isBuy;
         activeSignals[n].entryLevel = entry_level;
         activeSignals[n].timeCreated = iTime(_Symbol, _Period, 0);
         activeSignals[n].triggerShift = power_shift;
         activeSignals[n].levelPrice = level_price;
         activeSignals[n].isResistance = levels[level_idx].isResistance;
         activeSignals[n].timeframe = levels[level_idx].timeframe;
         activeSignals[n].pivotTime = levels[level_idx].time;
         levels[level_idx].tradesTaken++;
         levels[level_idx].reclaimPowerCandleConfirmed = false;
         levels[level_idx].reclaimDetected = false;
         levels[level_idx].breakoutDetected = false;
         return true;
        }
     }
   return false;
  }
bool IsWithinSession()
  {
         MqlDateTime dt;
         TimeToStruct(TimeGMT(), dt);
         int current_gmt_minutes = dt.hour * 60 + dt.min;
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
void ManagePendingOrders()
  {
  }
void EnforceHedgeRule()
  {
   if(EnableHedge) return;
  }
void CheckBreakeven()
  {
   if(!EnableBreakeven) return;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
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
               Trade.PositionModify(ticket, newSL, tp);
               Print("Trade ", ticket, " moved to breakeven: Triggered at reward ratio ", BreakevenTriggerReward, ", new SL at reward ratio ", BreakevenReward);
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
               Trade.PositionModify(ticket, newSL, tp);
               Print("Trade ", ticket, " moved to breakeven: Triggered at reward ratio ", BreakevenTriggerReward, ", new SL at reward ratio ", BreakevenReward);
              }
           }
        }
     }
  }
void CheckPartialClose()
  {
   if(!EnablePartialClose) return;
   double atr = g_atr_35m;
   if(atr <= 0) return;
   double trigger_distance = atr * PartialCloseAtrMultiplier;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber) continue;
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
               int size = ArraySize(partialClosedTickets);
               ArrayResize(partialClosedTickets, size + 1);
               partialClosedTickets[size] = ticket;
               Print("Trade ", ticket, " partially closed: ", PartialClosePercent, "% at ATR multiplier ", PartialCloseAtrMultiplier);
              }
           }
        }
     }
  }
void ManagePositionsBeforeNews()
  {
   double atr = g_atr_35m;
   if(atr <= 0)
     {
      return;
     }
   double be_offset = 0.1 * atr;
   int closed = 0, modified = 0, partial = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber)
        {
         double profit = PositionGetDouble(POSITION_PROFIT);
         if(profit < 0)
           {
            if(Trade.PositionClose(ticket))
              {
               closed++;
               Print("Trade ", ticket, " closed before news: Negative profit");
              }
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
               modified++;
               Print("Trade ", ticket, " SL modified before news to breakeven + offset");
              }
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
                     partial++;
                     Print("Trade ", ticket, " partially closed before news: ", PartialClosePercent, "%");
                    }
                 }
              }
           }
        }
     }
  }
double GetMostRecentResistance(ENUM_TIMEFRAMES tf)
  {
   datetime max_time = 0;
   double price = 0;
   for(int i = 0; i < ArraySize(levels); i++)
     {
      if(levels[i].timeframe == tf && levels[i].isResistance && !levels[i].expired)
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
   for(int i = 0; i < ArraySize(levels); i++)
     {
      if(levels[i].timeframe == tf && !levels[i].isResistance && !levels[i].expired)
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
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber) continue;
      bool already_handled = false;
      for(int j = 0; j < ArraySize(objPartialClosedTickets); j++)
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
         Trade.PositionClose(ticket);
         Print("Trade ", ticket, " closed at objective target: Negative profit");
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
               double risk = MathAbs(entry - sl);
               double new_sl = (posType == POSITION_TYPE_BUY) ? entry + risk * BreakevenReward : entry - risk * BreakevenReward;
               new_sl = NormalizeDouble(new_sl, _Digits);
               bool valid = (posType == POSITION_TYPE_BUY && new_sl <= tick.bid) || (posType == POSITION_TYPE_SELL && new_sl >= tick.ask);
               if(!valid) new_sl = entry;
               Trade.PositionModify(ticket, new_sl, tp);
               int size = ArraySize(objPartialClosedTickets);
               ArrayResize(objPartialClosedTickets, size + 1);
               objPartialClosedTickets[size] = ticket;
               Print("Trade ", ticket, " partially closed at objective target: ", ObjPartialClosePercent, "% at ", DoubleToString(target, _Digits));
              }
           }
        }
     }
  }
void CheckTradeExpiry()
  {
   if(!EnableTradeExpiry) return;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
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
         Print("Trade ", ticket, " closed due to expiry: Retraced to entry after ", TradeExpiryCandles, " candles");
        }
     }
  }
double GetNearestHigherResistance(double ref_price)
  {
   double nearest = DBL_MAX;
   bool found = false;
   for(int i = 0; i < ArraySize(levels); i++)
     {
      if(levels[i].isResistance && !levels[i].expired && levels[i].price > ref_price)
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
   for(int i = 0; i < ArraySize(levels); i++)
     {
      if(!levels[i].isResistance && !levels[i].expired && levels[i].price < ref_price)
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
void CheckDynamicTargets()
  {
   if(!EnableDynamicTarget) return;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      int bars_since = iBarShift(_Symbol, _Period, open_time);
      if(bars_since <= DynamicTargetCandles) continue;
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(posType == POSITION_TYPE_BUY)
        {
         double res = GetNearestHigherResistance(open_price);
         if(res > 0 && tick.bid >= res)
           {
            Trade.PositionClose(ticket);
            Print("Trade ", ticket, " closed at dynamic target: Nearest resistance after ", DynamicTargetCandles, " candles");
           }
        }
      else
        {
         double sup = GetNearestLowerSupport(open_price);
         if(sup > 0 && tick.ask <= sup)
           {
            Trade.PositionClose(ticket);
            Print("Trade ", ticket, " closed at dynamic target: Nearest support after ", DynamicTargetCandles, " candles");
           }
        }
     }
  }
void CheckTrailingSL()
  {
   if(!EnableTrailingSL) return;
   double close1 = iClose(_Symbol, _Period, 1);
   int total = PositionsTotal();
   for(int p = 0; p < total; p++)
     {
      ulong ticket = PositionGetTicket(p);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != EA_MagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      bool found = false;
      for(int j = 0; j < ArraySize(trailingPositions); j++)
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
                     Trade.PositionModify(ticket, new_sl, tp);
                     Print("Trade ", ticket, " trailing SL updated: Triggered at reward ", TrailingSLTriggerReward, ", distance ", TrailingSLDistanceReward);
                    }
                 }
               else
                 {
                  new_sl = close1 + TrailingSLDistanceReward * r;
                  new_sl = NormalizeDouble(new_sl, _Digits);
                  if(new_sl < current_sl || current_sl == 0)
                    {
                     Trade.PositionModify(ticket, new_sl, tp);
                     Print("Trade ", ticket, " trailing SL updated: Triggered at reward ", TrailingSLTriggerReward, ", distance ", TrailingSLDistanceReward);
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
   for(int j = ArraySize(trailingPositions) - 1; j >= 0; j--)
     {
      if(!PositionSelectByTicket(trailingPositions[j].ticket))
        ArrayRemove(trailingPositions, j, 1);
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
         UpdateMacdTrend();
         if(EnableMacdFilter)
           {
            if(activeSignals[i].isBuy)
              {
               if(macdTrendState == -1 || (macdTrendState == 0 && !MacdAllowNeutral)) continue;
              }
            else
              {
               if(macdTrendState == 1 || (macdTrendState == 0 && !MacdAllowNeutral)) continue;
              }
           }
         if(PlaceTrade(activeSignals[i].isBuy, activeSignals[i].levelPrice, activeSignals[i].isResistance,
                       activeSignals[i].timeframe, activeSignals[i].pivotTime, activeSignals[i].triggerShift))
           {
            ArrayRemove(activeSignals, i, 1);
            break;
           }
         }
         else
         {
         ArrayRemove(activeSignals, i, 1);
         }
        }
     }
  }
void CloseAllTrades()
  {
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == EA_MagicNumber)
        {
         Trade.PositionClose(ticket);
         Print("Trade ", ticket, " closed: All trades closed");
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
      for(int j = 0; j < HistoryDealsTotal(); j++)
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
         Print("Trading stopped for day: Daily loss limit reached ", DailyLossPercent, "%");
        }
     }
  }
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
   return INIT_SUCCEEDED;
  }
void OnTick()
  {
   datetime ExpirationDate = StringToTime("2025.12.31 23:59:59");
   if(TimeCurrent() > ExpirationDate)
     {
      return;
     }
   if(EnableNewsManagement)
     {
      if(pendingSleep && TimeGMT() >= sleepStart)
        {
         pendingSleep = false;
         inSleepMode = true;
        }
      if(inSleepMode && TimeGMT() >= sleepEndTime)
        {
         inSleepMode = false;
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
      g_atr_35m = GetCustom35MinATR();
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.day != LastTradeDay)
        {
         TradesToday = 0;
         LastTradeDay = dt.day;
         stopped_for_day = false;
        }
      if(!inSleepMode)
        {
         UpdateHTFPowerCandleTrend();
         UpdateLevels();
         UpdateLevelExpiry();
         UpdateMacdTrend();
         DrawMacdIndicator();
         for(int i = ArraySize(levels) - 1; i >= 0; i--)
           {
            bool tradeWasPlaced = false;
            if(levels[i].isResistance)
              {
               if(ProcessResistanceLevel(i))
                 {
                  tradeWasPlaced = true;
                 }
              }
            else
              {
               if(ProcessSupportLevel(i))
                 {
                  tradeWasPlaced = true;
                 }
              }
            if(tradeWasPlaced)
              {
               break;
              }
           }
         UpdateIndicatorPlots();
        }
      CheckDailyLossLimit();
      CheckTrailingSL();
      LastBarTime = currentBarTime;
     }
   CheckBreakeven();
   CheckPartialClose();
   CheckObjTarget();
   EnforceHedgeRule();
   CheckTradeExpiry();
   CheckDynamicTargets();
   if(ExecutionType != AGGRESSIVE && !inSleepMode)
     {
      CheckActiveSignals();
     }
   if(EnablePeakDrawdownExit){
      double buy_profit = 0;
      double sell_profit = 0;
      int total = PositionsTotal();
      for(int i=0; i<total; i++){
         if(PositionInfo.SelectByIndex(i)){
            if(PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber){
               double profit = PositionInfo.Profit();
               ENUM_POSITION_TYPE typ = PositionInfo.PositionType();
               if(typ == POSITION_TYPE_BUY){
                  buy_profit += profit;
               }else{
                  sell_profit += profit;
               }
            }
         }
      }
      if(HasOpenBuyPositions()){
         double profit_percent = (buy_profit / initialBalance_buy) * 100.0;
         if(!peakDrawdownActive_buy && profit_percent >= PeakDrawdownStartPercent){
            peakDrawdownActive_buy = true;
            buy_peak_profit = buy_profit;
         }
         if(peakDrawdownActive_buy){
            if(buy_profit > buy_peak_profit){
               buy_peak_profit = buy_profit;
            }
            double drawdown = buy_peak_profit - buy_profit;
            double dd_percent = (drawdown / buy_peak_profit) * 100;
            if(dd_percent >= PeakProfitDrawdownPercent){
               CloseAllBuys();
               Print("All buy trades closed: Peak drawdown ", PeakProfitDrawdownPercent, "% from peak");
               peakDrawdownActive_buy = false;
               buy_peak_profit = 0;
            }
         }
      }else{
         ResetBuyVars();
      }
      if(HasOpenSellPositions()){
         double profit_percent = (sell_profit / initialBalance_sell) * 100.0;
         if(!peakDrawdownActive_sell && profit_percent >= PeakDrawdownStartPercent){
            peakDrawdownActive_sell = true;
            sell_peak_profit = sell_profit;
         }
         if(peakDrawdownActive_sell){
            if(sell_profit > sell_peak_profit){
               sell_peak_profit = sell_profit;
            }
            double drawdown = sell_peak_profit - sell_profit;
            double dd_percent = (drawdown / sell_peak_profit) * 100;
            if(dd_percent >= PeakProfitDrawdownPercent){
               CloseAllSells();
               Print("All sell trades closed: Peak drawdown ", PeakProfitDrawdownPercent, "% from peak");
               peakDrawdownActive_sell = false;
               sell_peak_profit = 0;
            }
         }
      }else{
         ResetSellVars();
      }
   }
   if(EnableWeeklyProfitTarget && !stopped_for_week)
     {
      MqlDateTime wdt;
      TimeToStruct(TimeCurrent(), wdt);
      int dow = wdt.day_of_week;
      datetime this_week_start = TimeCurrent() - (datetime)(( (long)dow - 1LL ) * 86400LL );
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
        }
      double curr_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double target_equity = week_start_equity * (1 + WeeklyProfitPercent / 100.0);
      if(curr_equity >= target_equity)
        {
         CloseAllTrades();
         Print("All trades closed: Weekly profit target ", WeeklyProfitPercent, "% reached");
         stopped_for_week = true;
        }
     }
   for(int i = ArraySize(partialClosedTickets) - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(partialClosedTickets[i]))
        {
         ArrayRemove(partialClosedTickets, i, 1);
        }
     }
   for(int i = ArraySize(objPartialClosedTickets) - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(objPartialClosedTickets[i]))
        {
         ArrayRemove(objPartialClosedTickets, i, 1);
        }
     }
  }
void CloseAllBuys()
  {
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i))
        {
         if(PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber && PositionInfo.PositionType() == POSITION_TYPE_BUY)
           {
            Trade.PositionClose(PositionInfo.Ticket());
           }
        }
     }
  }
void CloseAllSells()
  {
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      if(PositionInfo.SelectByIndex(i))
        {
         if(PositionInfo.Symbol() == _Symbol && PositionInfo.Magic() == EA_MagicNumber && PositionInfo.PositionType() == POSITION_TYPE_SELL)
           {
            Trade.PositionClose(PositionInfo.Ticket());
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
   for(int i = 0; i < ArraySize(levels); i++)
     {
      if(levels[i].isResistance == is_resistance && MathAbs(levels[i].price - price) < _Point * 5 && !levels[i].expired)
        {
         return true;
        }
     }
   return false;
  }