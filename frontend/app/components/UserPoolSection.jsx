import React, { useState, useEffect } from 'react';
import Deposit from './Deposit.jsx';
import Withdraw from './Withdraw.jsx';
import PivotMechanism from './PivotMechanism.jsx';


const UserPoolSection = ({ fetchPoolData, user, poolData, provider, setErrorMessage, txData, setTxData }) => {
    const userData = poolData?.user

    let userPositionInfo = null
    let pivotMechanism = null

    if (userData) {

        let stakePct = Number(userData?.userRatio?.toString()) / (10 ** 16)
        if (!userData?.userRatio) {
            stakePct = "0.00"
        }
        let fundsText = "No Deposits From User"
        if (userData?.userDepositValue > 0) {
            fundsText = "Position: " + userData?.userDepositValue + " " + poolData?.poolAssetSymbol
        }

        userPositionInfo = (
            <div style={{ margin: "14px 0" }}>
                <span className="infoSpan" style={{ border: "white 1px solid", fontSize: "20px" }}>{fundsText}</span>
                <span className="infoSpan" style={{ border: "white 1px solid", fontSize: "20px" }}>Your Stake: {stakePct}%</span>
                {poolData?.isPivoting ? null : <span className="infoSpan" style={poolData?.currentApy < 0 ? { color: "red", border: "white 1px solid", fontSize: "20px" } : { color: "white", border: "white 1px solid", fontSize: "20px" }}>APY: {poolData?.currentApy?.toFixed(2)}%</span>}
            </div>
        )
    }

    let withdraw = null
    if (!!userData.userRatio) {
        console.log(poolData)
        withdraw = <Withdraw fetchPoolData={fetchPoolData} poolAddress={poolData?.address} poolData={poolData} provider={provider} setErrorMessage={(x) => setErrorMessage(x)} txData={txData} setTxData={setTxData} />
        pivotMechanism = <PivotMechanism fetchPoolData={fetchPoolData} poolData={poolData} provider={provider} setErrorMessage={(x) => setErrorMessage(x)} txData={txData} setTxData={setTxData} />
    }
    return (
        <div style={{ width: "100%", backgroundColor: "#374d59", padding: "50px 30px", display: "flex" }}>
            <div style={{ flex: 5 }}>

                <span className="infoSpan" style={{ color: "#1f2c33", backgroundColor: "white", fontSize: "26px" }}><b>{user}</b></span>
                {userPositionInfo}
                <div style={{ display: "flex" }}>
                    <Deposit fetchPoolData={fetchPoolData} poolAddress={poolData?.address} poolData={poolData} provider={provider} setErrorMessage={(x) => setErrorMessage(x)} txData={txData} setTxData={setTxData} />
                    {withdraw}
                    {pivotMechanism}
                </div>
            </div>
        </div>

    );
};

export default UserPoolSection;


