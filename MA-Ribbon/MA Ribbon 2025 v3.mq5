//+------------------------------------------------------------------+
//|                                                   MA_Ribbon.mq5  |
//|                        Copyright 2021, [Your Name]               |
//|                        https://www.mql5.com                      |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// Input parameters for strategy and filters
input ENUM_MA_METHOD MA_Method         = MODE_EMA;    // Type of Moving Average
input bool          EnableReversalClose = true;        // Enable reversal close logic
input double        PartialCloseProfitPips= 30.0;        // Profit in pips to initiate partial close
input double        PartialClosePercentage= 50.0;         // Percentage of the position to close
input bool          SetBreakeven          = true;        // Enable setting breakeven
input double        MaxPipsFromMA         = 10.0;        // Maximum allowed distance (in pips) from the MA for opening trades
input int           Slippage              = 3;           // Slippage in points
input ulong         MagicNumber           = 123456;      // Unique identifier for EA's orders
input int           LookbackPeriod        = 14;          // Lookback period for high and low
input int           StartHour             = 8;           // Trading session start (GMT)
input int           StartMinute           = 0;           // Trading session start minute (GMT)
input int           EndHour               = 17;          // Trading session end (GMT)
input int           EndMinute             = 0;           // Trading session end minute (GMT)
input int           BrokerGMTOffset       = 0;           // Broker GMT Offset
input int           MAPeriod1             = 5;           // First MA period
input int           MAPeriod2             = 10;          // Second MA period
input int           MAPeriod3             = 15;          // Third MA period
input int           MAPeriod4             = 20;          // Fourth MA period
input int           MAPeriod5             = 25;          // Fifth MA period
input int           MAPeriod6             = 30;          // Sixth MA period
input int           BollingerPeriod       = 20;          // Bollinger Bands period
input double        BollingerDeviation    = 2.0;         // Bollinger Bands deviation

// New inputs for ATR-based risk management:
input int    ATRPeriod         = 14;    // ATR period
input double ATRSLMultiplier   = 2.0;   // Stop loss = ATRSLMultiplier * ATR
input double RiskRewardRatio   = 5.0;   // Take profit = RiskRewardRatio * (ATRSLMultiplier * ATR)
input double RiskPerTrade      = 50.0;  // Fixed risk per trade in USD
input bool   UsePercentageRisk = false; // If true, risk is calculated as a percentage of account balance
input double RiskPercentage    = 1.0;   // Risk percentage (if UsePercentageRisk is true)

// New filter inputs:
input bool UseDailyBias      = false;  // If true, only take trades in the direction of yesterday's bias
input int  MaxTradesPerDay   = 5;      // Maximum trades allowed per day

// New input for position management:
// When false (default), only one trade may be open at a time.
input bool AllowMultiplePositions = false;

// Enum and global variables
enum TradeDirection { LONG = 1, NONE = 0, SHORT = -1 };
TradeDirection tradeDirection = NONE; // persistent global trend

int    maHandles[6];      // Handles for Moving Averages
int    BandHandle;        // Handle for Bollinger Bands
int    ATRHandle;         // Handle for ATR indicator
double upperBand[1];      // Upper Bollinger Band
double lowerBand[1];      // Lower Bollinger Band

CTrade trade;             // Trade object for order management
datetime lastBarTime = 0; // To track the time of the last processed bar

// Variables for max trades per day
int tradesToday = 0;
int lastTradeDay = 0;

//--- Function declarations
void   InitializeIndicators();
void   UpdateTradeDirection(); // Update persistent trend only on reversal
ENUM_ORDER_TYPE GetTradeSignal();
TradeDirection GetDailyBias();
void   CheckReversalClose();
void   ManageTrades();
bool   IsWithinSession();
bool   IsAboveAllMovingAverages();
bool   IsBelowAllMovingAverages();
bool   IsAlready
();
bool   IsAlreadySold();
bool   IsAnyTradeOpen(); // New: check if any trade is open for the current symbol by our EA
double CalculateDistanceFromMA(int maHandle, string symbol, ENUM_TIMEFRAMES period);
double FindMAWithHighestDistance(string symbol, ENUM_TIMEFRAMES period, int &indexOfMaxDistance);
double PositionGetProfitPips(ulong ticket);
void   CheckAndExecutePartialClose();
void   OpenTrade(ENUM_ORDER_TYPE orderType);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   InitializeIndicators();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime != lastBarTime)
   {
      // Update the persistent trend direction before processing trades.
      UpdateTradeDirection();
      
      // Process new bar actions
      ManageTrades();
      lastBarTime = currentBarTime;
   }
   // Check for partial close on every tick
   CheckAndExecutePartialClose();
}

//+------------------------------------------------------------------+
//| Initialize all indicators: MAs, Bollinger Bands, and ATR         |
//+------------------------------------------------------------------+
void InitializeIndicators()
{
   // Initialize Moving Averages
   for(int i = 0; i < ArraySize(maHandles); i++)
   {
      int period = MAPeriod1 + i * 5;
      maHandles[i] = iMA(_Symbol, _Period, period, 0, MA_Method, PRICE_CLOSE);
      if(maHandles[i] == INVALID_HANDLE)
      {
         Print("Failed to get handle for MA with period ", period);
         return;
      }
   }
   // Initialize Bollinger Bands
   BandHandle = iBands(_Symbol, _Period, BollingerPeriod, 0, BollingerDeviation, PRICE_CLOSE);
   
   // Initialize ATR indicator
   ATRHandle = iATR(_Symbol, _Period, ATRPeriod);
   if(ATRHandle == INVALID_HANDLE)
      Print("Failed to initialize ATR indicator.");
}

//+------------------------------------------------------------------+
//| Update persistent trade direction                                |
//| Updates global 'tradeDirection' only on a clear reversal.        |
//+------------------------------------------------------------------+
void UpdateTradeDirection()
{
   double lastClose = iClose(_Symbol, _Period, 1);
   // Refresh Bollinger Bands buffers
   if(CopyBuffer(BandHandle, 1, 0, 1, upperBand) <= 0)
      Print("Error copying upper band data in UpdateTradeDirection.");
   if(CopyBuffer(BandHandle, 2, 0, 1, lowerBand) <= 0)
      Print("Error copying lower band data in UpdateTradeDirection.");
   
   if(tradeDirection == NONE)
   {
      if(lastClose > upperBand[0])
         tradeDirection = LONG;
      else if(lastClose < lowerBand[0])
         tradeDirection = SHORT;
   }
   else if(tradeDirection == LONG)
   {
      // Remain LONG until price closes below lower band.
      if(lastClose < lowerBand[0])
         tradeDirection = SHORT;
   }
   else if(tradeDirection == SHORT)
   {
      // Remain SHORT until price closes above upper band.
      if(lastClose > upperBand[0])
         tradeDirection = LONG;
   }
}

//+------------------------------------------------------------------+
//| Determine the trade signal (buy/sell) using filters              |
//| Uses the persistent global 'tradeDirection' set by UpdateTradeDirection() |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE GetTradeSignal()
{
   ENUM_ORDER_TYPE signal = (ENUM_ORDER_TYPE)-1;
   
   if(tradeDirection == LONG && !IsBelowAllMovingAverages())
      signal = ORDER_TYPE_BUY;
   else if(tradeDirection == SHORT && !IsAboveAllMovingAverages())
      signal = ORDER_TYPE_SELL;
   
   // Apply daily bias filter if enabled
   if(UseDailyBias && signal != (ENUM_ORDER_TYPE)-1)
   {
      TradeDirection dailyBias = GetDailyBias();
      if(dailyBias != tradeDirection)
         signal = (ENUM_ORDER_TYPE)-1;
   }
   
   return signal;
}

//+------------------------------------------------------------------+
//| Get daily bias from the previous day's price action              |
//+------------------------------------------------------------------+
TradeDirection GetDailyBias()
{
   double dailyOpen  = iOpen(_Symbol, PERIOD_D1, 1);
   double dailyClose = iClose(_Symbol, PERIOD_D1, 1);
   if(dailyClose > dailyOpen)
      return LONG;
   else
      return SHORT;
}

//+------------------------------------------------------------------+
//| Check and execute reversal close conditions                      |
//+------------------------------------------------------------------+
void CheckReversalClose()
{
   double highestHigh = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, LookbackPeriod, 2));
   double lowestLow   = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, LookbackPeriod, 2));
   double currentClose= iClose(_Symbol, _Period, 1);
   bool buyClose  = EnableReversalClose && (currentClose > highestHigh);
   bool sellClose = EnableReversalClose && (currentClose < lowestLow);
   
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         string posSymbol = PositionGetString(POSITION_SYMBOL);
         ulong posMagic   = PositionGetInteger(POSITION_MAGIC);
         if(posSymbol != _Symbol || posMagic != MagicNumber)
            continue;
         
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(buyClose && posType == POSITION_TYPE_SELL)
         {
            Print("Closing SELL position due to reversal buy signal.");
            if(!trade.PositionClose(ticket))
               Print("Error closing SELL position: ", GetLastError());
         }
         else if(sellClose && posType == POSITION_TYPE_BUY)
         {
            Print("Closing BUY position due to reversal sell signal.");
            if(!trade.PositionClose(ticket))
               Print("Error closing BUY position: ", GetLastError());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if any trade is already open for this symbol and EA        |
//+------------------------------------------------------------------+
bool IsAnyTradeOpen()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Manage trades: check signal, filters, max daily trades, and open  |
//| new trades                                                       |
//+------------------------------------------------------------------+
void ManageTrades()
{
   // Reset trade count if a new day has started.
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   int currentDay = tm.day;
   if(currentDay != lastTradeDay)
   {
      tradesToday = 0;
      lastTradeDay = currentDay;
   }
   
   // If maximum trades for today have been reached, do not trade.
   if(tradesToday >= MaxTradesPerDay)
      return;
      
   // If not allowing multiple positions and any trade is open, exit.
   if(!AllowMultiplePositions && IsAnyTradeOpen())
      return;
      
   // First, check reversal close logic.
   CheckReversalClose();
   
   // Get the current trade signal.
   ENUM_ORDER_TYPE signal = GetTradeSignal();
   
   // Check maximum distance filter from moving averages.
   int indexOfMaxDistance = -1;
   double maxDistance = FindMAWithHighestDistance(_Symbol, _Period, indexOfMaxDistance);
   
   if(maxDistance < MaxPipsFromMA && IsWithinSession())
   {
      if(signal == ORDER_TYPE_BUY && !IsAlreadyBought())
      {
         OpenTrade(ORDER_TYPE_BUY);
         tradesToday++;
      }
      else if(signal == ORDER_TYPE_SELL && !IsAlreadySold())
      {
         OpenTrade(ORDER_TYPE_SELL);
         tradesToday++;
      }
   }
}

//+------------------------------------------------------------------+
//| Check if current time is within trading session                  |
//+------------------------------------------------------------------+
bool IsWithinSession()
{
   datetime serverTime = TimeCurrent();
   datetime gmtTime = serverTime - BrokerGMTOffset * 3600;
   MqlDateTime gmtDateTime;
   TimeToStruct(gmtTime, gmtDateTime);
   int sessionStart = StartHour * 3600 + StartMinute * 60;
   int sessionEnd   = EndHour * 3600 + EndMinute * 60;
   int currentTime  = gmtDateTime.hour * 3600 + gmtDateTime.min * 60;
   return (currentTime >= sessionStart && currentTime < sessionEnd);
}

//+------------------------------------------------------------------+
//| Check if price is above all MAs                                  |
//+------------------------------------------------------------------+
bool IsAboveAllMovingAverages()
{
   double maBuffer[1];
   for(int i = 0; i < ArraySize(maHandles); i++)
   {
      if(CopyBuffer(maHandles[i], 0, 1, 1, maBuffer) > 0)
      {
         if(iClose(_Symbol, _Period, 1) <= maBuffer[0])
            return false;
      }
      else
      {
         Print("Failed to copy data for MA handle: ", maHandles[i]);
         return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Check if price is below all MAs                                  |
//+------------------------------------------------------------------+
bool IsBelowAllMovingAverages()
{
   double maBuffer[1];
   for(int i = 0; i < ArraySize(maHandles); i++)
   {
      if(CopyBuffer(maHandles[i], 0, 1, 1, maBuffer) > 0)
      {
         if(iClose(_Symbol, _Period, 1) >= maBuffer[0])
            return false;
      }
      else
      {
         Print("Failed to copy data for MA handle: ", maHandles[i]);
         return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Check for existing BUY positions                                 |
//+------------------------------------------------------------------+
bool IsAlreadyBought()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check for existing SELL positions                                |
//+------------------------------------------------------------------+
bool IsAlreadySold()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calculate distance between price and a given MA                  |
//+------------------------------------------------------------------+
double CalculateDistanceFromMA(int maHandle, string symbol, ENUM_TIMEFRAMES period)
{
   double maBuffer[1];
   if(CopyBuffer(maHandle, 0, 0, 1, maBuffer) <= 0)
   {
      Print("Failed to copy data for MA handle: ", maHandle);
      return -1;
   }
   double currentPrice = iClose(symbol, period, 0);
   return MathAbs(currentPrice - maBuffer[0]);
}

//+------------------------------------------------------------------+
//| Find the MA with the highest distance from current price         |
//+------------------------------------------------------------------+
double FindMAWithHighestDistance(string symbol, ENUM_TIMEFRAMES period, int &indexOfMaxDistance)
{
   indexOfMaxDistance = -1;
   double maxDistance = 0;
   double distance;
   for(int i = 0; i < ArraySize(maHandles); i++)
   {
      distance = CalculateDistanceFromMA(maHandles[i], symbol, period);
      if(distance == -1)
         continue;
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      if(digits == 5 || digits == 3)
         distance /= 0.0001;
      else if(digits == 4 || digits == 2)
         distance /= 0.01;
      if(distance > maxDistance)
      {
         maxDistance = distance;
         indexOfMaxDistance = i;
      }
   }
   Print("maxDistance: ", maxDistance, " MaxPipsFromMA: ", MaxPipsFromMA);
   return maxDistance;
}

//+------------------------------------------------------------------+
//| Calculate profit in pips for a given position ticket             |
//+------------------------------------------------------------------+
double PositionGetProfitPips(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return 0;
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ?
                         SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double profitPips = (currentPrice - openPrice) / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? profitPips : -profitPips;
}

//+------------------------------------------------------------------+
//| Check and execute partial close if conditions are met            |
//+------------------------------------------------------------------+
void CheckAndExecutePartialClose()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         string posSymbol = PositionGetString(POSITION_SYMBOL);
         ulong posMagic   = PositionGetInteger(POSITION_MAGIC);
         if(posSymbol != _Symbol || posMagic != MagicNumber)
            continue;
         double profitPips = PositionGetProfitPips(ticket);
         if(profitPips >= PartialCloseProfitPips)
         {
            double volumeToClose = NormalizeDouble(PositionGetDouble(POSITION_VOLUME) * (PartialClosePercentage / 100.0), 2);
            if(trade.PositionClosePartial(ticket, volumeToClose))
            {
               Print("Partial close executed for ticket #", ticket);
               if(SetBreakeven)
               {
                  double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                  double newStopLoss = openPrice;
                  if(!trade.PositionModify(ticket, newStopLoss, PositionGetDouble(POSITION_TP)))
                     Print("Error setting new SL after partial close: ", GetLastError());
               }
            }
            else
            {
               Print("Error in partial closing: ", GetLastError());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Open a new trade based on ATR risk management                    |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE orderType)
{
   double atrValue[1];
   if(CopyBuffer(ATRHandle, 0, 1, 1, atrValue) <= 0)
   {
      Print("Failed to get ATR value.");
      return;
   }
   double atr = atrValue[0];
   
   double stopLossDistance   = atr * ATRSLMultiplier;
   double takeProfitDistance = stopLossDistance * RiskRewardRatio;
   
   double entryPrice, slPrice, tpPrice;
   if(orderType == ORDER_TYPE_BUY)
   {
      entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      slPrice    = entryPrice - stopLossDistance;
      tpPrice    = entryPrice + takeProfitDistance;
   }
   else if(orderType == ORDER_TYPE_SELL)
   {
      entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      slPrice    = entryPrice + stopLossDistance;
      tpPrice    = entryPrice - takeProfitDistance;
   }
   else
   {
      Print("Invalid order type.");
      return;
   }
   
   double riskAmount;
   if(UsePercentageRisk)
      riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercentage / 100.0;
   else
      riskAmount = RiskPerTrade;
      
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double riskPerLot = (stopLossDistance / tickSize) * tickValue;
   if(riskPerLot <= 0)
   {
      Print("Invalid risk per lot calculation.");
      return;
   }
   
   double lotSizeCalculated = riskAmount / riskPerLot;
   double volMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotSizeCalculated < volMin)
      lotSizeCalculated = volMin;
   else
      lotSizeCalculated = MathFloor(lotSizeCalculated / volStep) * volStep;
   lotSizeCalculated = NormalizeDouble(lotSizeCalculated, 2);
   
   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};
   
   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = _Symbol;
   request.volume    = lotSizeCalculated;
   request.type      = orderType;
   request.price     = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                     : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl        = slPrice;
   request.tp        = tpPrice;
   request.deviation = Slippage;
   request.magic     = MagicNumber;
   request.comment   = "MA Ribbon Trade with ATR Risk Management";
   
   if(!trade.OrderSend(request, result))
      Print("OrderSend failed with error code: ", GetLastError());
   else
      Print("Trade opened with ticket #: ", result.order);
}
