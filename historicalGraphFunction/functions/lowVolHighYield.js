const curPoolId = args[0];
const marketTokenAddress = args[3];
const base = `https://api.thegraph.com/subgraphs/name/messari/`;
const curSubgraphURL = base + args[1];
const desSubgraphURL = base + args[2];

const curPositionData = await Functions.makeHttpRequest({
    url: curSubgraphURL,
    method: "POST",
    headers: {
        "Content-Type": "application/json",
    },
    data: {
        query: `{
	marketDailySnapshots(first: 30, orderBy: timestamp, orderDirection: desc, where: {market:"${curPoolId}"}) {
        totalDepositBalanceUSD
        dailySupplySideRevenueUSD
    }
}`
    }
});

const positionDesData = await Functions.makeHttpRequest({
    url: desSubgraphURL,
    method: "POST",
    headers: {
        "Content-Type": "application/json",
    },
    data: {
        query: `{
            markets (where: {inputToken:"${marketTokenAddress}"}) {
                id
            } 
	marketDailySnapshots(first: 30, orderBy: timestamp, orderDirection: desc, where: {market_:{inputToken:"${marketTokenAddress}"}}) {
        totalDepositBalanceUSD
        dailySupplySideRevenueUSD
    }
}`
    }
});

const curROR = curPositionData.data.data.marketDailySnapshots.map(ins => (Number(ins.dailySupplySideRevenueUSD) * 365) / Number(ins.totalDepositBalanceUSD) || 0);
const curMeanROR = curROR.reduce((acc, curr) => acc + curr, 0) / curROR.length;

const curVariance = curROR.reduce((acc, curr) => acc + Math.pow(curr - curMeanROR, 2), 0) / curROR.length;
const curStandardDeviation = Math.sqrt(curVariance);

const curSharpeRatio = (curMeanROR / curStandardDeviation) || -1;

const desPoolId = positionDesData.data.data.markets?.[0]?.id
if (!desPoolId) {
    return Functions.encodeString(curPoolId)
}

const desROR = positionDesData.data.data.marketDailySnapshots.map(ins => (ins.dailySupplySideRevenueUSD * 365) / ins.totalDepositBalanceUSD);
const desMeanROR = desROR.reduce((acc, curr) => acc + curr, 0) / desROR.length;

const desVariance = desROR.reduce((acc, curr) => acc + Math.pow(curr - desMeanROR, 2), 0) / desROR.length;
const desStandardDeviation = Math.sqrt(desVariance);

const desSharpeRatio = desMeanROR / desStandardDeviation;

if (desSharpeRatio > curSharpeRatio && desSharpeRatio > 0) {
    return Functions.encodeString(desPoolId)
}

return Functions.encodeString(curPoolId)
