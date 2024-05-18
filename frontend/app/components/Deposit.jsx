import React, { useEffect, useMemo, useState } from 'react';
import { ethers, parseEther } from 'ethers';
import BigNumber from 'bignumber.js';
import PoolABI from '../ABI/PoolABI.json'; // Adjust the path as needed
import PoolTokenABI from '../ABI/PoolTokenABI.json'; // Adjust the path as needed
import WethABI from '../ABI/WethABI.json'; // Adjust the path as needed

import ISpokePoolABI from '../ABI/ISpokePoolABI.json'; // Adjust the path as needed
import { formatEther, zeroAddress } from 'viem'

import networks from '../JSON/networks.json'
import protocolHashes from '../JSON/protocolHashes.json'
import contractAddresses from '../JSON/contractAddresses.json'
import LoadingPopup from './LoadingPopup.jsx';
import DepositStatus from './DepositStatus.jsx';

import TxPopup from './TxPopup';
import { decodeAcrossDepositEvent, userLastDeposit } from '../utils';


const Deposit = ({ fetchPoolData, poolAddress, poolData, provider, setErrorMessage }) => {
    const [assetAmount, setAssetAmount] = useState(0.0001);
    const [initialMarket, setInitialMarket] = useState("0x2943ac1216979aD8dB76D9147F64E61adc126e96E4aB69C077896252FAFBD49EFD26B5D171A32410")
    const [chainId, setChainId] = useState(11155111)
    const [protocolName, setProtocolName] = useState("compound-v3")
    const [depoInitialized, setDepoInitialized] = useState(false);
    const [userAssetBalance, setUserAssetBalance] = useState(0)
    const [depositId, setDepositId] = useState("")
    useEffect(() => {
        if (poolData) {
            getBalanceOf()
            if (!poolData.userIsDepositing) {
                setDepositId("")
            }
        }
    }, [poolData])

    useEffect(() => {
        fetchPoolData()
    }, [depositId])

    const getBalanceOf = async () => {
        if (poolData?.poolAsset && zeroAddress !== poolData.poolAsset) {
            const asset = new ethers.Contract(poolData?.poolAsset || "0x0", PoolTokenABI, provider)
            const balance = (await asset.balanceOf(windowOverride?.ethereum?.selectedAddress))
            setUserAssetBalance(balance)
        }
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
            const asset = new ethers.Contract(contractAddresses["sepolia"].WETH || "0x0", WethABI, signer)
            const formattedAmount = parseEther(assetAmount + "")
            if (formatEther(userAssetBalance) <= assetAmount) {
                const amountToWrap = Number(formattedAmount) - Number(userAssetBalance)
                await (await asset.deposit({ value: formattedAmount, gasLimit: 8000000 }))
            }

            if (Number(await asset.allowance(windowOverride?.ethereum?.selectedAddress, poolAddress)) < Number(formattedAmount)) {
                const approval = await asset.approve(poolAddress, formattedAmount)
                await approval.wait()
            }

            console.log('REACHED', protocolName, initialMarket, chainId)

            const tx = await (await pool.userDepositAndSetPosition(
                formattedAmount,
                totalFeeCalc(Number(formattedAmount)),
                protocolName,
                initialMarket,
                chainId,
                { gasLimit: 8000000 }
            )).wait()

            const eventData = await decodeAcrossDepositEvent(tx.logs)
            if (eventData) {

                setDepositId(eventData.depositId);
                setTimeout(() => fetchPoolData(), 60000)

            }
            setTimeout(() => {
                fetchPoolData()
            }, 20000)


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
        const asset = new ethers.Contract(contractAddresses["sepolia"].WETH || "0x0", WethABI, signer)
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
            if (eventData) {

                setDepositId(eventData.depositId);
                setTimeout(() => fetchPoolData(), 60000)
            }
            setTimeout(() => {
                fetchPoolData()
            }, 20000)

            // setTxData({ hash: tx.hash, URI: ["https://sepolia.basescan.org/tx/" + tx.hash], poolAddress, message: `Chaser is processing your pool configuration and deposit. ${txAcrossMessage}` })

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
        <span className="">Deposit Amount</span>
        <input
            type="number"
            placeholder="0.0"
            className="new-pool-inputs"
            value={assetAmount}
            onChange={(x) => setAssetAmount(x.target.value)}
        />
        <span onClick={() => setAssetAmount(Number(formatEther(userAssetBalance)))} style={{ cursor: "pointer", fontSize: "13px", width: "100%", display: "block", textAlign: "right" }}><b>Balance: {formatEther(userAssetBalance)?.slice(0, 7)}</b></span>

    </>);
    if (poolData?.nonce?.toString() === '0' || !poolData?.nonce) {
        input = <>
            <span className="">Deposit Amount</span>
            <div style={{ marginBottom: "10px" }}>
                <input
                    type="number"
                    placeholder="0.0"
                    className="new-pool-inputs"
                    value={assetAmount}
                    onChange={(x) => {
                        setAssetAmount(x.target.value)
                    }}
                />
            </div>


            <div style={{ padding: 0 }} className="new-pool-inputs">
                <span className="">Chain</span>
                <select style={{ marginTop: 0, marginBottom: "10px" }} onChange={(x) => {
                    setChainId(x.target.value)
                    let marketIdKey = ""
                    if (protocolName == 'aave-v3') {
                        marketIdKey = "aaveMarketId"
                    }
                    if (protocolName == 'compound-v3') {
                        marketIdKey = "compoundMarketId"
                    }
                    const networkKey = networks[x.target.value]
                    setInitialMarket(contractAddresses[networkKey][marketIdKey])
                }} value={chainId} >
                    {Object.keys(networks).map(network => (
                        <option key={networks[network]} value={network}>{networks[network]}</option>
                    ))}
                </select>

                <span className="">Protocol</span>

                <select style={{ marginTop: 0, marginBottom: "10px" }} onChange={(x) => {
                    setProtocolName(x.target.value)

                    let marketIdKey = ""
                    if (x.target.value == 'aave-v3') {
                        marketIdKey = "aaveMarketId"
                    }
                    if (x.target.value == 'compound-v3') {
                        marketIdKey = "compoundMarketId"
                    }
                    const networkKey = networks[chainId]
                    setInitialMarket(contractAddresses[networkKey][marketIdKey])
                }} value={protocolName} >
                    {Object.values(protocolHashes).map(protocol => (
                        <option key={protocol} value={protocol}>{protocol}</option>
                    ))}
                </select>
            </div>
            <span className="">Market ID</span>
            <div style={{ marginBottom: "10px" }}>
                <input
                    type="text"
                    placeholder="0x0"
                    className="new-pool-inputs"
                    value={initialMarket}
                    disabled
                    onChange={(x) => {
                        setInitialMarket(x.target.value)
                    }}
                />
            </div>
        </>
    }

    let depoLoader = null;
    if (depoInitialized) {
        depoLoader = <LoadingPopup loadingMessage={"Please wait for your transactions to fill"} />
    }

    let depositPopup = null
    if (poolData?.userIsDepositing || depositId) {
        depositPopup = <DepositStatus provider={provider} depositId={depositId} poolData={poolData} fetchPoolData={fetchPoolData} poolAddress={poolAddress} />
    }

    return (
        <div className="interactionSection">
            {depositPopup}
            {depoLoader}
            <div>

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