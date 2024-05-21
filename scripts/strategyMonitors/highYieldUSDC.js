
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

const getYield = async (data) => {
  let curROR = 0;
  let curMeanROR

  if (data) {
    console.log(data.marketDailySnapshots)
    data.marketDailySnapshots.forEach(ins => {
      const rate = (Number(ins.rates[0].rate))
      curROR += rate
      if (!highestRateByDay[ins.days] || highestRateByDay[ins.days] < rate) {
        highestRateByDay[ins.days] = rate
        highestRateMarketByDay[ins.days] = 1

      }
    });
    curMeanROR = curROR / data.marketDailySnapshots.length;
  }
  return curMeanROR

}

const sepoliaMonitor = async (poolAddress) => {
  // read current position
  const pool = await hre.ethers.getContractAt("PoolControl", poolAddress)
  const calcContract = await hre.ethers.getContractAt("PoolCalculations", await pool.poolCalculations())

  const protocol = await calcContract.currentPositionProtocol(poolAddress)
  const marketId = await calcContract.currentPositionMarketId(poolAddress)
  const chain = await pool.currentPositionChain()

  const network = networks[chain]

  // make fetch and process for current yield here
  const currentMarketData = await fetchAndPrepareData(protocol, network, marketId)
  const ror = await getYield(currentMarketData.data)

  console.log('Yield', currentMarketData, ror)
  //call highYieldUSDC
  const best = await strategyCalculation()
  console.log(best)

  if (ror > best.yield) {
    console.log('NO PIVOT')
  } else {
    console.log("BETTER INVESTMENT RIGHT NOW", best)
    await sepoliaCallPivot(best)
  }
  return
  //If returns higher than current yield and is differen market/depo/protocol, then sepoliaCallPivot
}

const sepoliaCallPivot = async (poolAddress, target) => {
  const pool = await hre.ethers.getContractAt("PoolControl", poolAddress)

  const chainToName = { "base": 84532, "sepolia": 11155111 }
  // Get hash of protocol
  // const WETH = await hre.ethers.getContractAt("ERC20", deployments[chainName]["WETH"]);
  // await (await WETH.transfer(deployments[chainName]["integratorAddress"], "100000000000")).wait()




  const USDC = await hre.ethers.getContractAt("ERC20", "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238");
  await (await USDC.approve(deployments.sepolia["arbitrationContract"], 500000)).wait()
  console.log((await (await pool.queryMovePosition(protocolName + "-v3", deployments[target.depo][protocolName + "MarketId"], chainToName[target.depo], { gasLimit: 7000000 })).wait()).hash)
}



async function mainExecution() {

  try {
    // DEMO STEPS
    // Instructions: Uncomment the below function calls one at a time. Pay attention to the purpose of each section and execute according to what functionality you would like to test
    // Prerequisites:  0.003 WETH and .1 ETH on Base Sepolia, and .1 ETH on Ethereum Sepolia
    // 1. Add private key as "WALLET_PK" env in "../.env"
    // 2. Add your RPC URI/key in "../hardhat.config.js"
    // --------------------------------------------------------------------------------------------
    // IF LOOKING TO DEPLOY YOUR OWN INSTANCE OF ALL CONTRACTS - EXECUTE THE FOLLOWING TWO FUNCTIONS ONE AT A TIME.
    // await sepoliaDeployments() //CHECK THAT THE DEFAULT NETWORK IN "..hardhat.config.js" IS sepolia
    // await baseDeployments() //CHANGE THE DEFAULT NETWORK IN "..hardhat.config.js" TO base
    // await sepoliaSecondConfig() //CHANGE THE DEFAULT NETWORK IN "..hardhat.config.js" TO sepolia
    // --------------------------------------------------------------------------------------------

    // await baseIntegrationsTest()
    // await testLogFinder()

    //sepoliaMonitor executes on one hour interval
    //Fetches data from all of the deployments 
    //processes the data
    //reads on the pool/pool calc what the current position is
    //If the market with best yield is not the current position, call sepoliaCallPivot with market that is
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