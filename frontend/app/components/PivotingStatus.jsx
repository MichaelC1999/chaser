import React, { useEffect, useState } from 'react';
import { numberToHex, zeroAddress } from 'viem';
import PoolABI from '../ABI/PoolABI.json'; // Adjust the path as needed
import networks from '../JSON/networks.json'
import protocolHashes from '../JSON/protocolHashes.json'
import contractAddresses from '../JSON/contractAddresses.json'
import UmaABI from '../ABI/UmaABI.json'; // Adjust the path as needed
import Loader from './Loader.jsx';
import { decodePoolPivot, fetchAcrossRelayFillTx, findAcrossDepositFromTxHash, findCcipMessageFromTxHash } from "../utils.jsx"

import PoolCalculationABI from '../ABI/PoolCalculationsABI.json'; // Adjust the path as needed
import { ethers, parseEther, solidityPackedKeccak256 } from 'ethers';


function PivotingStatus({ provider, pivotTx, fetchPoolData, poolAddress, closePopup }) {

    const [targetData, setTargetData] = useState({})
    const [ccip1, setCcip1MessageId] = useState("")
    const [ccip2, setCcip2MessageId] = useState("")
    const [acrossDepositId, setAcrossDepositId] = useState("")
    const [ccip1Loaded, setCcip1Loaded] = useState(false)
    const [ccip2Loaded, setCcip2Loaded] = useState(false)
    const [acrossLoaded, setAcrossLoaded] = useState(false)

    //If openAssetion
    //-display target market, protocol, chain
    //-Whether or not withdraws/deposits are still open (setInterval changes state on this without refetching)
    //-If has not past expiry time, Countdown until assertion settled
    //-If is past expirytime, button to settle the assertion and execute the pivot
    useEffect(() => {
        getPivotTargetData()
    }, [])

    useEffect(() => {
        if (Object.keys(targetData)?.length > 0) {
            fetchPivotEventData()
            setTimeout(() => fetchPivotEventData(), 20000)
            setTimeout(() => fetchPivotEventData(), 40000)

            if (!ccip1 && !ccip2 && !acrossDepositId) {
                setTimeout(() => fetchPivotEventData(), 60000)
            }
        }
        fetchPoolData()
        if (targetData?.targetChainId?.toString() === "0") {
            closePopup()
        }
    }, [targetData])

    useEffect(() => {
        if (acrossDepositId && !acrossLoaded && targetData) {
            fetchAcrossTx()
        }
        const interval = setInterval(() => {
            if (acrossDepositId && !acrossLoaded && targetData) {
                fetchAcrossTx()
            }
        }, 90000);
        return () => clearInterval(interval);

        //Clearing the interval
    }, [acrossDepositId, targetData])

    useEffect(() => {
        if (ccip1 && !ccip1Loaded && targetData) {
            fetchCCIPStatus(ccip1, 1)
        }
        const interval = setInterval(() => {
            if (ccip1 && !ccip1Loaded && targetData) {
                fetchCCIPStatus(ccip1, 1)
            }
        }, 120000);
        return () => clearInterval(interval);

        //Clearing the interval
    }, [ccip1, ccip1Loaded, targetData])

    useEffect(() => {
        if (ccip2 && !ccip2Loaded && targetData) {
            fetchCCIPStatus(ccip2, 2)
        }
        const interval = setInterval(() => {
            if (ccip2 && !ccip2Loaded && targetData) {
                fetchCCIPStatus(ccip2, 2)

            }
        }, 120000);
        return () => clearInterval(interval);

        //Clearing the interval
    }, [ccip2, ccip2Loaded, targetData])


    const getPivotTargetData = async () => {
        const pool = new ethers.Contract(poolAddress || "0x0", PoolABI, provider);
        const poolCalculations = new ethers.Contract(contractAddresses["sepolia"].poolCalculationsAddress || "0x0", PoolCalculationABI, provider);
        const data = {}
        data.targetPositionMarketId = await poolCalculations.targetPositionMarketId(poolAddress)
        data.targetChainId = await poolCalculations.targetPositionChain(poolAddress)
        data.targetPositionProtocol = await poolCalculations.targetPositionProtocol(poolAddress)

        const currents = await pool.readPoolCurrentPositionData()
        data.currentPositionAddress = currents["0"]
        data.currentChainId = currents["4"]
        data.currentPositionAddress = await poolCalculations.currentPositionAddress(poolAddress)
        data.currentPositionMarketId = await poolCalculations.currentPositionMarketId(poolAddress)
        data.currentPositionProtocol = await poolCalculations.currentPositionProtocol(poolAddress)
        setTargetData(data)
    }

    const fetchPivotEventData = async () => {
        let id = ""
        let medium = ""
        if (pivotTx) {
            const msg = await findCcipMessageFromTxHash(pivotTx, process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID)
            if (msg.messageId) {
                id = msg.messageId
                medium = "ccip1"
            }
            const depo = await findAcrossDepositFromTxHash(pivotTx, process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID)
            if (depo?.depositId) {
                id = depo.depositId
                medium = "across"
            }

        } else {
            const pivotData = await decodePoolPivot(poolAddress)
            id = pivotData.id
            medium = pivotData.medium
        }

        if (medium == "ccip1") {
            setCcip1MessageId(id)
        } else if (medium == "ccip2") {
            setCcip2MessageId(id)
        } else if (medium == "across") {
            setAcrossDepositId(id)
        }
    }

    const fetchCCIPStatus = async (messageId, ccipStep) => {
        console.log("fetching CCIP status", messageId)
        const url = "https://corsproxy.io/?https%3A%2F%2Fccip.chain.link%2Fapi%2Fquery%2FMESSAGE_DETAILS_QUERY%3Fvariables%3D%257B%2522messageId%2522%253A%2522" + messageId + "%2522%257D";

        const depos = await fetch(url, {
            method: "get",
            headers: {
                "Content-Type": "application/json",
            }
        })

        const deployments = await depos.json()
        const messageData = (deployments.data.allCcipMessages.nodes[0])

        const msg = await findCcipMessageFromTxHash(messageData.receiptTransactionHash, messageData.destChainId)
        console.log(msg)
        let success = false
        if (msg.messageId) {
            setCcip2MessageId(msg.messageId)
            success = msg.success
        } else {
            const depo = await findAcrossDepositFromTxHash(messageData?.receiptTransactionHash, messageData?.destChainId)
            console.log("GETTING THE DEPO FROM TX: " + messageData?.receiptTransactionHash)
            if (depo.depositId) {
                setAcrossDepositId(depo.depositId)
                success = depo.success
            }
        }

        if (success) {
            if (ccipStep == 1) {
                setCcip1Loaded(true)
            } else {
                setCcip2Loaded(true)
            }
        }
    }


    const fetchAcrossTx = async () => {
        console.log("fetching Across Tx")
        if (!targetData?.targetChainId?.toString()) {
            return
        }
        const message = await fetchAcrossRelayFillTx(targetData?.targetChainId?.toString(), numberToHex(Number(acrossDepositId), { size: 32 }))
        //Fetch the destination spokepool's recent events. 
        // If the matching message ID is there, set step
        //possibly get the  CCIP message id
        if (message.success) {
            setAcrossLoaded(true)
        }
        if (message.messageId) {

            if (ccip1Loaded) {
                setCcip2MessageId(message.messageId)
            } else {
                setCcip1MessageId(message.messageId)
            }
        }
    }


    //Propose Pivot button
    //Popup comes up saying "In order to open the proposal on the UMA oracle, you must approve USDC first to putup the assertion bond. After the approval and proposal execution, you must wait for the proposal to be approved. This takes 5 minutes, if there are no disputes (this period will be longer in production). Link to USDC faucet"
    // Smaller section  to click stating "skip proposal, execute pivot directly". This triggers the sendExecutePivot function
    let display = null

    if (targetData?.targetChainId?.toString() === process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID && targetData?.currentChainId?.toString() !== process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID) {
        console.log('CONDITION 1')

        let ccipStatus = null
        let acrossStatus = null
        let ccipMsg = ""
        let acrossMsg = ""

        if (!ccip1) {
            ccipStatus = <><div style={{ border: "3px solid yellow" }} className="small-loader"></div></>
            ccipMsg = <span>Execution Pending</span>
        }
        if (ccip1 && !ccip1Loaded) {
            ccipStatus = <div className="small-loader"></div>
            ccipMsg = <span>CCIP Message: <a href={"https://ccip.chain.link/msg/" + ccip1} target="_blank"><u>{ccip1.slice(0, 7) + "..." + ccip1.slice(ccip1.length - 8)}</u></a></span>

        }
        if (ccip1 && ccip1Loaded) {
            ccipStatus = <span style={{ color: "green" }}><b>SUCCESS</b></span>
            ccipMsg = <span>CCIP Message: <a href={"https://ccip.chain.link/msg/" + ccip1} target="_blank"><u>{ccip1.slice(0, 7) + "..." + ccip1.slice(ccip1.length - 8)}</u></a></span>
        }

        if (!acrossDepositId) {
            acrossStatus = <><div style={{ border: "3px solid yellow" }} className="small-loader"></div></>
            acrossMsg = "Execution Pending"
        }
        if (acrossDepositId && !acrossLoaded) {
            acrossStatus = <><div className="small-loader"></div></>
            acrossMsg = "Across Deposit" + acrossDepositId

        }
        if (acrossDepositId && acrossLoaded) {
            acrossStatus = <span style={{ color: "green" }}><b>SUCCESS</b></span>
            acrossMsg = "Across Deposit" + acrossDepositId
        }


        display = (<>
            <div className="enabled-pools">
                <table>
                    <thead>
                        <tr>
                            <th></th>
                            <th></th>
                            <th></th>
                        </tr>
                    </thead>
                    <tbody>

                        <tr style={{ height: '22px' }}>
                            <td style={{ padding: "0 15px" }}><span>Withdraw Pool Position on <b>{networks[targetData?.currentChainId?.toString()]?.toUpperCase()}</b> </span></td>
                            <td style={{ padding: "0 15px" }}>{ccipMsg}</td>
                            <td style={{ padding: "0 15px" }}>{ccipStatus}</td>
                        </tr>
                        <tr style={{ height: '22px' }}>
                            <td style={{ padding: "0 15px" }}><span>Bridge and Enter Position on <b>{networks[targetData?.targetChainId?.toString()]?.toUpperCase()}</b> </span></td>
                            <td style={{ padding: "0 15px" }}>{acrossMsg}</td>
                            <td style={{ padding: "0 15px" }}>{acrossStatus}</td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </>)
    } else if (targetData?.targetChainId?.toString() !== process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID && targetData?.currentChainId?.toString() === process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID) {
        //across, then CCIP
        let ccipStatus = null
        let acrossStatus = null
        let ccipMsg = ""
        let acrossMsg = ""


        if (!ccip1) {
            ccipStatus = <><div style={{ border: "3px solid yellow" }} className="small-loader"></div></>
            ccipMsg = <span>Execution Pending</span>
        }
        if (ccip1 && !ccip1Loaded) {
            ccipStatus = <div className="small-loader"></div>
            ccipMsg = <span>CCIP Message: <a href={"https://ccip.chain.link/msg/" + ccip1} target="_blank"><u>{ccip1.slice(0, 7) + "..." + ccip1.slice(ccip1.length - 8)}</u></a></span>

        }
        if (ccip1 && ccip1Loaded) {
            ccipStatus = <span style={{ color: "green" }}><b>SUCCESS</b></span>
            ccipMsg = <span>CCIP Message: <a href={"https://ccip.chain.link/msg/" + ccip1} target="_blank"><u>{ccip1.slice(0, 7) + "..." + ccip1.slice(ccip1.length - 8)}</u></a></span>
        }

        if (!acrossDepositId) {
            acrossStatus = <><div style={{ border: "3px solid yellow" }} className="small-loader"></div></>
            acrossMsg = "Execution Pending"
        }
        if (acrossDepositId && !acrossLoaded) {
            acrossStatus = <><div className="small-loader"></div></>
            acrossMsg = "Across Deposit: " + acrossDepositId

        }
        if (acrossDepositId && acrossLoaded) {
            acrossStatus = <span style={{ color: "green" }}><b>SUCCESS</b></span>
            acrossMsg = "Across Deposit: " + acrossDepositId
        }

        display = (<>
            <div className="enabled-pools">
                <table>
                    <thead>
                        <tr>
                            <th></th>
                            <th></th>
                            <th></th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr style={{ height: '22px' }}>
                            <td style={{ padding: "0 15px" }}><span>Enter Position on <b>{networks[targetData?.targetChainId?.toString()]?.toUpperCase()}</b> </span></td>
                            <td style={{ padding: "0 15px" }}>{acrossMsg}</td>
                            <td style={{ padding: "0 15px" }}>{acrossStatus}</td>
                        </tr>
                        <tr style={{ height: '22px' }}>
                            <td style={{ padding: "0 15px" }}><span>Finalize Pivot on <b>{networks[process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID]?.toUpperCase()}</b></span></td>
                            <td style={{ padding: "0 15px" }}>{ccipMsg}</td>
                            <td style={{ padding: "0 15px" }}>{ccipStatus}</td>
                        </tr>
                    </tbody>
                </table>
            </div>

        </>)

    } else if (targetData?.targetChainId?.toString() !== process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID && targetData?.currentChainId?.toString() !== process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID && Object.keys(targetData).length > 0) {

        let ccip1Status = null
        let acrossStatus = null
        let ccip2Status = null

        let ccip1Msg = ""
        let acrossMsg = ""
        let ccip2Msg = ""

        if (!ccip1) {
            ccip1Status = <><div style={{ border: "3px solid yellow" }} className="small-loader"></div></>
            ccip1Msg = <span>Execution Pending</span>
        }
        if (ccip1 && !ccip1Loaded) {
            ccip1Status = <div className="small-loader"></div>
            ccip1Msg = <span>CCIP Message: <a href={"https://ccip.chain.link/msg/" + ccip1} target="_blank"><u>{ccip1.slice(0, 7) + "..." + ccip1.slice(ccip1.length - 8)}</u></a></span>

        }
        if (ccip1 && ccip1Loaded) {
            ccip1Status = <span style={{ color: "green" }}><b>SUCCESS</b></span>
            ccip1Msg = <span>CCIP Message: <a href={"https://ccip.chain.link/msg/" + ccip1} target="_blank"><u>{ccip1.slice(0, 7) + "..." + ccip1.slice(ccip1.length - 8)}</u></a></span>
        }

        let acrossEle = null

        if (targetData?.targetChainId?.toString() !== targetData?.currentChainId?.toString()) {
            if (!acrossDepositId) {
                acrossStatus = <><div style={{ border: "3px solid yellow" }} className="small-loader"></div></>
                acrossMsg = "Execution Pending"
            }
            if (acrossDepositId && !acrossLoaded) {
                acrossStatus = <><div className="small-loader"></div></>
                acrossMsg = "Across Deposit: " + acrossDepositId

            }
            if (acrossDepositId && acrossLoaded) {
                acrossStatus = <span style={{ color: "green" }}><b>SUCCESS</b></span>
                acrossMsg = "Across Deposit: " + acrossDepositId
            }
            acrossEle = (<tr style={{ height: '22px' }}>
                <td style={{ padding: "0 15px" }}><span>Enter Position on <b>{networks[targetData?.targetChainId?.toString()]?.toUpperCase()}</b> </span></td>
                <td style={{ padding: "0 15px" }}>{acrossMsg}</td>
                <td style={{ padding: "0 15px" }}>{acrossStatus}</td>
            </tr>)
        }


        if (!ccip2) {
            ccip2Status = <><div style={{ border: "3px solid yellow" }} className="small-loader"></div></>
            ccip2Msg = <span>Execution Pending</span>
        }
        if (ccip2 && !ccip2Loaded) {
            ccip2Status = <div className="small-loader"></div>
            ccip2Msg = <span>CCIP Message: <a href={"https://ccip.chain.link/msg/" + ccip2} target="_blank"><u>{ccip2.slice(0, 7) + "..." + ccip2.slice(ccip2.length - 8, ccip2.length - 1)}</u></a></span>

        }
        if (ccip2 && ccip2Loaded) {
            ccip2Status = <span style={{ color: "green" }}><b>SUCCESS</b></span>
            ccip2Msg = <span>CCIP Message: <a href={"https://ccip.chain.link/msg/" + ccip2} target="_blank"><u>{ccip2.slice(0, 7) + "..." + ccip2.slice(ccip2.length - 8, ccip2.length - 1)}</u></a></span>
        }

        display = (<>
            <div className="enabled-pools">
                <table>
                    <thead>
                        <tr>
                            <th></th>
                            <th></th>
                            <th></th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr style={{ height: '22px' }}>
                            <td style={{ padding: "0 15px" }}><span>Withdraw Position on <b>{networks[targetData?.targetChainId?.toString()]?.toUpperCase()}</b> </span></td>
                            <td style={{ padding: "0 15px" }}>{ccip1Msg}</td>
                            <td style={{ padding: "0 15px" }}>{ccip1Status}</td>
                        </tr>
                        {acrossEle}
                        <tr style={{ height: '22px' }}>
                            <td style={{ padding: "0 15px" }}><span>Finalize Pivot on <b>{networks[process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID]?.toUpperCase()}</b></span></td>
                            <td style={{ padding: "0 15px" }}>{ccip2Msg}</td>
                            <td style={{ padding: "0 15px" }}>{ccip2Status}</td>
                        </tr>
                    </tbody>
                </table>
            </div>

        </>)

    }

    let displaySection = <><div className="popup-title">Pivoting to <b>{targetData?.targetPositionProtocol} {networks[targetData?.targetChainId?.toString()]?.toUpperCase()}</b></div>
        <div className="popup-message">
            <div style={{ display: "block", marginTop: "22px", fontSize: "16px" }}>
                <span style={{ display: "block" }} >This pivot will deposit into market <b>{targetData?.targetPositionMarketId?.slice(0, 6)}...{targetData?.targetPositionMarketId?.slice(targetData?.targetPositionMarketId?.length - 15, targetData?.targetPositionMarketId - 1)}</b></span>
                <span style={{ display: "block" }} >This involves exiting the current position on <b>{targetData?.currentPositionProtocol} {networks[targetData?.currentChainId?.toString()]?.toUpperCase()}</b> and entering into <b>{targetData?.targetPositionProtocol} {networks[targetData?.targetChainId?.toString()]?.toUpperCase()}</b></span>

            </div>
            {display}
        </div></>

    if (!display) {
        displaySection = <><div className="popup-title"><span>Fetching pivot</span></div><Loader /></>
    }


    return (
        <div className="popup-container">
            <div className="popup">
                <div style={{ width: "100%", display: "flex", justifyContent: "flex-end" }}>
                    <button style={{ backgroundColor: "#374d59", marginRight: "30px", width: "134px" }} onClick={() => closePopup()} className={'demoButton'}><b>Close</b></button>
                </div>
                {displaySection}
            </div>
        </div>
    );
}

export default PivotingStatus;