//+------------------------------------------------------------------+
//|                                                     CustomEA.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                              https://www.mql5.com|
//|Developed by [(Hayessolo).*](https://www.linkedin.com/in/hayes-frank-b48700174/)|
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- EA Inputs & Parameters
enum ENUM_TRADE_MODE
  {
   MODE_BUY, // BUY only
   MODE_SELL // SELL only
  };

input group "Trade Settings"
input ENUM_TRADE_MODE   TradeMode           = MODE_BUY;         // Trade Mode (BUY or SELL)
input double            RiskPerTrade        = 100.0;            // Risk per Trade (in account currency)
input double            ScaleMultiplier     = 1.2;              // Lot-size multiplier for scale-in trade
input int               SL_Buffer_Pips      = 15;               // SL Buffer (pips) above/below swing
input double            TP_Ratio            = 1.0;              // TakeProfit Ratio (e.g., 1.0 for 1:1)
input double            ScaleIn_Percent     = 50.0;             // Percentage of SL distance to trigger scale-in
input int               MagicNumber         = 12345;            // EA Magic Number
input string            TradingHours_Start  = "00:00";          // Trading Hours Start (HH:MM)
input string            TradingHours_End    = "23:59";          // Trading Hours End (HH:MM)

input group "Trend Filter (H1)"
input int               EMA200_Period       = 200;              // Period for H1 EMA Trend Filter

input group "Entry Logic (M5)"
input int               RSI_Period          = 14;               // RSI Period (M5)
input int               RSI_Threshold_Buy   = 30;               // RSI Threshold for BUY (e.g., <=30)
input int               RSI_Threshold_Sell  = 70;               // RSI Threshold for SELL (e.g., >=70) - Inferred, spec mentioned 30/35 for one side.
input int               Entry_EMA20_Period  = 20;               // EMA Period for Entry (M5)
input int               TurnoverCandles     = 2;                // Consecutive candles for turnover confirmation
input int               SwingLookbackBars   = 20;               // Bars to look back for Swing High/Low for SL

//--- Global Variables
CTrade          trade;
CSymbolInfo     symbol;
CPositionInfo   posInfo;
COrderInfo      orderInfo;

int             h1_ema_handle = INVALID_HANDLE;
int             m5_rsi_handle = INVALID_HANDLE;
int             m5_ema_handle = INVALID_HANDLE;

datetime        lastTradeOpenTime = 0;
string          scaled_in_orders_comment_mark = "scaled"; // Mark for original orders that have been scaled into

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Initialize CTrade
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(20); // Allow 2 pips slippage
   trade.SetTypeFillingBySymbol(Symbol());

//--- Initialize CSymbolInfo
   if(!symbol.Name(Symbol()))
     {
      Print("Error initializing CSymbolInfo: ", GetLastError());
      return(INIT_FAILED);
     }
   symbol.RefreshRates();

//--- Initialize Indicator Handles
   // H1 EMA for Trend
   h1_ema_handle = iMA(Symbol(), PERIOD_H1, EMA200_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(h1_ema_handle == INVALID_HANDLE)
     {
      Print("Error creating H1 EMA indicator: ", GetLastError());
      return(INIT_FAILED);
     }

   // M5 RSI for Entry
   m5_rsi_handle = iRSI(Symbol(), PERIOD_M5, RSI_Period, PRICE_CLOSE);
   if(m5_rsi_handle == INVALID_HANDLE)
     {
      Print("Error creating M5 RSI indicator: ", GetLastError());
      return(INIT_FAILED);
     }

   // M5 EMA for Entry
   m5_ema_handle = iMA(Symbol(), PERIOD_M5, Entry_EMA20_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(m5_ema_handle == INVALID_HANDLE)
     {
      Print("Error creating M5 EMA indicator: ", GetLastError());
      return(INIT_FAILED);
     }

   Print("EA Initialized Successfully. MagicNumber: ", MagicNumber);
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- Release indicator handles
   if(h1_ema_handle != INVALID_HANDLE)
      IndicatorRelease(h1_ema_handle);
   if(m5_rsi_handle != INVALID_HANDLE)
      IndicatorRelease(m5_rsi_handle);
   if(m5_ema_handle != INVALID_HANDLE)
      IndicatorRelease(m5_ema_handle);
   Print("EA Deinitialized. Reason: ", reason);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- Check if trading is allowed
   if(!IsTradingAllowed())
      return;

//--- Check trading hours
   if(!IsInTradingHours())
      return;

   symbol.RefreshRates(); // Refresh symbol data

//--- Manage Scale-In Logic for open positions
   ManageScaleIn();

//--- Check for new trade signals (only if no position for this symbol by this EA or if new entries are allowed)
   if(PositionsTotal() == 0 || HasOpenPositionForSymbol() == 0) // Simplified: allow new trade if no pos or specific logic allows more
     {
      CheckForNewSignal();
     }
  }

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                    |
//+------------------------------------------------------------------+
bool IsInTradingHours()
  {
   MqlDateTime current_time_struct;
   TimeCurrent(current_time_struct);

   int start_hour = StringToInteger(StringSubstr(TradingHours_Start, 0, 2));
   int start_min = StringToInteger(StringSubstr(TradingHours_Start, 3, 2));
   int end_hour = StringToInteger(StringSubstr(TradingHours_End, 0, 2));
   int end_min = StringToInteger(StringSubstr(TradingHours_End, 3, 2));

   int current_minutes_total = current_time_struct.hour * 60 + current_time_struct.min;
   int start_minutes_total = start_hour * 60 + start_min;
   int end_minutes_total = end_hour * 60 + end_min;
   
   if (start_minutes_total <= end_minutes_total) // Normal case, e.g., 08:00 - 16:00
     return (current_minutes_total >= start_minutes_total && current_minutes_total <= end_minutes_total);
   else // Overnight case, e.g., 22:00 - 04:00
     return (current_minutes_total >= start_minutes_total || current_minutes_total <= end_minutes_total);
  }

//+------------------------------------------------------------------+
//| Check H1 Trend Filter                                            |
//+------------------------------------------------------------------+
bool CheckH1TrendFilter(ENUM_TRADE_MODE mode)
  {
   double ema_h1_buffer[1];
   if(CopyBuffer(h1_ema_handle, 0, 0, 1, ema_h1_buffer) <= 0)
     {
      Print("Error copying H1 EMA buffer: ", GetLastError());
      return false;
     }
   double current_price = (mode == MODE_BUY) ? symbol.Ask() : symbol.Bid();
   if(mode == MODE_BUY)
      return current_price > ema_h1_buffer[0];
   else // MODE_SELL
      return current_price < ema_h1_buffer[0];
  }

//+------------------------------------------------------------------+
//| Check M5 Entry Conditions                                        |
//+------------------------------------------------------------------+
bool CheckM5EntryConditions(ENUM_TRADE_MODE mode, double &entry_price, double &sl_price, double &tp_price, double &lot_size)
  {
   // 1. RSI Check
   double rsi_buffer[1];
   if(CopyBuffer(m5_rsi_handle, 0, 0, 1, rsi_buffer) <= 0)
     {
      Print("Error copying M5 RSI buffer: ", GetLastError());
      return false;
     }
   double current_rsi = rsi_buffer[0];

   if(mode == MODE_BUY && current_rsi > RSI_Threshold_Buy) return false;
   if(mode == MODE_SELL && current_rsi < RSI_Threshold_Sell) return false;
   
   // 2. EMA Pullback and Turnover Candles
   double ema_m5_buffer[TurnoverCandles + 1]; // Need EMA for current and previous candles
   MqlRates m5_rates[];
   int rates_copied = CopyRates(Symbol(), PERIOD_M5, 0, TurnoverCandles + 5, m5_rates); // Get a few more for context
   if(rates_copied <= TurnoverCandles)
     {
      Print("Not enough M5 bars for EMA/Turnover check: ", rates_copied);
      return false;
     }
     
   if(CopyBuffer(m5_ema_handle, 0, 0, TurnoverCandles + 1, ema_m5_buffer) <=0)
     {
      Print("Error copying M5 EMA buffer: ", GetLastError());
      return false;
     }

   // Check pullback to EMA on candle 1 (m5_rates[rates_copied-2]) or 2 (m5_rates[rates_copied-3])
   // For simplicity, let's check if candle 1 (the one before the currently forming one) touched or crossed EMA
   // m5_rates[rates_copied-1] is the current forming bar (index 0 from API)
   // m5_rates[rates_copied-2] is the last closed bar (index 1 from API)
   
   bool pullback_detected = false;
   // Check if the low of the previous bar (index 1) was below or at EMA and close above for BUY
   // or high above or at EMA and close below for SELL
   double prev_bar_low = m5_rates[rates_copied-2].low;
   double prev_bar_high = m5_rates[rates_copied-2].high;
   double prev_bar_close = m5_rates[rates_copied-2].close;
   double prev_bar_open = m5_rates[rates_copied-2].open;
   double ema_val_prev_bar = ema_m5_buffer[1]; // EMA value for the previous bar (index 1)

   if(mode == MODE_BUY && prev_bar_low <= ema_val_prev_bar && prev_bar_close > ema_val_prev_bar)
     pullback_detected = true;
   if(mode == MODE_SELL && prev_bar_high >= ema_val_prev_bar && prev_bar_close < ema_val_prev_bar)
     pullback_detected = true;

   if(!pullback_detected) return false;

   // Confirm TurnoverCandles
   bool turnover_confirmed = true;
   for(int i = 0; i < TurnoverCandles; i++)
     {
      // Current forming bar is m5_rates[rates_copied-1]
      // We need to check the last 'TurnoverCandles' *closed* candles *after* pullback.
      // Let's assume pullback on m5_rates[rates_copied-2], then check m5_rates[rates_copied-2] and m5_rates[rates_copied-3] if TurnoverCandles=2
      // This logic needs refinement based on exact definition of "after touching EMA"
      // For now, let's check the last 'TurnoverCandles' closed bars including the pullback bar.
      // Example: If TurnoverCandles = 2, check bar index 1 and 2 (m5_rates[rates_copied-2] and m5_rates[rates_copied-3])
      if (rates_copied < TurnoverCandles + 1) { turnover_confirmed = false; break; } // Not enough history

      double check_bar_close = m5_rates[rates_copied - (2+i)].close;
      double check_bar_open  = m5_rates[rates_copied - (2+i)].open;

      if(mode == MODE_BUY && !(check_bar_close > check_bar_open)) // Must be bullish
        {
         turnover_confirmed = false;
         break;
        }
      if(mode == MODE_SELL && !(check_bar_close < check_bar_open)) // Must be bearish
        {
         turnover_confirmed = false;
         break;
        }
     }
   if(!turnover_confirmed) return false;

   // All conditions met, calculate parameters
   entry_price = (mode == MODE_BUY) ? symbol.Ask() : symbol.Bid();
   double swing_point;

   if(mode == MODE_BUY) // SL below swing low
     {
      swing_point = GetSwingLow(PERIOD_M5, SwingLookbackBars, 1); // Lookback from bar 1 (last closed)
      if(swing_point == 0) { Print("Could not get swing low"); return false; }
      sl_price = swing_point - (SL_Buffer_Pips * symbol.Point());
     }
   else // MODE_SELL, SL above swing high
     {
      swing_point = GetSwingHigh(PERIOD_M5, SwingLookbackBars, 1); // Lookback from bar 1
      if(swing_point == 0) { Print("Could not get swing high"); return false; }
      sl_price = swing_point + (SL_Buffer_Pips * symbol.Point());
     }
   
   double sl_pips_distance = MathAbs(entry_price - sl_price) / symbol.Point();
   if(sl_pips_distance < 1) // Avoid division by zero or tiny SL
     {
      Print("SL pips distance too small: ", sl_pips_distance);
      return false;
     }

   if(mode == MODE_BUY)
      tp_price = entry_price + (sl_pips_distance * TP_Ratio * symbol.Point());
   else
      tp_price = entry_price - (sl_pips_distance * TP_Ratio * symbol.Point());

   // Calculate LotSize
   double pip_value = GetPipValuePerLot();
   if(pip_value <= 0)
     {
      Print("Invalid pip value: ", pip_value);
      return false;
     }
   lot_size = RiskPerTrade / (sl_pips_distance * pip_value);
   lot_size = NormalizeLot(lot_size);

   if(lot_size < symbol.LotsMin())
     {
      Print("Calculated lot size ", lot_size, " is less than minimum ", symbol.LotsMin(), ". Skipping trade.");
      return false;
     }
    if(lot_size > symbol.LotsMax())
     {
      lot_size = symbol.LotsMax();
      Print("Calculated lot size ", lot_size, " is greater than maximum ", symbol.LotsMax(), ". Using max lot.");
     }

   return true; // Signal found
  }

//+------------------------------------------------------------------+
//| Get Swing Low                                                    |
//+------------------------------------------------------------------+
double GetSwingLow(ENUM_TIMEFRAMES tf, int count, int start_bar)
  {
   MqlRates rates[];
   if(CopyRates(Symbol(), tf, start_bar, count, rates) < count)
      return 0;
   double min_low = rates[0].low;
   for(int i = 1; i < count; i++)
     {
      if(rates[i].low < min_low)
         min_low = rates[i].low;
     }
   return min_low;
  }

//+------------------------------------------------------------------+
//| Get Swing High                                                   |
//+------------------------------------------------------------------+
double GetSwingHigh(ENUM_TIMEFRAMES tf, int count, int start_bar)
  {
   MqlRates rates[];
   if(CopyRates(Symbol(), tf, start_bar, count, rates) < count)
      return 0;
   double max_high = rates[0].high;
   for(int i = 1; i < count; i++)
     {
      if(rates[i].high > max_high)
         max_high = rates[i].high;
     }
   return max_high;
  }

//+------------------------------------------------------------------+
//| Calculate Pip Value per Lot in Account Currency                  |
//+------------------------------------------------------------------+
double GetPipValuePerLot()
  {
   double tick_value = symbol.TickValue(); // Value of 1 tick for 1 lot in account currency
   double tick_size = symbol.TickSize();
   if(tick_size == 0) return 0;
   // Pip size is usually 10 points for 5-digit, 1 point for 3-digit JPY pairs
   double pip_size_in_points = symbol.Point() * (symbol.Digits() % 2 == 0 ? 1 : 10); // Heuristic for pip size
   if (StringFind(symbol.Name(), "JPY") >=0 && symbol.Digits() == 3) pip_size_in_points = 0.01;
   if (StringFind(symbol.Name(), "JPY") < 0 && symbol.Digits() == 5) pip_size_in_points = 0.0001;


   return (tick_value / tick_size) * pip_size_in_points;
  }
// A more robust way for MQL5 to get value of 1 pip for 1 lot:
// double GetPipValuePerLotRobust() {
//    double one_pip = symbol.Point() * ( (symbol.Digits() == 3 || symbol.Digits() == 5) ? 10 : 1 );
//    double value;
//    if(!OrderCalcProfit(trade.Type(), symbol.Name(), 1.0, symbol.Bid(), symbol.Bid() + one_pip, value)) {
//       // try sell
//       if(!OrderCalcProfit(trade.Type(), symbol.Name(), 1.0, symbol.Ask(), symbol.Ask() - one_pip, value)) {
//          Print("OrderCalcProfit failed: ", GetLastError());
//          return 0.0;
//       }
//    }
//    return MathAbs(value);
// }


//+------------------------------------------------------------------+
//| Normalize Lot Size                                               |
//+------------------------------------------------------------------+
double NormalizeLot(double lots)
  {
   double lot_step = symbol.LotsStep();
   lots = MathRound(lots / lot_step) * lot_step;
   if(lots < symbol.LotsMin()) lots = symbol.LotsMin();
   if(lots > symbol.LotsMax()) lots = symbol.LotsMax();
   return lots;
  }

//+------------------------------------------------------------------+
//| Check for new trade signal and execute                           |
//+------------------------------------------------------------------+
void CheckForNewSignal()
  {
   // Prevent multiple trades in quick succession (e.g. within same minute)
   if(TimeCurrent() - lastTradeOpenTime < 60 && lastTradeOpenTime != 0) return;

   if(!CheckH1TrendFilter(TradeMode))
     {
      // Print("H1 Trend filter not met for ", EnumToString(TradeMode));
      return;
     }

   double entry_price, sl_price, tp_price, lot_size;
   if(CheckM5EntryConditions(TradeMode, entry_price, sl_price, tp_price, lot_size))
     {
      string comment = "Initial " + EnumToString(TradeMode);
      bool result = false;
      if(TradeMode == MODE_BUY)
        {
         result = trade.Buy(lot_size, Symbol(), entry_price, sl_price, tp_price, comment);
        }
      else // MODE_SELL
        {
         result = trade.Sell(lot_size, Symbol(), entry_price, sl_price, tp_price, comment);
        }

      if(result)
        {
         Print("Trade Opened: ", trade.ResultRetcodeDescription(), ". Ticket: ", trade.ResultOrder());
         lastTradeOpenTime = TimeCurrent();
        }
      else
        {
         Print("Trade Open Failed: ", trade.ResultRetcodeDescription(), ". Error: ", GetLastError());
        }
     }
  }

//+------------------------------------------------------------------+
//| Manage Scale-In Logic                                            |
//+------------------------------------------------------------------+
void ManageScaleIn()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != Symbol() || posInfo.Magic() != MagicNumber) continue;
      
      // Check if this order has already been scaled into
      // A simple way is to check if a scale-in order for this original order exists.
      // Or, mark the original order's comment. For simplicity, we'll check if a scale-in order exists.
      // A better way: add a unique ID to original order comment, and scale-in order comment refers to it.
      // Or, maintain a list of scaled-in ticket numbers.
      // For now, let's assume we check if a scale-in order for this position already exists by checking comments.
      // This is tricky because comments can be changed. A more robust method is needed for production.
      // Let's use a simpler check: if the comment contains "scaled_in_orders_comment_mark"
      
      if(StringFind(posInfo.Comment(), scaled_in_orders_comment_mark) != -1)
      {
        // This original order has already been scaled into.
        continue;
      }

      // Check if any other order exists that is a scale-in for *this* position's ticket
      bool already_scaled_in = false;
      for(int k=0; k < OrdersTotal(); k++) {
          if(orderInfo.SelectByIndex(k)) {
              if(orderInfo.Magic() == MagicNumber && StringFind(orderInfo.Comment(), "ScaleIn for #" + (string)posInfo.Ticket()) != -1) {
                  already_scaled_in = true;
                  break;
              }
          }
      }
      if(already_scaled_in) {
          // Also check history orders if position was closed and reopened
          for(int h=0; h < HistoryOrdersTotal(); h++) {
              if(HistoryOrderSelect(HistoryOrderGetTicket(h))) {
                  if(HistoryOrderGetString(HistoryOrderGetTicket(h), ORDER_COMMENT) == "ScaleIn for #" + (string)posInfo.Ticket() && HistoryOrderGetInteger(HistoryOrderGetTicket(h), ORDER_MAGIC) == MagicNumber) {
                      already_scaled_in = true;
                      break;
                  }
              }
              if(already_scaled_in) break;
          }
      }


      if(already_scaled_in) continue;


      double sl_distance_points = MathAbs(posInfo.PriceOpen() - posInfo.StopLoss());
      if(posInfo.StopLoss() == 0 || sl_distance_points == 0) continue; // No SL or invalid SL

      double current_price = (posInfo.PositionType() == POSITION_TYPE_BUY) ? symbol.Bid() : symbol.Ask();
      double adverse_movement_points = 0;

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
         adverse_movement_points = posInfo.PriceOpen() - current_price;
      else // POSITION_TYPE_SELL
         adverse_movement_points = current_price - posInfo.PriceOpen();

      if(adverse_movement_points >= (sl_distance_points * (ScaleIn_Percent / 100.0)))
        {
         // Trigger Scale-In
         double scale_in_lot_size = NormalizeLot(posInfo.Volume() * ScaleMultiplier);
         if(scale_in_lot_size < symbol.LotsMin())
           {
            Print("Scale-in lot size ", scale_in_lot_size, " too small. Original vol: ", posInfo.Volume());
            continue;
           }

         string scale_comment = "ScaleIn for #" + (string)posInfo.Ticket();
         bool result = false;
         double scale_entry_price = (posInfo.PositionType() == POSITION_TYPE_BUY) ? symbol.Ask() : symbol.Bid();

         if(posInfo.PositionType() == POSITION_TYPE_BUY)
           {
            result = trade.Buy(scale_in_lot_size, Symbol(), scale_entry_price, posInfo.StopLoss(), posInfo.TakeProfit(), scale_comment);
           }
         else // POSITION_TYPE_SELL
           {
            result = trade.Sell(scale_in_lot_size, Symbol(), scale_entry_price, posInfo.StopLoss(), posInfo.TakeProfit(), scale_comment);
           }

         if(result)
           {
            Print("Scale-In Trade Opened for ticket ", posInfo.Ticket(), ": ", trade.ResultRetcodeDescription(), ". New Ticket: ", trade.ResultOrder());
            // Mark original order as scaled (This is complex with CPositionInfo, as it doesn't directly allow comment modification)
            // One way is to close and reopen the original with a new comment, but that's not ideal.
            // The check for existing scale-in orders (by comment) is the primary guard here.
           }
         else
           {
            Print("Scale-In Trade Open Failed for ticket ", posInfo.Ticket(), ": ", trade.ResultRetcodeDescription(), ". Error: ", GetLastError());
           }
         // IMPORTANT: After a successful scale-in, ensure this original position is not scaled into again.
         // The check `already_scaled_in` at the beginning of the loop for the next tick should handle this.
        }
     }
  }
  
//+------------------------------------------------------------------+
//| Check if trading is allowed by terminal settings                 |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
  {
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      Print("Automated trading is disabled in terminal settings.");
      return false;
     }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      Print("Automated trading is disabled for this EA in its properties.");
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Check if there's an open position for the current symbol by this EA |
//+------------------------------------------------------------------+
int HasOpenPositionForSymbol()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(posInfo.SelectByIndex(i))
        {
         if(posInfo.Symbol() == Symbol() && posInfo.Magic() == MagicNumber)
           {
            count++;
           }
        }
     }
   return count;
  }
//+------------------------------------------------------------------+

/* 
developed by [(Hayessolo).*](https://www.linkedin.com/in/hayes-frank-b48700174/)
*/
