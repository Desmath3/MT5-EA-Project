//+------------------------------------------------------------------+
//|                                              RSI_MartingaleEA.mq5|
//|                        Copyright 2025, [Your Name]               |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

#define PIP_SIZE (_Point * 10)

// Input Parameters (unchanged)
input double InitialLotSize         = 0.01;
input double LotMultiplier          = 2.0;
input int    MaxMartingaleSteps     = 5;
input bool   TradeNewYork           = true;
input bool   TradeLondon            = true;
input bool   TradeTokyo             = false;
input bool   TradeSydney            = false;
input int    RSIPeriod              = 14;
input int    RSI_UpperLevel         = 80;
input int    RSI_LowerLevel         = 20;
input int    MartingalePips         = 10;
input int    BaseTP_Pips            = 20;
input bool   UseDailyReset          = true;
input double MaxDailyDrawdownPct    = 1.0;
input int    MaxTradesPerDay        = 10;
input ulong  EA_MagicNumber         = 123456;
input bool   EnableBBFilter         = true;
input int    BB_Period              = 100;
input double BB_Deviation           = 2.0;
input bool   EnableMAFilter         = true;
input ENUM_MA_METHOD MA_Method      = MODE_EMA;
input int    MA_StartPeriod         = 100;
input int    MA_PeriodStep          = 20;
#define NUM_MA 6

class CRSI_MartingaleEA
{
private:
   // Parameters (unchanged)
   double m_InitialLot, m_LotMultiplier;
   int    m_MaxSteps, m_MartPips, m_BaseTP;
   bool   m_TradeNY, m_TradeLD, m_TradeTK, m_TradeSY;
   int    m_RSIPer, m_RSIUp, m_RSILo;
   bool   m_DailyReset;
   double m_MaxDD;
   int    m_MaxTrades;
   ulong  m_Magic;
   bool   m_EnableBB;
   int    m_BBPeriod;
   double m_BBDev;
   bool   m_EnableMA;
   ENUM_MA_METHOD m_MAMethod;
   int    m_MAStart, m_MAPeriod;

   // State
   enum RSIState {NONE, WAIT_BUY, WAIT_SELL} m_state;
   datetime m_dayStart;
   double   m_startEquity;
   int      m_currentStep;
   double   m_originalEntry;
   bool     m_inMartingale;
   bool     m_stepTriggered;
   bool     m_tradingHalted;  // New flag to halt trading after daily loss
   int      m_tradesToday;    // New counter for daily trades

   // Indicators (unchanged)
   int    m_RSIHandle, m_BBHandle, m_MAHandles[NUM_MA];
   CTrade m_trade;

   bool SessionOK()
   {
      datetime t = TimeGMT(); MqlDateTime dt; TimeToStruct(t, dt);
      int m = dt.hour * 60 + dt.min;
      if(m_TradeTK && m < 7 * 60) return true;
      if(m_TradeLD && m >= 7 * 60 && m < 12 * 60) return true;
      if(m_TradeNY && m >= 12 * 60 && m < 21 * 60) return true;
      if(m_TradeSY && m >= 21 * 60) return true;
      return false;
   }

   void CheckDailyReset()
   {
      if(!m_DailyReset || m_startEquity == 0) return;
      if(AccountInfoDouble(ACCOUNT_EQUITY) <= m_startEquity * (1.0 - m_MaxDD / 100.0))
      {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong tk = PositionGetTicket(i);
            if(PositionSelectByTicket(tk) && PositionGetInteger(POSITION_MAGIC) == m_Magic)
               m_trade.PositionClose(tk);
         }
         m_tradingHalted = true;  // Halt trading for the day
         Print("Daily drawdown limit reached. Trading halted until next day.");
      }
   }

   bool HasPosition() { return PositionsTotal() > 0; }

   ENUM_POSITION_TYPE CurrentDirection()
   {
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong tk = PositionGetTicket(i);
         if(PositionSelectByTicket(tk) && PositionGetInteger(POSITION_MAGIC) == m_Magic)
            return (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      }
      return POSITION_TYPE_BUY;
   }

   double LotsForStep(int step)
   {
      return NormalizeDouble(m_InitialLot * pow(m_LotMultiplier, step - 1), 2);
   }

   void OpenTradeWithLots(ENUM_ORDER_TYPE type, double lot)
   {
      double price = (type == ORDER_TYPE_BUY)
         ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
         : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      MqlTradeRequest req = {};
      MqlTradeResult res = {};
      req.action = TRADE_ACTION_DEAL;
      req.symbol = _Symbol;
      req.volume = lot;
      req.type = type;
      req.price = price;
      req.deviation = 10;
      req.magic = m_Magic;
      m_trade.OrderSend(req, res);
   }

   void UpdateAllTPs(ENUM_ORDER_TYPE type)
   {
      // Calculate average entry price
      double totalLots = 0;
      double weightedSum = 0;
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong tk = PositionGetTicket(i);
         if(PositionSelectByTicket(tk) && PositionGetInteger(POSITION_MAGIC) == m_Magic)
         {
            double lot = PositionGetDouble(POSITION_VOLUME);
            double entry = PositionGetDouble(POSITION_PRICE_OPEN);
            totalLots += lot;
            weightedSum += lot * entry;
         }
      }
      if(totalLots > 0)
      {
         double averageEntry = weightedSum / totalLots;
         // Set TP at fixed distance from average entry
         double commonTP = (type == ORDER_TYPE_BUY)
            ? averageEntry + m_BaseTP * PIP_SIZE
            : averageEntry - m_BaseTP * PIP_SIZE;
         // Update TP for all positions
         for(int i = 0; i < PositionsTotal(); i++)
         {
            ulong tk = PositionGetTicket(i);
            if(PositionSelectByTicket(tk) && PositionGetInteger(POSITION_MAGIC) == m_Magic)
               m_trade.PositionModify(tk, PositionGetDouble(POSITION_SL), commonTP);
         }
      }
   }

public:
   CRSI_MartingaleEA()
   {
      m_InitialLot    = InitialLotSize;
      m_LotMultiplier = LotMultiplier;
      m_MaxSteps      = MaxMartingaleSteps;
      m_MartPips      = MartingalePips;
      m_BaseTP        = BaseTP_Pips;
      m_TradeNY       = TradeNewYork;
      m_TradeLD       = TradeLondon;
      m_TradeTK       = TradeTokyo;
      m_TradeSY       = TradeSydney;
      m_RSIPer        = RSIPeriod;
      m_RSIUp         = RSI_UpperLevel;
      m_RSILo         = RSI_LowerLevel;
      m_DailyReset    = UseDailyReset;
      m_MaxDD         = MaxDailyDrawdownPct;
      m_MaxTrades     = MaxTradesPerDay;
      m_Magic         = EA_MagicNumber;
      m_EnableBB      = EnableBBFilter;
      m_BBPeriod      = BB_Period;
      m_BBDev         = BB_Deviation;
      m_EnableMA      = EnableMAFilter;
      m_MAMethod      = MA_Method;
      m_MAStart       = MA_StartPeriod;
      m_MAPeriod      = MA_PeriodStep;

      m_state         = NONE;
      m_dayStart      = 0;
      m_startEquity   = 0;
      m_currentStep   = 0;
      m_originalEntry = 0;
      m_stepTriggered = false;
      m_inMartingale  = false;
      m_tradingHalted = false;  // Initialize trading halt flag
      m_tradesToday   = 0;      // Initialize daily trade counter
   }

   int OnInit()
   {
      m_RSIHandle = iRSI(_Symbol, _Period, m_RSIPer, PRICE_CLOSE);
      if(m_EnableBB)
         m_BBHandle = iBands(_Symbol, _Period, m_BBPeriod, 0, m_BBDev, PRICE_CLOSE);
      if(m_EnableMA)
         for(int i = 0; i < NUM_MA; i++)
            m_MAHandles[i] = iMA(_Symbol, _Period, m_MAStart + i * m_MAPeriod, 0, m_MAMethod, PRICE_CLOSE);
      return INIT_SUCCEEDED;
   }

   void OnTick()
   {
      // Daily reset
      datetime now = TimeCurrent(); MqlDateTime dt; TimeToStruct(now, dt);
      if(m_dayStart != dt.day)
      {
         m_dayStart    = dt.day;
         m_startEquity = AccountInfoDouble(ACCOUNT_BALANCE);
         m_state       = NONE;
         m_currentStep = 0;
         m_stepTriggered = false;
         m_inMartingale = false;
         m_tradingHalted = false;  // Reset trading halt flag
         m_tradesToday = 0;        // Reset daily trade counter
      }

      // Exit if trading is halted
      if(m_tradingHalted) return;

      CheckDailyReset();
      if(!SessionOK()) return;

      bool hasPositions = HasPosition();
      
      if(m_inMartingale && !hasPositions)
      {
         m_inMartingale = false;
         m_currentStep = 0;
      }

      // No position: RSI trigger
      if(!hasPositions && !m_inMartingale && m_tradesToday < m_MaxTrades)
      {
         double arr[1]; CopyBuffer(m_RSIHandle, 0, 1, 1, arr);
         double rsi = arr[0];
         if(rsi < m_RSILo) m_state = WAIT_BUY;
         if(rsi > m_RSIUp) m_state = WAIT_SELL;

         if(m_state == WAIT_BUY)
         {
            OpenTradeWithLots(ORDER_TYPE_BUY, m_InitialLot);
            m_tradesToday++;  // Increment trade counter
            m_originalEntry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            m_currentStep   = 1;
            m_inMartingale  = true;
            UpdateAllTPs(ORDER_TYPE_BUY);
            m_state = NONE;
         }
         else if(m_state == WAIT_SELL)
         {
            OpenTradeWithLots(ORDER_TYPE_SELL, m_InitialLot);
            m_tradesToday++;  // Increment trade counter
            m_originalEntry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            m_currentStep   = 1;
            m_inMartingale  = true;
            UpdateAllTPs(ORDER_TYPE_SELL);
            m_state = NONE;
         }
         return;
      }

      // In position: Martingale
      if(hasPositions && m_currentStep < m_MaxSteps && m_tradesToday < m_MaxTrades)
      {
         ENUM_POSITION_TYPE dir = CurrentDirection();
         double curPrice = (dir == POSITION_TYPE_BUY)
            ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
            : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double diff = (dir == POSITION_TYPE_BUY)
            ? (m_originalEntry - curPrice)
            : (curPrice - m_originalEntry);
         double threshold = m_currentStep * m_MartPips * PIP_SIZE;

         if(!m_stepTriggered && diff >= threshold)
         {
            double lot = LotsForStep(m_currentStep + 1);
            OpenTradeWithLots((dir == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, lot);
            m_tradesToday++;  // Increment trade counter
            m_currentStep++;
            UpdateAllTPs((dir == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
            m_stepTriggered = true;
            return;
         }
         if(m_stepTriggered && diff < threshold - PIP_SIZE)
            m_stepTriggered = false;
      }
   }
};

CRSI_MartingaleEA ea;
int OnInit() { return ea.OnInit(); }
void OnTick() { ea.OnTick(); }
//+------------------------------------------------------------------+