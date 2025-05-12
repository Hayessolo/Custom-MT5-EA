# CustomEA Expert Advisor - User Manual

## Table of Contents
1. [Introduction](#introduction)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [Trading Logic](#trading-logic)
5. [Monitoring & Operation](#monitoring--operation)
6. [Testing](#testing)
7. [Troubleshooting](#troubleshooting)
8. [FAQ](#faq)

## Introduction

CustomEA is a MetaTrader 5 Expert Advisor designed for automated trading based on RSI and EMA indicators. It implements:

- Dollar-based risk management for precise position sizing
- Scale-in mechanism at 50% of stop-loss distance
- Trend filtering with H1 EMA
- Entry logic with RSI and EMA pullback signals on M5 timeframe

The EA is designed for forex trading with a focus on precious metals (particularly XAUUSD/Gold).

## Installation

### Step 1: File Placement

1. Open MetaTrader 5
2. Navigate to `File > Open Data Folder` to open your MT5 data directory
3. In the data folder, navigate to:
   ```
   MQL5/Experts/
   ```
4. Copy the `CustomEA.mq5` file into this directory

### Step 2: Compilation

1. In MetaTrader 5, press `F4` to open the MetaEditor
2. In the Navigator panel, expand "Expert Advisors"
3. Locate `CustomEA.mq5`, right-click and select "Compile"
4. Ensure compilation completes without errors
5. Once compiled, the EA will appear as `CustomEA.ex5` in the same directory

## Configuration

### Applying to Chart

1. In MetaTrader 5, open a chart for your desired symbol (recommended: XAUUSD)
2. Set the chart timeframe to M5 (5-minute)
3. In the Navigator panel (`Ctrl+N`), find CustomEA under "Expert Advisors"
4. Either double-click or drag-and-drop the EA onto your chart
5. The EA settings dialog will appear

### Input Parameters

#### Trade Settings

| Parameter | Description | Default | Recommended Range |
|-----------|-------------|---------|------------------|
| TradeMode | BUY or SELL only mode | BUY | Per market analysis |
| RiskPerTrade | Dollar amount to risk per trade | 100.0 | Based on account size |
| ScaleMultiplier | Multiplier for scale-in position size | 1.2 | 1.2 - 1.5 |
| SL_Buffer_Pips | Buffer pips for stop-loss | 15 | 15 - 30 |
| TP_Ratio | Risk:reward ratio for take-profit | 1.0 | 1.0 - 3.0 |
| ScaleIn_Percent | % of SL distance for scale-in | 50.0 | 25.0 - 75.0 |
| MagicNumber | Unique identifier for EA orders | 12345 | Any unique number |
| TradingHours_Start | Trading session start (HH:MM) | "00:00" | Based on preference |
| TradingHours_End | Trading session end (HH:MM) | "23:59" | Based on preference |

#### Trend Filter

| Parameter | Description | Default | Notes |
|-----------|-------------|---------|-------|
| EMA200_Period | Period for H1 EMA trend filter | 200 | Standard setting |

#### Entry Logic Parameters

| Parameter | Description | Default | Notes |
|-----------|-------------|---------|-------|
| RSI_Period | Period for RSI calculation | 14 | Standard setting |
| RSI_Threshold_Buy | RSI level for BUY signals | 30 | 30-35 recommended |
| RSI_Threshold_Sell | RSI level for SELL signals | 70 | 65-70 recommended |
| Entry_EMA20_Period | Period for entry EMA | 20 | Standard setting |
| TurnoverCandles | Consecutive candles for confirmation | 2 | 1-3 recommended |
| SwingLookbackBars | Bars to check for swing points | 20 | Adjust per instrument |

### Common Parameter Adjustments

- **For More Conservative Trading**: Increase RSI thresholds (35 for buys, 65 for sells)
- **For More Aggressive Trading**: Decrease RSI thresholds (25 for buys, 75 for sells)
- **For Wider Stop-Loss**: Increase SL_Buffer_Pips to 20-30
- **For Better Risk:Reward**: Increase TP_Ratio to 1.5 or 2.0

## Trading Logic

### How CustomEA Works

The EA implements a multi-timeframe strategy:

1. **Trend Filter (H1 timeframe)**
   - For BUY: Price must be above 200 EMA
   - For SELL: Price must be below 200 EMA

2. **Entry Logic (M5 timeframe)**
   - **RSI Condition**:
     - For BUY: RSI must be at or below RSI_Threshold_Buy (default: 30)
     - For SELL: RSI must be at or above RSI_Threshold_Sell (default: 70)
   
   - **Pullback Detection**:
     - For BUY: Price pulls back to 20 EMA (touches or crosses from below)
     - For SELL: Price pulls back to 20 EMA (touches or crosses from above)
   
   - **Turnover Confirmation**:
     - For BUY: 2 consecutive bullish candles (close > open)
     - For SELL: 2 consecutive bearish candles (close < open)

3. **Risk Management**
   - Stop-loss based on recent swing low/high plus buffer
   - Position size calculated based on dollar risk and distance to SL
   - Take-profit set at TP_Ratio times the SL distance

4. **Scale-In Strategy**
   - When price moves against position by 50% of SL distance
   - Scale-in position is larger by ScaleMultiplier (default: 1.2x)
   - Only one scale-in per original position
   - Identical SL and TP for both positions

## Monitoring & Operation

### Starting the EA

1. After attaching the EA to a chart, ensure all parameters are set correctly
2. Make sure the "AutoTrading" button is enabled (top toolbar, should display a smiling face)
3. The EA will automatically start monitoring for trade conditions

### Switching Trade Direction

To change from BUY to SELL mode (or vice versa):

1. Right-click on the chart and select "Expert Advisors > Properties"
2. Change the "TradeMode" parameter
3. Click "OK" to apply the changes

### Monitoring Activity

- Check the "Experts" tab (Ctrl+T) to see EA messages and activity logs
- All trades will be tagged with your specified MagicNumber
- Scale-in trades will have comments referencing the original trade ticket

## Testing

### Strategy Tester

Before using the EA with real funds, thoroughly test it:

1. Press Ctrl+R to open the Strategy Tester
2. Select "CustomEA" from the Expert Advisor dropdown
3. Configure:
   - Symbol: XAUUSD (or your trading instrument)
   - Timeframe: M5
   - Model: "Every tick" for most accurate results
   - Date range: At least 3-6 months of data
4. Click "Start" to run the test

### Forward Testing

After successful backtesting:

1. Apply the EA to a demo account for at least 2-4 weeks
2. Monitor its performance across various market conditions
3. Only move to a live account after satisfactory results

## Troubleshooting

### Common Issues

1. **"AutoTrading disabled"**
   - Check the "AutoTrading" button in MT5
   - Ensure EA is allowed to trade in platform settings

2. **No Trades Being Opened**
   - Check the RSI threshold values
   - Verify trend filter conditions
   - Check Expert logs for error messages
   - Ensure sufficient account balance

3. **Scale-In Not Triggering**
   - Check ScaleIn_Percent setting
   - Verify position has proper stop-loss set
   - Check Expert logs for any errors

4. **Lot Size Too Small/Large**
   - Adjust RiskPerTrade parameter
   - Check lot limits for your instrument

### Error Messages

| Error Message | Possible Cause | Solution |
|---------------|----------------|----------|
| "Error copying buffer" | Indicator data unavailable | Restart platform or check network |
| "SL pips distance too small" | Stop-loss too close to entry | Increase SL_Buffer_Pips |
| "Invalid pip value" | Symbol not supported correctly | Try updating pip calculation method |
| "Error initializing CSymbolInfo" | Symbol issues | Verify symbol available on your broker |

## FAQ

**Q: Is CustomEA suitable for day trading?**
A: Yes, the EA is designed for intraday trading with a focus on the M5 timeframe.

**Q: Can I use CustomEA on any forex pair?**
A: Yes, but it was primarily designed for XAUUSD/Gold. You may need to adjust parameters for other symbols.

**Q: How much capital do I need to use CustomEA effectively?**
A: The EA uses dollar-based risk sizing, so it can adapt to any account size. A reasonable starting point would be at least 20x your RiskPerTrade setting.

**Q: Can I add additional indicators to the EA?**
A: Not without modifying the source code. If you have programming skills, you can enhance the EA by editing CustomEA.mq5.

**Q: What if I want to disable scale-in functionality?**
A: You can effectively disable it by setting ScaleIn_Percent to a large value like 99.0.

---

*Last Updated: May 12, 2025*

*For support or questions, please contact your EA provider.*
