

// Function for lowVolHighYield comparison oracle
// Needs 2 sets of inputs, chain provided protocol data for current deposit pool, user provided protocol data for a pool to possibly transfer to 

// For each position to compare needs protocol slug, chain name, token address of input token 

// If the funds are not currently deposited, just check that pool to transfer to is above 0

// Input args [currentPoolId, currentProtocolSlug, destinationProtocolSlug, marketTokenAddress]


const currentPoolId = args[0]
const marketTokenAddress = args[3]

const currentSubgraphURL = `https://api.thegraph.com/subgraphs/name/messari/` + args[1];

const destinationSubgraphURL = `https://api.thegraph.com/subgraphs/name/messari/` + args[2];

const timeframe = 30;

// Loop through valid subgraphs and query for each of them
const currentPositionData = await Functions.makeHttpRequest({
    url: currentSubgraphURL,
    method: "POST",
    headers: {
        "Content-Type": "application/json",
    },
    data: {
        query: `{
	marketDailySnapshots(first: ${timeframe}, orderBy: timestamp, orderDirection: desc, where: {market:"${currentPoolId}"}) {

        totalDepositBalanceUSD
        dailySupplySideRevenueUSD
    }
}`
    }
});

const positionDestinationData = await Functions.makeHttpRequest({
    url: destinationSubgraphURL,
    method: "POST",
    headers: {
        "Content-Type": "application/json",
    },
    data: {
        query: `{
            markets (where: {inputToken:"${marketTokenAddress}"}) {
                id
            } 
	marketDailySnapshots(first: ${timeframe}, orderBy: timestamp, orderDirection: desc, where: {market_:{inputToken:"${marketTokenAddress}"}}) {
        totalDepositBalanceUSD
        dailySupplySideRevenueUSD
    }
}`
    }
});

// console.log(currentSubgraphURL, JSON.stringify(positionDestinationData.data))
let currentCumulative = 0;
let currentRate = 0;
currentPositionData.data.data.marketDailySnapshots.forEach((instance, index) => {
    const instanceApy = Number(((Number(instance.dailySupplySideRevenueUSD) * 365) / Number(Number(instance.totalDepositBalanceUSD)).toFixed(4)))
    if (instanceApy) {
        currentRate = (currentCumulative + instanceApy) / (index + 1)
        currentCumulative += instanceApy
    }
}
);

let returnJson = {
    slug: args[1],
    value: currentRate,
    subgraphPoolId: currentPoolId
}

const destinationPoolId = positionDestinationData.data.data.markets?.[0]?.id
if (!destinationPoolId) {
    return Functions.encodeString(JSON.stringify(returnJson))
}

let destinationCumulative = 0;
let destinationRate = 0;
positionDestinationData.data.data.marketDailySnapshots.forEach((instance, index) => {
    const instanceApy = Number(((Number(instance.dailySupplySideRevenueUSD) * 365) / Number(Number(instance.totalDepositBalanceUSD)).toFixed(4)))
    if (instanceApy) {

        destinationRate = (destinationCumulative + instanceApy) / (index + 1)
        destinationCumulative += instanceApy
    }
}
);

const destinationObject = {
    slug: args[2],
    value: destinationRate,
    subgraphPoolId: destinationPoolId
}

if (destinationRate > currentRate && destinationRate > 0) {
    returnJson = destinationObject;
}

return Functions.encodeString(JSON.stringify(returnJson))