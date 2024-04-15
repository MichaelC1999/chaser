import React, { useEffect, useMemo, useState } from 'react';
import { ethers, parseEther, solidityPackedKeccak256 } from 'ethers';
import PoolABI from '../ABI/PoolABI.json'; // Adjust the path as needed
import PoolTokenABI from '../ABI/PoolTokenABI.json'; // Adjust the path as needed
import { formatEther } from 'viem'
import networks from '../JSON/networks.json'
import { decodeCCIPSendMessageEvent } from '../utils';
import LoadingPopup from './LoadingPopup';


const Withdraw = ({ poolAddress, poolData, provider, setErrorMessage, txData, setTxData }) => {
    const [assetAmount, setAssetAmount] = useState('');
    const [buyInputError, setBuyInputError] = useState(false);
    const [withdrawInitialized, setWithdrawInitialized] = useState(false);
    const [userAssetBalance, setUserAssetBalance] = useState(0)

    useEffect(() => {
        getBalanceOf()
    }, [])

    const getBalanceOf = async () => {
        const asset = new ethers.Contract(poolData?.poolAsset || "0x0", PoolTokenABI, provider)
        return (await asset.balanceOf(poolData?.user?.address))
    }

    useEffect(() => {
        // Buy flow starts with clearing input errors detected on last buy attempt
        if (withdrawInitialized) {
            setBuyInputError(false);
            handleWithdraw();
        }
    }, [withdrawInitialized])

    const windowOverride = useMemo(() => (
        typeof window !== 'undefined' ? window : null
    ), []);

    const handleWithdraw = async () => {
        let signer = null;
        try {
            await provider.send("eth_requestAccounts", []);
            signer = await provider.getSigner();
        } catch (err) {
            console.log("Connection Error: " + err?.info?.error?.message ?? err?.message);
            setErrorMessage(err?.info?.error?.message ?? "This transaction has failed, try again or get in touch with the Chaser devs")

        }
        const pool = new ethers.Contract(poolAddress || "0x0", PoolABI, signer)
        const formattedAmount = parseEther(assetAmount + "")

        try {
            const tx = await (await pool.userWithdrawOrder(
                formattedAmount,
                { gasLimit: 1000000 }
            )).wait()

            const URIs = ["https://sepolia.basescan.org/tx/" + tx.hash]
            let txCCIPMessage = ''
            if (networks[poolData?.currentChain] !== 'base') {
                const ccipData = await decodeCCIPSendMessageEvent(tx.logs)
                txCCIPMessage = `CCIP is sending a message to Chaser contracts on ${networks[poolData?.currentChain]} network. The CCIP message ID is ${ccipData?.messageId}. This CCIP message will trigger functions on ${networks[poolData?.currentChain]} which will send your funds through the Across bridge back to your wallet on Base Sepolia. This whole process can take up to 30 minutes.`
                URIs.push("https://ccip.chain.link/msg/" + ccipData?.messageId)
            }
            setTxData({ hash: tx.hash, URI: URIs, poolAddress, message: `Chaser is processing your Withdraw. ${txCCIPMessage}` })
        } catch (err) {
            console.log('HIT?', err?.hash, err?.error, err, Object.getOwnPropertyNames(err), 'data', err.data, 'reason', err.reason, 'meassage', err.message, 'transaction', err.transaction, 'receipt', err.receipt)
            setErrorMessage(err?.info?.error?.message ?? "This transaction has failed\n\n" + (err?.receipt ? "TX: " + err.receipt.hash : ""))
        }
        setWithdrawInitialized(false)
    };


    let withdrawLoader = null;
    if (withdrawInitialized) {
        withdrawLoader = <LoadingPopup loadingMessage={"Please wait for your transactions to fill"} />
    }
    return (
        <div className="interactionSection">
            {withdrawLoader}
            <div>
                <span className="">Withdraw Amount</span>
                <input
                    type="number"
                    placeholder="0.0"
                    className="new-pool-inputs"
                    value={assetAmount}
                    onChange={(x) => setAssetAmount(x.target.value)}
                />
            </div>
            <button className="button" onClick={() => {
                if (formatEther(userAssetBalance) > assetAmount) {
                    setWithdrawInitialized(true)
                }
            }}>Withdraw</button>
        </div>
    );
};

export default Withdraw;

function totalFeeCalc(amount) {
    return (parseInt((Number(amount) / 400).toString())).toString()
}