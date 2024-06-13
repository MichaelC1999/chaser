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
 */

class StrategyPivotBot {
  #poolAddresses
  #protocolMarkets
  #strategies
  #botIntervalTimeout
  #botInterval

  constructor ({
    poolAddresses,
    protocolMarkets,
    strategies,
    botIntervalTimeout
  }) {
    this.#poolAddresses = poolAddresses
    this.#protocolMarkets = protocolMarkets
    this.#strategies = strategies
    this.#botIntervalTimeout = botIntervalTimeout
    this.#botInterval = null
  }

  async #fetchMarketData ({ protocol, chain, marketId }) {
    const base = 'https://api.thegraph.com/subgraphs/name/messari/'

    const marketDataQuery = marketId => {
      return `{                                                                                                               
								marketDailySnapshots(first: 90, orderBy: timestamp, orderDirection: desc, where: { market: ${marketId} }) {                                                                                                             \
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

    let marketData = await fetch(base + protocol + '-' + chain, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        query: marketDataQuery(marketId)
      })
    })
    return await marketData.json()
  }

  #getStrategyByPoolAddress (poolAddress) {
		try {
			if (poolAddress != null) {
				let strategyIndex = 0
				/* 
					Will place a logic here to get a target strategy from strategies array by the given poolAddress
					
					* * *

				*/
				return this.#strategies[strategyIndex]
			} else
			return null
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
      if (
        Array.isArray(this.#poolAddresses) &&
        this.#poolAddresses.length > 0
      ) {
        // Validate poolAddresses variable

        this.#poolAddresses.forEach((poolAddress, poolIndex) => {
          // Start a loop for poolAddresses

          const { curMarketId } = this.#getCurrentPositionDataByPoolAddress(poolAddress) // Get current position data from a given pool address

          let bestMarketId = curMarketId
          let bestRor = 0

          const strategy = this.#getStrategyByPoolAddress(poolAddress) // Get a target strategy for the given poolAddress

          if (strategy !== null && curMarketId != null) {
            // Validate the target strategy

            if (
              Array.isArray(this.#protocolMarkets) &&
              this.#protocolMarkets.length > 0
            ) {
              // Validate protocolMarkets variable

              this.#protocolMarkets.forEach(
                (protocolMarket, protocolMarketIndex) => {
                  // Start a loop for protocolMarkets

                  const marketData = this.#fetchMarketData(protocolMarket)
                  const condition = strategy.checkConditions(
                    marketData,
                    protocolMarket
                  )
                  const ror = condition
                    ? strategy.getReturnRate(marketData)
                    : null

                  if (ror > bestRor) {
                    // Get the best marketId and ror
                    bestRor = ror
                    bestMarketId = protocolMarket.marketId
                  }
                }
              )
            } else {
              throw new Error(
                'The protocolMarkets must be an array and not empty.'
              )
            }
          } else {
            throw new Error('Invalid variables.')
          }

          if (bestMarketId != curMarketId) {
            this.#executePivot()
          }
        })
      } else {
        throw new Error('The poolAddresses must be an array and not empty.')
      }
    } catch (error) {
      this.#handleError(error)
    }
  }

  async #executePivot () {
    /* 
			Will place a pivot logic here
			
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
