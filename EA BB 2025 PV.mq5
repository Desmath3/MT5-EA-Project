//+------------------------------------------------------------------+
//|                                              BB_ReversalEA.mq5   |
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
input int           BollingerPeriod       = 100;         // Bollinger Bands period
input double        BollingerDeviation    = 2.0;         // Bollinger Bands deviation

// ATR-based risk management parameters
input int           ATRPeriod             = 14;          // ATR period
input double        ATRSLMultiplier       = 2.0;         // Stop loss = ATRSLMultiplier * ATR
input double        RiskRewardRatio       = 10.0;        // Final target = Entry ± (risk * RiskRewardRatio)
input double        RiskPerTrade          = 50.0;        // Fixed risk per trade in USD
input bool          UsePercentageRisk     = false;       // If true, risk is calculated as a percentage of account balance
input double        RiskPercentage        = 1.0;         // Risk percentage (if above is true)

// Reward-based partial close & breakeven parameters (multiples of risk)
input double        PartialCloseReward    = 5.0;         // Partial close level = risk * 5.0
input bool          SetBreakeven          = true;        // Enable setting breakeven after partial close
input double        BreakevenReward       = 1.0;         // Breakeven level = risk * 1.0
input double        PartialClosePercentage= 50.0;        // Percentage of the position to close
input bool          EnableReversalClose   = true;        // Enable reversal close logic
input int           LookbackPeriod        = 14;          // Lookback period for high and low

// Daily bias and trade management
input bool          UseDailyBias          = false;       // If true, only trade in the direction of yesterday's bias
input int           MaxTradesPerDay       = 5;           // Maximum trades allowed per day
input bool          AllowMultiplePositions= false;       // When false, only one trade may be open at a time

//+------------------------------------------------------------------+
//|                      CBBReversalEA Class                         |
//+------------------------------------------------------------------+
class CBBReversalEA
  {
private:
   // Instance-specific copies of input parameters:
   int           m_Slippage;
   ulong         m_MagicNumber;
   int           m_StartHour, m_StartMinute, m_EndHour, m_EndMinute;
   int           m_BrokerGMTOffset;
   
   int           m_BollingerPeriod;
   double        m_BollingerDeviation;
   
   int           m_ATRPeriod;
   double        m_ATRSLMultiplier;
   double        m_RiskRewardRatio;
   double        m_RiskPerTrade;
   bool          m_UsePercentageRisk;
   double        m_RiskPercentage;
   
   double        m_PartialCloseReward;
   bool          m_SetBreakeven;
   double        m_BreakevenReward;
   double        m_PartialClosePercentage;
   bool          m_EnableReversalClose;
   int           m_LookbackPeriod;
   
   bool          m_UseDailyBias;
   int           m_MaxTradesPerDay;
   bool          m_AllowMultiplePositions;
   
   // Instance-specific state variables:
   enum BBState { BB_NONE, BB_WAIT_BUY, BB_WAIT_SELL } m_bbState;
   int           m_tradesToday;
   int           m_lastTradeDay;
   datetime      m_lastBarTime;
   ulong         m_partialClosedTickets[];
   
   // Indicator handles and buffers:
   int           m_BandHandle;
   double        m_upperBand[1];
   double        m_lowerBand[1];
   int           m_ATRHandle;
   
   // Trade object:
   CTrade        m_trade;
   
public:
   // Constructor: initialize instance members using the global inputs
   CBBReversalEA()
     {
      m_Slippage              = Slippage;
      m_MagicNumber           = MagicNumber;
      m_StartHour             = StartHour;
      m_StartMinute           = StartMinute;
      m_EndHour               = EndHour;
      m_EndMinute             = EndMinute;
      m_BrokerGMTOffset       = BrokerGMTOffset;
      
      m_BollingerPeriod       = BollingerPeriod;
      m_BollingerDeviation    = BollingerDeviation;
      
      m_ATRPeriod             = ATRPeriod;
      m_ATRSLMultiplier       = ATRSLMultiplier;
      m_RiskRewardRatio       = RiskRewardRatio;
      m_RiskPerTrade          = RiskPerTrade;
      m_UsePercentageRisk     = UsePercentageRisk;
      m_RiskPercentage        = RiskPercentage;
      
      m_PartialCloseReward    = PartialCloseReward;
      m_SetBreakeven          = SetBreakeven;
      m_BreakevenReward       = BreakevenReward;
      m_PartialClosePercentage= PartialClosePercentage;
      m_EnableReversalClose   = EnableReversalClose;
      m_LookbackPeriod        = LookbackPeriod;
      
      m_UseDailyBias          = UseDailyBias;
      m_MaxTradesPerDay       = MaxTradesPerDay;
      m_AllowMultiplePositions= AllowMultiplePositions;
      
      // Initialize state
      m_bbState    = BB_NONE;
      m_tradesToday= 0;
      m_lastTradeDay = 0;
      m_lastBarTime  = 0;
      ArrayResize(m_partialClosedTickets, 0);
     }
     
   // Initialize the indicators: Bollinger Bands and ATR
   void InitializeIndicators()
     {
      m_BandHandle = iBands(_Symbol, _Period, m_BollingerPeriod, 0, m_BollingerDeviation, PRICE_CLOSE);
      if(m_BandHandle == INVALID_HANDLE)
         Print("Failed to get handle for Bollinger Bands.");
      
      m_ATRHandle = iATR(_Symbol, _Period, m_ATRPeriod);
      if(m_ATRHandle == INVALID_HANDLE)
         Print("Failed to initialize ATR indicator.");
     }
     
   // Update Bollinger reversal state:
   // If no state is active, set state based on whether the previous bar's close is below
   // the lower band (wait for BUY) or above the upper band (wait for SELL).
   void UpdateBBState()
     {
      double lastClose = iClose(_Symbol, _Period, 1);
      if(CopyBuffer(m_BandHandle, 1, 0, 1, m_upperBand) <= 0)
         Print("Error copying upper band data in UpdateBBState.");
      if(CopyBuffer(m_BandHandle, 2, 0, 1, m_lowerBand) <= 0)
         Print("Error copying lower band data in UpdateBBState.");
      
      if(m_bbState == BB_NONE)
        {
         if(lastClose < m_lowerBand[0])
            m_bbState = BB_WAIT_BUY;
         else if(lastClose > m_upperBand[0])
            m_bbState = BB_WAIT_SELL;
        }
     }
     
   // Generate a trade signal based on the Bollinger reversal state.
   // When the waiting condition is satisfied (price reverses back), return the signal.
   ENUM_ORDER_TYPE GetTradeSignalBB()
     {
      ENUM_ORDER_TYPE signal = (ENUM_ORDER_TYPE)-1;
      double lastClose = iClose(_Symbol, _Period, 1);
      
      if(m_bbState == BB_WAIT_BUY && lastClose > m_lowerBand[0])
        {
         signal = ORDER_TYPE_BUY;
         m_bbState = BB_NONE;
        }
      else if(m_bbState == BB_WAIT_SELL && lastClose < m_upperBand[0])
        {
         signal = ORDER_TYPE_SELL;
         m_bbState = BB_NONE;
        }
      
      return signal;
     }
     
   // Determine the daily bias from the previous day's price action.
   // Returns 1 for a long bias (close > open) or -1 for a short bias.
   int GetDailyBias()
     {
      double dailyOpen = iOpen(_Symbol, PERIOD_D1, 1);
      double dailyClose = iClose(_Symbol, PERIOD_D1, 1);
      return (dailyClose > dailyOpen) ? 1 : -1;
     }
     
   // Check and execute reversal close conditions.
   // If the current price reverses beyond the highest high or lowest low over the lookback period,
   // close positions in the opposite direction.
   void CheckReversalClose()
     {
      double highestHigh = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, m_LookbackPeriod, 2));
      double lowestLow = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, m_LookbackPeriod, 2));
      double currentClose = iClose(_Symbol, _Period, 1);
      bool buyClose = m_EnableReversalClose && (currentClose > highestHigh);
      bool sellClose = m_EnableReversalClose && (currentClose < lowestLow);
      
      for(int i = PositionsTotal()-1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
           {
            string posSymbol = PositionGetString(POSITION_SYMBOL);
            ulong posMagic = PositionGetInteger(POSITION_MAGIC);
            if(posSymbol != _Symbol || posMagic != m_MagicNumber)
               continue;
            
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            if(buyClose && posType == POSITION_TYPE_SELL)
              {
               Print("Closing SELL position due to reversal buy signal.");
               if(!m_trade.PositionClose(ticket))
                  Print("Error closing SELL position: ", GetLastError());
              }
            else if(sellClose && posType == POSITION_TYPE_BUY)
              {
               Print("Closing BUY position due to reversal sell signal.");
               if(!m_trade.PositionClose(ticket))
                  Print("Error closing BUY position: ", GetLastError());
              }
           }
        }
     }
     
   // Check if any trade is already open for this symbol and EA instance.
   bool IsAnyTradeOpen()
     {
      for(int i = PositionsTotal()-1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
           {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == m_MagicNumber)
               return true;
           }
        }
      return false;
     }
     
   // Manage trades: check for valid signals, enforce daily limits,
   // and open trades when conditions are met.
   void ManageTrades()
     {
      MqlDateTime tm;
      TimeToStruct(TimeCurrent(), tm);
      int currentDay = tm.day;
      if(currentDay != m_lastTradeDay)
        {
         m_tradesToday = 0;
         m_lastTradeDay = currentDay;
        }
      
      if(m_tradesToday >= m_MaxTradesPerDay)
         return;
      
      if(!m_AllowMultiplePositions && IsAnyTradeOpen())
         return;
      
      // Get the trade signal from Bollinger reversal logic.
      ENUM_ORDER_TYPE signal = GetTradeSignalBB();
      
      // Apply daily bias filter if enabled.
      if(m_UseDailyBias && signal != (ENUM_ORDER_TYPE)-1)
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
            m_tradesToday++;
           }
         else if(signal == ORDER_TYPE_SELL && !IsAlreadySold())
           {
            OpenTrade(ORDER_TYPE_SELL);
            m_tradesToday++;
           }
        }
     }
     
   // Check if current time is within the allowed trading session.
   bool IsWithinSession()
     {
      datetime serverTime = TimeCurrent();
      datetime gmtTime = serverTime - m_BrokerGMTOffset * 3600;
      MqlDateTime gmtDateTime;
      TimeToStruct(gmtTime, gmtDateTime);
      int sessionStart = m_StartHour * 3600 + m_StartMinute * 60;
      int sessionEnd   = m_EndHour * 3600 + m_EndMinute * 60;
      int currentTime  = gmtDateTime.hour * 3600 + gmtDateTime.min * 60;
      return (currentTime >= sessionStart && currentTime < sessionEnd);
     }
     
   // Check for an existing BUY position.
   bool IsAlreadyBought()
     {
      for(int i = PositionsTotal()-1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
           {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == m_MagicNumber &&
               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               return true;
           }
        }
      return false;
     }
     
   // Check for an existing SELL position.
   bool IsAlreadySold()
     {
      for(int i = PositionsTotal()-1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
           {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == m_MagicNumber &&
               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
               return true;
           }
        }
      return false;
     }
     
   // Helper function: check if a ticket has already been partially closed.
   bool IsTicketPartialClosed(ulong ticket)
     {
      for(int i = 0; i < ArraySize(m_partialClosedTickets); i++)
         if(m_partialClosedTickets[i] == ticket)
            return true;
      return false;
     }
     
   // Helper function: add a ticket to the partial close tracking array.
   void AddPartialClosedTicket(ulong ticket)
     {
      int pos = ArraySize(m_partialClosedTickets);
      ArrayResize(m_partialClosedTickets, pos+1);
      m_partialClosedTickets[pos] = ticket;
     }
     
   // Check and execute a partial close if the reward target is met.
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
               PositionGetInteger(POSITION_MAGIC) != m_MagicNumber)
               continue;
            
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double slPrice   = PositionGetDouble(POSITION_SL);
            double risk      = MathAbs(openPrice - slPrice);
            double currentPrice = iClose(_Symbol, _Period, 0);
            
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double targetPrice, breakevenPrice;
            if(posType == POSITION_TYPE_BUY)
              {
               targetPrice = openPrice + risk * m_PartialCloseReward;
               breakevenPrice = openPrice + risk * m_BreakevenReward;
               if(currentPrice >= targetPrice)
                 {
                  double volumeToClose = NormalizeDouble(PositionGetDouble(POSITION_VOLUME) * (m_PartialClosePercentage / 100.0), 2);
                  if(m_trade.PositionClosePartial(ticket, volumeToClose))
                    {
                     Print("Partial close executed for ticket #", ticket);
                     AddPartialClosedTicket(ticket);
                     if(m_SetBreakeven)
                       {
                        if(!m_trade.PositionModify(ticket, breakevenPrice, PositionGetDouble(POSITION_TP)))
                           Print("Error setting new SL after partial close: ", GetLastError());
                       }
                    }
                  else
                     Print("Error in partial closing: ", GetLastError());
                 }
              }
            else if(posType == POSITION_TYPE_SELL)
              {
               targetPrice = openPrice - risk * m_PartialCloseReward;
               breakevenPrice = openPrice - risk * m_BreakevenReward;
               if(currentPrice <= targetPrice)
                 {
                  double volumeToClose = NormalizeDouble(PositionGetDouble(POSITION_VOLUME) * (m_PartialClosePercentage / 100.0), 2);
                  if(m_trade.PositionClosePartial(ticket, volumeToClose))
                    {
                     Print("Partial close executed for ticket #", ticket);
                     AddPartialClosedTicket(ticket);
                     if(m_SetBreakeven)
                       {
                        if(!m_trade.PositionModify(ticket, breakevenPrice, PositionGetDouble(POSITION_TP)))
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
     
   // Open a new trade based on ATR risk management calculations.
   void OpenTrade(ENUM_ORDER_TYPE orderType)
     {
      double atrValue[1];
      if(CopyBuffer(m_ATRHandle, 0, 1, 1, atrValue) <= 0)
        {
         Print("Failed to get ATR value.");
         return;
        }
      double atr = atrValue[0];
      double stopLossDistance  = atr * m_ATRSLMultiplier;
      double takeProfitDistance= stopLossDistance * m_RiskRewardRatio;
      
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
      
      double riskAmount = m_UsePercentageRisk ? AccountInfoDouble(ACCOUNT_BALANCE) * m_RiskPercentage / 100.0 : m_RiskPerTrade;
      double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
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
      request.price     = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      request.sl        = slPrice;
      request.tp        = tpPrice;
      request.deviation = m_Slippage;
      request.magic     = m_MagicNumber;
      request.comment   = "BB Reversal Trade with ATR Risk Management";
      
      if(!m_trade.OrderSend(request, result))
         Print("OrderSend failed with error code: ", GetLastError());
      else
         Print("Trade opened with ticket #: ", result.order);
     }
     
   // The main OnTick method for this instance.
   void OnTick()
     {
      datetime currentBarTime = iTime(_Symbol, _Period, 0);
      if(currentBarTime != m_lastBarTime)
        {
         UpdateBBState();
         ManageTrades();
         m_lastBarTime = currentBarTime;
        }
      CheckAndExecutePartialClose();
      CheckReversalClose();
     }
  };

//+------------------------------------------------------------------+
//| Global instance of the EA class (one per chart instance)         |
//+------------------------------------------------------------------+
CBBReversalEA eaInstance;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
             // Expiration date: May 31, 2025 23:59:59 GMT
   datetime ExpirationDate = StringToTime("2025.05.31 23:59:59");
   if(TimeCurrent() > ExpirationDate)
   {
      Print("EA expired. This EA is no longer active. Contact +2349078065153");
      return(INIT_FAILED);
   }
   eaInstance.InitializeIndicators();
   return(INIT_SUCCEEDED);
  }
  
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   eaInstance.OnTick();
  }
