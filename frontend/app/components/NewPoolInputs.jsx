import React, { useEffect, useMemo, useState } from 'react';
import SubmitButton from './SubmitButton.jsx';
import ManagerABI from '../ABI/ManagerABI.json'; // Adjust the path as needed
import InvestmentStrategyABI from '../ABI/InvestmentStrategyABI.json'; // Adjust the path as needed
import { ethers } from 'ethers';
import networks from '../JSON/networks.json'
import contractAddresses from '../JSON/contractAddresses.json'
import LoadingPopup from './LoadingPopup.jsx';
import StrategyPopup from './StrategyPopup.jsx'
import StrategyFetch from './StrategyFetch.jsx'
import { useRouter } from 'next/navigation';
import { useWeb3Modal, useWeb3ModalAccount } from '@web3modal/ethers/react';

const NewPoolInputs = ({ provider, setTxPopupData, setErrorMessage }) => {
    const router = useRouter()
    const { open } = useWeb3Modal()
    const { isConnected } = useWeb3ModalAccount()

    const instructionBoxDefault = 'Hover over an input for more instruction...'
    const [poolName, setPoolName] = useState('');
    const [assetAddress, setAssetAddress] = useState('0x980B62Da83eFf3D4576C647993b0c1D7faf17c73');
    const [strategyIndex, setStrategyIndex] = useState('0');
    const [instructionBox, setInstructionBox] = useState(instructionBoxDefault)
    const [submitting, setSubmitting] = useState(false)
    const [showStrategyPopup, setShowStrategyPopup] = useState(false)
    const [strategyCount, setStrategyCount] = useState(0)
    const [strategyNames, setStrategyNames] = useState({})


    useEffect(() => {
        getStrategyCount()
    }, [])

    const getStrategyCount = async () => {
        const investmentStrategyContract = new ethers.Contract(contractAddresses.arbitrum["investmentStrategy"], InvestmentStrategyABI, provider);
        const count = Number(await investmentStrategyContract.strategyCount() || 0)
        console.log(count)
        setStrategyCount(count)
    }

    const submitLogic = async () => {
        let signer = null;
        try {
            await provider.send("eth_requestAccounts", []);
            signer = await provider.getSigner();
        } catch (err) {
            console.log("Connection Error: " + err?.info?.error?.message ?? err?.message);
            setErrorMessage("Connection Error: " + err?.info?.error?.message)
            setSubmitting(false)
            return
        }
        const manager = new ethers.Contract(contractAddresses["arbitrum"].managerAddress || "0x0", ManagerABI, signer)
        //Maybe here a loading spinner popup? Then once Tx success or fail then do tx popup?
        try {
            const poolTx = await (await manager.createNewPool(
                assetAddress,
                strategyIndex,
                poolName,
                {
                    gasLimit: 7000000
                }
            )).wait();
            const poolAddress = '0x' + poolTx.logs[0].topics[1].slice(-40);
            const hash = poolTx.hash
            router.push(("/pool/" + poolAddress))
        } catch (err) {
            console.log('test! ', err)
            setErrorMessage(err?.info?.error?.message)
        }
        setSubmitting(false)
    }

    useEffect(() => {
        if (submitting) {
            if (isConnected) {

                submitLogic()
            } else {
                open({})
            }
        }
    }, [submitting, isConnected])

    let submittingLoader = null;
    if (submitting && isConnected) {
        submittingLoader = <LoadingPopup loadingMessage={"Please wait for your transactions to fill"} />
    }
    let strategyExecution = null
    if (strategyCount > 0) {
        strategyExecution = Array.from({ length: strategyCount }, (_, index) => {
            return <StrategyFetch key={"strat" + index} provider={provider} stratNumber={index} setStrategyNames={setStrategyNames} />
        })
    }
    return (<div style={{ display: "flex" }}>
        {submittingLoader}
        {strategyExecution}
        <div key={'top-new-pool-inputs'} className="new-pool-inputs" style={{ flex: 5 }}>
            <label key={1} onMouseEnter={() => setInstructionBox("Give your pool a name to make it more identifiable")} onMouseLeave={() => setInstructionBox(instructionBoxDefault)}>
                Pool Name:
                <input type="text" value={poolName} onChange={(e) => setPoolName(e.target.value)} />
            </label>
            <label key={2} onMouseEnter={() => setInstructionBox("Add the asset address that will be used for deposits and investments.\nThis address should be on Arbitrum Sepolia. Chaser uses Across to bridge to the equivalent of this asset on other networks.\nFor the time being, the only asset allowed is WETH.")} onMouseLeave={() => setInstructionBox(instructionBoxDefault)}>
                Asset Address:
                <input type="text" value={assetAddress} onChange={() => null} />
            </label>
            <label key={3} onMouseEnter={() => setInstructionBox("Select a strategy for your pool to determine where and how to move funds in order to make the best ROI while following custom risk parameters. Each strategy contains code that helps the UMA OO determine where to move deposits.")} onMouseLeave={() => setInstructionBox(instructionBoxDefault)}>
                Strategy: {strategyNames[strategyIndex] ?? ""}

                <div className="button" style={{ textAlign: "center", border: "white 1px solid" }} onClick={() => setShowStrategyPopup(true)}>Strategy Selection</div>
                {showStrategyPopup ? <StrategyPopup getStrategyCount={getStrategyCount} setErrorMessage={(x) => setErrorMessage(x)} provider={provider} strategyIndexOnPool={null} strategyIndex={strategyIndex} setStrategyIndex={setStrategyIndex} strategies={Object.values(strategyNames)} setShowStrategyPopup={(x) => setShowStrategyPopup(x)} /> : null}

            </label>
            <label key={4} onMouseEnter={() => setInstructionBox("Network selection will allow the deploying user to select what chains they want enabled for deposits.\nCurrently the pool does not take in this input, but will be supported at a later date.")} onMouseLeave={() => setInstructionBox(instructionBoxDefault)}>
                Networks Enabled:
                <select onChange={() => null} multiple >
                    {Object.keys(networks).map(network => (
                        <option key={networks[network]} value={networks[network]}>{networks[network]}</option>
                    ))}
                </select>
            </label>
            <div onMouseEnter={() => setInstructionBox("Click submit to deploy the pool.\nAfter deployment, you can specify the first position to invest into and make the initial deposit.")} onMouseLeave={() => setInstructionBox(instructionBoxDefault)}>
                <SubmitButton submitMethod={() => setSubmitting(true)} />
            </div>
        </div>
        <div key={'bottom-new-pool-inputs'} className="new-pool-inputs" style={{ border: "white 1px solid", flex: 2, margin: "43px 20px 32px 20px", padding: "20px" }}>
            {instructionBox.split("\n").map((x, idx) => {
                return <div key={"div" + idx}><span key={idx} style={{ display: "inline-block", lineHeight: "25px", paddingBottom: "10px" }}>{x}</span></div>
            })}
        </div>
    </div>
    );
};

export default NewPoolInputs;
