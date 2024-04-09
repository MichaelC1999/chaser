'use client';

import { useEffect, useMemo, useState } from "react";
import ErrorPopup from "./ErrorPopup";
import { ethers } from 'ethers';
import RegistryABI from '../ABI/RegistryABI.json'; // Adjust the path as needed
import ManagerABI from '../ABI/ManagerABI.json'; // Adjust the path as needed
import Loader from "./Loader";
import NewPoolInputs from "./NewPoolInputs";
import EnabledPools from "./EnabledPools";
import TxPopup from "./TxPopup";


export default function Pools() {
    // const router = useRouter()
    const [errorMessage, setErrorMessage] = useState("")
    const [newPool, toggleNewPool] = useState(false)

    const [poolCount, setPoolCount] = useState(null);
    const [txPopupData, setTxPopupData] = useState({})


    const windowOverride: any = useMemo(() => (
        typeof window !== 'undefined' ? window : null
    ), []);

    const provider = useMemo(() => (
        windowOverride ? new ethers.BrowserProvider(windowOverride.ethereum) : null
    ), [windowOverride]);

    const registry: any = useMemo(() => (
        provider ? new ethers.Contract(process.env.NEXT_PUBLIC_REGISTRY_ADDRESS || "0x0", RegistryABI, provider) : null
    ), [provider]);


    useEffect(() => {
        const fetchPoolCount = async () => {
            if (!registry) {
                return;
            }
            const count = await registry.poolCount();
            setPoolCount(count);
        };

        fetchPoolCount();
    }, []);


    let inputs = null;


    if (newPool) {
        inputs = <NewPoolInputs provider={provider} setTxPopupData={setTxPopupData} />


    } else {
        inputs = (<>
            <EnabledPools poolCount={Number(poolCount)} provider={provider} registry={registry} />
        </>)

    }

    let txPopup = null
    if (Object.keys(txPopupData)?.length > 0) {
        txPopup = <TxPopup popupData={txPopupData} clearPopupData={() => setTxPopupData({})} />
    }

    return (<>
        <button onClick={() => toggleNewPool(!newPool)} className="button">{newPool ? "View Pool List" : "Create New Pool"}</button>
        {inputs}
        {txPopup}

    </>
    );
}