/*

   MA Cross with Formula TS.mqh
   Copyright 2022, Orchard Forex
   https://www.orchardforex.com

*/

#property copyright "Copyright 2022, Orchard Forex"
#property link "https://www.orchardforex.com"
#property version "1.00"
#property strict

//
//	Inputs
//
//
//	Fast MA
//
input int                InpFastMABars         = 20;          // Fast MA Bars
input ENUM_MA_METHOD     InpFastMAMethod       = MODE_EMA;    // Fast MA Method
input ENUM_APPLIED_PRICE InpFastMAAppliedPrice = PRICE_CLOSE; // Fast MA Applied Price

//
//	Slow MA
//
input int                InpSlowMABars         = 50;          // Slow MA Bars
input ENUM_MA_METHOD     InpSlowMAMethod       = MODE_EMA;    // Slow MA Method
input ENUM_APPLIED_PRICE InpSlowMAAppliedPrice = PRICE_CLOSE; // Slow MA Applied Price
input int                InpSlowMAShift        = 0;           // Slow MA shift

//
// Trailing Stop based on ATR
//
input int                InpATRBars            = 10;  // ATR Bars for trailing stop
input double             InpATRFactor          = 2.0; // ATR Multiplier for trailing stop

//
//	The basic expert uses fixed take profit, stop loss and order size
//
input double             InpOrderSize          = 0.01;  // Order size in lots
input double             InpTakeProfitPips     = 100.0; // Take profit in pips
input double             InpStopLossPips       = 100.0; // Stop loss in pips

//
//	Trades also have a magic number and a comment
//
input int                InpMagic              = 222222;                     // Magic number
input string             InpTradeComment       = "Example MA Cross with TS"; // Trade comment

// Some global values
double                   TakeProfit;
double                   StopLoss;
double                   ATRValue;

//
//	Pips, points conversion
//
double                   PipSize() { return ( PipSize( Symbol() ) ); }
double                   PipSize( string symbol ) {
   double point  = SymbolInfoDouble( symbol, SYMBOL_POINT );
   int    digits = ( int )SymbolInfoInteger( symbol, SYMBOL_DIGITS );
   return ( ( ( digits % 2 ) == 1 ) ? point * 10 : point );
}

double PipsToDouble( double pips ) { return ( pips * PipSize( Symbol() ) ); }
double PipsToDouble( double pips, string symbol ) { return ( pips * PipSize( symbol ) ); }

bool   IsMarketOpen() { return IsMarketOpen( Symbol(), TimeCurrent() ); }
bool   IsMarketOpen( datetime time ) { return IsMarketOpen( Symbol(), time ); }
bool   IsMarketOpen( string symbol, datetime time ) {

   static string   lastSymbol   = "";
   static bool     isOpen       = false;
   static datetime sessionStart = 0;
   static datetime sessionEnd   = 0;

   if ( lastSymbol == symbol && sessionEnd > sessionStart ) {
      if ( ( isOpen && time >= sessionStart && time <= sessionEnd ) || ( !isOpen && time > sessionStart && time < sessionEnd ) ) return isOpen;
   }

   lastSymbol = symbol;

   MqlDateTime mtime;
   TimeToStruct( time, mtime );
   datetime seconds  = mtime.hour * 3600 + mtime.min * 60 + mtime.sec;

   mtime.hour        = 0;
   mtime.min         = 0;
   mtime.sec         = 0;
   datetime dayStart = StructToTime( mtime );
   datetime dayEnd   = dayStart + 86400;

   datetime fromTime;
   datetime toTime;

   sessionStart = dayStart;
   sessionEnd   = dayEnd;

   for ( int session = 0;; session++ ) {

      if ( !SymbolInfoSessionTrade( symbol, ( ENUM_DAY_OF_WEEK )mtime.day_of_week, session, fromTime, toTime ) ) {
         sessionEnd = dayEnd;
         isOpen     = false;
         return isOpen;
      }

      if ( seconds < fromTime ) { // not inside a session
         sessionEnd = dayStart + fromTime;
         isOpen     = false;
         return isOpen;
      }

      if ( seconds > toTime ) { // maybe a later session
         sessionStart = dayStart + toTime;
         continue;
      }

      // at this point must be inside a session
      sessionStart = dayStart + fromTime;
      sessionEnd   = dayStart + toTime;
      isOpen       = true;
      return isOpen;
   }

   return false;
}

bool IsNewBar( bool first_call = false ) {

   static bool result = false;
   if ( !first_call ) return ( result );

   static datetime previous_time = 0;
   datetime        current_time  = iTime( Symbol(), Period(), 0 );
   result                        = false;
   if ( previous_time != current_time ) {
      previous_time = current_time;
      result        = true;
   }
   return ( result );
}
