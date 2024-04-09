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
import Deposit from './Deposit';
import Withdraw from './Withdraw';

const UserPoolSection = ({ user, poolData, provider }: any) => {
    const router = useRouter()
    const userData = poolData?.user
    useEffect(() => {


    }, []);

    let userPositionInfo = null

    if (userData) {

        let stakePct: any = Number(userData?.userRatio?.toString()) / (10 ** 16)
        if (!userData?.userRatio) {
            stakePct = "0.00"
        }
        userPositionInfo = (
            <div style={{ margin: "26px 0" }}>

                <span className="infoSpan" style={{ border: "white 1px solid", fontSize: "20px" }}>Value ({poolData?.poolAssetSymbol}) - {userData?.userDepositValue ?? 0}</span>
                <span className="infoSpan" style={{ border: "white 1px solid", fontSize: "20px" }}>Stake - {stakePct}%</span>
                <span className="infoSpan" style={poolData?.currentApy < 0 ? { color: "red", border: "white 1px solid", fontSize: "20px" } : { color: "white", border: "white 1px solid", fontSize: "20px" }}>Earning APY - {poolData?.currentApy?.toFixed(2)}%</span>

            </div>
        )
    }

    let withdraw = null
    if (!!userData.userRatio) {
        withdraw = <Withdraw poolAddress={poolData?.address} poolData={poolData} provider={provider} />
    }
    return (
        <div style={{ width: "100%", backgroundColor: "#374d59", padding: "50px 30px" }}>
            <span className="infoSpan" style={{ color: "#1f2c33", backgroundColor: "white", marginBottom: "300px", fontSize: "26px" }}><b>{user}</b></span>
            {userPositionInfo}
            <div style={{ display: "flex" }}>
                <Deposit poolAddress={poolData?.address} poolData={poolData} provider={provider} />
                {withdraw}
            </div>
        </div>

    );
};

export default UserPoolSection;


