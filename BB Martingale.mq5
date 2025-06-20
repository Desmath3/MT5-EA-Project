//+------------------------------------------------------------------+
//|                                             BB MartingaleEA.mq5  |
//|                        Copyright 2025, [Your Name]               |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#define PIP_SIZE (_Point * 10)

// Input Parameters
input double InitialLotSize      = 0.01;
input double LotMultiplier       = 2.0;
input int    MaxMartingaleSteps  = 5;
input bool   TradeNewYork        = true;
input bool   TradeLondon         = true;
input bool   TradeTokyo          = false;
input bool   TradeSydney         = false;
input int    MartingalePips      = 10;
input int    BaseTP_Pips         = 20;
input bool   UseDailyReset       = true;
input double MaxDailyDrawdownPct = 1.0;
input int    MaxTradesPerDay     = 10;
input ulong  EA_MagicNumber      = 123456;

// Bollinger Bands (entry logic)
input int    BB_Period    = 100;
input double BB_Deviation = 2.0;

//----------------------------------------------------------------------
// Structure to keep separate martingale state for each direction
struct TradeGroup
{
   bool   active;       // Is there an active sequence?
   int    step;         // Current martingale step (1 = initial trade)
   double entryPrice;   // Price of the first trade in the sequence
   bool   triggered;    // Has the threshold been triggered this step?
};

class CBBMartingaleEA
{
private:
   // Parameters
   double m_initLot;
   double m_lotMult;
   int    m_maxSteps;
   int    m_pips;
   int    m_tpPips;
   bool   m_tNY;
   bool   m_tLD;
   bool   m_tTK;
   bool   m_tSY;
   bool   m_dailyReset;
   double m_maxDD;
   int    m_maxTrades;
   ulong  m_magic;

   // State
   TradeGroup m_buy;
   TradeGroup m_sell;
   datetime   m_day;
   double     m_startEq;
   bool       m_halted;
   int        m_count;

   // BB handle
   int    m_bb;
   CTrade m_trade;

   // Check if within allowed session hours
   bool SessionOK()
   {
      datetime t = TimeGMT();
      MqlDateTime dt;
      TimeToStruct(t, dt);
      int minutes = dt.hour * 60 + dt.min;
      
      // Tokyo session (00:00 - 09:00 GMT)
      if(m_tTK && minutes >= 0 && minutes < 9 * 60)   
         return true;
      
      // London session (08:00 - 16:00 GMT)
      if(m_tLD && minutes >= 8 * 60 && minutes < 16 * 60)  
         return true;
      
      // New York session (13:00 - 22:00 GMT)
      if(m_tNY && minutes >= 13 * 60 && minutes < 22 * 60)  
         return true;
      
      // Sydney session (22:00 - 07:00 GMT)
      if(m_tSY && (minutes >= 22 * 60 || minutes < 7 * 60)) 
         return true;
         
      return false;
   }

   // Check and enforce daily drawdown reset
   void CheckReset()
   {
      if(!m_dailyReset || m_startEq == 0.0)
         return;
         
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= m_startEq * (1.0 - m_maxDD / 100.0))
      {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket)
               && PositionGetInteger(POSITION_MAGIC) == m_magic)
            {
               m_trade.PositionClose(ticket);
            }
         }
         m_halted = true;
         Print("Daily drawdown reached. Trading halted.");
      }
   }

   // Does a position of given type and magic exist?
   bool HasPos(ENUM_POSITION_TYPE posType)
   {
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket)
            && PositionGetInteger(POSITION_MAGIC) == m_magic
            && PositionGetInteger(POSITION_TYPE) == posType)
         {
            return true;
         }
      }
      return false;
   }

   // Open a market order
   void OpenOrder(ENUM_ORDER_TYPE orderType, double volume)
   {
      double price = (orderType == ORDER_TYPE_BUY) ? 
                     SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                     SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double tpPrice = (orderType == ORDER_TYPE_BUY) ? 
                       price + m_tpPips * PIP_SIZE : 
                       price - m_tpPips * PIP_SIZE;
                     
      if(m_trade.PositionOpen(_Symbol, orderType, volume, price, 0, tpPrice, "BB Martingale"))
      {
         Print("Order opened: ", orderType, " volume: ", volume, " price: ", price, " TP: ", tpPrice);
      }
      else
      {
         Print("Failed to open order: ", m_trade.ResultRetcode(), ", ", m_trade.ResultRetcodeDescription());
      }
   }

   // Update take-profit for all positions of this order type
   void UpdateTP(ENUM_ORDER_TYPE orderType)
   {
      double totalLots = 0.0;
      double weightedSum = 0.0;
      ENUM_POSITION_TYPE posType = (orderType == ORDER_TYPE_BUY) ? 
                                    POSITION_TYPE_BUY : 
                                    POSITION_TYPE_SELL;
                                    
      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket)
            && PositionGetInteger(POSITION_MAGIC) == m_magic
            && PositionGetInteger(POSITION_TYPE) == posType)
         {
            double vol = PositionGetDouble(POSITION_VOLUME);
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            totalLots += vol;
            weightedSum += vol * price;
         }
      }
      
      if(totalLots > 0)
      {
         double averageEntry = weightedSum / totalLots;
         double tpLevel = (orderType == ORDER_TYPE_BUY) ? 
                           averageEntry + m_tpPips * PIP_SIZE : 
                           averageEntry - m_tpPips * PIP_SIZE;
                           
         for(int i = 0; i < PositionsTotal(); i++)
         {
            ulong ticket = PositionGetTicket(i);
            if(PositionSelectByTicket(ticket)
               && PositionGetInteger(POSITION_MAGIC) == m_magic
               && PositionGetInteger(POSITION_TYPE) == posType)
            {
               m_trade.PositionModify(ticket, 0, tpLevel);
            }
         }
      }
   }

public:
   CBBMartingaleEA()
   {
      // Initialize parameters
      m_initLot    = InitialLotSize;
      m_lotMult    = LotMultiplier;
      m_maxSteps   = MaxMartingaleSteps;
      m_pips       = MartingalePips;
      m_tpPips     = BaseTP_Pips;
      m_tNY        = TradeNewYork;
      m_tLD        = TradeLondon;
      m_tTK        = TradeTokyo;
      m_tSY        = TradeSydney;
      m_dailyReset = UseDailyReset;
      m_maxDD      = MaxDailyDrawdownPct;
      m_maxTrades  = MaxTradesPerDay;
      m_magic      = EA_MagicNumber;

      // Reset state
      m_buy.active       = false;
      m_buy.step         = 0;
      m_buy.entryPrice   = 0.0;
      m_buy.triggered    = false;

      m_sell.active      = false;
      m_sell.step        = 0;
      m_sell.entryPrice  = 0.0;
      m_sell.triggered   = false;

      m_day     = 0;
      m_startEq = 0.0;
      m_halted  = false;
      m_count   = 0;
      
      // Setup trade object
      m_trade.SetExpertMagicNumber(m_magic);
   }

   int OnInit()
   {
      // Initialize Bollinger Bands handle
      m_bb = iBands(_Symbol, _Period, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
      if(m_bb == INVALID_HANDLE)
      {
         Print("Failed to create Bollinger Bands indicator");
         return INIT_FAILED;
      }
      
      return INIT_SUCCEEDED;
   }
   
   void OnDeinit(const int reason)
   {
      // Release indicator handle
      if(m_bb != INVALID_HANDLE)
         IndicatorRelease(m_bb);
   }

   void OnTick()
   {
      // Daily reset at start of new day
      datetime now = TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(now, dt);
      
      if(dt.day != m_day)
      {
         m_day     = dt.day;
         m_startEq = AccountInfoDouble(ACCOUNT_BALANCE);
         // Reset buy group
         m_buy.active      = false;
         m_buy.step        = 0;
         m_buy.entryPrice  = 0.0;
         m_buy.triggered   = false;
         // Reset sell group
         m_sell.active     = false;
         m_sell.step       = 0;
         m_sell.entryPrice = 0.0;
         m_sell.triggered  = false;
         // Reset counters
         m_count  = 0;
         m_halted = false;
      }
      
      if(m_halted)
         return;

      CheckReset();
      
      if(!SessionOK())
         return;

      // Get Bollinger Bands values
      double upper[3], middle[3], lower[3], close[3];
      
      // Copy recent bars: [0] - current, [1] - last closed, [2] - previous
      if(CopyBuffer(m_bb, 1, 0, 3, upper) < 3 ||    // Upper band (1)
         CopyBuffer(m_bb, 0, 0, 3, middle) < 3 ||   // Middle band (0)
         CopyBuffer(m_bb, 2, 0, 3, lower) < 3)      // Lower band (2)
      {
         Print("Failed to copy indicator buffers");
         return;
      }
      
      // Get close prices
      if(CopyClose(_Symbol, _Period, 0, 3, close) < 3)
      {
         Print("Failed to copy close prices");
         return;
      }
      
      // UPDATED ENTRY LOGIC
      if(m_count < m_maxTrades)
      {
         // SELL signal: Current candle closed BELOW the LOWER band
         if(!m_sell.active && !HasPos(POSITION_TYPE_SELL))
         {
            if(close[1] < lower[1])
            {
               OpenOrder(ORDER_TYPE_SELL, m_initLot);
               m_sell.active      = true;
               m_sell.step        = 1;
               m_sell.entryPrice  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
               m_sell.triggered   = false;
               m_count++;
               UpdateTP(ORDER_TYPE_SELL);
               Print("SELL signal: Current candle closed below lower band");
            }
         }

         // BUY signal: Current candle closed ABOVE the UPPER band
         if(!m_buy.active && !HasPos(POSITION_TYPE_BUY))
         {
            if(close[1] > upper[1])
            {
               OpenOrder(ORDER_TYPE_BUY, m_initLot);
               m_buy.active       = true;
               m_buy.step         = 1;
               m_buy.entryPrice   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               m_buy.triggered    = false;
               m_count++;
               UpdateTP(ORDER_TYPE_BUY);
               Print("BUY signal: Current candle closed above upper band");
            }
         }
      }

      // Martingale management for SELL group
      if(m_sell.active && m_sell.step < m_maxSteps && m_count < m_maxTrades)
      {
         if(HasPos(POSITION_TYPE_SELL))
         {
            double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double diff         = currentPrice - m_sell.entryPrice;
            double threshold    = m_sell.step * m_pips * PIP_SIZE;
            
            if(!m_sell.triggered && diff >= threshold)
            {
               double vol = NormalizeDouble(m_initLot * MathPow(m_lotMult, m_sell.step), 2);
               OpenOrder(ORDER_TYPE_SELL, vol);
               m_sell.step      += 1;
               m_sell.triggered = true;
               m_count++;
               UpdateTP(ORDER_TYPE_SELL);
               Print("SELL martingale step ", m_sell.step, " triggered at price ", currentPrice);
            }
            
            if(m_sell.triggered && diff < threshold - PIP_SIZE)
               m_sell.triggered = false;
         }
         else
         {
            // If all sell positions closed, reset group
            m_sell.active      = false;
            m_sell.step        = 0;
            m_sell.entryPrice  = 0.0;
            m_sell.triggered   = false;
            Print("SELL group reset - all positions closed");
         }
      }

      // Martingale management for BUY group
      if(m_buy.active && m_buy.step < m_maxSteps && m_count < m_maxTrades)
      {
         if(HasPos(POSITION_TYPE_BUY))
         {
            double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double diff         = m_buy.entryPrice - currentPrice;
            double threshold    = m_buy.step * m_pips * PIP_SIZE;
            
            if(!m_sell.triggered && diff >= threshold)
            {
               double vol = NormalizeDouble(m_initLot * MathPow(m_lotMult, m_buy.step), 2);
               OpenOrder(ORDER_TYPE_BUY, vol);
               m_buy.step       += 1;
               m_buy.triggered  = true;
               m_count++;
               UpdateTP(ORDER_TYPE_BUY);
               Print("BUY martingale step ", m_buy.step, " triggered at price ", currentPrice);
            }
            
            if(m_buy.triggered && diff < threshold - PIP_SIZE)
               m_buy.triggered = false;
         }
         else
         {
            // If all buy positions closed, reset group
            m_buy.active      = false;
            m_buy.step        = 0;
            m_buy.entryPrice  = 0.0;
            m_buy.triggered   = false;
            Print("BUY group reset - all positions closed");
         }
      }
   }
};

CBBMartingaleEA ea;

int OnInit() 
{ 
   return ea.OnInit(); 
}

void OnDeinit(const int reason)
{
   ea.OnDeinit(reason);
}

void OnTick() 
{ 
   ea.OnTick(); 
}