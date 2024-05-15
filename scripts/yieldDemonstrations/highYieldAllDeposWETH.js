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
    // try {
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

    const highestRateByDay = {}
    const highestRateMarketByDay = {}
    let pivots = 0
    let currentMarket = -1


    const base = "https://api.thegraph.com/subgraphs/name/messari/";
    const curSubgraphURL = base + currentProtocol + '-' + currentChain;
    const desSubgraphURL = base + requestProtocol + '-' + requestChain;

    console.log(curSubgraphURL, desSubgraphURL)
    const aavev3 = {}
    const compoundv3 = {}
    const aavev2 = {}
    const makeQuery = (marketId) => {
        return '{                                                                                                               \
                marketDailySnapshots(first: 90, orderBy: timestamp, orderDirection: desc, where: { market:"'+ marketId + '"}) {   \                                                                                                            \
                    days                                                                                                                \
                    rates(where: {side: LENDER}) {                                                                                  \
                        side                                                                                                        \
                        rate                                                                                                        \
                    }                                                                                                               \
                }                                                                                                                   \
            }'
    }

    let aavev3arbitrum = await fetch(base + "aave-v3-arbitrum", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            query: makeQuery("0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8")
        })
    });
    aavev3["arbitrum"] = { weth: null }
    aavev3["arbitrum"]["weth"] = await aavev3arbitrum.json();

    let aavev3base = await fetch(base + "aave-v3-base", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            query: makeQuery("0xd4a0e0b9149bcee3c920d2e00b5de09138fd8bb7")
        })
    });
    aavev3["base"] = { weth: null }
    aavev3["base"]["weth"] = await aavev3base.json();

    let aavev3ethereum = await fetch(base + "aave-v3-ethereum", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            query: makeQuery("0x4d5f47fa6a74757f35c14fd3a6ef8e3c9bc514e8")
        })
    });
    aavev3["ethereum"] = { weth: null }
    aavev3["ethereum"]["weth"] = await aavev3ethereum.json();

    let aavev3optimism = await fetch(base + "aave-v3-optimism", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            query: makeQuery("0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8")
        })
    });
    aavev3["optimism"] = { weth: null }
    aavev3["optimism"]["weth"] = await aavev3optimism.json();

    let aavev3polygon = await fetch(base + "aave-v3-polygon", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            query: makeQuery("0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8")
        })
    });
    aavev3["polygon"] = { weth: null }
    aavev3["polygon"]["weth"] = await aavev3polygon.json();

    let compoundv3ethereum = await fetch(base + "compound-v3-ethereum", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            query: makeQuery("0xc3d688b66703497daa19211eedff47f25384cdc3c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2")
        })
    });
    compoundv3["ethereum"] = { weth: null }
    compoundv3["ethereum"]["weth"] = await compoundv3ethereum.json();

    let compoundv3arbitrum = await fetch(base + "compound-v3-arbitrum", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            query: makeQuery("0x9c4ec768c28520b50860ea7a15bd7213a9ff58bf82af49447d8a07e3bd95bd0d56f35241523fbab1")
        })
    });
    compoundv3["arbitrum"] = { weth: null }
    compoundv3["arbitrum"]["weth"] = await compoundv3arbitrum.json();

    let compoundv3polygon = await fetch(base + "compound-v3-polygon", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            query: makeQuery("0xf25212e676d1f7f89cd72ffee66158f5412464457ceb23fd6bc0add59e62ac25578270cff1b9f619")
        })
    });
    compoundv3["polygon"] = { weth: null }
    compoundv3["polygon"]["weth"] = await compoundv3polygon.json();


    let aavev2ethereum = await fetch(base + "aave-v2-ethereum", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            query: makeQuery("0x030ba81f1c18d280636f32af80b9aad02cf0854e")
        })
    });
    aavev2["ethereum"] = { weth: null }
    aavev2["ethereum"]["weth"] = await aavev2ethereum.json();


    let aavev2polygon = await fetch(base + "aave-v2-polygon", {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
        },
        body: JSON.stringify({
            query: makeQuery("0x28424507fefb6f7f8e9d3860f56504e4e5f5f390")
        })
    });
    aavev2["polygon"] = { weth: null }
    aavev2["polygon"]["weth"] = await aavev2polygon.json();


    const results = { compoundv3: {}, aavev3: {}, aavev2: {} }

    Object.keys(aavev3).forEach(depo => {
        Object.keys(aavev3[depo]).forEach(asset => {
            let curROR = 0;
            console.log('aavev3', depo, asset)
            if (aavev3[depo][asset]?.data) {
                aavev3[depo][asset].data.marketDailySnapshots.forEach(ins => {
                    const rate = (Number(ins?.rates[0]?.rate))
                    if (rate) {
                        curROR += rate
                        if (!highestRateByDay[ins.days] || highestRateByDay[ins.days] < rate) {
                            highestRateByDay[ins.days] = rate
                            highestRateMarketByDay[ins.days] = 1

                        }

                    }
                });
                const curMeanROR = curROR / aavev3[depo][asset].data.marketDailySnapshots.length;
                console.log(curROR, 1, results["aavev3"][depo], 'krkakakak')
                if (!results["aavev3"][depo]) {
                    results["aavev3"][depo] = {}
                }
                results["aavev3"][depo][asset] = curMeanROR
            }
        })
    })

    Object.keys(compoundv3).forEach(depo => {
        Object.keys(compoundv3[depo]).forEach(asset => {
            let curROR = 0;
            console.log('comp', depo, asset)
            if (compoundv3[depo][asset]?.data) {

                compoundv3[depo][asset].data.marketDailySnapshots.forEach(ins => {
                    const rate = (Number(ins?.rates[0]?.rate))
                    if (rate) {
                        curROR += rate
                        if (!highestRateByDay[ins.days] || highestRateByDay[ins.days] < rate) {
                            highestRateByDay[ins.days] = rate
                            highestRateMarketByDay[ins.days] = 1

                        }

                    }
                });
                const curMeanROR = curROR / compoundv3[depo][asset].data.marketDailySnapshots.length;

                console.log(curROR, 1, results["compoundv3"][depo], 'krkakakak')
                if (!results["compoundv3"][depo]) {
                    results["compoundv3"][depo] = {}
                }
                results["compoundv3"][depo][asset] = curMeanROR
            }
        })
    })

    Object.keys(aavev2).forEach(depo => {
        Object.keys(aavev2[depo]).forEach(asset => {
            let curROR = 0;
            console.log('aavev2', depo, asset)
            if (aavev2[depo][asset]?.data) {
                aavev2[depo][asset].data.marketDailySnapshots.forEach(ins => {
                    const rate = (Number(ins?.rates[0]?.rate))
                    if (rate) {
                        curROR += rate
                        if (!highestRateByDay[ins.days] || highestRateByDay[ins.days] < rate) {
                            highestRateByDay[ins.days] = rate
                            highestRateMarketByDay[ins.days] = 1

                        }

                    }
                });
                const curMeanROR = curROR / aavev2[depo][asset].data.marketDailySnapshots.length;
                console.log(curROR, 1, results["aavev2"][depo], 'krkakakak')
                if (!results["aavev2"][depo]) {
                    results["aavev2"][depo] = {}
                }
                results["aavev2"][depo][asset] = curMeanROR
            }
        })
    })



    highMeanRor = 0
    Object.values(highestRateByDay).forEach(x => highMeanRor += x)

    let lastMarket = ""
    Object.values(highestRateMarketByDay).forEach((x) => {
        if (x !== lastMarket) {
            pivots += 1
        }
        lastMarket = x
    })

    console.log(results)

    console.log("DAILY HIGHEST MEAN: ", highMeanRor / Object.keys(highestRateByDay).length, pivots)


    // } catch (err) {
    //     console.log("Error caught - ", err.message);
    // }
    return false;
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