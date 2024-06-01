import React, { useEffect, useState } from 'react';
import { fromHex } from 'viem'
import networks from "../JSON/networks.json"


export function NetworkSwitcher() {
    const windowOverride = typeof window !== 'undefined' ? window : null;
    const [isEthereumAvailable, setIsEthereumAvailable] = useState(false);
    const [chainId, setChainId] = useState("")
    useEffect(() => {
        if (typeof window !== 'undefined' && 'ethereum' in window) {
            setIsEthereumAvailable(true);
            getChainId()
        }
    }, [])

    const getChainId = async () => {
        setChainId(await windowOverride.ethereum.request({ method: 'eth_chainId' }))
    }

    const newChain = chainId

    const switchNetwork = async () => {
        try {
            await windowOverride?.ethereum?.request({
                method: 'wallet_switchEthereumChain',
                params: [{ chainId: '0x66eee' }],
            });
        } catch (switchError) {
            console.log(switchError.message);
        }
    }

    if (isEthereumAvailable) {
        if (chainId == "0x66eee" || fromHex(newChain, 'number') == 0) {
            return null;
        }
    } else {
        // If injected provider is not in use, do not render this modal by default
        return null;
    }
    return (
        <div className="popup-container">
            <div className="popup">
                <div className="popup-title">Network</div>
                <div className="popup-message">Chaser is interfaced on {networks[process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID]} (Chain ID {process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID})</div>
                <div className="popup-message">
                    You are currently connected to Chain ID {fromHex(newChain, 'number') || "N/A"}
                </div>
                <button onClick={switchNetwork} className="popup-ok-button">Switch to {networks[process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID]} sepolia</button>
            </div>
        </div>
    );
}
