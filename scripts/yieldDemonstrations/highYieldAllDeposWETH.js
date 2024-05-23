
const strategyCalculation = async () => {

    const highestRateByDay = {}
    const highestRateMarketByDay = {}
    let pivots = 0
    let currentMarket = -1


    const base = "https://api.thegraph.com/subgraphs/name/messari/";

    const aavev3 = {}
    const compoundv3 = {}
    const aavev2 = {}
    const makeQuery = (marketId) => {
        return '{                                                                                                               \
                marketDailySnapshots(first: 35, skip: 1, orderBy: timestamp, orderDirection: desc, where: { market:"'+ marketId + '"}) {   \                                                                                                            \
                    market {                                                                                                        \
                        id                                                                                                          \
                    }                                                                                                                \
                    days                                                                                                                \
                    rates(where: {side: LENDER}) {                                                                                  \
                        side                                                                                                        \
                        rate                                                                                                        \
                    }                                                                                                               \
                }                                                                                                                   \
            }'
    }
    const fetchAndPrepareData = async (protocol, marketId) => {
        let req = await fetch(base + protocol, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                query: makeQuery(marketId)
            })
        });
        try {
            const ret = await req.json();
            return ret
        } catch {
            return {}
        }
    }

    aavev3["arbitrum"] = { weth: null }
    aavev3["arbitrum"]["weth"] = await fetchAndPrepareData("aave-v3-arbitrum", "0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8")

    aavev3["base"] = { weth: null }
    aavev3["base"]["weth"] = await fetchAndPrepareData("aave-v3-base", "0xd4a0e0b9149bcee3c920d2e00b5de09138fd8bb7")

    aavev3["ethereum"] = { weth: null }
    aavev3["ethereum"]["weth"] = await fetchAndPrepareData("aave-v3-ethereum", "0x4d5f47fa6a74757f35c14fd3a6ef8e3c9bc514e8")

    aavev3["optimism"] = { weth: null }
    aavev3["optimism"]["weth"] = await fetchAndPrepareData("aave-v3-optimism", "0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8")

    aavev3["polygon"] = { weth: null }
    aavev3["polygon"]["weth"] = await fetchAndPrepareData("aave-v3-polygon", "0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8")

    compoundv3["ethereum"] = { weth: null }
    compoundv3["ethereum"]["weth"] = await fetchAndPrepareData("compound-v3-ethereum", "0xc3d688b66703497daa19211eedff47f25384cdc3c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2")

    compoundv3["arbitrum"] = { weth: null }
    compoundv3["arbitrum"]["weth"] = await fetchAndPrepareData("compound-v3-arbitrum", "0x9c4ec768c28520b50860ea7a15bd7213a9ff58bf82af49447d8a07e3bd95bd0d56f35241523fbab1")

    compoundv3["polygon"] = { weth: null }
    compoundv3["polygon"]["weth"] = await fetchAndPrepareData("compound-v3-polygon", "0xf25212e676d1f7f89cd72ffee66158f5412464457ceb23fd6bc0add59e62ac25578270cff1b9f619")


    aavev2["ethereum"] = {}
    aavev2["ethereum"]["weth"] = await fetchAndPrepareData("aave-v2-ethereum", "0x030ba81f1c18d280636f32af80b9aad02cf0854e")

    aavev2["polygon"] = {}
    aavev2["polygon"]["weth"] = await fetchAndPrepareData("aave-v2-polygon", "0x28424507fefb6f7f8e9d3860f56504e4e5f5f390")

    // aavev3["arbitrum"]["dai"] = await fetchAndPrepareData("aave-v3-arbitrum", "0x82e64f49ed5ec1bc6e43dad4fc8af9bb3a2312ee")

    // aavev3["ethereum"]["dai"] = await fetchAndPrepareData("aave-v3-ethereum", "0x018008bfb33d285247a21d44e50697654f754e63")

    // aavev3["optimism"]["dai"] = await fetchAndPrepareData("aave-v3-optimism", "0x82e64f49ed5ec1bc6e43dad4fc8af9bb3a2312ee")

    // aavev3["polygon"]["dai"] = await fetchAndPrepareData("aave-v3-polygon", "0x82e64f49ed5ec1bc6e43dad4fc8af9bb3a2312ee")

    // aavev2["ethereum"]["dai"] = await fetchAndPrepareData("aave-v2-ethereum", "0x028171bca77440897b824ca71d1c56cac55b68a3")

    // aavev2["polygon"]["dai"] = await fetchAndPrepareData("aave-v2-polygon", "0x27f8d03b3a2196956ed754badc28d73be8830a6e")


    const results = { "compound-v3": {}, "aave-v3": {}, "aave-v2": {} }

    Object.keys(aavev3).forEach(depo => {
        Object.keys(aavev3[depo]).forEach(asset => {
            let curROR = 0;

            if (aavev3[depo][asset]?.data) {
                aavev3[depo][asset].data.marketDailySnapshots.forEach(ins => {
                    const rate = (Number(ins.rates[0]?.rate)) || 0
                    curROR += rate
                    if (!highestRateByDay[ins.days] || highestRateByDay[ins.days] < rate) {
                        highestRateByDay[ins.days] = rate
                        highestRateMarketByDay[ins.days] = 1

                    }
                });
                const curMeanROR = curROR / aavev3[depo][asset].data.marketDailySnapshots.length;
                if (!results["aave-v3"][depo]) {
                    results["aave-v3"][depo] = {}
                }
                const marketId = aavev3[depo][asset].data.marketDailySnapshots[0].market.id
                results["aave-v3"][depo][marketId] = curMeanROR
            }
        })
    })

    Object.keys(compoundv3).forEach(depo => {
        Object.keys(compoundv3[depo]).forEach(asset => {
            let curROR = 0;

            if (compoundv3[depo][asset]?.data) {
                compoundv3[depo][asset].data.marketDailySnapshots.forEach(ins => {
                    const rate = (Number(ins.rates[0]?.rate)) || 0
                    curROR += rate
                    if (!highestRateByDay[ins.days] || highestRateByDay[ins.days] < rate) {
                        highestRateByDay[ins.days] = rate
                        highestRateMarketByDay[ins.days] = 1

                    }
                });
                const curMeanROR = curROR / compoundv3[depo][asset].data.marketDailySnapshots.length;

                if (!results["compound-v3"][depo]) {
                    results["compound-v3"][depo] = {}
                }
                const marketId = compoundv3[depo][asset].data.marketDailySnapshots[0].market.id

                results["compound-v3"][depo][marketId] = curMeanROR
            }
        })
    })

    Object.keys(aavev2).forEach(depo => {
        Object.keys(aavev2[depo]).forEach(asset => {
            let curROR = 0;
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
                if (!results["aave-v2"][depo]) {
                    results["aave-v2"][depo] = {}
                }
                const marketId = aavev2[depo][asset].data.marketDailySnapshots[0].market.id

                results["aave-v2"][depo][marketId] = curMeanROR
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

    const best = { protocol: "", depo: "", market: "", yield: "" }
    console.log(results)

    Object.keys(results).forEach(protocol => {
        Object.keys(results[protocol]).forEach(depo => {
            Object.keys(results[protocol][depo]).forEach(market => {
                console.log(protocol, depo, market, results[protocol][depo][market])
                if (results[protocol][depo][market] > (results[best?.protocol]?.[best?.depo]?.[best?.market] || 0)) {
                    best.protocol = protocol
                    best.depo = depo
                    best.market = market
                    best.yield = results[protocol][depo][market]
                }
            })

        })
    })

    console.log("DAILY HIGHEST MEAN: ", highMeanRor / Object.keys(highestRateByDay).length, pivots)
    return best;
}

const res = strategyCalculation();
res.then(x => console.log(x))