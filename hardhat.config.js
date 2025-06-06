require("hardhat-deploy");
require("@nomicfoundation/hardhat-toolbox");
require('hardhat-contract-sizer');
require('@openzeppelin/hardhat-upgrades');

/** @type import('hardhat/config').HardhatUserConfig */
require('dotenv').config({ path: __dirname + '/.env' });

module.exports = {
  defaultNetwork: "arbitrum",
  solidity: {
    version: "0.8.22",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hardhat: {
      chainId: 1,
      forking: {
        enabled: true,
        url: "https://mainnet.infura.io/v3/" + process.env.INFURA_API_KEY
      },
      accounts: { privateKey: process.env.WALLET_PK, balance: "1000000000000000000000" }
    },
    sepolia: {
      url: "https://sepolia.infura.io/v3/" + process.env.INFURA_API_KEY,
      chainId: 11155111,
      accounts: [process.env.WALLET_PK]
    },
    mumbai: {
      url: "https://polygon-mumbai.infura.io/v3/" + process.env.INFURA_API_KEY,
      chainId: 80001,
      accounts: [process.env.WALLET_PK]
    },
    base: {
      url: "https://sepolia.base.org",
      chainId: 84532,
      accounts: [process.env.WALLET_PK]
    },
    arbitrum: {
      url: "https://sepolia-rollup.arbitrum.io/rpc",
      chainId: 421614,
      accounts: [process.env.WALLET_PK]
    },
    optimism: {
      url: "https://sepolia.optimism.io",
      chainId: 11155420,
      accounts: [process.env.WALLET_PK]
    }
  },
  namedAccounts: {
    deployer: {
      default: 0
    }
  }
};
