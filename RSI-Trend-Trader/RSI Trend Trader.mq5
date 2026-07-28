//+------------------------------------------------------------------+
//|                                              RSI_ReversalEA.mq5  |
//|                        Copyright 2025, [Your Name]               |
//|                        https://www.mql5.com                      |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//------------------ Session Filter Inputs --------------------------
input bool TradeNewYork           = true;    // Trade New York session
input bool TradeLondon            = true;    // Trade London session
input bool TradeTokyo             = false;   // Trade Tokyo session
input bool TradeSydney            = false;   // Trade Sydney session

//------------------ RSI Settings -----------------------------------
input int  RSIPeriod              = 14;      // RSI Period
input int  RSI_UpperLevel         = 80;      // RSI Upper Level
input int  RSI_LowerLevel         = 20;      // RSI Lower Level

//------------------ Basic Risk Management & Trade Settings ---------
input int    ATR_Period           = 14;      // ATR Period
input double ATR_SL_Multiplier    = 2.0;     // ATR Multiplier for Stop Loss
input double RiskRewardRatio      = 10.0;    // Risk-Reward Ratio
input double FixedRiskPerTrade    = 50.0;    // Fixed Risk per Trade ($)
input bool   UsePercentRisk       = false;   // Use Percent Risk
input double RiskPercentage       = 1.0;     // Risk Percentage (%)
input int    AllowedSlippage      = 3;       // Allowed Slippage (points)
input bool   UseDailyBias         = false;   // Use Daily Bias Filter
input int    MaxTradesPerDay      = 5;       // Max Trades per Day
input ulong  EA_MagicNumber       = 123456;  // EA Magic Number

//------------------ Additional Trade Management Settings ----------
input bool   EnableBreakeven      = true;    // Enable Breakeven
input double BreakevenReward      = 1.0;     // Breakeven Reward Multiplier
input double PartialClosePct      = 50.0;    // Partial Close Percentage
input double PartialCloseReward   = 5.0;     // Partial Close Reward Multiplier
input int    LookbackHighLow      = 14;      // Lookback for Reversal Exit
input bool   EnableReversalExit   = true;    // Enable Reversal Exit

//------------------ Additional Filters: BB Trend & MA Ribbon -------
input bool   EnableBBTrendFilter  = true;    // Enable BB Trend Filter
input int    BB_Period            = 100;     // Bollinger Bands Period
input double BB_Deviation         = 2.0;     // Bollinger Bands Deviation
input bool   EnableMARibbonFilter = true;    // Enable MA Ribbon Filter
input ENUM_MA_METHOD MA_Method    = MODE_EMA;// MA Method
input int    MA_StartPeriod       = 100;     // MA Starting Period
input int    MA_PeriodStep        = 20;      // MA Period Step
#define NUM_MA 6                             // Number of MAs in Ribbon

//+------------------------------------------------------------------+
//| Expert Advisor Class Definition                                  |
//+------------------------------------------------------------------+
class CRSIReversalEA
  {
private:
   // Input Variables
   bool          m_TradeNewYork, m_TradeLondon, m_TradeTokyo, m_TradeSydney;
   int           m_RSIPeriod, m_RSIUpper, m_RSILower;
   int           m_ATRPeriod;
   double        m_ATRSLMultiplier, m_RiskRewardRatio;
   double        m_RiskPerTrade;
   bool          m_UsePercentRisk;
   double        m_RiskPercentage;
   int           m_Slippage;
   bool          m_UseDailyBias;
   int           m_MaxTradesPerDay;
   ulong         m_Magic;
   bool          m_EnableBreakeven;
   double        m_BreakevenReward, m_PartialCloseReward;
   double        m_PartialClosePct;
   int           m_Lookback;
   bool          m_EnableReversalExit;
   bool          m_EnableBB;
   int           m_BBPeriod;
   double        m_BBDev;
   bool          m_EnableMA;
   ENUM_MA_METHOD m_MAMethod;
   int           m_MAStart, m_MAPeriod;

   // State Variables
   int           m_tradesToday, m_lastDay;
   datetime      m_lastBar;
   ulong         m_partialTickets[];

   // Indicator Handles
   int           m_RSIHandle, m_ATRHandle, m_BBHandle;
   int           m_MAHandles[NUM_MA];
   int           m_BBTrend;

   // Trade Object
   CTrade        m_trade;

   // Helper Function: Check if Ticket is in Partial Close Array
   bool IsTicketClosed(ulong ticket)
     {
      for(int i = 0; i < ArraySize(m_partialTickets); i++)
         if(m_partialTickets[i] == ticket) return true;
      return false;
     }

public:
   // Constructor
   CRSIReversalEA()
     {
      m_TradeNewYork      = TradeNewYork;
      m_TradeLondon       = TradeLondon;
      m_TradeTokyo        = TradeTokyo;
      m_TradeSydney       = TradeSydney;
      m_RSIPeriod         = RSIPeriod;
      m_RSIUpper          = RSI_UpperLevel;
      m_RSILower          = RSI_LowerLevel;
      m_ATRPeriod         = ATR_Period;
      m_ATRSLMultiplier   = ATR_SL_Multiplier;
      m_RiskRewardRatio   = RiskRewardRatio;
      m_RiskPerTrade      = FixedRiskPerTrade;
      m_UsePercentRisk    = UsePercentRisk;
      m_RiskPercentage    = RiskPercentage;
      m_Slippage          = AllowedSlippage;
      m_UseDailyBias      = UseDailyBias;
      m_MaxTradesPerDay   = MaxTradesPerDay;
      m_Magic             = EA_MagicNumber;
      m_EnableBreakeven   = EnableBreakeven;
      m_BreakevenReward   = BreakevenReward;
      m_PartialCloseReward= PartialCloseReward;
      m_PartialClosePct   = PartialClosePct;
      m_Lookback          = LookbackHighLow;
      m_EnableReversalExit= EnableReversalExit;
      m_EnableBB          = EnableBBTrendFilter;
      m_BBPeriod          = BB_Period;
      m_BBDev             = BB_Deviation;
      m_EnableMA          = EnableMARibbonFilter;
      m_MAMethod          = MA_Method;
      m_MAStart           = MA_StartPeriod;
      m_MAPeriod          = MA_PeriodStep;

      m_tradesToday       = 0;
      m_lastDay           = 0;
      m_lastBar           = 0;
      ArrayResize(m_partialTickets, 0);
     }

   // Initialization Function
   int OnInit()
     {
      m_RSIHandle = iRSI(_Symbol, _Period, m_RSIPeriod, PRICE_CLOSE);
      m_ATRHandle = iATR(_Symbol, _Period, m_ATRPeriod);
      if(m_EnableBB)
         m_BBHandle = iBands(_Symbol, _Period, m_BBPeriod, 0, m_BBDev, PRICE_CLOSE);
      if(m_EnableMA)
         for(int i = 0; i < NUM_MA; i++)
            m_MAHandles[i] = iMA(_Symbol, _Period, m_MAStart + i * m_MAPeriod, 0, m_MAMethod, PRICE_CLOSE);
      return INIT_SUCCEEDED;
     }

   // Signal Generation Function
   ENUM_ORDER_TYPE GetSignal()
     {
      double rsi[2];
      if(CopyBuffer(m_RSIHandle, 0, 1, 2, rsi) < 2) return (ENUM_ORDER_TYPE)-1;
      if(rsi[1] <= m_RSIUpper && rsi[0] > m_RSIUpper) return ORDER_TYPE_BUY;  // RSI crosses above upper level
      if(rsi[1] >= m_RSILower && rsi[0] < m_RSILower) return ORDER_TYPE_SELL; // RSI crosses below lower level
      return (ENUM_ORDER_TYPE)-1;
     }

   // Session Filter Check
   bool SessionOK()
     {
      datetime t = TimeGMT();
      MqlDateTime dt;
      TimeToStruct(t, dt);
      int m = dt.hour * 60 + dt.min;
      if(m_TradeTokyo && m < 7 * 60) return true;              // Tokyo: 00:00-07:00 GMT
      if(m_TradeLondon && m >= 7 * 60 && m < 12 * 60) return true;  // London: 07:00-12:00 GMT
      if(m_TradeNewYork && m >= 12 * 60 && m < 21 * 60) return true; // New York: 12:00-21:00 GMT
      if(m_TradeSydney && m >= 21 * 60) return true;          // Sydney: 21:00-00:00 GMT
      return false;
     }

   // Trade Management Function
   void ManageTrades()
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.day != m_lastDay) { m_tradesToday = 0; m_lastDay = dt.day; }
      if(m_tradesToday >= m_MaxTradesPerDay) return;

      ENUM_ORDER_TYPE sig = GetSignal();
      if(sig == (ENUM_ORDER_TYPE)-1) return;

      // Bollinger Bands Trend Filter
      if(m_EnableBB)
        {
         double ub[1], lb[1];
         CopyBuffer(m_BBHandle, 1, 0, 1, ub); // Upper band
         CopyBuffer(m_BBHandle, 2, 0, 1, lb); // Lower band
         double lastClose = iClose(_Symbol, _Period, 1);
         if(m_BBTrend == 0)
            m_BBTrend = (lastClose > ub[0] ? 1 : (lastClose < lb[0] ? -1 : 0));
         else if(m_BBTrend == 1 && lastClose < lb[0]) m_BBTrend = -1;
         else if(m_BBTrend == -1 && lastClose > ub[0]) m_BBTrend = 1;
         if((sig == ORDER_TYPE_BUY && m_BBTrend != 1) || (sig == ORDER_TYPE_SELL && m_BBTrend != -1)) return;
        }

      // MA Ribbon Filter
      if(m_EnableMA)
        {
         double price = iClose(_Symbol, _Period, 1);
         for(int i = 0; i < NUM_MA; i++)
           {
            double ma[1];
            CopyBuffer(m_MAHandles[i], 0, 1, 1, ma);
            if((sig == ORDER_TYPE_BUY && price <= ma[0]) || (sig == ORDER_TYPE_SELL && price >= ma[0]))
               return;
           }
        }

      // Daily Bias Filter
      if(m_UseDailyBias)
        {
         int bias = (iClose(_Symbol, PERIOD_D1, 1) > iOpen(_Symbol, PERIOD_D1, 1) ? 1 : -1);
         if((sig == ORDER_TYPE_BUY && bias != 1) || (sig == ORDER_TYPE_SELL && bias != -1)) return;
        }

      if(!SessionOK()) return;

      // Open Trade if No Existing Position in Same Direction
      if(sig == ORDER_TYPE_BUY && !IsPosition(POSITION_TYPE_BUY)) Open(sig);
      if(sig == ORDER_TYPE_SELL && !IsPosition(POSITION_TYPE_SELL)) Open(sig);
     }

   // Check for Existing Position
   bool IsPosition(ENUM_POSITION_TYPE type)
     {
      for(int i = 0; i < PositionsTotal(); i++)
        {
         ulong tk = PositionGetTicket(i);
         if(PositionSelectByTicket(tk) &&
            PositionGetInteger(POSITION_MAGIC) == m_Magic &&
            PositionGetInteger(POSITION_TYPE) == type)
            return true;
        }
      return false;
     }

   // Open Trade Function
   void Open(ENUM_ORDER_TYPE t)
     {
      double atr[1];
      CopyBuffer(m_ATRHandle, 0, 1, 1, atr);
      double dist = atr[0] * m_ATRSLMultiplier;
      double price = (t == ORDER_TYPE_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID));
      double sl = (t == ORDER_TYPE_BUY ? price - dist : price + dist);
      double tp = (t == ORDER_TYPE_BUY ? price + dist * m_RiskRewardRatio : price - dist * m_RiskRewardRatio);
      double riskAmt = m_UsePercentRisk ? AccountInfoDouble(ACCOUNT_BALANCE) * m_RiskPercentage / 100.0 : m_RiskPerTrade;
      double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double lotRisk = (dist / tickSize) * tickVal;
      double lots = NormalizeDouble(riskAmt / lotRisk, 2);

      MqlTradeRequest req = {};
      MqlTradeResult res = {};
      req.action    = TRADE_ACTION_DEAL;
      req.symbol    = _Symbol;
      req.volume    = lots;
      req.type      = t;
      req.price     = price;
      req.sl        = sl;
      req.tp        = tp;
      req.deviation = m_Slippage;
      req.magic     = m_Magic;
      m_trade.OrderSend(req, res);
      m_tradesToday++;
     }

   // Partial Close and Breakeven Function
   void CheckAndExecutePartialClose()
     {
      for(int i = 0; i < PositionsTotal(); i++)
        {
         ulong tk = PositionGetTicket(i);
         if(!PositionSelectByTicket(tk) || PositionGetInteger(POSITION_MAGIC) != m_Magic) continue;
         if(IsTicketClosed(tk)) continue;

         double open = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl   = PositionGetDouble(POSITION_SL);
         double risk = MathAbs(open - sl);
         double cur  = iClose(_Symbol, _Period, 0);
         ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double target = (pt == POSITION_TYPE_BUY ? open + risk * m_PartialCloseReward : open - risk * m_PartialCloseReward);

         if((pt == POSITION_TYPE_BUY && cur >= target) || (pt == POSITION_TYPE_SELL && cur <= target))
           {
            double vol = NormalizeDouble(PositionGetDouble(POSITION_VOLUME) * (m_PartialClosePct / 100.0), 2);
            if(m_trade.PositionClosePartial(tk, vol))
              {
               ArrayResize(m_partialTickets, ArraySize(m_partialTickets) + 1);
               m_partialTickets[ArraySize(m_partialTickets) - 1] = tk;
               if(m_EnableBreakeven)
                  m_trade.PositionModify(tk,
                     (pt == POSITION_TYPE_BUY ? open + risk * m_BreakevenReward : open - risk * m_BreakevenReward),
                     PositionGetDouble(POSITION_TP));
              }
           }
        }
     }

   // Reversal Exit Function
   void CheckReversalExit()
     {
      double hh = iHigh(_Symbol, _Period, iHighest(_Symbol, _Period, MODE_HIGH, m_Lookback, 2));
      double ll = iLow(_Symbol, _Period, iLowest(_Symbol, _Period, MODE_LOW, m_Lookback, 2));
      double cur = iClose(_Symbol, _Period, 1);
      for(int i = 0; i < PositionsTotal(); i++)
        {
         ulong tk = PositionGetTicket(i);
         if(!PositionSelectByTicket(tk) || PositionGetInteger(POSITION_MAGIC) != m_Magic) continue;
         ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(!m_EnableReversalExit) continue;
         if(pt == POSITION_TYPE_SELL && cur > hh) m_trade.PositionClose(tk);
         if(pt == POSITION_TYPE_BUY  && cur < ll) m_trade.PositionClose(tk);
        }
     }

   // Tick Handler
   void OnTick()
     {
      datetime bt = iTime(_Symbol, _Period, 0);
      if(bt != m_lastBar)
        {
         ManageTrades();
         m_lastBar = bt;
        }
      CheckAndExecutePartialClose();
      CheckReversalExit();
     }
  };

// Global EA Instance
CRSIReversalEA ea;

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   return ea.OnInit();
  }

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   ea.OnTick();
  }
//+------------------------------------------------------------------+