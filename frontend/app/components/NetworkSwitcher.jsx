import React, { useEffect, useState } from 'react';
import { fromHex } from 'viem'


export function NetworkSwitcher() {
    const windowOverride = typeof window !== 'undefined' ? window : null;
    const [errorMessage, setErrorMessage] = useState("");
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
            // Prompt user to switch to Sepolia
            await windowOverride?.ethereum?.request({
                method: 'wallet_addEthereumChain',
                params: [{ chainId: '0x14a34', rpcUrls: ["https://sepolia.base.org"], chainName: "Base Sepolia", nativeCurrency: { symbol: "ETH", decimals: 18, name: "Ether" } }],
            });
            await windowOverride?.ethereum?.request({
                method: 'wallet_switchEthereumChain',
                params: [{ chainId: '0x14a34' }],
            });
        } catch (switchError) {

            console.log(switchError.message)

            setErrorMessage(switchError.message);
        }
    }

    if (isEthereumAvailable) {
        if (chainId == "0x14a34" || fromHex(newChain, 'number') == 0) {
            return null;
        }
    } else {
        // If injected provider is not in use, do not render this modal by default
        return null;
    }
    return (
        <div className="popup-container">
            <div className="popup">
                <div className="popup-title">Network Switcher</div>
                <div className="popup-message">Chaser is interfaced on Base Sepolia (Chain ID 84532)</div>
                <div className="popup-message">
                    You are currently connected to Chain ID {fromHex(newChain, 'number') || "N/A"}
                </div>
                <button onClick={switchNetwork} className="popup-ok-button">Switch to Base</button>
            </div>
        </div>
    );
}
