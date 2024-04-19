import React, { useEffect, useMemo, useState } from 'react';
import { ethers, parseEther } from 'ethers';
import BigNumber from 'bignumber.js';
import PoolABI from '../ABI/PoolABI.json'; // Adjust the path as needed
import PoolTokenABI from '../ABI/PoolTokenABI.json'; // Adjust the path as needed
import WethABI from '../ABI/WethABI.json'; // Adjust the path as needed

import ISpokePoolABI from '../ABI/ISpokePoolABI.json'; // Adjust the path as needed
import { formatEther } from 'viem'

import networks from '../JSON/networks.json'
import protocolHashes from '../JSON/protocolHashes.json'
import contractAddresses from '../JSON/contractAddresses.json'
import LoadingPopup from './LoadingPopup.jsx';
import TxPopup from './TxPopup';
import { decodeAcrossDepositEvent } from '../utils';


const Deposit = ({ poolAddress, poolData, provider, setErrorMessage, txData, setTxData, changeStep, demoMode }) => {
    const [assetAmount, setAssetAmount] = useState(0.0001);
    const [chainId, setChainId] = useState(84532)
    const [protocolName, setProtocolName] = useState("compound-v3")
    const [depoInitialized, setDepoInitialized] = useState(false);
    const [userAssetBalance, setUserAssetBalance] = useState(0)

    useEffect(() => {
        if (poolData) {
            getBalanceOf()
        }
    }, [poolData])

    const getBalanceOf = async () => {
        const asset = new ethers.Contract(poolData?.poolAsset || "0x0", PoolTokenABI, provider)
        const balance = (await asset.balanceOf(windowOverride?.ethereum?.selectedAddress))
        setUserAssetBalance(balance)
        return
    }

    useEffect(() => {
        // Depo flow starts with clearing input errors detected on last depo attempt
        if (depoInitialized) {
            if (poolData?.nonce?.toString() === "0" || !poolData?.nonce) {
                handleSetPositionDeposit()
            } else {
                handleDeposit();

            }
        }
    }, [depoInitialized])


    const windowOverride = useMemo(() => (
        typeof window !== 'undefined' ? window : null
    ), []);

    const handleSetPositionDeposit = async () => {
        let signer = null;
        try {
            await provider.send("eth_requestAccounts", []);
            signer = await provider.getSigner();
        } catch (err) {
            console.log("Connection Error: " + err?.info?.error?.message ?? err?.message);
            setErrorMessage("Connection Error: " + err?.info?.error?.message ?? err?.message)
        }
        const pool = new ethers.Contract(poolAddress || "0x0", PoolABI, signer)

        try {
            const asset = new ethers.Contract(contractAddresses["base"].WETH || "0x0", WethABI, signer)
            const formattedAmount = parseEther(assetAmount + "")
            if (formatEther(userAssetBalance) <= assetAmount) {
                const amountToWrap = Number(formattedAmount) - Number(userAssetBalance)
                await (await asset.deposit({ value: formattedAmount, gasLimit: 8000000 }))
            }

            if (Number(await asset.allowance(windowOverride?.ethereum?.selectedAddress, poolAddress)) < Number(formattedAmount)) {
                await (await asset.approve(poolAddress, formattedAmount)).wait()
            }

            const tx = await (await pool.userDepositAndSetPosition(
                formattedAmount,
                totalFeeCalc(Number(formattedAmount)),
                "0x0242242424242",
                chainId,
                protocolName,
                { gasLimit: 8000000 }
            )).wait()
            const eventData = await decodeAcrossDepositEvent(tx.logs)
            let txAcrossMessage = ''
            if (networks[chainId] !== 'base') {
                txAcrossMessage = `Chaser is processing your pool configuration and deposit. Using Across V3, your funds and input data are being bridged to Chaser contracts on the ${networks[chainId]} network. The Across depositID is ${eventData?.depositId}. Look for a 'FilledV3Relay' event on the ${networks[poolData?.currentChain]} SpokePool with this depositID. Once processed on ${networks[chainId]}, Chaser will send data through CCIP back to the contract you just interacted with. This should all finalize within the next 30 minutes.`
            } else {
                txAcrossMessage = `Chaser has successfully processed your deposit and position setting.`
            }
            setTxData({ hash: tx.hash, URI: ["https://sepolia.basescan.org/tx/" + tx.hash], poolAddress, message: `${txAcrossMessage}` })

        } catch (err) {
            console.log('HIT?', err?.hash, err?.error, err)
            setErrorMessage(err?.info?.error?.message ?? "This transaction has failed\n\n" + (err?.receipt ? "TX: " + err.receipt.hash : ""))
        }
        setDepoInitialized(false)
    }

    const handleDeposit = async () => {
        let signer = null;
        try {
            await provider.send("eth_requestAccounts", []);
            signer = await provider.getSigner();
        } catch (err) {
            console.log("Connection Error: " + err?.info?.error?.message ?? err?.message);
            setErrorMessage("Connection Error: " + err?.info?.error?.message ?? err?.message)

        }

        const pool = new ethers.Contract(poolAddress || "0x0", PoolABI, signer)
        const asset = new ethers.Contract(contractAddresses["base"].WETH || "0x0", WethABI, signer)
        const formattedAmount = parseEther(assetAmount + "")
        try {
            if (formatEther(userAssetBalance) <= assetAmount) {
                await (await asset.deposit({ value: formattedAmount, gasLimit: 8000000 }))
            }
            if (Number(await asset.allowance(windowOverride?.ethereum?.selectedAddress, poolAddress)) < Number(formattedAmount)) {
                await (await asset.approve(poolAddress, formattedAmount)).wait()
            }

            const tx = await (await pool.userDeposit(
                formattedAmount,
                totalFeeCalc(Number(formattedAmount)),
                { gasLimit: 1000000 }
            )).wait()
            const eventData = await decodeAcrossDepositEvent(tx.logs)
            let txAcrossMessage = ''
            if (networks[poolData?.currentChain] !== 'base') {
                txAcrossMessage = `Using Across V3, your funds and input data are being bridged to Chaser contracts on the ${networks[chainId]} network. The Across depositID is ${eventData?.depositId}. Look for a 'FilledV3Relay' event on the ${networks[poolData?.currentChain]} SpokePool with this depositID. Once processed on ${networks[chainId]}, Chaser will send data through CCIP back to the contract you just interacted with. This should all finalize within the next 30 minutes.`
            }
            setTxData({ hash: tx.hash, URI: ["https://sepolia.basescan.org/tx/" + tx.hash], poolAddress, message: `Chaser is processing your pool configuration and deposit. ${txAcrossMessage}` })

            //From event data get the Across depositId, destination chain
            //Event in logs array with topic[0] = 0xa123dc29aebf7d0c3322c8eeb5b999e859f39937950ed31056532713d0de396f
            //Set up etherscan API listener to check destination spokepool for new relayFill events and check for matching depositId
            //In the detected transaction, look for event with CCIP message id
            //Link to CCIP dashboard
        } catch (err) {
            console.log('HIT?', err?.hash, err?.error, err)
            setErrorMessage(err?.info?.error?.message ?? "This transaction has failed\n\n" + (err?.receipt ? "TX: " + err.receipt.hash : ""))
        }
        setDepoInitialized(false)

    };

    let input = (<>

        <input
            type="number"
            placeholder="0.0"
            className="new-pool-inputs"
            value={assetAmount}
            onChange={(x) => setAssetAmount(x.target.value)}
        />

    </>);
    if (poolData?.nonce?.toString() === '0' || !poolData?.nonce) {
        input = (<>
            <input
                type="number"
                placeholder="0.0"
                className="new-pool-inputs"
                value={assetAmount}
                onChange={(x) => {
                    if (!demoMode) {
                        setAssetAmount(x.target.value)
                    }
                }}
            />
            <input
                type="number"
                placeholder="0.0"
                className="new-pool-inputs"
                value={chainId}
                onChange={(x) => {
                    if (!demoMode) {
                        setChainId(x.target.value)
                    }
                }}

            />
            <input
                type="text"
                placeholder="0.0"
                className="new-pool-inputs"
                value={protocolName}
                onChange={(x) => {
                    if (!demoMode) {
                        setProtocolName(x.target.value)
                    }
                }}

            />
        </>)
    }

    let depoLoader = null;
    if (depoInitialized) {
        depoLoader = <LoadingPopup loadingMessage={"Please wait for your transactions to fill"} />
    }


    return (
        <div className="interactionSection">
            {depoLoader}
            <div>
                <span className="">Deposit Amount</span>
                {input}
            </div>
            <button className="button" onClick={() => {

                if (!assetAmount) {
                    setErrorMessage("Enter an amount to deposit");
                    return
                }
                // if (formatEther(userAssetBalance) <= assetAmount) {
                //     setErrorMessage("Your balance is not high enough for this deposit")
                //     return
                // }

                if (poolData?.nonce?.toString() === '0' || !poolData?.nonce) {
                    if (!networks[chainId]) {
                        setErrorMessage("The chain you have entered is not supported at this time.")
                        return
                    }
                    if (!Object.values(protocolHashes)?.includes(protocolName)) {
                        setErrorMessage("The protocol you have entered is not supported at this time.")
                        return
                    }
                }
                setDepoInitialized(true)
            }}>{poolData?.nonce?.toString() === '0' || !poolData?.nonce ? "Set Position Deposit" : "Deposit"}</button>
        </div>
    );
};

export default Deposit;

function totalFeeCalc(amount) {
    return (parseInt((Number(amount) / 400).toString())).toString()
}