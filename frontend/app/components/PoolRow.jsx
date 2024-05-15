import React, { useState, useEffect } from 'react';
import Loader from './Loader.jsx'; // Assuming Loader component is available
import { ethers } from 'ethers';
import PoolABI from '../ABI/PoolABI.json'; // Adjust the path as needed
import PoolCalculationsABI from '../ABI/PoolCalculationsABI.json'; // Adjust the path as needed

import { useRouter, usePathname, useSearchParams } from 'next/navigation'
import { createPublicClient, getContract, http, formatEther } from 'viem';
import { sepolia, baseSepolia } from 'viem/chains';
import BridgeLogicABI from '../ABI/BridgeLogicABI.json'; // Adjust the path as needed
import protocolHashes from '../JSON/protocolHashes.json'
import networks from '../JSON/networks.json'
import contractAddresses from '../JSON/contractAddresses.json'


const PoolRow = ({ poolNumber, provider, registry, setErrorMessage }) => {
    const router = useRouter()
    const [poolData, setPoolData] = useState(null);
    const [loaded, setLoaded] = useState(false)

    useEffect(() => {
        // Fetch pool data here and update poolData state
        // setPoolData(fetchedData);
        const getPoolAddress = async () => {
            const address = await registry.poolCountToPool(poolNumber);
            return address
        }

        const getPoolData = async (address) => {
            const pool = new ethers.Contract(address || "0x0", PoolABI, provider);

            const metaData = await pool.poolMetaData()
            const currents = await pool.readPoolCurrentPositionData()
            const returnObj = { address, name: metaData["2"], currentChain: currents["4"], currentProtocol: protocolHashes[currents["1"]] }
            return returnObj
        }

        const getBridgedPoolData = async (address, chainId) => {
            if (chainId == '0') {
                return { tvl: 0 }
            }
            let chain = sepolia
            let chainName = 'sepolia'
            if (chainId.toString() === "84532") {
                chain = baseSepolia
                chainName = 'base'
            }
            const publicClient = createPublicClient({
                chain,
                transport: http()
            })

            const bridgeLogic = getContract({
                address: contractAddresses[chainName].bridgeLogicAddress,
                abi: BridgeLogicABI,
                // 1a. Insert a single client
                client: publicClient,
            })

            //Check aToken balance of integrator
            const tvl = await bridgeLogic.read.getPositionBalance([address]);
            return { tvl }
        }

        const execution = async () => {
            try {

                const address = await getPoolAddress()
                const poolDataReturn = await getPoolData(address)
                const bridgedPoolData = await getBridgedPoolData(address, poolDataReturn.currentChain)
                setPoolData({ ...poolDataReturn, ...bridgedPoolData })


            } catch (err) {
                setErrorMessage('Error Loading Pool: ' + err.message)
            }
            setLoaded(true)
        }
        if (poolNumber > 8) {

            execution()
        }
    }, []);

    if (!poolData && !loaded) {
        return (
            <tr style={{ height: '22px' }}>
                <td colSpan={4}><div className="small-loader"></div></td>
                <td></td>
                <td></td>
            </tr>
        );
    }
    if (!poolData && loaded) {
        return null;
    }

    return (
        <tr className="pool-row" style={{ height: '22px', cursor: "pointer" }} onClick={() => router.push('/pool/' + poolData.address)}>
            <td>{poolData?.name} - 0x...{poolData.address.slice(22, 42)}</td>
            <td>{(formatEther(poolData?.tvl?.toString())).slice(0, 10)}</td>
            <td>{networks[poolData?.currentChain?.toString()]} - {poolData?.currentProtocol}</td>
        </tr>
    );
};

export default PoolRow;
