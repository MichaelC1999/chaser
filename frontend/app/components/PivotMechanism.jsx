import React, { useEffect, useMemo, useState } from 'react';
import { ethers, parseEther, solidityPackedKeccak256 } from 'ethers';
import BigNumber from 'bignumber.js';
import PoolTokenABI from '../ABI/PoolTokenABI.json'; // Adjust the path as needed
import PoolABI from '../ABI/PoolABI.json'; // Adjust the path as needed
import { createPublicClient, getContract, http, formatEther, zeroAddress } from 'viem'
import networks from '../JSON/networks.json'
import protocolHashes from '../JSON/protocolHashes.json'
import contractAddresses from '../JSON/contractAddresses.json'
import LoadingPopup from './LoadingPopup.jsx';
import { decodeAcrossDepositEvent, decodeCCIPSendMessageEvent } from '../utils';


const PivotMechanism = ({ poolData, provider, setErrorMessage, txData, setTxData, step, demoMode, changeStep }) => {
    const [targetChain, setTargetChain] = useState('11155111');
    const [protocolName, setProtocolName] = useState("aave-v3")
    const [pivotInitialized, setPivotInitialized] = useState(false);

    useEffect(() => {
        // Depo flow starts with clearing input errors detected on last depo attempt
        if (pivotInitialized) {
            handlePivot();
        }
    }, [pivotInitialized])

    useEffect(() => {
        if (step === 3) {
            setTargetChain('11155111')
            setProtocolName('aave-v3')
        }
    }, [step])

    const windowOverride = useMemo(() => (
        typeof window !== 'undefined' ? window : null
    ), []);

    const handlePivot = async () => {
        let signer = null;
        try {
            await provider.send("eth_requestAccounts", []);
            signer = await provider.getSigner();
        } catch (err) {
            console.log("Connection Error: " + err?.info?.error?.message ?? err?.message);
        }

        const pool = new ethers.Contract(poolData.address || "0x0", PoolABI, signer)
        const asset = new ethers.Contract(contractAddresses["sepolia"].WETH || "0x0", PoolTokenABI, signer)
        try {


            // const protocolHash = Object.keys(protocolHashes).find(x => protocolHashes[x] === protocolName);
            const tx = await (await pool.sendPositionChange(
                "0x0585585858585",
                protocolName,
                targetChain,
                { gasLimit: 3000000 }
            )).wait()

            let eventData = {}
            if (networks[poolData?.currentChain] !== 'sepolia') {
                eventData = await decodeCCIPSendMessageEvent(tx.logs)
            } else if (networks[targetChain] !== 'sepolia') {
                eventData = await decodeAcrossDepositEvent(tx.logs)

            }
            let otherChainInteraction = ''
            if ((poolData?.currentChain === 'sepolia' || !poolData?.currentChain) && networks[targetChain] === 'sepolia') {
                eventData = { message: `The Pivot from ${protocolHashes[poolData?.protocol]} ${networks[poolData?.currentChain]} to ${protocolName} ${networks[targetChain]} was successful and has finalized.` }
            } else {
                otherChainInteraction = "This entire process could take up to 30 minutes."
                let message = `The Pivot from ${protocolHashes[poolData?.protocol]} ${networks[poolData?.currentChain]} to ${protocolName} ${networks[targetChain]} has been initiated`;

                if (networks[poolData?.currentChain] !== 'sepolia' || !poolData?.currentChain) {
                    message += " with a CCIP message to Chaser contracts on " + networks[poolData?.currentChain];
                    if (eventData.messageId) {
                        message += ' with a messageId of ' + eventData.messageId;
                    }
                }

                if (networks[poolData?.currentChain] !== networks[targetChain] && poolData?.currentChain) {
                    message += `. The funds on ${networks[poolData?.currentChain]} will be bridged through Across to ${networks[targetChain]}`;
                    if (eventData.depositId) {
                        message += ' with a depositID of ' + eventData.depositId;
                    }
                    message += '. ';
                }

                if (networks[targetChain] !== 'sepolia') {
                    message += "To finalize, a CCIP callback message will be sent back to sepolia. ";
                }

                message += otherChainInteraction;
                eventData.message =
                    message
            }

            setTxData({ hash: tx.hash, URI: ["https://sepolia.basescan.org/tx/" + tx.hash], poolAddress: poolData.address, message: eventData.message })
            changeStep(4)
        } catch (err) {
            console.log('HIT?', err?.hash, err?.error, err)
            setErrorMessage(err?.info?.error?.message ?? "This transaction has failed\n\n" + (err?.receipt ? "TX: " + err.receipt.hash : ""))
        }
        setPivotInitialized(false)
    };

    let depoLoader = null;
    if (pivotInitialized) {
        depoLoader = <LoadingPopup loadingMessage={"Please wait for your transactions to fill"} />
    }

    return (
        <div className="interactionSection">
            {depoLoader}
            <div>
                <span className="">Pivot Position</span>
                <div style={{ padding: 0 }} className="new-pool-inputs">
                    <select style={{ marginTop: 0, marginBottom: "10px" }} onChange={(x) => {
                        if (!demoMode) {
                            setTargetChain(x.target.value)
                        }
                    }} value={targetChain} >
                        {Object.keys(networks).map(network => (
                            <option key={networks[network]} value={network}>{networks[network]}</option>
                        ))}
                    </select>
                </div>
                <div style={{ padding: 0 }} className="new-pool-inputs">

                    <select style={{ marginTop: 0, marginBottom: "10px" }} onChange={(x) => {
                        if (!demoMode) {
                            setProtocolName(x.target.value)
                        }
                    }} value={protocolName} >
                        {Object.values(protocolHashes).map(protocol => (
                            <option key={protocol} value={protocol}>{protocol}</option>
                        ))}
                    </select>
                </div>

            </div>
            <button className="button" onClick={() => {

                if (!networks[targetChain]) {
                    setErrorMessage("The chain you have entered is not supported at this time.")
                    return
                }
                if (!Object.values(protocolHashes)?.includes(protocolName)) {
                    setErrorMessage("The protocol you have entered is not supported at this time.")
                    return
                }
                setPivotInitialized(true)

            }}>Send Pivot</button>
        </div>
    );
};

export default PivotMechanism;