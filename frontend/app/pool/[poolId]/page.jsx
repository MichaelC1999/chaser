'use client'

import { useEffect, useMemo, useState } from 'react'
import { usePathname } from 'next/navigation'
import { ethers } from 'ethers';
import PoolABI from '../../ABI/PoolABI.json'; // Adjust the path as needed
import PoolTokenABI from '../../ABI/PoolTokenABI.json'; // Adjust the path as needed
import PoolCalculationsABI from '../../ABI/PoolCalculationsABI.json'; // Adjust the path as needed

import BridgeLogicABI from '../../ABI/BridgeLogicABI.json'; // Adjust the path as needed
import { createPublicClient, getContract, http, formatEther, zeroAddress } from 'viem'
import protocolHashes from '../../JSON/protocolHashes.json'
import networks from '../../JSON/networks.json'
import { sepolia, baseSepolia } from 'viem/chains'
import UserPoolSection from '@/app/components/UserPoolSection';
import contractAddresses from '../../JSON/contractAddresses.json'
import ErrorPopup from '@/app/components/ErrorPopup.jsx';
import TxPopup from '@/app/components/TxPopup';
import DemoPopup from '@/app/components/DemoPopup';

export default function Page() {

    const [step, setStep] = useState(null);
    const [prevStep, setPrevStep] = useState(null)
    const [demoMode, setDemoMode] = useState(true);
    const [poolData, setPoolData] = useState(null);
    const [errorMessage, setErrorMessage] = useState("");
    const [txData, setTxData] = useState({})
    const [showPivotPopup, setShowPivotPopup] = useState(false)

    const pathname = usePathname()

    const poolId = pathname?.split('/')?.[2]

    const windowOverride = useMemo(() => (
        typeof window !== 'undefined' ? window : null
    ), []);

    const provider = useMemo(() => (
        windowOverride ? new ethers.BrowserProvider(windowOverride.ethereum) : null
    ), [windowOverride]);

    useEffect(() => {
        if (!ethers.isAddress(windowOverride?.ethereum?.selectedAddress)) {
            connect()
        }
    }, [])

    const connect = async () => {
        // If the user is not signed into metamask, execute this logic
        try {
            await provider.send("eth_requestAccounts", []);
            await provider.getSigner();
        } catch (err) {
            setErrorMessage("Connection Error: " + err?.info?.error?.message ?? err?.message);
        }
    }

    useEffect(() => {
        const getPoolData = async (address) => {
            const returnObject = {}
            const pool = new ethers.Contract(address || "0x0", PoolABI, provider);
            const poolCalc = new ethers.Contract(contractAddresses["base"].poolCalculationsAddress || "0x0", PoolCalculationsABI, provider);

            try {
                returnObject.poolTokenAddress = await pool.poolToken()
                if (returnObject.poolTokenAddress) {
                    const poolToken = new ethers.Contract(returnObject.poolTokenAddress || "0x0", PoolTokenABI, provider);
                }
            } catch (err) {

            }

            try {
                returnObject.poolAsset = await pool.asset()

                const poolAssetContract = new ethers.Contract(returnObject.poolAsset || "0x0", PoolTokenABI, provider);
                returnObject.poolAssetName = await poolAssetContract.name()
                returnObject.poolAssetSymbol = await poolAssetContract.symbol()
            } catch (err) {
                returnObject.poolAsset = zeroAddress
            }

            try {

                returnObject.recordPositionValue = formatEther(await pool.currentRecordPositionValue())
                returnObject.recordTimestamp = await pool.currentPositionValueTimestamp()
            } catch (err) {

            }

            try {

                returnObject.name = await pool.poolName()
                returnObject.nonce = await pool.poolNonce()
            } catch (err) {

            }

            try {

                returnObject.userRatio = await poolCalc.getScaledRatio(returnObject.poolTokenAddress, windowOverride?.ethereum?.selectedAddress)
                returnObject.currentChain = await pool.currentPositionChain()
                returnObject.protocol = await pool.currentPositionProtocolHash()
            } catch (err) {
                console.log(err)
            }
            try {
                returnObject.isPivoting = await pool.pivotPending()

            } catch (err) {
            }

            // Have json with mapping of protocol hashes to the protocol name, read slug/protocolname from this list. No need to be on chain
            return { address, name, user: { userRatio: returnObject.userRatio, address: windowOverride?.ethereum?.selectedAddress }, ...returnObject }
        }

        const getBridgePoolData = async (address, hash, chainId, data) => {
            if (!chainId) {
                return {}
            }
            let chain = baseSepolia
            let chainName = 'base'
            if (chainId.toString() === "11155111") {
                chain = sepolia
                chainName = 'sepolia'
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

                const tvl = await bridgeLogic.read.getPositionBalance([address]);
                const nonce = await bridgeLogic.read.bridgeNonce([address])

                let userDepositValue = 0
                if (Number(tvl.toString()) > 0) {
                    userDepositValue = formatEther(await bridgeLogic.read.getUserMaxWithdraw([tvl, data.user.userRatio, address, nonce]))
                }

                return { user: { ...data.user, userDepositValue }, TVL: formatEther(tvl) }
            } catch (err) {
                console.log(err)
                return {}
            }

        }

        const execution = async () => {
            const poolDataReturn = await getPoolData(poolId)
            try {
                const bridgedPoolData = await getBridgePoolData(poolId, poolDataReturn.protocol, poolDataReturn.currentChain, poolDataReturn)
                if (!poolDataReturn.isPivoting) {
                    poolDataReturn.currentApy = calculateAPY(poolDataReturn?.recordPositionValue, bridgedPoolData?.TVL, poolDataReturn?.recordTimestamp)
                }

                if (poolDataReturn?.isPivoting === false && poolData?.isPivoting === true) {
                    setShowPivotPopup(true)
                }
                setPoolData({ ...poolDataReturn, ...bridgedPoolData })

            } catch (err) {
                console.log(err)
                setErrorMessage("Error fetching pool data: " + (err?.info?.error?.message ?? "Try reloading"))
            }
        }
        execution()

        const interval = setInterval(execution, 300000); // 300000 ms = 5 minutes

        return () => clearInterval(interval); // Clean up the interval on component unmount

    }, [txData])


    useEffect(() => {

        // step logic
        let stepToSet = null
        if (!!step) {
            return
        }
        if (poolData?.nonce?.toString() === "0" && !poolData?.protocol && prevStep === null) {
            stepToSet = 0
        }
        if (poolData?.nonce?.toString() === "1" && protocolHashes[poolData?.protocol] === "compound" && !poolData?.isPivoting && !(prevStep > 0)) {
            stepToSet = 1
        }
        if (prevStep === 1) {
            stepToSet = 2;
        }
        if (prevStep === 2) {
            stepToSet = 3;
        }

        if (prevStep === 4) {
            stepToSet = 5;
        }

        if (poolData?.isPivoting === poolData?.nonce?.toString() === "1") {
            stepToSet = 6
        }
        if (!poolData?.isPivoting === poolData?.nonce?.toString() === "2" && poolData?.protocol === "aave") {
            stepToSet = 7
        }

        setStep(stepToSet)
    }, [poolData, txData, step])

    const changeStep = (newStep) => {
        setPrevStep(step)
        setStep(newStep)
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
                value = (poolData[x]).toFixed(2) + '%'
            } else {
                key = formatString(x)
            }
            if (x === 'protocol') {
                value = protocolHashes[poolData[x]]
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
        <span className="infoSpan">{protocolHashes?.[poolData?.protocol] ?? "Protocol"} - {networks?.[poolData?.currentChain?.toString()] ?? "Chain"}</span>
        <span className="infoSpan"><b>{poolData?.poolAssetSymbol}</b></span>
    </div>)

    if (poolData === null) {
        ele = <div style={{ width: "60%" }}><div style={{ marginTop: "22px" }} className="small-loader"></div></div>
        infoHeader = null
    }

    if (windowOverride?.ethereum?.selectedAddress && poolData) {
        userEle = <UserPoolSection demoMode={demoMode} step={step} setErrorMessage={(x) => setErrorMessage(x)} changeStep={changeStep} user={windowOverride?.ethereum?.selectedAddress} poolData={poolData} provider={provider} txData={txData} setTxData={setTxData} />
    }

    let txPopup = null
    if (Object.keys(txData)?.length > 0) {
        txPopup = <TxPopup popupData={txData} clearPopupData={() => setTxData({})} />
    }
    let demo = null
    let demoButton = <button style={{ backgroundColor: "lime", marginLeft: "8px" }} onClick={() => setDemoMode(true)} className={'demoButton'}><b>On</b></button>
    if (demoMode) {
        demo = <DemoPopup step={step} clearDemoStep={() => changeStep(null)} turnOffDemo={() => setDemoMode(false)} />
        demoButton = <button style={{ backgroundColor: "red", marginLeft: "16px" }} onClick={() => setDemoMode(false)} className={'demoButton'}><b>Off</b></button>
    }

    let pivotPopup = null
    if (showPivotPopup) {
        pivotPopup = (<div className="popup-container">
            <div className="popup">
                <div className="popup-title">Pivot Success</div>
                <div className="popup-message">
                    <span style={{ display: "block" }}>The pivot on this pool successfully moved funds to {protocolHashes[poolData.protocol]} {protocolHashes[poolData.currentChain]}. Deposits are now earning yield on this protocol. Interactions are now enabled once again.</span>
                </div>
                <button onClick={() => setShowPivotPopup(false)} className="popup-ok-button">OK</button>
            </div>
        </div>)
    }

    return (<>
        {demo}
        {pivotPopup}
        <ErrorPopup errorMessage={errorMessage} clearErrorMessage={() => setErrorMessage("")} />
        {txPopup}
        <div style={{ overflow: "auto", color: "white", width: "100%", padding: "0", margin: 0 }}>
            <div style={{ padding: "30px 12px", backgroundColor: "#374d59", width: "100%" }}>
                <span style={{ display: "block", fontSize: "28px" }}>{poolId}</span>

                {infoHeader}
                <div style={{ marginTop: "20px", width: "100%", display: "flex", justifyContent: "flex-start", alignItems: "center", paddingLeft: "8px" }}>
                    {poolData ?
                        (<>
                            <p>Demo Mode is <span style={demoMode ? { color: "lime" } : { color: "red" }}>{demoMode ? 'ON' : 'OFF'}</span></p>
                            {demoButton}
                        </>) :
                        null}
                </div>
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

    const timeElapsed = Date.now() / 1000 - Number(recordTimestamp)
    // Constants
    const secondsInYear = 365 * 24 * 60 * 60;

    // Calculate profit made on the investment
    const profit = currentDepositValue - baseDepositValue;

    // Calculate profit per second
    const profitPerSecond = profit / timeElapsed;

    // Extrapolate profit per second to APY
    // Note: Assuming compounding once per year for simplicity
    let apy = Math.pow((profitPerSecond * secondsInYear) / baseDepositValue + 1, 1) - 1;

    // Convert APY to a percentage
    apy = apy * 100;
    if (!apy) {
        return 0
    }

    console.log(`APY (Annual Percentage Yield): ${apy.toFixed(2)}%`);

    // Return the APY and profit per second as an object for further use
    return apy;
}
