import React, { useState, useEffect } from 'react';
import Loader from './Loader'; // Assuming Loader component is available
import { ethers } from 'ethers';
import PoolABI from '../ABI/PoolABI.json'; // Adjust the path as needed
import { useRouter, usePathname, useSearchParams } from 'next/navigation'
import { createPublicClient, getContract, http, formatEther } from 'viem';
import { sepolia } from 'viem/chains';
import IntegratorABI from '../ABI/IntegratorABI.json'; // Adjust the path as needed
import protocolHashes from '../JSON/protocolHashes.json'
import networks from '../JSON/networks.json'

const PoolRow = ({ poolNumber, provider, registry }: any) => {
    const router = useRouter()
    const [poolData, setPoolData] = useState<any>(null);

    useEffect(() => {
        // Fetch pool data here and update poolData state
        // setPoolData(fetchedData);
        const getPoolAddress = async () => {
            const address = await registry.poolCountToPool(poolNumber);
            return address
        }

        const getPoolData = async (address: any) => {
            const pool = new ethers.Contract(address || "0x0", PoolABI, provider);

            const name = await pool.poolName()
            const currentChain = await pool.currentPositionChain()
            const currentProtocolHash = await pool.currentPositionProtocolHash()
            return { address, name, currentChain, currentProtocolHash }
        }

        const getBridgedPoolData = async (address: any, hash: any) => {
            const publicClient = createPublicClient({
                chain: sepolia,
                transport: http()
            })
            const integratorContract = getContract({
                address: process.env.NEXT_PUBLIC_SEPOLIA_INTEGRATORADDRESS,
                abi: IntegratorABI,
                // 1a. Insert a single client
                client: publicClient,
            })


            //Check aToken balance of ntegrator
            const tvl = await integratorContract.read.getCurrentPosition([
                address,
                "0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357",
                "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951",
                hash
            ]);

            // console.log(await integratorContract.read.hasher(["aave"]), await integratorContract.read.hasher(["compound"]), await integratorContract.read.hasher(["spark"]))

            return { tvl }
        }

        const execution = async () => {
            const address = await getPoolAddress()
            const poolDataReturn = await getPoolData(address)

            const bridgedPoolData = await getBridgedPoolData(address, poolDataReturn.currentProtocolHash)
            setPoolData({ ...poolDataReturn, ...bridgedPoolData })
        }
        execution()

    }, []);

    if (!poolData) {
        return (
            <tr style={{ height: '22px' }}>
                <td colSpan={4}><div className="small-loader"></div></td>
                <td></td>
                <td></td>
            </tr>
        );
    }

    return (
        <tr className="pool-row" style={{ height: '22px', cursor: "pointer" }} onClick={() => router.push('/pool/' + poolData.address)}>
            <td>{poolData.name} - 0x...{poolData.address.slice(22, 42)}</td>
            <td>{(formatEther(poolData.tvl.toString())).slice(0, 10)}</td>
            <td>{networks[poolData.currentChain.toString()]} - {protocolHashes[poolData.currentProtocolHash]}</td>
        </tr>
    );
};

export default PoolRow;
