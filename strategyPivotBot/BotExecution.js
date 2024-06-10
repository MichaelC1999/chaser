const hre = require("hardhat");
const ethers = require("ethers");
const fs = require('fs');
const { stringToBytes, bytesToString, hexToString, decodeEventLog } = require('viem')


const deployments = require('../scripts/contractAddresses.json');
const { bestYieldOnStrategy } = require("./BestMarketForStrategy");
const { strategyCalculation } = require("./highYield3Month");

const networks = {
  "11155111": "ethereum",
  "84532": "base"
}
const makeQuery = (marketId) => {
  return '{                                                                                                               \
          marketDailySnapshots(first: 90, orderBy: timestamp, orderDirection: desc, where: { market:"'+ marketId + '"}) {   \                                                                                                            \
              market {                                                                                                        \
                  id                                                                                                          \
              }                                                                                                                \
              days                                                                                                                \
              rates(where: {side: LENDER}) {                                                                                  \
                  side                                                                                                        \
                  rate                                                                                                        \
              }                                                                                                               \
          }                                                                                                                   \
      }'
}
const fetchAndPrepareData = async (protocol, network, marketId) => {
  const base = "https://api.thegraph.com/subgraphs/name/messari/";

  let req = await fetch(base + protocol + '-' + network, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      query: makeQuery(marketId)
    })
  });
  return await req.json();
}

const getCurrentPositionYield = async (data) => {
  let curROR = 0;
  let curMeanROR

  if (data) {
    console.log(data.marketDailySnapshots)
    data.marketDailySnapshots.forEach(ins => {
      const rate = (Number(ins.rates[0].rate))
      curROR += rate

    });
    curMeanROR = curROR / data.marketDailySnapshots.length;
  }
  return curMeanROR

}

const TESTNET_ANALOG_MARKETS = {
  '0x61490650abaa31393464c3f34e8b29cd1c44118ee4ab69c077896252fafbd49efd26b5d171a32410': "0x46e6b214b524310239732d51387075e0e70970bf4200000000000000000000000000000000000006",
  '0x2943ac1216979ad8db76d9147f64e61adc126e96e4ab69c077896252fafbd49efd26b5d171a32410': "0xa17581a9e3356d9a858b789d68b4d866e593ae94c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
  '0x96e32de4b1d1617b8c2ae13a88b9cc287239b13f': "0xd4a0e0b9149bcee3c920d2e00b5de09138fd8bb7",
  '0x29598b72eb5cebd806c5dcd549490fda35b13cd8': "0x4d5f47fa6a74757f35c14fd3a6ef8e3c9bc514e8"
}


// SEPARATE EACH QUERY INTO OBJECTS WITH MARKET, CHAIN/NETWORK, PROTOCOL
// SET A MARKER SO THAT JORGE KNOWS THAT THESE ARE THE PROTOCOL/CHAINS TO LOOP THROUGH FOR EACH STRATEGY
const PROTOCOL_MARKET_PAIRS = [
  { subgraphEndpoint: "aave-v3-arbitrum", protocol: "aave-v3", chain: "arbitrum", market: "0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8" },
  { subgraphEndpoint: "aave-v3-base", protocol: "aave-v3", chain: "base", market: "0xd4a0e0b9149bcee3c920d2e00b5de09138fd8bb7" },
  { subgraphEndpoint: "aave-v3-ethereum", protocol: "aave-v3", chain: "ethereum", market: "0x4d5f47fa6a74757f35c14fd3a6ef8e3c9bc514e8" },
  { subgraphEndpoint: "aave-v3-optimism", protocol: "aave-v3", chain: "optimism", market: "0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8" },
  { subgraphEndpoint: "aave-v3-polygon", protocol: "aave-v3", chain: "polygon", market: "0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8" },
  { subgraphEndpoint: "compound-v3-ethereum", protocol: "compound-v3", chain: "ethereum", market: "0xc3d688b66703497daa19211eedff47f25384cdc3c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2" },
  { subgraphEndpoint: "compound-v3-arbitrum", protocol: "compound-v3", chain: "arbitrum", market: "0x9c4ec768c28520b50860ea7a15bd7213a9ff58bf82af49447d8a07e3bd95bd0d56f35241523fbab1" },
  { subgraphEndpoint: "compound-v3-polygon", protocol: "compound-v3", chain: "polygon", market: "0xf25212e676d1f7f89cd72ffee66158f5412464457ceb23fd6bc0add59e62ac25578270cff1b9f619" }]

const sepoliaMonitor = async (poolAddress) => {
  // read current position
  const pool = await hre.ethers.getContractAt("PoolControl", poolAddress)
  const calcContract = await hre.ethers.getContractAt("PoolCalculations", await pool.poolCalculations())

  // const curProtocol = await calcContract.currentPositionProtocol(poolAddress)

  // let curMarketId = await calcContract.currentPositionMarketId(poolAddress)
  // curMarketId = TESTNET_ANALOG_MARKETS[curMarketId] || curMarketId
  // const curChain = await pool.currentPositionChain()


  // // make fetch and process for current yield here
  const curProtocol = "aave-v3"
  const curChain = "arbitrum"
  const curMarketId = "0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8"
  const network = networks[curChain]
  const currentMarketData = await fetchAndPrepareData(curProtocol, network, curMarketId)
  const ror = await getCurrentPositionYield(currentMarketData.data)

  console.log('Yield', currentMarketData, ror)
  //call highYieldUSDC
  const best = await bestYieldOnStrategy()
  console.log(best)

  if (ror > best.yield) {
    console.log('NO PIVOT')
  } else {
    console.log("BETTER INVESTMENT RIGHT NOW", best)
    const chainToName = { "base": 84532, "sepolia": 11155111 }

    process.argv.push(curChain, chainToName[best.depo], curMarketId, best.market, curProtocol, best.protocol)
    const shouldPivot = await strategyCalculation()
    console.log('YES', shouldPivot)
    // IMPORTANT - COULD GET THE STRATEGY CODE, SAVE IT WITH FS, THEN GENERATE CODE TO EXECUTE IT

    // await sepoliaCallPivot(best)
  }
  return
  //If returns higher than current yield and is differen market/depo/protocol, then sepoliaCallPivot
}

const sepoliaCallPivot = async (poolAddress, target) => {
  const pool = await hre.ethers.getContractAt("PoolControl", poolAddress)

  // Get hash of protocol
  // const WETH = await hre.ethers.getContractAt("ERC20", deployments[chainName]["WETH"]);
  // await (await WETH.transfer(deployments[chainName]["integratorAddress"], "100000000000")).wait()




  const USDC = await hre.ethers.getContractAt("ERC20", "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238");
  console.log('TRYING TO CALL PIVOT')
  // await (await USDC.approve(deployments.sepolia["arbitrationContract"], 500000)).wait()
  // console.log((await (await pool.queryMovePosition(protocolName + "-v3", deployments[target.depo][protocolName + "MarketId"], chainToName[target.depo], { gasLimit: 7000000 })).wait()).hash)
}



async function mainExecution() {

  // IMPORTANT - THIS FILE WILL BE STANDARD FOR EXECUTING ALL MONITOR BOTS AND SUBMITTING PROPOSAL TX. NEEDS ITS OWN DIRECTORY FOR CLONING/FORKING
  // BestMarketForStrategy.js is to be customized per strategy. It serves to query all potential markets and analyze them according to strategy logic and return the best investment
  // highYield3Month.js is the actual strategy logic for confirming before submitting tx

  try {

    const poolAddress = "0xc96107268EDCE4B5d9D49c793719d1Ae213ed837"
    await sepoliaMonitor(poolAddress)
    const interval = setInterval(async () => await sepoliaMonitor(poolAddress), 300000); // 300000 ms = 5 minutes

    return () => clearInterval(interval); // Clean up the interval on component unmount

  } catch (error) {
    console.error(error);
    console.log(error.logs)
    process.exitCode = 1;
  }

}

mainExecution()