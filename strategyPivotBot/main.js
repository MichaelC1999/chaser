const StrategyPivotBot = require('./strategyPivotBot')

const {
  getReturnRate: getReturnRateOfLiquidationRisk,
  checkConditions: checkConditionsOfLiquidationRisk
} = require('../strategies/liquidationRisk')

const {
  getReturnRate: getReturnRateOfLowVolHighYield,
  checkConditions: checkConditionsOfLowVolHighYield
} = require('../strategies/lowVolHighYield')

const {
  getReturnRate: getReturnRateOfHighYield3Month,
  checkConditions: checkConditionsOfHighYield3Month
} = require('../strategies/highYield3Month')

const deployments = require('../scripts/contractAddresses.json')

const poolAddresses = ['0xc96107268EDCE4B5d9D49c793719d1Ae213ed837']

const protocolMarkets = [
  {
    subgraphEndpoint: 'aave-v3-arbitrum',
    protocol: 'aave-v3',
    chain: 'arbitrum',
    marketId: '0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8'
  },
  {
    subgraphEndpoint: 'aave-v3-base',
    protocol: 'aave-v3',
    chain: 'base',
    marketId: '0xd4a0e0b9149bcee3c920d2e00b5de09138fd8bb7'
  },
  {
    subgraphEndpoint: 'aave-v3-ethereum',
    protocol: 'aave-v3',
    chain: 'ethereum',
    marketId: '0x4d5f47fa6a74757f35c14fd3a6ef8e3c9bc514e8'
  },
  {
    subgraphEndpoint: 'aave-v3-optimism',
    protocol: 'aave-v3',
    chain: 'optimism',
    marketId: '0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8'
  },
  {
    subgraphEndpoint: 'aave-v3-polygon',
    protocol: 'aave-v3',
    chain: 'polygon',
    marketId: '0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8'
  },
  {
    subgraphEndpoint: 'compound-v3-ethereum',
    protocol: 'compound-v3',
    chain: 'ethereum',
    marketId:
      '0xc3d688b66703497daa19211eedff47f25384cdc3c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2'
  },
  {
    subgraphEndpoint: 'compound-v3-arbitrum',
    protocol: 'compound-v3',
    chain: 'arbitrum',
    marketId:
      '0x9c4ec768c28520b50860ea7a15bd7213a9ff58bf82af49447d8a07e3bd95bd0d56f35241523fbab1'
  },
  {
    subgraphEndpoint: 'compound-v3-polygon',
    protocol: 'compound-v3',
    chain: 'polygon',
    marketId:
      '0xf25212e676d1f7f89cd72ffee66158f5412464457ceb23fd6bc0add59e62ac25578270cff1b9f619'
  }
]

const strategies = [
  {
    getReturnRate: positionData => getReturnRateOfLiquidationRisk(positionData),
    checkConditions: async (positionData, protocol, chain, marketId) =>
      await checkConditionsOfLiquidationRisk(
        positionData,
        protocol,
        chain,
        marketId
      )
  },
  {
    getReturnRate: positionData => getReturnRateOfLowVolHighYield(positionData),
    checkConditions: async (positionData, protocol, chain, marketId) =>
      await checkConditionsOfLowVolHighYield(
        positionData,
        protocol,
        chain,
        marketId
      )
  },
  {
    getReturnRate: positionData => getReturnRateOfHighYield3Month(positionData),
    checkConditions: async (positionData, protocol, chain, marketId) =>
      await checkConditionsOfHighYield3Month(
        positionData,
        protocol,
        chain,
        marketId
      )
  },
]

const botIntervalTimeout = 300000   // 300000 ms = 5 minutes

const newStrategyPivotBot = new StrategyPivotBot({
    poolAddresses,
    protocolMarkets,
    strategies,
    deployments,
    botIntervalTimeout
})

newStrategyPivotBot.run()

// newStrategyPivotBot.terminate()