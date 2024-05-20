"use client"

import React, { useEffect, useMemo, useState } from "react";
import { NetworkSwitcher } from "../components/NetworkSwitcher";
import { ethers } from "ethers";
import ConnectButton from "../components/ConnectButton";
import ErrorPopup from "../components/ErrorPopup.jsx";
import Pools from "../components/Pools";
import contractAddresses from '../JSON/contractAddresses.json'
import RegistryABI from '../ABI/RegistryABI.json'; // Adjust the path as needed

const PoolPage = () => {
    //This page is for handling pool selection/deployment
    const windowOverride = typeof window !== 'undefined' ? window : null;
    const [errorMessage, setErrorMessage] = useState("");
    const [isCreatePool, setIsCreatePool] = useState(false)

    const provider = useMemo(() => (
        windowOverride ? new ethers.BrowserProvider(windowOverride.ethereum) : null
    ), [windowOverride]);

    const registry = useMemo(() => (
        provider ? new ethers.Contract(contractAddresses["sepolia"].registryAddress || "0x0", RegistryABI, provider) : null
    ), [provider]);

    return (<>
        <ErrorPopup errorMessage={errorMessage} clearErrorMessage={() => {
            setErrorMessage("")
        }} />
        <div className="MainPage">
            <div className="component-container">
                <span style={{ fontSize: "32px" }}>{isCreatePool ? "POOL CREATION" : "POOL SELECTION"}</span>
                <span style={{ fontSize: "18px" }}>{isCreatePool ? "Deploy a new Chaser pool. Select a strategy for you pool to follow or code your own strategy." : "To demo Chaser, you need to select a pool. You can either choose a pool from the list, or deploy a new pool"}</span>
            </div>
            <div className="component-container">
                <Pools setErrorMessage={(x) => setErrorMessage(x)} isCreatePool={isCreatePool} setIsCreatePool={setIsCreatePool} />
            </div>
        </div>
    </>
    );
};


export default PoolPage;
