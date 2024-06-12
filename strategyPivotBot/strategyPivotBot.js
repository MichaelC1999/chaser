const hre = require("hardhat");

const { bestYieldOnStrategy } = require("./BestMarketForStrategy");
const { strategyCalculation } = require("./highYield3Month");

class StrategyPivotBot {
    constructor(options) {
        this.options = options;
        this.botInterval = null;
    }

    async #makeQuery(marketId) {
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

    async #fetchAndPrepareData(protocol, network, marketId) {
        const base = "https://api.thegraph.com/subgraphs/name/messari/";
        
        let req = await fetch(base + protocol + '-' + network, {
            method: "POST",
            headers: {
            "Content-Type": "application/json",
            },
            body: JSON.stringify({
            query: this.#makeQuery(marketId)
            })
        });
        return await req.json();
    }
    
    async #getCurrentPositionYield(data) {
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

    async #sepoliaMonitor(poolAddress) {
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
        const network = this.options.networks[curChain]
        const currentMarketData = await this.#fetchAndPrepareData(curProtocol, network, curMarketId)
        const ror = await this.#getCurrentPositionYield(currentMarketData.data)
      
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

    run() {
        try {
            this.botInterval = setInterval(async () => await sepoliaMonitor(poolAddress), this.options.botIntervalTime);
        } catch (error) {
            console.log(error);
        }
    }

    terminate() {
        if (this.botInterval !== null)
            clearInterval(this.botInterval);
    }
}

export default StrategyPivotBot;