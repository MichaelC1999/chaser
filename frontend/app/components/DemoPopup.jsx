import React, { useEffect, useState } from 'react';


function DemoPopup({ step, clearDemoStep, turnOffDemo }) {

  const poolInstructions = [
    "In order to initialize your pool, you must set the position and send an initial deposit.\nFor this demo, set the position as the WETH market on Compound Base Sepolia and send 0.0001 WETH\n\nPart of the transaction sequence includes wrapping your ETH and approving WETH, if you do not have a sufficient WETH balance and allowance to the pool\n\n\b(Turn Demo mode OFF to test different protocols, networks, and amounts)", //tx executes
    "After the first deposit and position setting, we can see that your funds are currently invested into Compound.",
    "For this demo, the strategy that we are using is a simple comparison of current yields. In production, strategy contracts use the UMA Optimistic Oracle to let pools use a wide range of metrics to define what is a 'better' investment. Strategy examples include:\n\n\bHighest Yield with Lowest Historical volatility\n\bBest 90d Average Yield\n\bInvestments with Daily Volume over $1m\n\bHighest APY of a pool with a whale worth over $20m\n\bAny other measuable, custom metric!",
    "After checking some other protocols, we saw that the WETH market on Aave Sepolia yields 0.23%, higher than the 0.00071% we are currently yielding on Compound Base Sepolia. As you can see in the 'Pivot Position' section, Aave and Sepolia have been pre-filled.\n\n\bSend the Pivot.", //tx executes
    "As was stated in the TX popup, this pivot has multiple steps and will take up to 30 minutes to finalize. It uses the Across bridge to send the deposits to Sepolia, deposit into Aave, and then send a CCIP callback message to Base Sepolia to confirm that the new position was set.",
    'Keep in mind that in production, there will be an entire process for proposing a new market to pivot investment to. To streamline testing and demo, moving funds between markets is done with a single function call triggered by the "Send Pivot" button. Look at the "Is Pivoting" row above. Once the pivot has completed, this value will be marked false.',
    "There is currently a Pivot being executed on this pool. Keep waiting for the bridging and callbacks to finalize.",
    "Now that we see that the Pivot was successful has finalized, it is now time to withdraw your funds. Set an amount and then click the 'withdraw' button."
  ]


  if (!step && step !== 0 || step >= poolInstructions.length) return null
  return (
    <div className="popup-container">
      <div className="popup">
        <div style={{ width: "100%", display: "flex", justifyContent: "flex-end" }}>
          <button style={{ backgroundColor: "red", marginLeft: "16px" }} onClick={() => turnOffDemo()} className={'demoButton'}><b>Off</b></button>

        </div>
        <div className="popup-title">Demo</div>
        <div className="popup-message">{poolInstructions[step].split('\n').map((x, idx) => {
          if (x === '') {
            return <br key={idx} />
          }
          if (x.includes('\b')) {
            return <span key={idx} style={{ display: "block" }}><b>{x.split('\b').join('')}</b></span>
          }
          return <span key={idx} style={{ display: "block" }}>{x}</span>
        })}</div>
        <button onClick={() => clearDemoStep()} className="popup-ok-button">OK</button>
      </div>
    </div>
  );
}

export default DemoPopup;