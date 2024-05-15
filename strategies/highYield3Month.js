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
        // From this JSON get the decentralized network query id

        // console.log(Object.keys(deployments))



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
                    marketDailySnapshots(first: 90, orderBy: timestamp, orderDirection: desc, where: {market:"' + currentMarketId + '"}) {   \
                        market {                                                                                                        \
                            inputToken {                                                                                                \
                                id                                                                                                      \
                            }                                                                                                           \
                        }                                                                                                               \
                        rates(where: {side: LENDER}) {                                                                                  \
                            side                                                                                                        \
                            rate                                                                                                        \
                        }                                                                                                               \
                    }                                                                                                                   \
                }'
            })
        });
        const curPositionData = await curPositionDataRes.json();

        const desPositionDataRes = await fetch(desSubgraphURL, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                query: '{                                                                                                                   \
                    marketDailySnapshots(first: 90, orderBy: timestamp, orderDirection: desc, where: {market:"' + requestMarketId + '"}) {       \
                        market {                                                                                                            \
                            inputToken {                                                                                                    \
                                id                                                                                                          \
                            }                                                                                                               \
                        }                                                                                                                   \
                        rates(where: {side: LENDER}) {                                                                                      \
                            side                                                                                                            \
                            rate                                                                                                            \
                        }                                                                                                                   \
                    }                                                                                                                       \
                }'
            })
        });
        const desPositionData = await desPositionDataRes.json();
        console.log(curPositionData.data.marketDailySnapshots, desPositionData.data.marketDailySnapshots)


        let curROR = 0;
        if (curPositionData?.data) {
            curPositionData.data.marketDailySnapshots.forEach(ins => {
                curROR += (Number(ins.rates[0].rate))
            });
        }
        const curMeanROR = curROR / curPositionData.data.marketDailySnapshots.length;
        // console.log(curMeanROR, '/', curPositionData.data.marketDailySnapshots[0].market.rates[0].rate)

        let desROR = 0;
        if (desPositionData?.data) {
            desPositionData.data.marketDailySnapshots.forEach(ins => {
                desROR += (Number(ins.rates[0].rate))
            });
        }
        const desMeanROR = desROR / desPositionData.data.marketDailySnapshots.length;
        // console.log(desMeanROR, '/', desPositionData.data.marketDailySnapshots[0].market.rates[0].rate)
        console.log(desPositionData.data.marketDailySnapshots[0].market)
        if (!Object.values(supportedChainsAssets).map(x => x.toUpperCase()).includes(desPositionData.data.marketDailySnapshots[0].market.inputToken.id.toUpperCase())) return false

        return (desMeanROR > curMeanROR);
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

const requestChain = "ethereum"
const requestProtocol = "aave-v3"
const requestMarketId = "0x98c23e9d8f34fefb1b7bd6a91b7ff122f4e16f5c"
const currentChain = "arbitrum"
const currentProtocol = "compound-v3"
const currentMarketId = "0x9c4ec768c28520b50860ea7a15bd7213a9ff58bfaf88d065e77c8cc2239327c5edb3a432268e5831"
const res = strategyCalculation([requestChain, requestProtocol, requestMarketId, currentChain, currentProtocol, currentMarketId]);
res.then(x => console.log(x))