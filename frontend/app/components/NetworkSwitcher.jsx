import React, { useEffect, useState } from 'react';
import { useSwitchNetwork } from '@web3modal/ethers/react';


export function NetworkSwitcher() {
    const windowOverride = typeof window !== 'undefined' ? window : null;
    const [chainId, setChainId] = useState("")
    const { switchNetwork } = useSwitchNetwork()
    useEffect(() => {
        if (typeof window !== 'undefined' && 'ethereum' in window) {
            getChainId()
        }
    }, [])

    const getChainId = async () => {
        setChainId(await windowOverride.ethereum.request({ method: 'eth_chainId' }))
    }

    const newChain = chainId

    const switchNetworkAction = async () => {

    }

    return null;

}
