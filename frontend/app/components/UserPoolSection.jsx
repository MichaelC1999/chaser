import React, { useState, useEffect } from 'react';
import Deposit from './Deposit.jsx';
import Withdraw from './Withdraw.jsx';
import PivotMechanism from './PivotMechanism.jsx';


const UserPoolSection = ({ user, changeStep, poolData, provider, setErrorMessage, txData, setTxData, demoMode, step }) => {
    const userData = poolData?.user

    let userPositionInfo = null
    let pivotMechanism = null

    if (userData) {

        let stakePct = Number(userData?.userRatio?.toString()) / (10 ** 16)
        if (!userData?.userRatio) {
            stakePct = "0.00"
        }
        userPositionInfo = (
            <div style={{ margin: "14px 0" }}>
                <span className="infoSpan" style={{ border: "white 1px solid", fontSize: "20px" }}>Value ({poolData?.poolAssetSymbol}) - {userData?.userDepositValue ?? 0}</span>
                <span className="infoSpan" style={{ border: "white 1px solid", fontSize: "20px" }}>Your Stake - {stakePct}%</span>
                {poolData?.isPivoting ? null : <span className="infoSpan" style={poolData?.currentApy < 0 ? { color: "red", border: "white 1px solid", fontSize: "20px" } : { color: "white", border: "white 1px solid", fontSize: "20px" }}>Earning APY - {poolData?.currentApy?.toFixed(2)}%</span>}
            </div>
        )
    }

    let withdraw = null
    if (!!userData.userRatio) {
        withdraw = <Withdraw demoMode={demoMode} poolAddress={poolData?.address} poolData={poolData} provider={provider} setErrorMessage={(x) => setErrorMessage(x)} txData={txData} setTxData={setTxData} />
        pivotMechanism = <PivotMechanism demoMode={demoMode} changeStep={changeStep} step={step} poolData={poolData} provider={provider} setErrorMessage={(x) => setErrorMessage(x)} txData={txData} setTxData={setTxData} />
    }
    return (
        <div style={{ width: "100%", backgroundColor: "#374d59", padding: "50px 30px", display: "flex" }}>
            <div style={{ flex: 5 }}>

                <span className="infoSpan" style={{ color: "#1f2c33", backgroundColor: "white", fontSize: "26px" }}><b>{user}</b></span>
                {userPositionInfo}
                <div style={{ display: "flex" }}>
                    <Deposit poolAddress={poolData?.address} demoMode={demoMode} changeStep={changeStep} poolData={poolData} provider={provider} setErrorMessage={(x) => setErrorMessage(x)} txData={txData} setTxData={setTxData} />
                    {withdraw}
                    {pivotMechanism}
                </div>
            </div>
        </div>

    );
};

export default UserPoolSection;


