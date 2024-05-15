import React, { useMemo } from 'react';
import { ethers } from 'ethers';
import { sepolia, baseSepolia } from 'viem/chains';

const ConnectButton = ({ connected, setErrorMessage }) => {
    const windowOverride = typeof window !== 'undefined' ? window : null;

    // Instantiate the provider, if the window object remains the same no need to recalculate
    const provider = useMemo(() => {
        return new ethers.JsonRpcProvider("https://rpc.sepolia.org");
    }, [windowOverride]);

    const connect = async () => {
        if (!connected) {
            // If the user is not signed into metamask, execute this logic
            try {
                await provider.send("eth_requestAccounts", []);
                await provider.getSigner();

            } catch (err) {
                setErrorMessage("Connection Error: " + err?.info?.error?.message ?? err?.message);
            }
        }
    }
    let classes = 'button'
    if (connected === true) {
        classes += ' buttonConnected'
    }
    return (
        connected !== null ? <button className={classes} onClick={connect}>
            {connected ? '0x...' + (windowOverride?.ethereum?.selectedAddress?.slice(36) ?? "0000") : "Connect"}
        </button> : null
    );
};


export default ConnectButton;
