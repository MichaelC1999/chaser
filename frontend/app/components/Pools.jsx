'use client';

import { useEffect, useMemo, useState } from "react";
import ErrorPopup from "./ErrorPopup.jsx";
import { ethers } from 'ethers';
import RegistryABI from '../ABI/RegistryABI.json'; // Adjust the path as needed
import NewPoolInputs from "./NewPoolInputs.jsx";
import EnabledPools from "./EnabledPools.jsx";
import TxPopup from "./TxPopup.jsx";
import contractAddresses from '../JSON/contractAddresses.json'


export default function Pools({ setErrorMessage, isCreatePool, setIsCreatePool }) {
    // const router = useRouter()
    const [newPool, toggleNewPool] = useState(false)

    const [poolCount, setPoolCount] = useState(null);
    const [txPopupData, setTxPopupData] = useState({})


    const windowOverride = useMemo(() => (
        typeof window !== 'undefined' ? window : null
    ), []);

    const provider = useMemo(() => (
        windowOverride ? new ethers.BrowserProvider(windowOverride.ethereum) : null
    ), [windowOverride]);

    const registry = useMemo(() => (
        provider ? new ethers.Contract(contractAddresses["sepolia"].registryAddress || "0x0", RegistryABI, provider) : null
    ), [provider]);

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
        const fetchPoolCount = async () => {
            if (!registry) {
                return;
            }
            const count = await registry.poolCount();
            setPoolCount(Number(count));
        };

        fetchPoolCount();
    }, []);


    let inputs = null;


    if (isCreatePool) {
        inputs = <NewPoolInputs provider={provider} setTxPopupData={setTxPopupData} setErrorMessage={(x) => setErrorMessage(x)} />
    } else {
        inputs = (<>
            <EnabledPools poolCount={poolCount} provider={provider} registry={registry} setErrorMessage={(x) => setErrorMessage(x)} />
        </>)
    }

    let txPopup = null
    if (Object.keys(txPopupData)?.length > 0) {
        txPopup = <TxPopup popupData={txPopupData} clearPopupData={() => setTxPopupData({})} />
    }

    return (<>
        <button onClick={() => setIsCreatePool(!isCreatePool)} className="button">{isCreatePool ? "View Pool List" : "Create New Pool"}</button>
        {inputs}
        {txPopup}
    </>
    );
}