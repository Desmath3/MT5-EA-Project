//+------------------------------------------------------------------+
//|                                              EA_BB_V5_fixed.mq5  |
//|                        Copyright 2025, [Your Name]               |
//|                        https://www.mql5.com                      |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//------------------ Input Parameters -------------------------------
input int    Slippage            = 3;           // Slippage in points
input ulong  MagicNumber         = 123456;      // Unique identifier for EA's orders
input int    BrokerGMTOffset     = 0;           // Broker GMT offset in hours

input bool   TradeNewYork        = true;        // Trade during New York session
input bool   TradeLondon         = true;        // Trade during London session
input bool   TradeTokyo          = false;       // Trade during Tokyo session
input bool   TradeSydney         = false;       // Trade during Sydney session

input int    BollingerPeriod     = 100;         // Bollinger Bands period
input double BollingerDeviation  = 2.0;         // Bollinger Bands deviation

input int    ATRPeriod           = 14;          // ATR period
input double ATRSLMultiplier     = 2.0;         // Stop loss multiplier
input double RiskRewardRatio     = 10.0;        // Reward/Risk ratio
input double RiskPerTrade        = 50.0;        // Fixed risk per trade (USD)
input bool   UsePercentageRisk   = false;       // Use % of balance for risk
input double RiskPercentage      = 1.0;         // Risk % (if above true)

input double BreakevenTriggerReward = 5.0;      // Reward multiple to trigger SL move
input bool   SetBreakeven         = true;       // Enable breakeven SL move
input double BreakevenReward      = 1.0;       // Reward multiple for new SL

input bool   EnableReversalClose  = true;       // Enable reversal-based exits
input int    LookbackPeriod       = 14;         // Lookback for reversal levels

input bool   UseDailyBias         = false;      // Only trade with yesterday's bias
input int    MaxTradesPerDay      = 5;          // Max trades per day
input bool   AllowMultiplePositions = false;    // If false, only 1 position at a time

//+------------------------------------------------------------------+
class CBBReversalEA
  {
private:
   int           m_Slippage;
   ulong         m_MagicNumber;
   int           m_BrokerGMTOffset;
   bool          m_TradeNewYork;
   bool          m_TradeLondon;
   bool          m_TradeTokyo;
   bool          m_TradeSydney;
   int           m_BollingerPeriod;
   double        m_BollingerDeviation;
   int           m_ATRPeriod;
   double        m_ATRSLMultiplier;
   double        m_RiskRewardRatio;
   double        m_RiskPerTrade;
   bool          m_UsePercentageRisk;
   double        m_RiskPercentage;
   double        m_BreakevenTriggerReward;
   bool          m_SetBreakeven;
   double        m_BreakevenReward;
   bool          m_EnableReversalClose;
   int           m_LookbackPeriod;
   bool          m_UseDailyBias;
   int           m_MaxTradesPerDay;
   bool          m_AllowMultiplePositions;

   int           m_BandHandle;
   int           m_ATRHandle;

   double        m_upperBand[1];
   double        m_lowerBand[1];

   int           m_tradesToday;
   int           m_lastTradeDay;
   datetime      m_lastBarTime;
   ulong         m_breakevenTriggeredTickets[];
   CTrade        m_trade;

public:
   CBBReversalEA()
     {
      m_Slippage               = Slippage;
      m_MagicNumber            = MagicNumber;
      m_BrokerGMTOffset        = BrokerGMTOffset;
      m_TradeNewYork           = TradeNewYork;
      m_TradeLondon            = TradeLondon;
      m_TradeTokyo             = TradeTokyo;
      m_TradeSydney            = TradeSydney;
      m_BollingerPeriod        = BollingerPeriod;
      m_BollingerDeviation     = BollingerDeviation;
      m_ATRPeriod              = ATRPeriod;
      m_ATRSLMultiplier        = ATRSLMultiplier;
      m_RiskRewardRatio        = RiskRewardRatio;
      m_RiskPerTrade           = RiskPerTrade;
      m_UsePercentageRisk      = UsePercentageRisk;
      m_RiskPercentage         = RiskPercentage;
      m_BreakevenTriggerReward = BreakevenTriggerReward;
      m_SetBreakeven           = SetBreakeven;
      m_BreakevenReward        = BreakevenReward;
      m_EnableReversalClose    = EnableReversalClose;
      m_LookbackPeriod         = LookbackPeriod;
      m_UseDailyBias           = UseDailyBias;
      m_MaxTradesPerDay        = MaxTradesPerDay;
      m_AllowMultiplePositions = AllowMultiplePositions;

      m_tradesToday            = 0;
      m_lastTradeDay           = 0;
      m_lastBarTime            = 0;
      ArrayResize(m_breakevenTriggeredTickets,0);
     }

   void InitializeIndicators()
     {
      m_BandHandle = iBands(_Symbol,_Period,m_BollingerPeriod,0,m_BollingerDeviation,PRICE_CLOSE);
      m_ATRHandle  = iATR(_Symbol,_Period,m_ATRPeriod);
     }

   bool IsWithinSession()
     {
      datetime srv=TimeCurrent();
      datetime gmt=srv - m_BrokerGMTOffset*3600;
      MqlDateTime dt; TimeToStruct(gmt,dt);
      int minutes = dt.hour*60 + dt.min;
      bool within=false;
      // Tokyo: 00:00-09:00 GMT
      if(m_TradeTokyo && minutes>=0 && minutes<9*60) within=true;
      // London: 08:00-17:00 GMT
      if(m_TradeLondon && minutes>=8*60 && minutes<17*60) within=true;
      // New York: 13:30-20:00 GMT
      if(m_TradeNewYork && minutes>=13*60+30 && minutes<20*60) within=true;
      // Sydney: 22:00-06:00 GMT
      if(m_TradeSydney && (minutes>=22*60 || minutes<6*60)) within=true;
      return within;
     }

   int GetDailyBias()
     {
      return(iClose(_Symbol,PERIOD_D1,1) > iOpen(_Symbol,PERIOD_D1,1))?1:-1;
     }

   bool HasOpenOfType(ENUM_ORDER_TYPE type)
     {
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong t=PositionGetTicket(i);
         if(PositionSelectByTicket(t)
            && PositionGetString(POSITION_SYMBOL)==_Symbol
            && PositionGetInteger(POSITION_MAGIC)==m_MagicNumber
            && ((type==ORDER_TYPE_BUY  && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
             || (type==ORDER_TYPE_SELL && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL)))
            return true;
        }
      return false;
     }

   void OpenTrade(ENUM_ORDER_TYPE type)
     {
      double atrArr[1]; CopyBuffer(m_ATRHandle,0,1,1,atrArr);
      double atr=atrArr[0];
      double slDist=atr*m_ATRSLMultiplier;
      double tpDist=slDist*m_RiskRewardRatio;
      double price=(type==ORDER_TYPE_BUY?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID));
      double sl=(type==ORDER_TYPE_BUY?price-slDist:price+slDist);
      double tp=(type==ORDER_TYPE_BUY?price+tpDist:price-tpDist);

      double riskAmt=m_UsePercentageRisk?AccountInfoDouble(ACCOUNT_BALANCE)*m_RiskPercentage/100.0:m_RiskPerTrade;
      double tickVal = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
      double tickSize= SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
      double riskLot = (slDist/tickSize)*tickVal;
      double lots    = NormalizeDouble(riskAmt/riskLot,2);

      MqlTradeRequest req; MqlTradeResult res;
      ZeroMemory(req); ZeroMemory(res);
      req.action    = TRADE_ACTION_DEAL;
      req.symbol    = _Symbol;
      req.volume    = lots;
      req.type      = type;
      req.price     = price;
      req.sl        = sl;
      req.tp        = tp;
      req.deviation = m_Slippage;
      req.magic     = m_MagicNumber;
      m_trade.OrderSend(req,res);
     }

   void ManageTrades()
     {
      // reset daily count
      MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
      if(dt.day!=m_lastTradeDay)
        {
         m_tradesToday=0;
         m_lastTradeDay=dt.day;
        }
      if(m_tradesToday>=m_MaxTradesPerDay) return;
      if(!m_AllowMultiplePositions && PositionsTotal()>0) return;

      //--- detect BB cross on last closed bar
      double upperArr[1], lowerArr[1];
      CopyBuffer(m_BandHandle,1,1,1,upperArr);
      CopyBuffer(m_BandHandle,2,1,1,lowerArr);
      double open1  = iOpen(_Symbol,_Period,1);
      double close1 = iClose(_Symbol,_Period,1);
      ENUM_ORDER_TYPE sig = (ENUM_ORDER_TYPE)-1;
      if(open1 < upperArr[0] && close1 > upperArr[0]) sig = ORDER_TYPE_BUY;
      else if(open1 > lowerArr[0] && close1 < lowerArr[0]) sig = ORDER_TYPE_SELL;
      if(sig==(ENUM_ORDER_TYPE)-1) return;

      if(m_UseDailyBias)
        {
         int bias = GetDailyBias();
         if((sig==ORDER_TYPE_BUY && bias!=1) || (sig==ORDER_TYPE_SELL && bias!=-1)) return;
        }
      if(!IsWithinSession()) return;

      if(!HasOpenOfType(sig))
        {
         OpenTrade(sig);
         m_tradesToday++;
        }
     }

   void CheckBreakevenTrigger()
     {
      if(!m_SetBreakeven) return;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong t=PositionGetTicket(i);
         if(!PositionSelectByTicket(t)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol || PositionGetInteger(POSITION_MAGIC)!=m_MagicNumber) continue;
         bool done=false; 
         for(int j=0;j<ArraySize(m_breakevenTriggeredTickets);j++)
            if(m_breakevenTriggeredTickets[j]==t) { done=true; break; }
         if(done) continue;

         double open=PositionGetDouble(POSITION_PRICE_OPEN);
         double sl  =PositionGetDouble(POSITION_SL);
         double risk=MathAbs(open-sl);
         double cur =iClose(_Symbol,_Period,0);
         ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double trigger=(pt==POSITION_TYPE_BUY?open+risk*m_BreakevenTriggerReward:open-risk*m_BreakevenTriggerReward);
         if((pt==POSITION_TYPE_BUY&&cur>=trigger)||(pt==POSITION_TYPE_SELL&&cur<=trigger))
           {
            double new_sl=(pt==POSITION_TYPE_BUY?open+risk*m_BreakevenReward:open-risk*m_BreakevenReward);
            m_trade.PositionModify(t,new_sl,PositionGetDouble(POSITION_TP));
            ArrayResize(m_breakevenTriggeredTickets,ArraySize(m_breakevenTriggeredTickets)+1);
            m_breakevenTriggeredTickets[ArraySize(m_breakevenTriggeredTickets)-1]=t;
           }
        }
     }

   void CheckReversalClose()
     {
      if(!m_EnableReversalClose) return;
      double hh=iHigh(_Symbol,_Period,iHighest(_Symbol,_Period,MODE_HIGH,m_LookbackPeriod,2));
      double ll=iLow (_Symbol,_Period, iLowest(_Symbol,_Period,MODE_LOW ,m_LookbackPeriod,2));
      double cur=iClose(_Symbol,_Period,1);
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong t=PositionGetTicket(i);
         if(!PositionSelectByTicket(t)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol||PositionGetInteger(POSITION_MAGIC)!=m_MagicNumber) continue;
         ENUM_POSITION_TYPE pt=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(pt==POSITION_TYPE_SELL && cur>hh) m_trade.PositionClose(t);
         if(pt==POSITION_TYPE_BUY  && cur<ll) m_trade.PositionClose(t);
        }
     }

   void OnTick()
     {
      datetime bt=iTime(_Symbol,_Period,0);
      if(bt!=m_lastBarTime)
        {
         ManageTrades();
         m_lastBarTime=bt;
        }
      CheckBreakevenTrigger();
      CheckReversalClose();
     }
  };

//+------------------------------------------------------------------+
CBBReversalEA ea;

int OnInit()
  {
   ea.InitializeIndicators();
   return(INIT_SUCCEEDED);
  }

void OnTick()
  {
   ea.OnTick();
  }
//+------------------------------------------------------------------+
