//+------------------------------------------------------------------+
//|                                              BB_ReversalEA.mq5     |
//|                        Copyright 2021, [Your Name]               |
//|                        https://www.mql5.com                      |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//------------------ Input Parameters -------------------------------
// Trading settings & filters

input int           Slippage              = 3;           // Slippage in points
input ulong         MagicNumber           = 123456;      // Unique identifier for EA's orders
input int           StartHour             = 8;           // Trading session start (GMT)
input int           StartMinute           = 0;           // Trading session start minute (GMT)
input int           EndHour               = 17;          // Trading session end (GMT)
input int           EndMinute             = 0;           // Trading session end minute (GMT)
input int           BrokerGMTOffset       = 0;           // Broker GMT Offset

// Bollinger Bands parameters
input int    BollingerPeriod    = 100;  // Bollinger Bands period
input double BollingerDeviation = 2.0;  // Bollinger Bands deviation

// ATR-based risk management parameters
input int    ATRPeriod         = 14;    // ATR period
input double ATRSLMultiplier   = 2.0;   // Stop loss = ATRSLMultiplier * ATR
input double RiskRewardRatio   = 10.0;  // Final target = Entry ± (risk * RiskRewardRatio)
input double RiskPerTrade      = 50.0;  // Fixed risk per trade in USD
input bool   UsePercentageRisk = false; // If true, risk is calculated as a percentage of account balance
input double RiskPercentage    = 1.0;   // Risk percentage (if above is true)



// Reward-based partial close & breakeven parameters (multiples of risk)
input double PartialCloseReward   = 5.0;   // Partial close level = risk * 5.0
input bool SetBreakeven = true; // Enable setting breakeven after partial close
input double BreakevenReward      = 1.0;   // Breakeven level = risk * 1.0
input double PartialClosePercentage = 50.0; // Percentage of the position to close
input bool          EnableReversalClose = true;        // Enable reversal close logic
input int           LookbackPeriod        = 14;          // Lookback period for high and low

// Daily bias and trade management
input bool UseDailyBias      = false;  // If true, only trade in the direction of yesterday's bias
input int  MaxTradesPerDay   = 5;      // Maximum trades allowed per day
input bool AllowMultiplePositions = false; // When false, only one trade may be open at a time


//------------------ Global Variables -------------------------------
// Bollinger Bands reversal state
enum BBState { BB_NONE, BB_WAIT_BUY, BB_WAIT_SELL };
BBState bbState = BB_NONE;

// For daily bias filtering: 1 for LONG bias, -1 for SHORT bias.
enum DailyBias { DB_LONG = 1, DB_SHORT = -1 };

// Trade object
CTrade trade;

// Indicator handles and buffers
int BandHandle;
double upperBand[1];
double lowerBand[1];

int ATRHandle;

// Daily trade management variables
int tradesToday = 0;
int lastTradeDay = 0;

// Global array to store tickets that have been partially closed.
ulong partialClosedTickets[];

// To track the last processed bar time.
datetime lastBarTime = 0;

//------------------ Function Declarations --------------------------
void   InitializeIndicators();
void   UpdateBBState();               // Update Bollinger reversal state
ENUM_ORDER_TYPE GetTradeSignalBB();   // Return BUY/SELL signal based on Bollinger state
int    GetDailyBias();                // Returns 1 for LONG bias, -1 for SHORT bias
void   CheckReversalClose();
void   ManageTrades();
bool   IsWithinSession();
bool   IsAlreadyBought();
bool   IsAlreadySold();
bool   IsAnyTradeOpen();
void   CheckAndExecutePartialClose();
void   OpenTrade(ENUM_ORDER_TYPE orderType);

// Helper functions for partial close tracking:
bool IsTicketPartialClosed(ulong ticket)
{
   for(int i = 0; i < ArraySize(partialClosedTickets); i++)
      if(partialClosedTickets[i] == ticket)
         return true;
   return false;
}

void AddPartialClosedTicket(ulong ticket)
{
   int pos = ArraySize(partialClosedTickets);
   ArrayResize(partialClosedTickets, pos + 1);
   partialClosedTickets[pos] = ticket;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ArrayResize(partialClosedTickets, 0);
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
      UpdateBBState();
      ManageTrades();
      lastBarTime = currentBarTime;
   }
   CheckAndExecutePartialClose();
   CheckReversalClose();
}

//+------------------------------------------------------------------+
//| Initialize Indicators: Bollinger Bands and ATR                   |
//+------------------------------------------------------------------+
void InitializeIndicators()
{
   BandHandle = iBands(_Symbol, _Period, BollingerPeriod, 0, BollingerDeviation, PRICE_CLOSE);
   if(BandHandle == INVALID_HANDLE)
      Print("Failed to get handle for Bollinger Bands.");
   
   ATRHandle = iATR(_Symbol, _Period, ATRPeriod);
   if(ATRHandle == INVALID_HANDLE)
      Print("Failed to initialize ATR indicator.");
}

//+------------------------------------------------------------------+
//| Update Bollinger Reversal State                                  |
//| If no state is active, set state based on whether price closed     |
//| below the lower band (then wait for buy) or above the upper band     |
//| (then wait for sell).                                              |
//+------------------------------------------------------------------+
void UpdateBBState()
{
   double lastClose = iClose(_Symbol, _Period, 1);
   if(CopyBuffer(BandHandle, 1, 0, 1, upperBand) <= 0)
      Print("Error copying upper band data in UpdateBBState.");
   if(CopyBuffer(BandHandle, 2, 0, 1, lowerBand) <= 0)
      Print("Error copying lower band data in UpdateBBState.");
   
   if(bbState == BB_NONE)
   {
      if(lastClose < lowerBand[0])
         bbState = BB_WAIT_BUY;
      else if(lastClose > upperBand[0])
         bbState = BB_WAIT_SELL;
   }
   // Once in a waiting state, remain there until a trade signal is generated.
}

//+------------------------------------------------------------------+
//| Get Trade Signal based on Bollinger Reversal State               |
//| If in BB_WAIT_BUY and price returns above the lower band, signal BUY.|
//| If in BB_WAIT_SELL and price returns below the upper band, signal SELL.|
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE GetTradeSignalBB()
{
   ENUM_ORDER_TYPE signal = (ENUM_ORDER_TYPE)-1;
   double lastClose = iClose(_Symbol, _Period, 1);
   
   if(bbState == BB_WAIT_BUY && lastClose > lowerBand[0])
   {
      signal = ORDER_TYPE_BUY;
      bbState = BB_NONE;
   }
   else if(bbState == BB_WAIT_SELL && lastClose < upperBand[0])
   {
      signal = ORDER_TYPE_SELL;
      bbState = BB_NONE;
   }
   return signal;
}

//+------------------------------------------------------------------+
//| Get Daily Bias from previous day's price action                  |
//| Returns 1 for LONG bias, -1 for SHORT bias.                        |
//+------------------------------------------------------------------+
int GetDailyBias()
{
   double dailyOpen = iOpen(_Symbol, PERIOD_D1, 1);
   double dailyClose = iClose(_Symbol, PERIOD_D1, 1);
   return (dailyClose > dailyOpen) ? 1 : -1;
}

//+------------------------------------------------------------------+
//| Check and execute reversal close conditions                      |
//+------------------------------------------------------------------+
void CheckReversalClose()
{
   double highestHigh = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, LookbackPeriod, 2));
   double lowestLow = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, LookbackPeriod, 2));
   double currentClose = iClose(_Symbol, _Period, 1);
   bool buyClose = EnableReversalClose && (currentClose > highestHigh);
   bool sellClose = EnableReversalClose && (currentClose < lowestLow);
   
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         string posSymbol = PositionGetString(POSITION_SYMBOL);
         ulong posMagic = PositionGetInteger(POSITION_MAGIC);
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
//| Manage Trades: Check signal, daily limits, and open trades       |
//+------------------------------------------------------------------+
void ManageTrades()
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   int currentDay = tm.day;
   if(currentDay != lastTradeDay)
   {
      tradesToday = 0;
      lastTradeDay = currentDay;
   }
   
   if(tradesToday >= MaxTradesPerDay)
      return;
   
   if(!AllowMultiplePositions && IsAnyTradeOpen())
      return;
   
   // Get trade signal from Bollinger reversal logic.
   ENUM_ORDER_TYPE signal = GetTradeSignalBB();
   
   // Apply daily bias filter if enabled.
   if(UseDailyBias && signal != (ENUM_ORDER_TYPE)-1)
   {
      int dailyBias = GetDailyBias();
      if((signal == ORDER_TYPE_BUY && dailyBias != 1) ||
         (signal == ORDER_TYPE_SELL && dailyBias != -1))
         signal = (ENUM_ORDER_TYPE)-1;
   }
   
   if(signal != (ENUM_ORDER_TYPE)-1 && IsWithinSession())
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
   int sessionEnd = EndHour * 3600 + EndMinute * 60;
   int currentTime = gmtDateTime.hour * 3600 + gmtDateTime.min * 60;
   return (currentTime >= sessionStart && currentTime < sessionEnd);
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
//| Check and execute partial close if conditions are met            |
//| Using reward multipliers based on risk instead of fixed pips.     |
//+------------------------------------------------------------------+
void CheckAndExecutePartialClose()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(IsTicketPartialClosed(ticket))
            continue;
         
         if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
            PositionGetInteger(POSITION_MAGIC) != MagicNumber)
            continue;
         
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double slPrice = PositionGetDouble(POSITION_SL);
         double risk = MathAbs(openPrice - slPrice);
         
         double currentPrice = iClose(_Symbol, _Period, 0);
         
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double targetPrice, breakevenPrice;
         if(posType == POSITION_TYPE_BUY)
         {
            targetPrice = openPrice + risk * PartialCloseReward;
            breakevenPrice = openPrice + risk * BreakevenReward;
            if(currentPrice >= targetPrice)
            {
               double volumeToClose = NormalizeDouble(PositionGetDouble(POSITION_VOLUME) * (PartialClosePercentage / 100.0), 2);
               if(trade.PositionClosePartial(ticket, volumeToClose))
               {
                  Print("Partial close executed for ticket #", ticket);
                  AddPartialClosedTicket(ticket);
                  if(SetBreakeven)
                  {
                     if(!trade.PositionModify(ticket, breakevenPrice, PositionGetDouble(POSITION_TP)))
                        Print("Error setting new SL after partial close: ", GetLastError());
                  }
               }
               else
                  Print("Error in partial closing: ", GetLastError());
            }
         }
         else if(posType == POSITION_TYPE_SELL)
         {
            targetPrice = openPrice - risk * PartialCloseReward;
            breakevenPrice = openPrice - risk * BreakevenReward;
            if(currentPrice <= targetPrice)
            {
               double volumeToClose = NormalizeDouble(PositionGetDouble(POSITION_VOLUME) * (PartialClosePercentage / 100.0), 2);
               if(trade.PositionClosePartial(ticket, volumeToClose))
               {
                  Print("Partial close executed for ticket #", ticket);
                  AddPartialClosedTicket(ticket);
                  if(SetBreakeven)
                  {
                     if(!trade.PositionModify(ticket, breakevenPrice, PositionGetDouble(POSITION_TP)))
                        Print("Error setting new SL after partial close: ", GetLastError());
                  }
               }
               else
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
   
   double stopLossDistance = atr * ATRSLMultiplier;
   double takeProfitDistance = stopLossDistance * RiskRewardRatio;
   
   double entryPrice, slPrice, tpPrice;
   if(orderType == ORDER_TYPE_BUY)
   {
      entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      slPrice = entryPrice - stopLossDistance;
      tpPrice = entryPrice + takeProfitDistance;
   }
   else if(orderType == ORDER_TYPE_SELL)
   {
      entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      slPrice = entryPrice + stopLossDistance;
      tpPrice = entryPrice - takeProfitDistance;
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
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double riskPerLot = (stopLossDistance / tickSize) * tickValue;
   if(riskPerLot <= 0)
   {
      Print("Invalid risk per lot calculation.");
      return;
   }
   
   double lotSizeCalculated = riskAmount / riskPerLot;
   double volMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotSizeCalculated < volMin)
      lotSizeCalculated = volMin;
   else
      lotSizeCalculated = MathFloor(lotSizeCalculated / volStep) * volStep;
   lotSizeCalculated = NormalizeDouble(lotSizeCalculated, 2);
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSizeCalculated;
   request.type = orderType;
   request.price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                 : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl = slPrice;
   request.tp = tpPrice;
   request.deviation = Slippage;
   request.magic = MagicNumber;
   request.comment = "BB Reversal Trade with ATR Risk Management";
   
   if(!trade.OrderSend(request, result))
      Print("OrderSend failed with error code: ", GetLastError());
   else
      Print("Trade opened with ticket #: ", result.order);
}
