import React, { useEffect, useMemo, useState } from 'react';
import { ethers, parseEther, solidityPackedKeccak256 } from 'ethers';
import BigNumber from 'bignumber.js';
import PoolABI from '../ABI/PoolABI.json'; // Adjust the path as needed
import PoolTokenABI from '../ABI/PoolTokenABI.json'; // Adjust the path as needed
import { createPublicClient, getContract, http, formatEther, zeroAddress } from 'viem'
import networks from '../JSON/networks.json'
import TxPopup from './TxPopup';


const Deposit = ({ poolAddress, poolData, provider }: any) => {
    const [assetAmount, setAssetAmount] = useState<string>('');
    const [targetChainId, setTargetChainId] = useState<string>("11155111")
    const [txData, setTxData] = useState<any>({})
    const [buyInputError, setBuyInputError] = useState<Boolean>(false);
    const [buyInitialized, setBuyInitialized] = useState<Boolean>(false);
    const [userAssetBalance, setUserAssetBalance] = useState<any>(0)
    // // isEthereumAvailable helps prevent 'window' object errors while browser loads injected provider 
    // const [isEthereumAvailable, setIsEthereumAvailable] = useState(false);

    useEffect(() => {

        getBalanceOf()
    }, [])

    const getBalanceOf = async () => {
        const asset: any = new ethers.Contract(poolData?.poolAsset || "0x0", PoolTokenABI, provider)
        return (await asset.balanceOf(poolData?.user?.address))

    }

    useEffect(() => {
        // Buy flow starts with clearing input errors detected on last buy attempt
        if (buyInitialized) {
            setBuyInputError(false);

            if (poolData?.nonce?.toString() === "0") {
                handleSetPositionDeposit()
            } else {
                handleDeposit();

            }
        }
    }, [buyInitialized])


    const windowOverride: any = useMemo(() => (
        typeof window !== 'undefined' ? window : null
    ), []);

    const handleSetPositionDeposit = async () => {
        let signer: any = null;
        try {
            await provider.send("eth_requestAccounts", []);
            signer = await provider.getSigner();
        } catch (err: any) {
            console.log("Connection Error: " + err?.info?.error?.message ?? err?.message);
        }
        const pool: any = new ethers.Contract(poolAddress || "0x0", PoolABI, signer)

        const asset: any = new ethers.Contract(process.env.NEXT_PUBLIC_BASE_WETH || "0x0", PoolTokenABI, signer)
        const formattedAmount = parseEther(assetAmount + "")

        await (await asset.approve(poolAddress, formattedAmount)).wait()

        const tx = await (await pool.userDepositAndSetPosition(
            formattedAmount,
            totalFeeCalc(Number(formattedAmount)),
            "0x0242242424242",
            targetChainId,
            "aave",
            { gasLimit: 1000000 }
        )).wait()

        setTxData({ hash: tx.hash, URI: "https://dashboard.tenderly.co/tx/base-sepolia/" + tx.hash, poolAddress, message: `Chaser is processing your pool configuration and deposit. Using Across V3, your funds and input data are being bridged to Chaser contracts on the ${networks[targetChainId]} network. Once processed on ${networks[targetChainId]}, Chaser will send data through CCIP back to the contract you just interacted with. This should all finalize within the next 30 minutes. ` })

    }

    const handleDeposit = async () => {
        let signer: any = null;
        try {
            await provider.send("eth_requestAccounts", []);
            signer = await provider.getSigner();
        } catch (err: any) {
            console.log("Connection Error: " + err?.info?.error?.message ?? err?.message);
        }
        const pool: any = new ethers.Contract(poolAddress || "0x0", PoolABI, signer)

        const asset: any = new ethers.Contract(process.env.NEXT_PUBLIC_BASE_WETH || "0x0", PoolTokenABI, signer)
        const formattedAmount = parseEther(assetAmount + "")

        await (await asset.approve(poolAddress, formattedAmount)).wait()

        const tx = await (await pool.userDeposit(
            formattedAmount,
            totalFeeCalc(Number(formattedAmount)),
            { gasLimit: 1000000 }
        )).wait()
        setTxData({ hash: tx.hash, URI: "https://dashboard.tenderly.co/tx/base-sepolia/" + tx.hash, poolAddress, message: `Chaser is processing your deposit. Using Across V3, your funds and input data are being bridged to Chaser contracts on the ${networks[targetChainId]} network. Once processed on ${networks[targetChainId]}, Chaser will send data through CCIP back to the contract you just interacted with. This should all finalize within the next 30 minutes.` })

    };

    let input: React.JSX.Element = (<>

        <input
            type="number"
            placeholder="0.0"
            className="new-pool-inputs"
            value={assetAmount}
            onChange={(x) => setAssetAmount(x.target.value)}
        />
        <button className="button" onClick={() => {
            if (formatEther(userAssetBalance) > assetAmount) {

                setBuyInitialized(true)
            }
        }}>Deposit</button>
    </>);

    if (poolData?.poolNonce?.toString() === '0') {
        input = (<>
            <input
                type="number"
                placeholder="0.0"
                className="new-pool-inputs"
                value={assetAmount}
                onChange={(x) => setAssetAmount(x.target.value)}
            />
            <input
                type="number"
                placeholder="0.0"
                className="new-pool-inputs"
                value={11155111}
            />
            <input
                type="text"
                placeholder="0.0"
                className="new-pool-inputs"
                value={"aave"}
            />
            <button className="button" onClick={() => {
                if (formatEther(userAssetBalance) > assetAmount) {

                    setBuyInitialized(true)
                }

            }}>Set Position Deposit</button>
        </>)
    }

    let txPopup = null
    if (Object.keys(txData)?.length > 0) {
        txPopup = <TxPopup popupData={txData} clearPopupData={() => setTxData({})} />
    }

    return (
        <div className="interactionSection">
            <span className="">Deposit Amount</span>
            {input}

            {txPopup}
        </div>
    );
};

export default Deposit;

function totalFeeCalc(amount: Number) {
    return (parseInt((Number(amount) / 400).toString())).toString()
}