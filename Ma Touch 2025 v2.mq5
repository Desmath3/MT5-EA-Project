//+------------------------------------------------------------------+
//|                                               MA_Touch_2025.mq5  |
//|                        Copyright 2021, [Your Name]               |
//|                        https://www.mql5.com                      |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//====================================================================
// Input Parameters - Strategy, Filters, and Risk Management
//====================================================================
// --- Moving Average Settings ---
input ENUM_MA_METHOD   MA_Method          = MODE_EMA;    // Moving Average method (e.g. EMA)
input int              MA_StartPeriod     = 100;         // Starting period for MA calculation
input int              MA_PeriodStep      = 20;          // Period step between successive MAs
#define NUM_MA 6                                     // Number of MAs to create

// --- Trade Entry Filters ---
// A trade is triggered only if at least one MA is touched by the previous bar.
input bool             EnableReversalExit = true;        // Enable reversal exit logic
input int              LookbackHighLow    = 14;          // Lookback period for reversal high/low

// --- Partial Close & Breakeven Settings ---
input double           PartialClosePct    = 50.0;        // Percentage of the position to close partially
input double           PartialCloseReward = 5.0;         // Partial close trigger level = risk * this multiplier
input bool             EnableBreakeven    = true;        // Enable moving SL to breakeven after partial close
input double           BreakevenReward    = 1.0;         // Breakeven level = risk * this multiplier

// --- Session Filter Inputs ---
input bool             TradeNewYork       = true;        // New York session: 13:00 - 22:00 GMT
input bool             TradeLondon        = true;        // London session: 08:00 - 17:00 GMT
input bool             TradeTokyo         = false;       // Tokyo session: 00:00 - 09:00 GMT
input bool             TradeSydney        = false;       // Sydney session: 22:00 - 07:00 GMT

// --- Daily Filters ---
input bool             UseDailyBias       = false;       // Only take trades in direction of yesterday's bias
input int              MaxTradesPerDay    = 5;           // Maximum trades allowed per day
input bool             AllowMultiplePos   = false;       // If false, only one trade may be open at a time

// --- ATR-Based Risk Management ---
input int              ATR_Period         = 14;          // ATR period
input double           ATR_SL_Multiplier  = 2.0;         // Stop loss distance = ATR * multiplier
input double           RiskRewardRatio    = 10.0;        // Target = risk * this multiplier
input double           FixedRiskPerTrade  = 50.0;        // Fixed risk per trade in USD
input bool             UsePercentRisk     = false;       // If true, risk is calculated as a percentage of account balance
input double           RiskPercentage     = 1.0;         // Risk percentage (if UsePercentRisk is true)

// --- Other Trade Settings ---
input int              AllowedSlippage    = 3;           // Slippage (in points)
input ulong            EA_MagicNumber     = 123456;      // Unique identifier for the EA's orders

// --- Bollinger Bands Settings (for additional filtering/trend) ---
input int              BB_Period          = 100;         // Bollinger Bands period
input double           BB_Deviation       = 2.0;         // Bollinger Bands deviation

//====================================================================
// Class Definition: CMaRibbonEA
//====================================================================
class CMaRibbonEA
  {
private:
   // --- Instance copies of the input parameters ---
   // Moving Averages
   ENUM_MA_METHOD  m_MAMethod;
   int             m_MAStartPeriod;
   int             m_MAPeriodStep;
   int             m_NumMAs;
   
   // Trade Entry Filters (MA Touch Only)
   bool            m_EnableReversalExit;
   int             m_LookbackHL;
   
   // Partial Close & Breakeven Settings
   double          m_PartialClosePct;
   double          m_PartialCloseReward;
   bool            m_EnableBreakeven;
   double          m_BreakevenReward;
   
   // Daily Filters
   bool            m_UseDailyBias;
   int             m_MaxTradesPerDay;
   bool            m_AllowMultiplePos;
   
   // ATR Risk Management
   int             m_ATRPeriod;
   double          m_ATRSLMultiplier;
   double          m_RiskRewardRatio;
   double          m_FixedRiskPerTrade;
   bool            m_UsePercentRisk;
   double          m_RiskPercentage;
   
   // Other Trade Settings
   int             m_AllowedSlippage;
   ulong           m_EAMagicNumber;
   
   // Bollinger Bands Settings
   int             m_BBPeriod;
   double          m_BBDeviation;
   
   // --- Session Filter Booleans (new inputs) ---
   bool            m_TradeNewYork;
   bool            m_TradeLondon;
   bool            m_TradeTokyo;
   bool            m_TradeSydney;
   
   // --- Instance-specific state variables ---
   // Moving Average indicator handles
   int             m_MAHandles[NUM_MA];
   // Bollinger Bands handle and buffers
   int             m_BBHandle;
   double          m_BBUpper[1], m_BBLower[1];
   // ATR indicator handle
   int             m_ATRHandle;
   
   // Persistent trend direction: LONG = 1, SHORT = -1, NONE = 0.
   enum TradeDir { LONG = 1, NONE = 0, SHORT = -1 };
   TradeDir        m_TrendDir;
   
   // Daily trade management
   int             m_TradesToday;
   int             m_LastTradeDay;
   datetime        m_LastBarTime;
   
   // Partial close tracking array (tickets already partially closed)
   ulong           m_PartialClosedTickets[];
   
   // Trade object for order management
   CTrade          m_Trade;
   
   //--- Helper: Calculate the distance (in pips) from current price to a given MA.
   double CalculateMADistance(int maHandle, string symbol, ENUM_TIMEFRAMES period)
     {
      double arr[1];
      if(CopyBuffer(maHandle, 0, 0, 1, arr) <= 0)
      {
         Print("Failed to copy data for MA handle: ", maHandle);
         return -1;
      }
      double currPrice = iClose(symbol, period, 0);
      double distance = MathAbs(currPrice - arr[0]);
      // Convert to pips (assumes 4 or 5-digit pricing)
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      if(digits == 5 || digits == 3)
         distance /= 0.0001;
      else if(digits == 4 || digits == 2)
         distance /= 0.01;
      return distance;
     }
     
   //--- Check if at least one MA is touched by the previous bar.
   // "Touch" means the previous bar's range (low to high) includes the MA value.
   bool IsMATouched()
     {
      double maValue[1];
      double barHigh = iHigh(_Symbol, _Period, 1);
      double barLow  = iLow(_Symbol, _Period, 1);
      for(int i = 0; i < m_NumMAs; i++)
      {
         if(CopyBuffer(m_MAHandles[i], 0, 1, 1, maValue) <= 0)
         {
            Print("Failed to copy data for MA handle: ", m_MAHandles[i]);
            continue;
         }
         if(barLow <= maValue[0] && maValue[0] <= barHigh)
            return true;
      }
      return false;
     }
     
   //--- New Session Filter: Check if current GMT time is within any enabled session.
   bool IsWithinSessionNew()
     {
      // Get current GMT time
      datetime currentTime = TimeGMT();
      MqlDateTime dt;
      TimeToStruct(currentTime, dt);
      int curTimeInMinutes = dt.hour * 60 + dt.min;
      
      bool inSession = false;
      // New York session: 13:00 - 22:00 GMT
      if(m_TradeNewYork)
      {
         if(curTimeInMinutes >= 12 * 60 && curTimeInMinutes < 21 * 60)
            inSession = true;
      }
      // London session: 08:00 - 17:00 GMT
      if(m_TradeLondon)
      {
         if(curTimeInMinutes >= 7 * 60 && curTimeInMinutes < 12 * 60)
            inSession = true;
      }
      // Tokyo session: 00:00 - 09:00 GMT
      if(m_TradeTokyo)
      {
         if(curTimeInMinutes >= 0 && curTimeInMinutes < 7 * 60)
            inSession = true;
      }
      // Sydney session: 22:00 - 07:00 GMT (spans midnight)
      if(m_TradeSydney)
      {
         if(curTimeInMinutes >= 21 * 60 || curTimeInMinutes < 0 * 60)
            inSession = true;
      }
      return inSession;
     }
     
public:
   // Constructor: initialize instance members using the global inputs
   CMaRibbonEA()
     {
      m_MAMethod           = MA_Method;
      m_MAStartPeriod      = MA_StartPeriod;
      m_MAPeriodStep       = MA_PeriodStep;
      m_NumMAs             = NUM_MA;
      
      m_EnableReversalExit = EnableReversalExit;
      m_LookbackHL         = LookbackHighLow;
      
      m_PartialClosePct    = PartialClosePct;
      m_PartialCloseReward = PartialCloseReward;
      m_EnableBreakeven    = EnableBreakeven;
      m_BreakevenReward    = BreakevenReward;
      
      // Set session filter booleans from new inputs
      m_TradeNewYork       = TradeNewYork;
      m_TradeLondon        = TradeLondon;
      m_TradeTokyo         = TradeTokyo;
      m_TradeSydney        = TradeSydney;
      
      m_UseDailyBias       = UseDailyBias;
      m_MaxTradesPerDay    = MaxTradesPerDay;
      m_AllowMultiplePos   = AllowMultiplePos;
      
      m_ATRPeriod          = ATR_Period;
      m_ATRSLMultiplier    = ATR_SL_Multiplier;
      m_RiskRewardRatio    = RiskRewardRatio;
      m_FixedRiskPerTrade  = FixedRiskPerTrade;
      m_UsePercentRisk     = UsePercentRisk;
      m_RiskPercentage     = RiskPercentage;
      
      m_AllowedSlippage    = AllowedSlippage;
      m_EAMagicNumber      = EA_MagicNumber;
      
      m_BBPeriod           = BB_Period;
      m_BBDeviation        = BB_Deviation;
      
      m_TrendDir           = NONE;
      m_TradesToday        = 0;
      m_LastTradeDay       = 0;
      m_LastBarTime        = 0;
      ArrayResize(m_PartialClosedTickets, 0);
     }
     
   //--- Initialization: Create all indicators (MAs, Bollinger Bands, ATR)
   void InitializeIndicators()
     {
      for(int i = 0; i < m_NumMAs; i++)
      {
         int period = m_MAStartPeriod + i * m_MAPeriodStep;
         m_MAHandles[i] = iMA(_Symbol, _Period, period, 0, m_MAMethod, PRICE_CLOSE);
         if(m_MAHandles[i] == INVALID_HANDLE)
         {
            Print("Failed to initialize MA indicator with period ", period);
            return;
         }
      }
      m_BBHandle = iBands(_Symbol, _Period, m_BBPeriod, 0, m_BBDeviation, PRICE_CLOSE);
      if(m_BBHandle == INVALID_HANDLE)
         Print("Failed to initialize Bollinger Bands indicator.");
      m_ATRHandle = iATR(_Symbol, _Period, m_ATRPeriod);
      if(m_ATRHandle == INVALID_HANDLE)
         Print("Failed to initialize ATR indicator.");
     }
     
   //--- Update the persistent trend direction based on Bollinger Bands
   void UpdateTrendDirection()
     {
      double lastClose = iClose(_Symbol, _Period, 1);
      if(CopyBuffer(m_BBHandle, 1, 0, 1, m_BBUpper) <= 0)
         Print("Error copying upper Bollinger Band data in UpdateTrendDirection.");
      if(CopyBuffer(m_BBHandle, 2, 0, 1, m_BBLower) <= 0)
         Print("Error copying lower Bollinger Band data in UpdateTrendDirection.");
      
      if(m_TrendDir == NONE)
      {
         if(lastClose > m_BBUpper[0])
            m_TrendDir = LONG;
         else if(lastClose < m_BBLower[0])
            m_TrendDir = SHORT;
      }
      else if(m_TrendDir == LONG)
      {
         if(lastClose < m_BBLower[0])
            m_TrendDir = SHORT;
      }
      else if(m_TrendDir == SHORT)
      {
         if(lastClose > m_BBUpper[0])
            m_TrendDir = LONG;
      }
     }
     
   //--- Generate a trade signal based on the persistent trend and MA touch
   ENUM_ORDER_TYPE GetTradeSignal()
     {
      ENUM_ORDER_TYPE signal = (ENUM_ORDER_TYPE)-1;
      
      if(m_TrendDir == LONG && !IsBelowAllMAs() && IsMATouched())
         signal = ORDER_TYPE_BUY;
      else if(m_TrendDir == SHORT && !IsAboveAllMAs() && IsMATouched())
         signal = ORDER_TYPE_SELL;
      
      if(m_UseDailyBias && signal != (ENUM_ORDER_TYPE)-1)
      {
         TradeDir dailyBias = GetDailyBias();
         if(dailyBias != m_TrendDir)
            signal = (ENUM_ORDER_TYPE)-1;
      }
      
      return signal;
     }
     
   //--- Get daily bias from previous day's price action
   TradeDir GetDailyBias()
     {
      double dOpen  = iOpen(_Symbol, PERIOD_D1, 1);
      double dClose = iClose(_Symbol, PERIOD_D1, 1);
      return (dClose > dOpen) ? LONG : SHORT;
     }
     
   //--- Check reversal exit conditions using lookback high/low
   void CheckReversalExit()
     {
      double highestHigh = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, m_LookbackHL, 2));
      double lowestLow   = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, m_LookbackHL, 2));
      double currentClose= iClose(_Symbol, _Period, 1);
      bool closeBuy  = m_EnableReversalExit && (currentClose > highestHigh);
      bool closeSell = m_EnableReversalExit && (currentClose < lowestLow);
      
      for(int i = PositionsTotal()-1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
         {
            string sym = PositionGetString(POSITION_SYMBOL);
            ulong magic = PositionGetInteger(POSITION_MAGIC);
            if(sym != _Symbol || magic != m_EAMagicNumber)
               continue;
               
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            if(closeBuy && posType == POSITION_TYPE_SELL)
            {
               Print("Closing SELL position due to reversal buy signal.");
               if(!m_Trade.PositionClose(ticket))
                  Print("Error closing SELL position: ", GetLastError());
            }
            else if(closeSell && posType == POSITION_TYPE_BUY)
            {
               Print("Closing BUY position due to reversal sell signal.");
               if(!m_Trade.PositionClose(ticket))
                  Print("Error closing BUY position: ", GetLastError());
            }
         }
      }
     }
     
   //--- Check if any trade is already open by this EA on the current symbol
   bool IsAnyTradeOpen()
     {
      for(int i = PositionsTotal()-1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
         {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == m_EAMagicNumber)
               return true;
         }
      }
      return false;
     }
     
   //--- Manage trade entries: signal, daily limits, and session times
   void ManageTrades()
     {
      MqlDateTime tm;
      TimeToStruct(TimeCurrent(), tm);
      int currDay = tm.day;
      if(currDay != m_LastTradeDay)
      {
         m_TradesToday = 0;
         m_LastTradeDay = currDay;
      }
      
      if(m_TradesToday >= m_MaxTradesPerDay)
         return;
      
      if(!m_AllowMultiplePos && IsAnyTradeOpen())
         return;
      
      ENUM_ORDER_TYPE signal = GetTradeSignal();
      
      if(IsWithinSessionNew())
      {
         if(signal == ORDER_TYPE_BUY && !IsAlreadyBought())
         {
            OpenTrade(ORDER_TYPE_BUY);
            m_TradesToday++;
         }
         else if(signal == ORDER_TYPE_SELL && !IsAlreadySold())
         {
            OpenTrade(ORDER_TYPE_SELL);
            m_TradesToday++;
         }
      }
     }
     
     
   //--- Check if price is above all moving averages
   bool IsAboveAllMAs()
     {
      double buf[1];
      for(int i = 0; i < m_NumMAs; i++)
      {
         if(CopyBuffer(m_MAHandles[i], 0, 1, 1, buf) > 0)
         {
            if(iClose(_Symbol, _Period, 1) <= buf[0])
               return false;
         }
         else
         {
            Print("Failed to copy data for MA handle: ", m_MAHandles[i]);
            return false;
         }
      }
      return true;
     }
     
   //--- Check if price is below all moving averages
   bool IsBelowAllMAs()
     {
      double buf[1];
      for(int i = 0; i < m_NumMAs; i++)
      {
         if(CopyBuffer(m_MAHandles[i], 0, 1, 1, buf) > 0)
         {
            if(iClose(_Symbol, _Period, 1) >= buf[0])
               return false;
         }
         else
         {
            Print("Failed to copy data for MA handle: ", m_MAHandles[i]);
            return false;
         }
      }
      return true;
     }
     
   //--- Check for an existing BUY position from this EA
   bool IsAlreadyBought()
     {
      for(int i = PositionsTotal()-1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
         {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == m_EAMagicNumber &&
               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               return true;
         }
      }
      return false;
     }
     
   //--- Check for an existing SELL position from this EA
   bool IsAlreadySold()
     {
      for(int i = PositionsTotal()-1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
         {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
               PositionGetInteger(POSITION_MAGIC) == m_EAMagicNumber &&
               PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
               return true;
         }
      }
      return false;
     }
     
   //--- Helper: Check if a ticket has already been partially closed
   bool IsTicketPartialClosed(ulong ticket)
     {
      for(int i = 0; i < ArraySize(m_PartialClosedTickets); i++)
         if(m_PartialClosedTickets[i] == ticket)
            return true;
      return false;
     }
     
   //--- Helper: Add a ticket to the partial close tracking array
   void AddPartialClosedTicket(ulong ticket)
     {
      int pos = ArraySize(m_PartialClosedTickets);
      ArrayResize(m_PartialClosedTickets, pos + 1);
      m_PartialClosedTickets[pos] = ticket;
     }
     
   //--- Check and execute partial close if reward target is met.
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
               PositionGetInteger(POSITION_MAGIC) != m_EAMagicNumber)
               continue;
               
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double slPrice   = PositionGetDouble(POSITION_SL);
            double risk      = MathAbs(openPrice - slPrice);
            double currPrice = iClose(_Symbol, _Period, 0);
            
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double targetPrice, breakevenPrice;
            if(posType == POSITION_TYPE_BUY)
            {
               targetPrice = openPrice + risk * m_PartialCloseReward;
               breakevenPrice = openPrice + risk * m_BreakevenReward;
               if(currPrice >= targetPrice)
               {
                  double volumeToClose = NormalizeDouble(PositionGetDouble(POSITION_VOLUME) * (m_PartialClosePct / 100.0), 2);
                  if(m_Trade.PositionClosePartial(ticket, volumeToClose))
                  {
                     Print("Partial close executed for ticket #", ticket);
                     AddPartialClosedTicket(ticket);
                     if(m_EnableBreakeven)
                     {
                        if(!m_Trade.PositionModify(ticket, breakevenPrice, PositionGetDouble(POSITION_TP)))
                           Print("Error setting new SL after partial close: ", GetLastError());
                     }
                  }
                  else
                  {
                     Print("Error in partial closing: ", GetLastError());
                  }
               }
            }
            else if(posType == POSITION_TYPE_SELL)
            {
               targetPrice = openPrice - risk * m_PartialCloseReward;
               breakevenPrice = openPrice - risk * m_BreakevenReward;
               if(currPrice <= targetPrice)
               {
                  double volumeToClose = NormalizeDouble(PositionGetDouble(POSITION_VOLUME) * (m_PartialClosePct / 100.0), 2);
                  if(m_Trade.PositionClosePartial(ticket, volumeToClose))
                  {
                     Print("Partial close executed for ticket #", ticket);
                     AddPartialClosedTicket(ticket);
                     if(m_EnableBreakeven)
                     {
                        if(!m_Trade.PositionModify(ticket, breakevenPrice, PositionGetDouble(POSITION_TP)))
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
     }
     
   //--- Open a new trade using ATR-based risk management
   void OpenTrade(ENUM_ORDER_TYPE orderType)
     {
      double atrVal[1];
      if(CopyBuffer(m_ATRHandle, 0, 1, 1, atrVal) <= 0)
      {
         Print("Failed to retrieve ATR value.");
         return;
      }
      double atr = atrVal[0];
      double stopLossDist   = atr * m_ATRSLMultiplier;
      double takeProfitDist = stopLossDist * m_RiskRewardRatio;
      
      double entryPrice, slPrice, tpPrice;
      if(orderType == ORDER_TYPE_BUY)
      {
         entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         slPrice = entryPrice - stopLossDist;
         tpPrice = entryPrice + takeProfitDist;
      }
      else if(orderType == ORDER_TYPE_SELL)
      {
         entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         slPrice = entryPrice + stopLossDist;
         tpPrice = entryPrice - takeProfitDist;
      }
      else
      {
         Print("Invalid order type encountered in OpenTrade().");
         return;
      }
      
      double riskAmount = m_UsePercentRisk ? AccountInfoDouble(ACCOUNT_BALANCE) * m_RiskPercentage / 100.0 : m_FixedRiskPerTrade;
      double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double riskPerLot = (stopLossDist / tickSize) * tickVal;
      if(riskPerLot <= 0)
      {
         Print("Invalid risk per lot calculation.");
         return;
      }
      
      double lotSize = riskAmount / riskPerLot;
      double volMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(lotSize < volMin)
         lotSize = volMin;
      else
         lotSize = MathFloor(lotSize / volStep) * volStep;
      lotSize = NormalizeDouble(lotSize, 2);
      
      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};
      
      request.action    = TRADE_ACTION_DEAL;
      request.symbol    = _Symbol;
      request.volume    = lotSize;
      request.type      = orderType;
      request.price     = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                                        : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      request.sl        = slPrice;
      request.tp        = tpPrice;
      request.deviation = m_AllowedSlippage;
      request.magic     = m_EAMagicNumber;
      request.comment   = "MA Ribbon Trade with ATR Risk Management";
      
      if(!m_Trade.OrderSend(request, result))
         Print("OrderSend failed with error code: ", GetLastError());
      else
         Print("Trade opened with ticket #: ", result.order);
     }
     
   //--- Main OnTick processing for this EA instance
   void OnTick()
     {
      datetime currBarTime = iTime(_Symbol, _Period, 0);
      if(currBarTime != m_LastBarTime)
      {
         UpdateTrendDirection();
         ManageTrades();
         m_LastBarTime = currBarTime;
      }
      CheckAndExecutePartialClose();
      CheckReversalExit();
     }
  };

//+------------------------------------------------------------------+
//| Global instance of CMaRibbonEA (one instance per chart)          |
//+------------------------------------------------------------------+
CMaRibbonEA maRibbonInstance;

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
   maRibbonInstance.InitializeIndicators();
   return(INIT_SUCCEEDED);
  }
  
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   maRibbonInstance.OnTick();
  }
