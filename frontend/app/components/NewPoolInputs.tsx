import React, { useMemo, useState } from 'react';
import SubmitButton from './SubmitButton';
import ManagerABI from '../ABI/ManagerABI.json'; // Adjust the path as needed
import { ethers } from 'ethers';
import networks from '../JSON/networks.json'

const NewPoolInputs = ({ provider, setTxPopupData }: any) => {
    const [poolName, setPoolName] = useState('');
    const [assetAddress, setAssetAddress] = useState('0x4200000000000000000000000000000000000006');
    const [strategyAddress, setStrategyAddress] = useState('0x0');
    const [description, setDescription] = useState('');
    const [supportedNetworks, setSupportedNetworks] = useState<string[]>([]);

    const submitLogic = async () => {
        let signer: any = null;
        try {
            await provider.send("eth_requestAccounts", []);
            signer = await provider.getSigner();
        } catch (err: any) {
            console.log("Connection Error: " + err?.info?.error?.message ?? err?.message);
        }
        const manager: any = new ethers.Contract(process.env.NEXT_PUBLIC_MANAGER_ADDRESS || "0x0", ManagerABI, signer)

        const poolTx = await (await manager.createNewPool(
            assetAddress,
            strategyAddress,
            poolName,
            {
                gasLimit: 7000000
            }
        )).wait();
        const poolAddress = '0x' + poolTx.logs[0].topics[1].slice(-40);
        const hash = poolTx.hash

        setTxPopupData({ hash, poolAddress, URI: ("/pool/" + poolAddress), message: "New Pool created at " + poolAddress + ". Now you need to set the initial position market with a deposit. Click here to go the pool page." })
    }

    const setNetworkSelection = (event: any) => {
        const selectedNetworks = Array.from(event.target.selectedOptions, option => option.value);
        setSupportedNetworks(selectedNetworks);
    };

    return (
        <div className="new-pool-inputs">
            <label>Pool Name:
                <input type="text" value={poolName} onChange={(e) => setPoolName(e.target.value)} />
            </label>
            <label>Asset Address:
                <input type="text" value={assetAddress} />
            </label>
            <label>Strategy Address:
                <input type="text" value={strategyAddress} />
            </label>
            <label>Description:
                <textarea value={description} onChange={(e) => setDescription(e.target.value)} />
            </label>
            <label>Networks:
                <select multiple value={supportedNetworks} onChange={setNetworkSelection}>
                    {Object.keys(networks).map(network => (
                        <option key={networks[network]} value={networks[network]}>{networks[network]}</option>
                    ))}
                </select>
            </label>
            <SubmitButton submitMethod={submitLogic} />
        </div>
    );
};

export default NewPoolInputs;
