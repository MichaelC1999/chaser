import React, { useEffect, useState } from 'react';
import { numberToHex, zeroAddress } from 'viem';
import PoolABI from '../ABI/PoolABI.json'; // Adjust the path as needed
import networks from '../JSON/networks.json'
import protocolHashes from '../JSON/protocolHashes.json'
import contractAddresses from '../JSON/contractAddresses.json'
import UmaABI from '../ABI/UmaABI.json'; // Adjust the path as needed
import Loader from './Loader.jsx';
import { decodePoolPivot, fetchAcrossRelayFillTx, findAcrossDepositFromTxHash, findCcipMessageFromTxHash, userLastDeposit } from "../utils.jsx"

import PoolCalculationABI from '../ABI/PoolCalculationsABI.json'; // Adjust the path as needed
import { ethers, parseEther, solidityPackedKeccak256 } from 'ethers';


function DepositStatus({ provider, depositId, poolData, fetchPoolData, poolAddress }) {
    const [showPopup, setShowPopup] = useState(true)
    const [ccip1, setCcip1MessageId] = useState("")
    const [acrossDepositId, setAcrossDepositId] = useState(depositId)
    const [ccip1Loaded, setCcip1Loaded] = useState(false)
    const [acrossLoaded, setAcrossLoaded] = useState(false)
    const [targetData, setTargetData] = useState({})

    useEffect(() => {
        getPositionIntializeTargetData()
    }, [])

    const getPositionIntializeTargetData = async () => {
        const pool = new ethers.Contract(poolAddress || "0x0", PoolABI, provider);
        const poolCalculations = new ethers.Contract(contractAddresses["arbitrum"].poolCalculationsAddress || "0x0", PoolCalculationABI, provider);
        const data = {}
        data.targetPositionMarketId = await poolCalculations.targetPositionMarketId(poolAddress)
        data.targetChainId = await poolCalculations.targetPositionChain(poolAddress)
        data.targetPositionProtocol = await poolCalculations.targetPositionProtocol(poolAddress)
        setTargetData(data)
    }


    useEffect(() => {
        if (depositId) {
            setAcrossDepositId(depositId)
        }
    }, [depositId])

    useEffect(() => {
        if (!depositId) {
            fetchDepositEventData()
        }
        fetchPoolData()

    }, [])

    useEffect(() => {
        if (ccip1Loaded) {
            setTimeout(() => fetchPoolData(), 30000)
        }
    }, [ccip1Loaded])


    useEffect(() => {
        if (acrossDepositId && !acrossLoaded) {
            fetchAcrossTx()
        }
        const interval = setInterval(() => {
            if (acrossDepositId && !acrossLoaded) {
                fetchAcrossTx()
            }
        }, 90000);
        return () => clearInterval(interval);

        //Clearing the interval
    }, [acrossDepositId, poolData, targetData])

    useEffect(() => {
        if (ccip1 && !ccip1Loaded) {
            fetchCCIPStatus(ccip1)
        }
        const interval = setInterval(() => {
            if (ccip1 && !ccip1Loaded) {
                fetchCCIPStatus(ccip1)
            }
        }, 120000);
        return () => clearInterval(interval);

        //Clearing the interval
    }, [ccip1, ccip1Loaded])


    const fetchDepositEventData = async () => {
        const deposit = await userLastDeposit(poolAddress, poolData?.user?.address)
        setAcrossDepositId(deposit.depositId)
    }

    const fetchCCIPStatus = async (messageId) => {
        if (!messageId) return
        const url = "https://ccip.chain.link/api/h/atlas/message/" + messageId;

        let messageData = {}
        try {
            const depos = await fetch(url, {
                method: "get",
                headers: {
                    "Content-Type": "application/json",
                }
            })

            const deployments = await depos.json()
            messageData = (deployments.data.allCcipMessages.nodes[0])
        } catch (err) { }

        if (messageData?.receiptTransactionHash) {
            setCcip1Loaded(true)
        }
    }

    const fetchAcrossTx = async () => {
        console.log("fetching Across Tx", poolData, targetData)
        let chainId = poolData?.currentChain?.toString()
        if (chainId === "0") {
            chainId = targetData?.targetChainId?.toString()

        }
        const message = await fetchAcrossRelayFillTx(process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID, chainId, numberToHex(Number(acrossDepositId), { size: 32 }))
        //Fetch the destination spokepool's recent events. 
        // If the matching message ID is there, set step
        //possibly get the  CCIP message id
        console.log('fetchAcrossTx message', message)
        if (message.success) {
            setAcrossLoaded(true)
        }
        if (message.messageId) {

            setCcip1MessageId(message.messageId)
        }
    }


    //Propose Pivot button
    //Popup comes up saying "In order to open the proposal on the UMA oracle, you must approve USDC first to putup the assertion bond. After the approval and proposal execution, you must wait for the proposal to be approved. This takes 5 minutes, if there are no disputes (this period will be longer in production). Link to USDC faucet"
    // Smaller section  to click stating "skip proposal, execute pivot directly". This triggers the sendExecutePivot function
    let display = null
    // IMPORTANT - WHAT TO DO WHEN THE USER HAS CLICKED AWAY AND WE NEED TO RECOVER THE MESSAGE IDs?
    // LOOK AT POOL EVENTS AND LOOK AT RECENT EVENTS FOR THE PIVOT
    let chain = poolData?.currentChain
    if (targetData?.targetChainId?.toString() !== "0") {
        chain = targetData?.targetChainId
    }
    if (poolData) {
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
                            <td style={{ padding: "0 15px" }}><span>Enter Position on <b>{networks[chain?.toString()]?.toUpperCase()}</b> </span></td>
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

    }

    let displaySection = <><div className="popup-title">Depositing to <b>{poolData?.protocol ?? targetData?.targetPositionProtocol} {networks[chain?.toString()]?.toUpperCase()}</b></div>
        <div className="popup-message">
            {display}
        </div></>

    if (!display) {
        displaySection = <Loader />
    }

    if (!showPopup) return null

    return (
        <div className="popup-container">
            <div className="popup">
                <div style={{ width: "100%", display: "flex", justifyContent: "flex-end" }}>
                    <button style={{ backgroundColor: "#374d59", marginRight: "30px", width: "134px" }} onClick={() => setShowPopup(false)} className={'demoButton'}><b>Close</b></button>
                </div>
                {displaySection}
            </div>
        </div>
    );
}

export default DepositStatus;