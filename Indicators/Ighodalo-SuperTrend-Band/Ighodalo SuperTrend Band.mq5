//+------------------------------------------------------------------+
//|                                      SuperTrend Bands for MT5    |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Generated based on Pine Script"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   2

//--- plot settings
#property indicator_label1  "ST Up Band"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrLime
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "ST Dn Band"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrMaroon
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

//--- inputs
input group "Common"
input ENUM_APPLIED_PRICE source = PRICE_MEDIAN; // Source
input int delay_period = 0; // Delay Candles for Band Reset

input group "Supertrend (Mult=5)"
input int atr_period = 10; // ATR Period
input double atr_mult = 5.0; // ATR Multiplier

//--- buffers
double up_buffer[];
double dn_buffer[];
double tr_buffer[];
double atr_buffer[];

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   SetIndexBuffer(0, up_buffer);
   SetIndexBuffer(1, dn_buffer);
   SetIndexBuffer(2, tr_buffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, atr_buffer, INDICATOR_CALCULATIONS);

   IndicatorSetString(INDICATOR_SHORTNAME, "SuperTrend Bands");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < 2) return(0);

// Static states for delays and old values
   static int delay_up1 = 0;
   static double old_up1 = 0;
   static int delay_dn1 = 0;
   static double old_dn1 = 0;

   int start_pos = prev_calculated - 1;
   if(start_pos < 0) start_pos = 0;

// Calculate TR
   for(int i = start_pos; i < rates_total; i++)
     {
      if(i == 0)
        {
         tr_buffer[i] = high[i] - low[i];
        }
      else
        {
         tr_buffer[i] = MathMax(high[i] - low[i], MathMax(MathAbs(high[i] - close[i-1]), MathAbs(low[i] - close[i-1])));
        }
     }

// Calculate ATR as SMA
   if(prev_calculated == 0)
     {
      for(int i = 0; i < rates_total; i++)
        {
         if(i < atr_period - 1)
           {
            atr_buffer[i] = EMPTY_VALUE;
           }
         else
           {
            double sum = 0.0;
            for(int j = 0; j < atr_period; j++)
              {
               sum += tr_buffer[i - j];
              }
            atr_buffer[i] = sum / atr_period;
           }
        }
     }
   else
     {
      for(int i = prev_calculated; i < rates_total; i++)
        {
         double sum = 0.0;
         for(int j = 0; j < atr_period; j++)
           {
            sum += tr_buffer[i - j];
           }
         atr_buffer[i] = sum / atr_period;
        }
     }

// Calculate bands
   if(prev_calculated == 0)
     {
      // Reset states
      delay_up1 = 0;
      old_up1 = 0;
      delay_dn1 = 0;
      old_dn1 = 0;

      // Initialize buffers
      ArrayInitialize(up_buffer, EMPTY_VALUE);
      ArrayInitialize(dn_buffer, EMPTY_VALUE);

      for(int i = 0; i < rates_total; i++)
        {
         if(atr_buffer[i] == EMPTY_VALUE)
           {
            up_buffer[i] = EMPTY_VALUE;
            dn_buffer[i] = EMPTY_VALUE;
            continue;
           }

         double src_i = 0.0;
         switch(source)
           {
            case PRICE_CLOSE:    src_i = close[i]; break;
            case PRICE_OPEN:     src_i = open[i]; break;
            case PRICE_HIGH:     src_i = high[i]; break;
            case PRICE_LOW:      src_i = low[i]; break;
            case PRICE_MEDIAN:   src_i = (high[i] + low[i]) / 2.0; break;
            case PRICE_TYPICAL:  src_i = (high[i] + low[i] + close[i]) / 3.0; break;
            case PRICE_WEIGHTED: src_i = (high[i] + low[i] + close[i] + close[i]) / 4.0; break;
           }

         double up = src_i - (atr_mult * atr_buffer[i]);
         double dn = src_i + (atr_mult * atr_buffer[i]);

         if(i == 0)
           {
            up_buffer[i] = up;
            dn_buffer[i] = dn;
            continue; // No update to delays on first bar
           }

         double up1_1 = up_buffer[i - 1];
         double dn1_1 = dn_buffer[i - 1];
         double close1 = close[i - 1];

         // Up band (lower)
         if(close1 > up1_1)
           {
            up = MathMax(up, up1_1);
            delay_up1 = 0;
           }
         else
           {
            if(delay_up1 == 0)
              {
               old_up1 = up1_1;
              }
            delay_up1 += 1;
            if(delay_up1 < delay_period)
              {
               up = old_up1;
              }
           }
         up_buffer[i] = up;

         // Dn band (upper)
         if(close1 < dn1_1)
           {
            dn = MathMin(dn, dn1_1);
            delay_dn1 = 0;
           }
         else
           {
            if(delay_dn1 == 0)
              {
               old_dn1 = dn1_1;
              }
            delay_dn1 += 1;
            if(delay_dn1 < delay_period)
              {
               dn = old_dn1;
              }
           }
         dn_buffer[i] = dn;
        }
     }
   else
     {
      for(int i = prev_calculated; i < rates_total; i++)
        {
         if(atr_buffer[i] == EMPTY_VALUE)
           {
            up_buffer[i] = EMPTY_VALUE;
            dn_buffer[i] = EMPTY_VALUE;
            continue;
           }

         double src_i = 0.0;
         switch(source)
           {
            case PRICE_CLOSE:    src_i = close[i]; break;
            case PRICE_OPEN:     src_i = open[i]; break;
            case PRICE_HIGH:     src_i = high[i]; break;
            case PRICE_LOW:      src_i = low[i]; break;
            case PRICE_MEDIAN:   src_i = (high[i] + low[i]) / 2.0; break;
            case PRICE_TYPICAL:  src_i = (high[i] + low[i] + close[i]) / 3.0; break;
            case PRICE_WEIGHTED: src_i = (high[i] + low[i] + close[i] + close[i]) / 4.0; break;
           }

         double up = src_i - (atr_mult * atr_buffer[i]);
         double dn = src_i + (atr_mult * atr_buffer[i]);

         double up1_1 = up_buffer[i - 1];
         double dn1_1 = dn_buffer[i - 1];
         double close1 = close[i - 1];

         // Up band (lower)
         if(close1 > up1_1)
           {
            up = MathMax(up, up1_1);
            delay_up1 = 0;
           }
         else
           {
            if(delay_up1 == 0)
              {
               old_up1 = up1_1;
              }
            delay_up1 += 1;
            if(delay_up1 < delay_period)
              {
               up = old_up1;
              }
           }
         up_buffer[i] = up;

         // Dn band (upper)
         if(close1 < dn1_1)
           {
            dn = MathMin(dn, dn1_1);
            delay_dn1 = 0;
           }
         else
           {
            if(delay_dn1 == 0)
              {
               old_dn1 = dn1_1;
              }
            delay_dn1 += 1;
            if(delay_dn1 < delay_period)
              {
               dn = old_dn1;
              }
           }
         dn_buffer[i] = dn;
        }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+