'use client'

import { createWeb3Modal, defaultConfig } from '@web3modal/ethers/react'
import { sepolia } from 'viem/chains'

// 1. Get projectId at https://cloud.walletconnect.com
const projectId = '8d59073cbe5cc16d4461e675fcc14a0c'

// 2. Set chains
const mainnet = {
    chainId: 421614,
    name: 'Arbitrum Sepolia',
    currency: 'ETH',
    explorerUrl: 'https://sepolia.arbiscan.io',
    rpcUrl: 'https://sepolia-rollup.arbitrum.io/rpc'
}

// 3. Create a metadata object
const metadata = {
    name: 'Chaser Finance',
    description: 'Chaser Finance',
    url: 'https://chaser.finance/', // origin must match your domain & subdomain
    // icons: ['https://avatars.mywebsite.com/']
}
// 4. Create Ethers config
const ethersConfig = defaultConfig({
    /*Required*/
    metadata,

    /*Optional*/
    enableEIP6963: true, // true by default
    enableInjected: true, // true by default
    enableCoinbase: true, // true by default

})

// 5. Create a Web3Modal instance
createWeb3Modal({
    ethersConfig,
    chains: [mainnet],
    projectId,
    enableAnalytics: true, // Optional - defaults to your Cloud configuration
    enableOnramp: true // Optional - false as default
})

export function Web3Modal({ children }) {
    return children
}