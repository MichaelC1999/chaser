'use client'

import { createWeb3Modal, defaultConfig } from '@web3modal/ethers/react'
import { sepolia } from 'viem/chains'

// 1. Get projectId at https://cloud.walletconnect.com
const projectId = '8d59073cbe5cc16d4461e675fcc14a0c'

// 2. Set chains
const mainnet = {
    chainId: 11155111,
    name: 'Ethereum Sepolia',
    currency: 'ETH',
    explorerUrl: 'https://etherscan.io',
    rpcUrl: 'https://rpc.sepolia.org'
}

// 3. Create a metadata object
const metadata = {
    name: 'My Website',
    description: 'My Website description',
    url: 'http://localhost:3000/', // origin must match your domain & subdomain
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