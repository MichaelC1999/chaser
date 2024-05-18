import React, { useEffect, useState } from 'react';
import { zeroAddress } from 'viem';
import PoolABI from '../ABI/PoolABI.json'; // Adjust the path as needed
import networks from '../JSON/networks.json'
import protocolHashes from '../JSON/protocolHashes.json'
import contractAddresses from '../JSON/contractAddresses.json'
import UmaABI from '../ABI/UmaABI.json'; // Adjust the path as needed
import Loader from './Loader.jsx';

import ArbitrationABI from '../ABI/ArbitrationABI.json'; // Adjust the path as needed
import { ethers, parseEther, solidityPackedKeccak256 } from 'ethers';
import PivotingStatus from './PivotingStatus.jsx';


function PivotPopup({ isPivoting, poolData, provider, tvl, pivotTx, fetchPoolData, poolAddress, pivotTarget, openAssertion, closePopup, openProposal, executePivot }) {

    const [loading, setLoading] = useState(false)
    const [assertionData, setAssertionData] = useState({})
    const [openingProposal, setOpeningProposal] = useState(true)

    useEffect(() => {
        fetchPoolData()
    }, [])

    useEffect(() => {
        if (!isPivoting && !openingProposal && (openAssertion === "0x0000000000000000000000000000000000000000000000000000000000000000" || !openAssertion)) {
            closePopup()
        }
        if (isPivoting || (openAssertion !== "0x0000000000000000000000000000000000000000000000000000000000000000" && openAssertion)) {
            setOpeningProposal(false)
        }
    }, [isPivoting, openAssertion])

    useEffect(() => {
        if (openAssertion && openAssertion !== "0x0000000000000000000000000000000000000000000000000000000000000000") {
            getPivotAssertionData()
        }
    }, [openAssertion])

    const getPivotAssertionData = async () => {
        const pool = new ethers.Contract(poolAddress || "0x0", PoolABI, provider);
        const arbitration = new ethers.Contract(contractAddresses["sepolia"].arbitrationContract || "0x0", ArbitrationABI, provider);
        const data = {}
        data.interactionPaused = await arbitration.inAssertionBlockWindow(openAssertion)
        data.assertionMarketId = await arbitration.assertionToRequestedMarketId(openAssertion);
        data.assertionProtocol = await arbitration.assertionToRequestedProtocol(openAssertion);
        data.assertionChainId = await arbitration.assertionToRequestedChainId(openAssertion);
        data.assertionBlockTime = await arbitration.assertionToBlockTime(openAssertion)
        if (Number(data.assertionBlockTime)) {
            data.assertionBlockTime = Number(data.assertionBlockTime) * 1000
        }
        data.assertionSettleTime = (await arbitration.assertionToSettleTime(openAssertion))
        if (Number(data.assertionSettleTime)) {
            data.assertionSettleTime = Number(data.assertionSettleTime) * 1000
        }
        data.currentChain = await pool.currentPositionChain();
        console.log(data)
        setAssertionData(data)
    }

    const settleAssertion = async () => {
        let signer = null;
        try {
            await provider.send("eth_requestAccounts", []);
            signer = await provider.getSigner();
        } catch (err) {
            console.log("Connection Error: " + err?.info?.error?.message ?? err?.message);
        }
        try {
            const UMAOO = new ethers.Contract("0xFd9e2642a170aDD10F53Ee14a93FcF2F31924944" || "0x0", UmaABI, signer);
            await (await UMAOO.settleAssertion(openAssertion, { gasLimit: 8000000 })).wait()
            fetchPoolData()
            closePopup()
        } catch (err) {
            console.log(err, openAssertion)
        }
        //IMPORTANT - Need to handle error
    }

    //Propose Pivot button
    //Popup comes up saying "In order to open the proposal on the UMA oracle, you must approve USDC first to putup the assertion bond. After the approval and proposal execution, you must wait for the proposal to be approved. This takes 5 minutes, if there are no disputes (this period will be longer in production). Link to USDC faucet"
    // Smaller section  to click stating "skip proposal, execute pivot directly". This triggers the sendExecutePivot function
    let display = <Loader />
    let popupTitle = <div className="popup-title">Pivot Proposal to <b>{pivotTarget}</b></div>
    const currentTimestamp = new Date().getTime()
    if (isPivoting || pivotTx) {
        display = <PivotingStatus provider={provider} pivotTx={pivotTx} fetchPoolData={fetchPoolData} poolAddress={poolAddress} closePopup={closePopup} />
    } else if (openAssertion && openAssertion !== "0x0000000000000000000000000000000000000000000000000000000000000000") {
        if (!assertionData?.assertionProtocol) {
            popupTitle = <div className="popup-title">Pivot proposal</div>

        } else {
            popupTitle = <div className="popup-title">Pivot proposal to <b>{assertionData?.assertionProtocol} {networks[assertionData?.assertionChainId?.toString()]?.toUpperCase()}</b></div>

        }

        const settleTime = new Date(assertionData?.assertionSettleTime)
        if ((Number(assertionData?.assertionBlockTime || 0) - currentTimestamp) > 0) {
            setTimeout(getPivotAssertionData, (Number(assertionData?.assertionBlockTime || 0) - currentTimestamp) + 15000)
            setTimeout(getPivotAssertionData, (Number(assertionData?.assertionBlockTime || 0) - currentTimestamp) + 45000)

        }

        let crossChain = assertionData?.assertionChainId !== assertionData?.currentChain //Get current position chain and target chain, if same change to true
        let settle = <span style={{ display: "block" }} >The assertion can be settled at {settleTime.getHours()}:{settleTime.getMinutes() < 10 ? "0" + settleTime.getMinutes() : settleTime.getMinutes()}<b></b></span> //get expiry time and js time, if js time greater, change for input

        if (currentTimestamp > Number(assertionData?.assertionSettleTime || 0)) {
            settle = <button style={{ marginTop: "5px", backgroundColor: "red", width: "254px" }} onClick={() => {
                setLoading(true)
                settleAssertion()
            }} className={'demoButton'}><b>Execute Pivot</b></button>
        } else {
            setTimeout(fetchPoolData, (Number(assertionData?.assertionSettleTime || 0) - currentTimestamp))
            setTimeout(fetchPoolData, (Number(assertionData?.assertionSettleTime || 0) - currentTimestamp) + 30000)

        }

        let assertionSection = <Loader />
        if (Object.keys(assertionData)?.length > 0) {
            assertionSection = <div style={{ display: "block", marginTop: "22px", fontSize: "16px", color: "white" }}>
                <span className="infoSpan"><b>{assertionData?.assertionProtocol} {networks[assertionData?.assertionChainId?.toString()]}</b></span>
                <span className="infoSpan"><b>{tvl} {poolData?.poolAssetSymbol?.toUpperCase()}</b></span>
                <span className="infoSpan"><b>Market <a href="">0x...{assertionData?.assertionMarketId?.slice(assertionData?.assertionMarketId?.length - 15)}</a></b></span>
            </div >

        }


        display = (<>
            {Object.keys(assertionData) === Object.keys({}) ? null : assertionSection}
            <div style={{ display: "block", marginTop: "22px", fontSize: "16px" }} className="popup-message">
                <span style={{ display: "block" }} >Interactions are <b>{assertionData?.interactionPaused ? <span style={{ color: "red" }}>PAUSED</span> : <span style={{ color: "green" }}>OPEN</span>}</b></span>
                <span style={{ display: "block" }} >This pivot will <b>{crossChain ? "bridge cross chain" : "NOT bridge cross chain"}</b></span>
                {settle}
            </div></>)
    } else if (!loading) {
        display = <><div className="popup-message">
            <div>
                <span style={{ display: "block" }}>To open the proposal, you must approve USDC for the assertion bond. After approving the USDC bond and then executing the proposal transaction, you must wait for the proposal to be approved. This takes 5 minutes if there are no disputes (this period will be longer in production).</span>
                <span style={{ margin: "10px 0", display: "block" }}><a target="_blank" href="https://faucet.circle.com/"><u>Click to access USDC faucet</u></a></span>
            </div>
        </div>
            <div style={{ width: "100%", display: "flex", justifyContent: "center", flexDirection: "column", alignItems: "center" }}>
                <button style={{ backgroundColor: "green", width: "254px" }} onClick={() => {
                    openProposal()
                    setLoading(true)
                }} className={'demoButton'}><b>Open Proposal</b></button>
                <button style={{ marginTop: "5px", backgroundColor: "red", width: "254px" }} onClick={() => {
                    executePivot()
                    setLoading(true)
                }} className={'demoButton'}><b>Skip Proposal, Execute Pivot</b></button>
            </div ></>
    }


    return (
        <div className="popup-container">
            <div className="popup">
                <div style={{ width: "100%", display: "flex", justifyContent: "flex-end" }}>
                    <button style={{ backgroundColor: "#374d59", marginRight: "30px", width: "134px" }} onClick={() => closePopup()} className={'demoButton'}><b>Close</b></button>
                </div>
                {popupTitle}
                {display}
            </div>
        </div>
    );
}

export default PivotPopup;