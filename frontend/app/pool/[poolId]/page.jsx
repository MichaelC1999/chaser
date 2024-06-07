'use client'

import { useEffect, useMemo, useState } from 'react'
import { usePathname } from 'next/navigation'
import { ethers } from 'ethers';
import PoolABI from '../../ABI/PoolABI.json'; // Adjust the path as needed
import PoolTokenABI from '../../ABI/PoolTokenABI.json'; // Adjust the path as needed
import PoolCalculationsABI from '../../ABI/PoolCalculationsABI.json'; // Adjust the path as needed
import InvestmentStrategyABI from '../../ABI/InvestmentStrategyABI.json'; // Adjust the path as needed

import BridgeLogicABI from '../../ABI/BridgeLogicABI.json'; // Adjust the path as needed
import { createPublicClient, getContract, http, formatEther, zeroAddress } from 'viem'
import protocolHashes from '../../JSON/protocolHashes.json'
import networks from '../../JSON/networks.json'

import { sepolia, baseSepolia, arbitrumSepolia, optimismSepolia } from 'viem/chains'
import UserPoolSection from '@/app/components/UserPoolSection';
import contractAddresses from '../../JSON/contractAddresses.json'
import ErrorPopup from '@/app/components/ErrorPopup.jsx';
import TxPopup from '@/app/components/TxPopup';
import Loader from '@/app/components/Loader';
import StrategyPopup from '@/app/components/StrategyPopup';
import { useWeb3Modal, useWeb3ModalAccount } from '@web3modal/ethers/react';

export default function Page() {
    const { open } = useWeb3Modal()
    const { address } = useWeb3ModalAccount()

    const [poolData, setPoolData] = useState(null);
    const [errorMessage, setErrorMessage] = useState("");
    const [txData, setTxData] = useState({})
    const [showPivotSuccess, setShowPivotSuccess] = useState(false)
    const [viewStrategy, setViewStrategy] = useState(false)
    const pathname = usePathname()

    const poolId = pathname?.split('/')?.[2]

    const windowOverride = useMemo(() => (
        typeof window !== 'undefined' ? window : null
    ), []);
    const provider = new ethers.JsonRpcProvider("https://sepolia-rollup.arbitrum.io/rpc/" + process.env.NEXT_PUBLIC_INFURA_API)

    const getPoolData = async (address) => {
        const returnObject = {}
        const pool = new ethers.Contract(address || "0x0", PoolABI, provider);
        const poolCalc = new ethers.Contract(contractAddresses["arbitrum"].poolCalculationsAddress || "0x0", PoolCalculationsABI, provider);
        const stratContact = new ethers.Contract(contractAddresses.arbitrum["investmentStrategy"], InvestmentStrategyABI, provider)

        const metaData = await pool.poolMetaData()
        returnObject.poolTokenAddress = metaData["0"]
        returnObject.poolAsset = metaData["1"]
        returnObject.name = metaData["2"]
        const currents = await pool.readPoolCurrentPositionData()
        returnObject.protocol = protocolHashes[currents["1"]]
        returnObject.recordPositionValue = formatEther(currents["2"])
        returnObject.recordTimestamp = currents["3"]
        returnObject.currentChain = currents["4"]
        const transactionStatus = await pool.transactionStatus()
        returnObject.depoNonce = transactionStatus["0"]
        returnObject.withdrawNonce = transactionStatus["1"]
        returnObject.nonce = returnObject.depoNonce + returnObject.withdrawNonce
        returnObject.userIsDepositing = await poolCalc.poolToUserPendingDeposit(address, windowOverride?.ethereum?.selectedAddress || zeroAddress)
        returnObject.userIsWithdrawing = await poolCalc.poolToUserPendingWithdraw(address, windowOverride?.ethereum?.selectedAddress || zeroAddress)

        returnObject.isPivoting = transactionStatus["2"]
        returnObject.openAssertion = transactionStatus["3"]

        returnObject.strategyIndex = await pool.strategyIndex()
        returnObject.strategyName = await stratContact.strategyName(returnObject.strategyIndex)

        console.log(returnObject)

        try {
            if (returnObject.poolTokenAddress) {
                const poolToken = new ethers.Contract(returnObject.poolTokenAddress || "0x0", PoolTokenABI, provider);
            }
        } catch (err) {

        }

        try {
            const poolAssetContract = new ethers.Contract(returnObject.poolAsset || "0x0", PoolTokenABI, provider);
            returnObject.poolAssetName = await poolAssetContract.name()
            returnObject.poolAssetSymbol = await poolAssetContract.symbol()
        } catch (err) {
            returnObject.poolAsset = zeroAddress
        }

        try {
            if (returnObject?.nonce > 0) {
                returnObject.userRatio = await poolCalc.getScaledRatio(returnObject.poolTokenAddress, windowOverride?.ethereum?.selectedAddress || zeroAddress)
            }
        } catch (err) {
            console.log(err)
        }

        // Have json with mapping of protocol hashes to the protocol name, read slug/protocolname from this list. No need to be on chain
        return { address, name, user: { userRatio: returnObject.userRatio, address: windowOverride?.ethereum?.selectedAddress || zeroAddress }, ...returnObject }
    }

    const getBridgePoolData = async (address, hash, chainId, data) => {
        if (!chainId) {
            return {}
        }
        let chain = arbitrumSepolia
        let chainName = 'arbitrum'
        if (chainId.toString() === "11155111") {
            chain = sepolia
            chainName = 'sepolia'
        }
        if (chainId.toString() === "11155420") {
            chain = optimismSepolia
            chainName = 'optimism'
        }
        if (chainId.toString() === "84532") {
            chain = baseSepolia
            chainName = 'base'
        }
        const publicClient = createPublicClient({
            chain,
            transport: http()
        })

        try {

            const bridgeLogic = getContract({
                address: contractAddresses[chainName].bridgeLogicAddress,
                abi: BridgeLogicABI,
                client: publicClient,
            })
            const tvl = await bridgeLogic.read.getNonPendingPositionBalance([address, data.depoNonce, data.withdrawNonce])
            let userDepositValue = 0
            if (Number(tvl.toString()) > 0) {
                const maxWithdraw = await bridgeLogic.read.getUserMaxWithdraw([tvl, data.user.userRatio])
                userDepositValue = formatEther(maxWithdraw)
            }

            return { user: { ...data.user, userDepositValue }, TVL: formatEther(tvl) }
        } catch (err) {
            console.log(err)
            return {}
        }

    }

    useEffect(() => {

        fetchPoolData()

        const interval = setInterval(fetchPoolData, 300000); // 300000 ms = 5 minutes

        return () => clearInterval(interval); // Clean up the interval on component unmount

    }, [txData, address])

    const fetchPoolData = async () => {
        try {
            const poolDataReturn = await getPoolData(poolId)
            const bridgedPoolData = await getBridgePoolData(poolId, poolDataReturn.protocol, poolDataReturn.currentChain, poolDataReturn)
            if (!poolDataReturn.isPivoting) {
                poolDataReturn.currentApy = calculateAPY(poolDataReturn?.recordPositionValue, bridgedPoolData?.TVL, poolDataReturn?.recordTimestamp)
            }

            if (poolDataReturn?.isPivoting === false && poolData?.isPivoting === true) {
                setShowPivotSuccess(true)
            }
            setPoolData({ ...poolDataReturn, ...bridgedPoolData })

        } catch (err) {
            console.log(err, provider)
            setErrorMessage("Error fetching pool data: " + (err?.info?.error?.message ?? "Try reloading"))
        }
    }

    let ele = null
    let userEle = null;
    if (poolData) {
        const poolInfo = []
        const assetInfo = []
        const userInfo = []
        Object.keys(poolData)?.forEach(x => {
            let value = poolData[x]?.toString()
            let key = x
            if (x === 'user' || x === 'recordTimestamp' || x === 'recordPositionValue') {
                return
            }
            if (x === 'TVL' || x.toUpperCase().includes('VALUE')) {
                key = `${formatString(x)} (${poolData?.poolAssetSymbol})`
            } else if (x === 'currentApy') {
                key = "Current APY";
                value = (poolData[x]).toFixed(10) + '%'
            } else {
                key = formatString(x)
            }
            if (x === 'protocol') {
                value = poolData[x]
            }
            if (x === 'currentChain') {
                value = networks[poolData.currentChain]
            }
            const element = (<tr key={x} style={{ height: '22px' }}>
                <td style={{ width: "200px" }}>{key}</td>
                <td>{value}</td>
            </tr>)
            if (x === "address" || x === "name" || x === "currentChain" || x === "protocol" || x === "TVL" || x === "nonce" || x === "poolAsset" || x === "poolAssetName" || x === "poolAssetSymbol" || x === "currentApy" || x === "isPivoting") {
                poolInfo.push(element)
            }

        })
        ele = <div style={{ padding: "20px" }}>

            <table>
                <thead>
                    <tr>
                        <th style={{ width: "200px" }}></th>
                        <th></th>
                    </tr>
                </thead>
                <tbody>
                    {poolInfo}
                </tbody>
            </table>
        </div>

    }

    let infoHeader = (<div style={{ display: "block", marginTop: "22px", fontSize: "16px" }}>
        <span className="infoSpan">{poolData?.name}</span>
        <span className="infoSpan">{poolData?.protocol ?? "Protocol"} - {networks?.[poolData?.currentChain?.toString()] ?? "Chain"}</span>
        <span className="infoSpan"><b>{poolData?.poolAssetSymbol}</b></span>
        {poolData?.strategyName ? <span className="infoSpan" style={{ cursor: "pointer" }} onClick={() => setViewStrategy(true)}><u>{poolData?.strategyName}</u></span> : null}
    </div>)

    if (poolData === null) {
        ele = <div style={{ margin: "30px" }}><div style={{ height: "50px", width: "50px" }} className="loader loaderBig"></div></div>
        infoHeader = null
    }

    if (address && poolData) {
        userEle = <UserPoolSection fetchPoolData={fetchPoolData} setErrorMessage={(x) => setErrorMessage(x)} user={windowOverride?.ethereum?.selectedAddress} poolData={poolData} provider={provider} txData={txData} setTxData={setTxData} />
    } else if (poolData && !address) {
        open()
    }

    let txPopup = null
    if (Object.keys(txData)?.length > 0) {
        txPopup = <TxPopup popupData={txData} clearPopupData={() => setTxData({})} />
    }

    let pivotPopup = null
    if (showPivotSuccess) {
        pivotPopup = (<div className="popup-container">
            <div className="popup">
                <div className="popup-title">Pivot Success</div>
                <div className="popup-message">
                    <span style={{ display: "block" }}>The pivot on this pool successfully moved funds to {poolData.protocol} {poolData.currentChain}. Deposits are now earning yield on this protocol. Interactions are now enabled once again.</span>
                </div>
                <button onClick={() => setShowPivotSuccess(false)} className="popup-ok-button">OK</button>
            </div>
        </div>)
    }

    let strategyPopup = null
    if (viewStrategy) {
        strategyPopup = <StrategyPopup provider={provider} getStrategyCount={() => null} setShowStrategyPopup={(x) => setViewStrategy(x)} strategyIndex={poolData?.strategyIndex?.toString()} strategyIndexOnPool={poolData?.strategyIndex?.toString()} setStrategyIndex={() => null} strategies={[]} />
    }

    return (<>
        {pivotPopup}
        {strategyPopup}
        <ErrorPopup errorMessage={errorMessage} clearErrorMessage={() => setErrorMessage("")} />
        {txPopup}
        <div style={{ overflow: "auto", color: "white", width: "100%", padding: "0", margin: 0 }}>
            <div style={{ padding: "30px 12px", backgroundColor: "#374d59", width: "100%" }}>
                <span style={{ display: "block", fontSize: "28px" }}>{poolId}</span>

                {infoHeader}

            </div>
            {ele}
            {userEle}
        </div >
    </>)
}

function formatString(inputString) {
    // Split the string at each capital letter

    const splitString = inputString.split(/(?=[A-Z])/);
    if (splitString.length === inputString.length) {
        return inputString
    }
    // Map through each element, capitalize the first letter, and join with a space
    const formattedString = splitString.map((element) => {
        return element.charAt(0).toUpperCase() + element.slice(1).toLowerCase();
    }).join(' ');

    return formattedString;
}

function calculateAPY(baseDepositValue, currentDepositValue, recordTimestamp) {

    //Need to fetch to BridgeLogic to match the current nonce recorded on pool (nonce of last completed AB=>BA depo/with)
    // Record the amount added+subtracted at the time of recording each nonce.
    // This determines how much yield was made between each nonce recorded 
    // Get the position value recorded on the bridge logic at the nonce, minus the deposit amount/plus the withdraw amount if the bridge nonce  
    if (!currentDepositValue) return 0
    const minsElapsed = (Date.now() / 1000 - Number(recordTimestamp)) / 60
    // Constants
    const minPerYear = 365 * 24 * 60;

    // Calculate profit made on the investment
    const profit = currentDepositValue - baseDepositValue;

    // Calculate profit per second
    const profitPerMin = profit / minsElapsed;

    // Extrapolate profit per second to APY
    // Note: Assuming compounding once per year for simplicity
    let apy = Math.pow((profitPerMin * minPerYear) / baseDepositValue + 1, 1) - 1;
    // Convert APY to a percentage
    apy = apy * 100;
    if (!apy || apy > 1 || apy < -0.1) {
        return 0
    }

    console.log(`APY (Annual Percentage Yield): ${apy.toFixed(12)}%`);

    // Return the APY and profit per second as an object for further use
    return apy;
}
