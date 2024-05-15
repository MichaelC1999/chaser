import React, { useEffect, useState } from 'react';
import { hexToString, numberToHex, zeroAddress } from 'viem';
import PoolABI from '../ABI/PoolABI.json'; // Adjust the path as needed
import networks from '../JSON/networks.json'
import protocolHashes from '../JSON/protocolHashes.json'
import contractAddresses from '../JSON/contractAddresses.json'
import InvestmentStrategyABI from '../ABI/InvestmentStrategyABI.json'; // Adjust the path as needed
import Loader from './Loader.jsx';
import { decodePoolPivot, fetchAcrossRelayFillTx, findAcrossDepositFromTxHash, findCcipMessageFromTxHash, userLastDeposit } from "../utils.jsx"

import PoolCalculationABI from '../ABI/PoolCalculationsABI.json'; // Adjust the path as needed
import { ethers, parseEther, solidityPackedKeccak256 } from 'ethers';


function StrategyPopup({ provider, strategyIndex, setStrategyIndex, strategies, setShowStrategyPopup }) {
    const [newStrategy, setNewStrategy] = useState(false)
    const [strategyToView, setStrategyToView] = useState(null)

    const [strategyCode, setStrategyCode] = useState("")

    useEffect(() => {
        console.log('reached strategy popup')
    }, [])

    useEffect(() => {
        // Fetch code from strategy contract
        if (strategyToView || strategyToView === 0) {
            getStrategyLogic()
        }
    }, [strategyToView])

    const getStrategyLogic = async () => {

        const investmentStrategyContract = new ethers.Contract(contractAddresses.sepolia["investmentStrategy"], InvestmentStrategyABI, provider);
        const code = hexToString(await investmentStrategyContract.strategyCode(strategyToView))
        console.log(code)
        setStrategyCode(code)
    }



    // DISPLAY 1 - SHOW LIST OF STRATEGY NAMES (else)
    // DISPLAY 2 - DEPENDING ON THE STRATEGY INDEX PROVIDED, READ THE STRATEGY CODE AND DISPLAY IT (if state.strategyToView)
    // DISPLAY 3 - INPUTS FOR CREATING NEW STRATEGY if (state.newStrategy)

    let display = (<>
        <select value={strategyIndex} onChange={(e) => setStrategyIndex(e.target.value)}>
            {(strategies).map((name, idx) => (
                <option key={name} value={idx}>{name}</option>
            ))}
        </select>
        <button onClick={() => setStrategyToView(strategyIndex)}>View Strategy Logic</button>
    </>)

    let displaySection = <>
        <div style={{ width: "100%", display: "flex", justifyContent: "flex-end" }}>
            <div style={{ backgroundColor: "#374d59", marginRight: "30px", width: "134px", textAlign: "center", border: "white 1px solid" }} onClick={() => setShowStrategyPopup(false)} className={'demoButton button'}>
                <b>Close</b>
            </div>
        </div>
        <div className="popup-title">Strategy Selection</div>
        <div className="popup-message">
            {display}
        </div></>

    if (strategyToView) {
        if (strategyCode) {
            display = <div style={{ fontFamily: "Courier New", fontWeight: "lighter", width: "100%", overflow: "scroll", backgroundColor: "black", color: "white", whiteSpace: "pre-wrap" }}>
                {strategyCode}

            </div>
        } else {
            display = <Loader />
        }
        displaySection = <>
            <div className="popup-title">{strategies[strategyToView]}</div>
            <div style={{ backgroundColor: "#374d59", marginRight: "30px", width: "134px", textAlign: "center", border: "white 1px solid" }} onClick={() => setStrategyToView(null)} className={'demoButton button'}><b>Back</b></div>
            {display}
            <div style={{ width: "100%", display: "flex", justifyContent: "flex-end" }}>
                <div style={{ backgroundColor: "#374d59", marginRight: "30px", width: "134px", textAlign: "center", border: "white 1px solid" }} onClick={() => setShowStrategyPopup(false)} className={'demoButton button'}>
                    <b>OK</b>
                </div>
            </div>
        </>
    }

    if (newStrategy) {

    }

    return (
        <div className="popup-container">
            <div className="popup">
                {displaySection}
            </div>
        </div>
    );
}

export default StrategyPopup;