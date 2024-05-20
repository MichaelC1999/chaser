import React, { useEffect, useState } from 'react';
import { hexToString, numberToHex, stringToBytes, zeroAddress } from 'viem';
import PoolABI from '../ABI/PoolABI.json'; // Adjust the path as needed
import networks from '../JSON/networks.json'
import protocolHashes from '../JSON/protocolHashes.json'
import contractAddresses from '../JSON/contractAddresses.json'
import InvestmentStrategyABI from '../ABI/InvestmentStrategyABI.json'; // Adjust the path as needed
import Loader from './Loader.jsx';
import { decodePoolPivot, fetchAcrossRelayFillTx, findAcrossDepositFromTxHash, findCcipMessageFromTxHash, userLastDeposit } from "../utils.jsx"

import PoolCalculationABI from '../ABI/PoolCalculationsABI.json'; // Adjust the path as needed
import { ethers, parseEther, solidityPackedKeccak256 } from 'ethers';


function StrategyPopup({ provider, strategyIndex, setStrategyIndex, strategies, setShowStrategyPopup, strategyIndexOnPool }) {
    const [newStrategy, setNewStrategy] = useState(false)
    const [newStrategyName, setNewStrategyName] = useState("")
    const [newStrategyCode, setNewStrategyCode] = useState("")

    const [strategyToView, setStrategyToView] = useState(strategyIndexOnPool)
    const [strategyCode, setStrategyCode] = useState("")

    useEffect(() => {
        // Fetch code from strategy contract
        if (strategyToView || strategyToView === "0") {
            getStrategyLogic()
        }
    }, [strategyToView])

    const getStrategyLogic = async () => {

        const investmentStrategyContract = new ethers.Contract(contractAddresses.sepolia["investmentStrategy"], InvestmentStrategyABI, provider);
        const code = hexToString(await investmentStrategyContract.strategyCode(strategyToView))
        console.log(code)
        setStrategyCode(code)
    }

    const submitNewStrategy = async () => {
        let signer = null;
        try {
            await provider.send("eth_requestAccounts", []);
            signer = await provider.getSigner();
        } catch (err) {
            console.log("Connection Error: " + err?.info?.error?.message ?? err?.message);
            // setErrorMessage("Connection Error: " + err?.info?.error?.message)
            return
        }
        const stratContact = new ethers.Contract(contractAddresses.sepolia["investmentStrategy"], InvestmentStrategyABI, signer)
        //Maybe here a loading spinner popup? Then once Tx success or fail then do tx popup?

        const codeBytes = stringToBytes(newStrategyCode)
        try {
            const stratTx = await (await stratContact.addStrategy(
                codeBytes,
                newStrategyName,
                {
                    gasLimit: 8000000
                }
            )).wait();

            const hash = stratTx.hash
            setStrategyIndex(strategies.length)
            setShowStrategyPopup(false)
        } catch (err) {
            // console.log('test! ', err)
            setErrorMessage(err?.info?.error?.message ?? "This transaction has failed\n\n" + (err?.receipt ? "TX: " + err.receipt.hash : ""))
            // setErrorMessage(err?.info?.error?.message)
        }
    }


    let popupStyle = {}

    let display = (<>
        <select value={strategyIndex} onChange={(e) => setStrategyIndex(e.target.value)}>
            {(strategies).map((name, idx) => (
                <option key={name} value={idx}>{name}</option>
            ))}
        </select>
        <div style={{ backgroundColor: "#374d59", marginRight: "30px", width: "100%", textAlign: "center", border: "white 1px solid" }} className={'demoButton button'} onClick={() => setStrategyToView(strategyIndex)}>View Strategy Logic</div>
        {strategyIndexOnPool ? null : <div style={{ backgroundColor: "#374d59", marginRight: "30px", width: "100%", textAlign: "center", border: "white 1px solid" }} className={'demoButton button'} onClick={() => setNewStrategy(true)}>Add New Strategy</div>}
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
            display = (<div style={{ fontFamily: "Courier New", fontSize: "14px", fontWeight: "lighter", width: "100%", overflow: "scroll", backgroundColor: "black", color: "white", whiteSpace: "pre-wrap" }}>
                {strategyCode}
            </div>)
            popupStyle = { height: "620px", width: "1100px" }
        } else {
            display = <Loader />
        }
        displaySection = <>
            <div style={{ width: "100%", display: "flex", justifyContent: "flex-end" }}>
                {strategyIndexOnPool ? null :
                    <div style={{ backgroundColor: "#374d59", marginRight: "30px", width: "134px", textAlign: "center", border: "white 1px solid" }} onClick={() => setStrategyToView(null)} className={'demoButton button'}>
                        <b>Back</b>
                    </div>}
            </div>
            <div className="popup-title">{strategies[strategyToView]}</div>
            {display}
            <div style={{ width: "100%", display: "flex", justifyContent: "center" }}>
                <div style={{ backgroundColor: "#374d59", marginRight: "30px", width: "134px", textAlign: "center", border: "white 1px solid" }} onClick={() => setShowStrategyPopup(false)} className={'demoButton button'}>
                    <b>OK</b>
                </div>
            </div>
        </>
    }

    if (newStrategy) {
        display = (<>
            <input onChange={(e) => setNewStrategyName(e.target.value)} value={newStrategyName} placeholder='Strategy Name'></input>
            <textarea onChange={(e) => setNewStrategyCode(e.target.value)} style={{ fontFamily: "Courier New", fontWeight: "lighter", height: "100%", width: "100%", overflow: "scroll", backgroundColor: "black", color: "white", whiteSpace: "pre-wrap" }}>
            </textarea></>)
        popupStyle = { height: "620px", width: "1100px" }

        displaySection = <>
            <div style={{ width: "100%", display: "flex", justifyContent: "flex-end" }}>
                {strategyIndexOnPool ? null :
                    <div style={{ backgroundColor: "#374d59", marginRight: "30px", width: "134px", textAlign: "center", border: "white 1px solid" }} onClick={() => setNewStrategy(false)} className={'demoButton button'}>
                        <b>Back</b>
                    </div>}
            </div>
            <div className="popup-title">New Strategy</div>
            {display}
            <div style={{ width: "100%", display: "flex", justifyContent: "center" }}>
                <div style={{ backgroundColor: "#374d59", marginRight: "30px", width: "134px", textAlign: "center", border: "white 1px solid" }} onClick={() => submitNewStrategy()} className={'demoButton button'}>
                    <b>Submit New Strategy</b>
                </div>
            </div>
        </>
    }

    return (
        <div className="popup-container">
            <div className="popup" style={popupStyle}>
                {displaySection}
            </div>
        </div>
    );
}

export default StrategyPopup;