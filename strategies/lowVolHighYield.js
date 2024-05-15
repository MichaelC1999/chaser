//STRATEGY SCRIPT REQUIREMENTS:
// - MUST MAKE QUERIES AGAINST A MESSARI DECENTRALIZED SUBGRAPH
// - MUST TAKE IN ARGUMENTS FOR THE CURRENT MARKET WHERE ASSETS ARE CURRENTLY HELD, AND FOR REQUESTED MARKET TO SWITCH TO
// - MUST INCLUDE A CONFIRMATION OF THE ASSET (MAYBE A HARDCODED MAPPING OF THE ASSET ON EACH SUPPORTED CHAIN)
// - - Market compares input token to supportedChainsAssets
// - WHILE THE WHOLE PURPOSE OF CHASER IS TO TAKE ADVANTAGE OF MARKET FLUCTUATIONS, IT IS RECOMMENDED THAT STRATEGIES ANALYZE DATA OVER LONGER TIME PERIODS
// - STRATEGIES THAT ONLY CONSIDER THE LAST HOUR/DAY/ETC ARE VULNERABLE TO INVESTMENT NO LONGER BEING VIABLE EVEN WHEN ASSERTION SETTLES TO TRUE
// - THE UMA OO CHECKS IF THE ASSERTION THIS STRATEGY MAKES WAS TRUE AT THE TIME OF OPENING, WITHIN THE HOURS BETWEEN THIS AND PIVOT, THIS COULD BECOME UNTRUE
//   (All of the above confirmations are specific to the strategy/pool. Chaser makes its own validation for supported protocols, networks, assets etc)

const strategyCalculation = async (args) => {
    const requestChain = args[0]
    const requestProtocol = args[1]
    const requestMarketId = args[2]
    const currentChain = args[3]
    const currentProtocol = args[4]
    const currentMarketId = args[5]
    if (!requestMarketId) return (false);
    const supportedChainsAssets = {
        "ethereum": "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
        "arbitrum": "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
        "base": "	0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
    }
    try {
        const url = "https://raw.githubusercontent.com/messari/subgraphs/master/deployment/deployment.json";

        const depos = await fetch(url, {
            method: "get",
            headers: {
                "Content-Type": "application/json",
            }
        })

        const deployments = await depos.json()

        const base = "https://api.thegraph.com/subgraphs/name/messari/";
        const curSubgraphURL = base + currentProtocol + '-' + currentChain;
        const desSubgraphURL = base + requestProtocol + '-' + requestChain;

        console.log(curSubgraphURL, desSubgraphURL)

        const curPositionDataRes = await fetch(curSubgraphURL, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                query: '{                                                                                                               \
                    marketDailySnapshots(first: 30, orderBy: timestamp, orderDirection: desc, where: {market:"' + currentMarketId + '"}) {   \
                        totalDepositBalanceUSD                                                                      \
                        dailySupplySideRevenueUSD                                                                                           \
                    }                                                                                                                   \
                }'
            })
        });
        const curPositionData = await curPositionDataRes.json();

        const positionDesDataRes = await fetch(desSubgraphURL, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                query: '{                                                                                                               \
                    marketDailySnapshots(first: 30, orderBy: timestamp, orderDirection: desc, where: {market:"' + requestMarketId + '"}) {   \
                        totalDepositBalanceUSD                                                                      \
                        dailySupplySideRevenueUSD                                                                                           \
                        market {                                                                                                        \
                            inputToken {                                                                                                \
                                id                                                                                                      \
                            }                                                                                                           \
                        }                                                                                                               \
                    }                                                                                                                   \
                }'
            })
        });
        const positionDesData = await positionDesDataRes.json();
        let curROR = [];
        if (curPositionData?.data) curROR = curPositionData.data.marketDailySnapshots.map(ins => (Number(ins.dailySupplySideRevenueUSD) * 365) / Number(ins.totalDepositBalanceUSD) || 0);
        const curMeanROR = curROR.reduce((acc, curr) => acc + curr, 0) / curROR.length;

        const curVariance = curROR.reduce((acc, curr) => acc + Math.pow(curr - curMeanROR, 2), 0) / curROR.length;
        const curStandardDeviation = Math.sqrt(curVariance);

        const curSharpeRatio = (curMeanROR / curStandardDeviation) || -1;

        let desROR = [];
        if (positionDesData?.data) desROR = positionDesData.data.marketDailySnapshots.map(ins => (ins.dailySupplySideRevenueUSD * 365) / ins.totalDepositBalanceUSD);
        const desMeanROR = desROR.reduce((acc, curr) => acc + curr, 0) / desROR.length;

        const desVariance = desROR.reduce((acc, curr) => acc + Math.pow(curr - desMeanROR, 2), 0) / desROR.length;
        const desStandardDeviation = Math.sqrt(desVariance);

        const desSharpeRatio = desMeanROR / desStandardDeviation;
        console.log(desMeanROR, desStandardDeviation, curMeanROR, curStandardDeviation, desSharpeRatio, curSharpeRatio, positionDesData.data.marketDailySnapshots[0].market.inputToken.id)
        if (!Object.values(supportedChainsAssets).map(x => x.toUpperCase()).includes(positionDesData.data.marketDailySnapshots[0].market.inputToken.id.toUpperCase())) {
            console.log('supported assets does not include ' + positionDesData.data.marketDailySnapshots[0].market.inputToken.id)
            return false
        }

        return (desSharpeRatio > curSharpeRatio);
    } catch (err) {
        console.log("Error caught - ", err.message);
        return false;
    }
}

// INPUT THE FOLLOWING TO THE ARGUMENT ARRAY IN THE SAME ORDER
// - The current pool ID where deposits are currently located
// - The subgraph slug of the protocol / network that funds are currently deposited
// - The proposed pool ID that the assertion says is a better investment
// - The subgraph slug of the protocol-network that the proposed investment is located

const requestChain = "arbitrum"
const requestProtocol = "compound-v3"
const requestMarketId = "0x9c4ec768c28520b50860ea7a15bd7213a9ff58bfaf88d065e77c8cc2239327c5edb3a432268e5831"
const currentChain = "ethereum"
const currentProtocol = "aave-v3"
const currentMarketId = "0x98c23e9d8f34fefb1b7bd6a91b7ff122f4e16f5c"
const res = strategyCalculation([requestChain, requestProtocol, requestMarketId, currentChain, currentProtocol, currentMarketId]);
res.then(x => console.log(x))