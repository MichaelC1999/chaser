import React, { useMemo } from 'react';
import { ethers } from 'ethers';

interface ConnectButtonProps {
    connected: Boolean | null;
    setErrorMessage: (message: string) => void;
}

type StyleProps = {
    connected?: Boolean | null;
};

const ConnectButton = ({ connected, setErrorMessage }: ConnectButtonProps) => {
    const windowOverride: any = typeof window !== 'undefined' ? window : null;

    // Instantiate the provider, if the window object remains the same no need to recalculate
    const provider = useMemo(() => {
        return new ethers.BrowserProvider(windowOverride?.ethereum);
    }, [windowOverride]);

    const connect = async () => {
        if (!connected) {
            // If the user is not signed into metamask, execute this logic
            try {
                await provider.send("eth_requestAccounts", []);
                await provider.getSigner();
            } catch (err: any) {
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
            {connected ? "Connected" : "Connect"}
        </button> : null
    );
};


export default ConnectButton;
