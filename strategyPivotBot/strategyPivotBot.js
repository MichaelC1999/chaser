const hre = require('hardhat')

/**
 * Strategy Structure
 * {
 * 		checkConditions: (positionData, protocol, chain, marketId) => checkConditionsOfStrategyName(positionData, protocol, chain, marketId),
 * 		getReturnRate: (positionData) => getReturnRateOfStrategyName(positionData)
 * },
 * 
 * Strategy Array
 * [
 * 		{
 * 			checkConditions: (positionData, protocol, chain, marketId) => checkConditionsOfStrategyName(positionData, protocol, chain, marketId),
 * 			getReturnRate: (positionData) => getReturnRateOfStrategyName(positionData)
 * 		},
 * ]
 * 
 * Pass the contractAddresses through "deployments" field of StrategyPivotBot class
 */

class StrategyPivotBot {
  #poolAddresses
  #protocolMarkets
  #strategies
  #deployments
  #botIntervalTimeout
  #botInterval

  constructor ({
    poolAddresses,
    protocolMarkets,
    strategies,
    deployments,
    botIntervalTimeout
  }) {
    this.#poolAddresses = poolAddresses
    this.#protocolMarkets = protocolMarkets
    this.#strategies = strategies
    this.#deployments = deployments
    this.#botIntervalTimeout = botIntervalTimeout
    this.#botInterval = null
  }

  async #fetchMarketData ({ protocol, chain, marketId }) {
    const base = 'https://api.thegraph.com/subgraphs/name/messari/'

    const marketDataQuery = marketId => {
      return `{                                                                                                               
								marketDailySnapshots(first: 90, orderBy: timestamp, orderDirection: desc, where: { market: ${marketId} }) {
									market {                                                                                                        
											id                                                                                                          
									}                                                                                                                
									days                                                                                                                
									rates(where: {side: LENDER}) {                                                                                  
											side                                                                                                        
											rate                                                                                                        
									}                                                                                                               
								}                                                                                                                   
							}`
    }

    const response = await fetch(base + protocol + '-' + chain, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        query: marketDataQuery(marketId)
      })
    })

    if (!response.ok) {
      throw new Error(`Error while fetching market data! status: ${response.status}`)
    }

    const marketData = await response.json()

    return marketData
  }

  // async #getStrategyByPoolAddress (poolAddress) {
    async #getStrategyByPoolAddress (poolAddress, strategyId) {      // choose the strategyId for now
		if (!poolAddress) return null
    try {
      let strategyIndex = 0
      /* 
        Will place a logic here to get a target strategy from strategies array by the given poolAddress
        
        * * *

      */
      return this.#strategies[strategyId]
			
		} catch (error) {
			this.#handleError(error)			
		}
  }

  async #getCurrentPositionDataByPoolAddress (poolAddress) {
    const pool = await hre.ethers.getContractAt('PoolControl', poolAddress)
    const calcContract = await hre.ethers.getContractAt(
      'PoolCalculations',
      await pool.poolCalculations()
    )

    const curProtocol = await calcContract.currentPositionProtocol(poolAddress)
    const curChain = await pool.currentPositionChain()
    const curMarketId = await calcContract.currentPositionMarketId(poolAddress)
    // curMarketId = TESTNET_ANALOG_MARKETS[curMarketId] || curMarketId

		return { curProtocol, curChain, curMarketId }
	}

  async #sepoliaMonitor () {
    try {
      // Validate poolAddresses variable
      if (!Array.isArray(this.#poolAddresses) || this.#poolAddresses.length <= 0)
        throw new Error('The poolAddresses must be an array and not empty.')
      
      // Validate protocolMarkets variable
      if (!Array.isArray(this.#protocolMarkets) || this.#protocolMarkets.length <= 0) {
        throw new Error('The protocolMarkets must be an array and not empty.');
      }

      // Start a loop for poolAddresses
      for (const poolAddress of this.#poolAddresses) {
        // Get current position data from a given pool address
        const { curMarketId, curProtocol, curChain } = await this.#getCurrentPositionDataByPoolAddress(poolAddress)

        let bestMarketId = curMarketId
        let bestRor = 0
        let bestProtocol = curProtocol
        let bestChain = curChain
        
        // Get a target strategy for the given poolAddress
        const strategy = await this.#getStrategyByPoolAddress(poolAddress, 0)     //0: liquidationRisk, 1: lowVolHighYield, 2: highYield3Month

        // Validate the target strategy
        if (strategy && curMarketId) {
          // Start a loop for protocolMarkets
          for (const protocolMarket of this.#protocolMarkets){
            const marketData = await this.#fetchMarketData(protocolMarket)
            const condition = await strategy.checkConditions(
              marketData,
              protocolMarket
            )
            
            if (condition) {
              const ror = strategy.getReturnRate(marketData)
              if (ror > bestRor) {
                bestRor = ror
                bestMarketId = protocolMarket.marketId
                bestProtocol = protocolMarket.protocol
                bestChain = protocolMarket.chain
              }
            }
          }
        } else {
          throw new Error('Invalid strategy or current market ID.')
        }

        console.log("Current Time => ", new Date())
        if (bestMarketId != curMarketId) {
          console.log("Pool Address => ", poolAddress)
          console.log("Best MarketId => ", bestMarketId)
          console.log("Best Protocol => ", bestProtocol)
          console.log("Best Chain => ", bestChain)
          console.log("Best ROR => ", bestRor)
          await this.#executePivot({poolAddress, bestProtocol, bestChain})
        } else {
          console.log("Pool Address => ", poolAddress, "No pivot on this pool")
        }
      }
    } catch (error) {
      this.#handleError(error)
    }
  }

  async #executePivot ({ poolAddress, bestProtocol, bestChain }) {
    /* 
			Will place a pivot logic here
			We can access to contractAddresses from this.#deployments
			* * *

		*/
  }

  #handleError (error) {
    console.error(error)
    this.terminate()
  }

  run () {
    try {
      this.#botInterval = setInterval(
        async () => await this.#sepoliaMonitor(),
        this.#botIntervalTimeout
      )
    } catch (error) {
      this.#handleError(error)
    }
  }

  terminate () {
    if (this.#botInterval !== null) clearInterval(this.#botInterval)
  }
}

export default StrategyPivotBot
