import React, { useMemo } from 'react';
import { ethers } from 'ethers';
import { useWeb3Modal } from '@web3modal/ethers/react';

const ConnectButton = ({ connected, address, setErrorMessage }) => {
    const windowOverride = typeof window !== 'undefined' ? window : null;

    // Instantiate the provider, if the window object remains the same no need to recalculate
    const provider = useMemo(() => {
        return new ethers.JsonRpcProvider("https://rpc.sepolia.org");
    }, [windowOverride]);

    const { open } = useWeb3Modal()

    const connect = async () => {
        console.log('connect', connected)
        try {
            if (connected) {
                open({ view: 'Account' })
            } else {
                open({})
            }
        } catch (err) {
            setErrorMessage("Connection Error: " + err?.info?.error?.message ?? err?.message);
        }
    }
    let classes = 'button'
    if (connected === true) {
        classes += ' buttonConnected'
    }
    return (
        connected !== null ? <button className={classes} onClick={connect}>
            {connected ? '0x' + address?.slice(2, 6) + '...' + (address?.slice(36) ?? "0000") : "Connect"}
        </button> : null
    );
};


export default ConnectButton;
