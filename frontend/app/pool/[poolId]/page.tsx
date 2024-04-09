'use client'

import { useEffect, useMemo, useState } from 'react'
import { useRouter, usePathname, useSearchParams } from 'next/navigation'
import { Networkish, ethers } from 'ethers';
import PoolABI from '../../ABI/PoolABI.json'; // Adjust the path as needed
import PoolTokenABI from '../../ABI/PoolTokenABI.json'; // Adjust the path as needed
import PoolCalculationsABI from '../../ABI/PoolCalculationsABI.json'; // Adjust the path as needed
import IntegratorABI from '../../ABI/IntegratorABI.json'; // Adjust the path as needed

import BridgeLogicABI from '../../ABI/BridgeLogicABI.json'; // Adjust the path as needed
import { createPublicClient, getContract, http, formatEther, zeroAddress } from 'viem'
import protocolHashes from '../../JSON/protocolHashes.json'
import networks from '../../JSON/networks.json'
import { sepolia } from 'viem/chains'
import Loader from '@/app/components/Loader';
import UserPoolSection from '@/app/components/UserPoolSection';

export default function Page() {
    const [step, setStep] = useState<Number>(1);
    const [poolData, setPoolData] = useState<any>(null);

    const pathname = usePathname()

    const poolId = pathname?.split('/')?.[2]

    const windowOverride: any = useMemo(() => (
        typeof window !== 'undefined' ? window : null
    ), []);

    const provider = useMemo(() => (
        windowOverride ? new ethers.BrowserProvider(windowOverride.ethereum) : null
    ), [windowOverride]);

    useEffect(() => {

        const getPoolData = async (address: any) => {

            console.log(windowOverride?.ethereum?.selectedAddress)
            const returnObject: any = {}
            const pool = new ethers.Contract(address || "0x0", PoolABI, provider);
            const poolCalc = new ethers.Contract(process.env.NEXT_PUBLIC_BASE_POOLCALCULATIONSADDRESS || "0x0", PoolCalculationsABI, provider);

            try {

                returnObject.poolTokenAddress = await pool.poolToken()
                if (returnObject.poolTokenAddress) {
                    const poolToken = new ethers.Contract(returnObject.poolTokenAddress || "0x0", PoolTokenABI, provider);
                    console.log(await poolToken.totalSupply(), await poolToken.balanceOf(windowOverride?.ethereum?.selectedAddress))
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
            } catch (err) {

            }

            returnObject.recordTimestamp = 1712238538 //change

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

            }
            try {
                returnObject.isPivoting = await pool.pivotPending()

            } catch (err) {

            }

            // Have json with mapping of protocol hashes to the protocol name, read slug/protocolname from this list. No need to be on chain
            return { address, name, user: { userRatio: returnObject.userRatio, address: windowOverride?.ethereum?.selectedAddress }, ...returnObject }
        }

        const getBridgePoolData = async (address: any, hash: any, chainId: Number, data: any) => {
            if (!chainId) {
                return {}
            }
            const chain: any = chainId
            const rpcURI = sepolia.rpcUrls.default.http[0]
            // const bridgeProvider = new ethers.BrowserProvider(windowOverride.ethereum, chain)
            const publicClient = createPublicClient({
                chain: sepolia,
                transport: http()
            })

            const bridgeLogic = getContract({
                address: process.env.NEXT_PUBLIC_SEPOLIA_BRIDGELOGICADDRESS,
                abi: BridgeLogicABI,
                // 1a. Insert a single client
                client: publicClient,
            })

            const integratorContract = getContract({
                address: process.env.NEXT_PUBLIC_SEPOLIA_INTEGRATORADDRESS,
                abi: IntegratorABI,
                // 1a. Insert a single client
                client: publicClient,
            })


            //Check aToken balance of ntegrator
            const curPos = await integratorContract.read.getCurrentPosition([
                address,
                "0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357",
                "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951",
                hash
            ]);
            const userDepositValue = formatEther(await bridgeLogic.read.getUserMaxWithdraw([curPos, data.user.userRatio, address, data.nonce]))

            console.log('USER MAX WITHDRAW: ', userDepositValue, 'TVL: ', data.TVL, 'Current Position: ', curPos)
            return { user: { ...data.user, userDepositValue }, TVL: formatEther(curPos) }
        }

        const execution = async () => {
            const poolDataReturn = await getPoolData(poolId)
            const bridgedPoolData = await getBridgePoolData(poolId, poolDataReturn.protocol, poolDataReturn.currentChain, poolDataReturn)
            poolDataReturn.currentApy = calculateAPY(poolDataReturn?.recordPositionValue, bridgedPoolData?.TVL, poolDataReturn?.recordTimestamp)

            setPoolData({ ...poolDataReturn, ...bridgedPoolData })
        }
        execution()
    }, [])



    // step 1 has all of the pool data displayed
    // regardless of connected address position, button for action
    // -Uses step 2, which is Deposit component
    // -Pass in prop for poolNonce, if nonce = 0, userDepositAndSetPosition, if nonce > 0 regular userDeposit
    // If connected address has a balance in the pool, button for withdraw
    // -Uses step 3, which is Withdraw component
    // Once tx hash goes through, bring up SequenceExecution component
    // -uses step 4
    // -Depending on the operation, this decodes tx and event data and uses Etherscan API calls to check if across/CCIP has gone through
    //Once tx hash goes through, button for manualExecution component
    // -step 5
    // -Decodes event data and puts it in an input for user to sign off on
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
            if (x === "address" || x === "name" || x === "currentChain" || x === "protocol" || x === "TVL" || x === "nonce" || x === "poolAsset" || x === "poolAssetName" || x === "poolAssetSymbol" || x === "currentApy") {
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
        userEle = <UserPoolSection user={windowOverride?.ethereum?.selectedAddress} poolData={poolData} provider={provider} />
    }

    return <div style={{ overflow: "auto", color: "white", width: "100%", padding: "0" }}>
        <div style={{ padding: "60px 12px", backgroundColor: "#374d59", width: "100%" }}>
            <span style={{ display: "block", fontSize: "28px" }}>{poolId}</span>
            {infoHeader}

        </div>
        {ele}
        {userEle}
    </div>

}

function formatString(inputString: any) {
    // Split the string at each capital letter

    const splitString = inputString.split(/(?=[A-Z])/);
    if (splitString.length === inputString.length) {
        return inputString
    }
    // Map through each element, capitalize the first letter, and join with a space
    const formattedString = splitString.map((element: any) => {
        return element.charAt(0).toUpperCase() + element.slice(1).toLowerCase();
    }).join(' ');

    return formattedString;
}

function calculateAPY(baseDepositValue: any, currentDepositValue: any, recordTimestamp: any) {
    const timeElapsed = Date.now() / 1000 - recordTimestamp
    // Constants
    const secondsInYear = 365 * 24 * 60 * 60;

    // Calculate profit made on the investment
    const profit = currentDepositValue - baseDepositValue;
    console.log(baseDepositValue, currentDepositValue, timeElapsed, profit)

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
