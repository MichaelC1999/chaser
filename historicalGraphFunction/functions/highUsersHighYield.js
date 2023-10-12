const supportedAssets = {
    "WETH": {
        "ethereum": "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
        "arbitrum": "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
        "optimism": "0x4200000000000000000000000000000000000006",
        "polygon": "0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619"
    },
    "USDC": {
        "ethereum": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
        "arbitrum": "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
        "optimism": "0x7f5c764cbc14f9669b88837ca1490cca17c31607",
        "polygon": "0x2791bca1f2de4661ed88a30c99a7a9449aa84174"
    },
    "DAI": {
        "ethereum": "0x6B175474E89094C44Da98b954EedeAC495271d0F",
        "arbitrum": "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1",
        "optimism": "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1",
        "polygon": "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063"
    },
    "USDT": {
        "ethereum": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
        "arbitrum": "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9",
        "optimism": "0x94b008aA00579c1307B0EF2c499aD98a8ce58e58",
        "polygon": "0xc2132D05D31c914a87C6611C10748AEb04B58e8F"
    },
    "WBTC": {
        "ethereum": "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599",
        "arbitrum": "0x2f2a2543b76a4166549f7aab2e75bef0aefc5b0f",
        "optimism": "0x68f180fcce6836688e9084f035309e29bf0a2095",
        "polygon": "0x1bfd67037b42cf73acf2047067bd4f2c47d9bfd6"
    }
}

const subgraphslist = JSON.parse(args[0]).slice(0, 4)

const subgraphQueryUrlList = Object.values(subgraphslist).map(subgraphSlug => ({ url: `https://api.thegraph.com/subgraphs/name/messari/${subgraphSlug}`, chain: subgraphSlug.split('-')[subgraphSlug.split('-').length - 1] }))

let timeframe = args[1]
if (!timeframe) {
    timeframe = 30;
}

// Loop through valid subgraphs and query for each of them
const requests = subgraphQueryUrlList.map(queryData => Functions.makeHttpRequest({
    url: queryData.url,
    method: "POST",
    headers: {
        "Content-Type": "application/json",
    },
    data: {
        query: `{
	marketDailySnapshots(first: ${timeframe}, orderBy: timestamp, orderDirection: desc, where: {market_:{inputToken:"${supportedAssets[args[2]][queryData.chain]}"}}) {
        totalDepositBalanceUSD
        dailySupplySideRevenueUSD
        dailyActiveUsers
  }
}`
    }
}));

const returnedData = await Promise.all(requests)

const vals = {}

returnedData.forEach((set, idx) => {
    const key = subgraphslist[idx];

    const ratesOfReturn = set.data.data.marketDailySnapshots.map(instance => (instance.dailySupplySideRevenueUSD * 365) / instance.totalDepositBalanceUSD);
    const normalize = (values) => {
        const max = Math.max(...values);
        const min = Math.min(...values);
        return values.map(value => (value - min) / (max - min));
    };

    const normalizedReturns = normalize(ratesOfReturn);
    const normalizedDepositors = normalize(set.data.data.marketDailySnapshots.map(instance => instance.dailyActiveUsers));

    // Calculate scores based on weighted average
    const scores = set.data.data.marketDailySnapshots.map((instance, index) => {
        const weightForReturn = 0.5;
        const weightForDepositors = 0.5;
        return weightForReturn * normalizedReturns[index] + weightForDepositors * normalizedDepositors[index];
    });

    // Find entry with the highest score
    const maxScoreIndex = scores.indexOf(Math.max(...scores));
    vals[key] = maxScoreIndex
})

return Functions.encodeString(JSON.stringify(vals))