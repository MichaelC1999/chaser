require("hardhat-deploy");
require("@nomicfoundation/hardhat-toolbox");
require('hardhat-contract-sizer');
require('@openzeppelin/hardhat-upgrades');

/** @type import('hardhat/config').HardhatUserConfig */
require('dotenv').config({ path: __dirname + '/.env' });

module.exports = {
  defaultNetwork: "base",
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
      chainId: 1337,
      allowUnlimitedContractSize: true
    },
    goerli: {
      url: "https://goerli.infura.io/v3/" + process.env.INFURA_API_KEY,
      chainId: 5,
      accounts: [process.env.WALLET_PK]
    },
    localhost: {
      chainId: 31337,
      allowUnlimitedContractSize: true
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
    }
  },
  namedAccounts: {
    deployer: {
      default: 0
    }
  }
};
