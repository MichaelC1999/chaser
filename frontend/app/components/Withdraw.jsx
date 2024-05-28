import React, { useEffect, useMemo, useState } from 'react';
import { ethers, parseEther, solidityPackedKeccak256 } from 'ethers';
import PoolABI from '../ABI/PoolABI.json'; // Adjust the path as needed
import PoolTokenABI from '../ABI/PoolTokenABI.json'; // Adjust the path as needed
import { formatEther } from 'viem'
import networks from '../JSON/networks.json'
import { decodeCCIPSendMessageEvent, userLastWithdraw } from '../utils';
import WithdrawStatus from './WithdrawStatus'
import LoadingPopup from './LoadingPopup';
import { useWeb3Modal, useWeb3ModalAccount } from '@web3modal/ethers/react';


const Withdraw = ({ poolAddress, poolData, provider, setErrorMessage, fetchPoolData }) => {
    const { open } = useWeb3Modal()
    const { isConnected } = useWeb3ModalAccount()
    const [assetAmount, setAssetAmount] = useState('');
    const [buyInputError, setBuyInputError] = useState(false);
    const [withdrawInitialized, setWithdrawInitialized] = useState(false);
    const [withdrawId, setWithdrawId] = useState("")

    useEffect(() => {
        if (poolData) {
            if (!poolData.userIsWithdrawing) {
                setWithdrawId("")
            }
        }
    }, [poolData])

    useEffect(() => {
        fetchPoolData()
    }, [withdrawId])

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
            if (isConnected) {
                setBuyInputError(false);
                handleWithdraw();
            } else {
                open({})
            }
        }
    }, [withdrawInitialized, isConnected])

    const windowOverride = useMemo(() => (
        typeof window !== 'undefined' ? window : null
    ), []);

    const handleWithdraw = async () => {
        if (!assetAmount) {
            setWithdrawInitialized(false)
            setErrorMessage("You need to set a valid amount to withdraw.")
            return
        }
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

            let txCCIPMessage = ''
            if (networks[poolData?.currentChain] !== 'arbitrum') {
                const ccipData = await decodeCCIPSendMessageEvent(tx.logs)
                setWithdrawId(ccipData?.messageId);
                setTimeout(() => fetchPoolData(), 60000)
            } else {
                setTimeout(() => fetchPoolData(), 20000)
            }

        } catch (err) {
            setErrorMessage(err?.info?.error?.message ?? "This transaction has failed\n\n" + (err?.receipt ? "TX: " + err.receipt.hash : ""))
        }
        setWithdrawInitialized(false)
    };


    let withdrawLoader = null;
    if (withdrawInitialized && isConnected) {
        withdrawLoader = <LoadingPopup loadingMessage={"Please wait for your transactions to fill"} />
    }

    let withdrawPopup = null
    if (poolData?.userIsWithdrawing || withdrawId) {
        console.log('HIT WITH')
        withdrawPopup = <WithdrawStatus provider={provider} withdrawId={withdrawId} poolData={poolData} fetchPoolData={fetchPoolData} poolAddress={poolAddress} />
    }
    return (
        <div className="interactionSection">
            {withdrawPopup}
            {withdrawLoader}
            <div>
                <span className="">Withdraw Amount</span>
                <input
                    step="0.00000001"
                    type="number"
                    placeholder="0.0"
                    className="new-pool-inputs"
                    value={assetAmount.toString()}
                    onChange={(x) => setAssetAmount(x.target.value)}
                />
                <span onClick={() => setAssetAmount((poolData.user.userDepositValue))} style={{ cursor: "pointer", fontSize: "13px", width: "100%", display: "block", textAlign: "right" }}><b>Deposited: {poolData?.user?.userDepositValue?.toString()?.slice(0, 7)}</b></span>

            </div>
            <button className="button" onClick={() => {
                if (Number(poolData.user.userDepositValue) >= assetAmount) {
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