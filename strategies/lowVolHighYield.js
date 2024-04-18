const strategyCalculation = async (args) => {
    const requestChain = args[0]
    const requestProtocol = args[1]
    const requestMarketId = args[2]
    const currentChain = args[3]
    const currentProtocol = args[4]
    const currentMarketId = args[5]
    try {
        const url = "https://raw.githubusercontent.com/messari/subgraphs/master/deployment/deployment.json";

        const depos = await fetch(url, {
            method: "get",
            headers: {
                "Content-Type": "application/json",
            }
        })

        const deployments = await depos.json()
        //look through deploymnts json and match the protocol and chain to the subgraph URI
        // console.log(Object.keys(deployments))



        const base = `https://api.thegraph.com/subgraphs/name/messari/`;
        const curSubgraphURL = base + currentProtocol + '-' + currentChain;
        const desSubgraphURL = base + requestProtocol + '-' + requestChain;

        console.log(curSubgraphURL, desSubgraphURL)

        const curPositionDataRes = await fetch(curSubgraphURL, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                query: `{
                    marketDailySnapshots(first: 30, orderBy: timestamp, orderDirection: desc, where: {market:"${currentMarketId}"}) {
                                            totalDepositBalanceUSD
                    dailySupplySideRevenueUSD
                    }
                }`
            })
        });
        const curPositionData = await curPositionDataRes.json();

        const positionDesDataRes = await fetch(desSubgraphURL, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                query: `{
                    marketDailySnapshots(first: 30, orderBy: timestamp, orderDirection: desc, where: {market:"${requestMarketId}"}) {
                                            totalDepositBalanceUSD
                    dailySupplySideRevenueUSD
                    }
                }`
            })
        });
        const positionDesData = await positionDesDataRes.json();
        console.log(curPositionData, positionDesData)
        let curROR = [];
        if (curPositionData?.data) curROR = curPositionData.data.marketDailySnapshots.map(ins => (Number(ins.dailySupplySideRevenueUSD) * 365) / Number(ins.totalDepositBalanceUSD) || 0);
        const curMeanROR = curROR.reduce((acc, curr) => acc + curr, 0) / curROR.length;

        const curVariance = curROR.reduce((acc, curr) => acc + Math.pow(curr - curMeanROR, 2), 0) / curROR.length;
        const curStandardDeviation = Math.sqrt(curVariance);

        const curSharpeRatio = (curMeanROR / curStandardDeviation) || -1;

        if (!requestMarketId) return (currentMarketId);

        let desROR = [];
        if (positionDesData?.data) desROR = positionDesData.data.marketDailySnapshots.map(ins => (ins.dailySupplySideRevenueUSD * 365) / ins.totalDepositBalanceUSD);
        const desMeanROR = desROR.reduce((acc, curr) => acc + curr, 0) / desROR.length;

        const desVariance = desROR.reduce((acc, curr) => acc + Math.pow(curr - desMeanROR, 2), 0) / desROR.length;
        const desStandardDeviation = Math.sqrt(desVariance);

        const desSharpeRatio = desMeanROR / desStandardDeviation;
        console.log(desSharpeRatio, curSharpeRatio, curROR)
        if (desSharpeRatio > curSharpeRatio) return (requestMarketId);
    } catch (err) {
        console.log("Error caught - ", err.message);
    }
    return (currentMarketId);
}

// INPUT THE FOLLOWING TO THE ARGUMENT ARRAY IN THE SAME ORDER
// - The current pool ID where deposits are currently located
// - The subgraph slug of the protocol / network that funds are currently deposited
// - The proposed pool ID that the assertion says is a better investment
// - The subgraph slug of the protocol-network that the proposed investment is located

const requestChain = "ethereum"
const requestProtocol = "aave-v3"
const requestMarketId = "0x4d5f47fa6a74757f35c14fd3a6ef8e3c9bc514e8"
const currentChain = "arbitrum"
const currentProtocol = "compound-v3"
const currentMarketId = "0x9c4ec768c28520b50860ea7a15bd7213a9ff58bf82af49447d8a07e3bd95bd0d56f35241523fbab1"
const res = strategyCalculation([requestChain, requestProtocol, requestMarketId, currentChain, currentProtocol, currentMarketId]);
res.then(x => console.log(x))