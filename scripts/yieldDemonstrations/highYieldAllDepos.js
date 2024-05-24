
const strategyCalculation = async () => {

    const url = "https://raw.githubusercontent.com/messari/subgraphs/master/deployment/deployment.json";

    const depos = await fetch(url, {
        method: "get",
        headers: {
            "Content-Type": "application/json",
        }
    })



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
                marketDailySnapshots(first: 90, skip: 1, orderBy: timestamp, orderDirection: desc, where: { market:"'+ marketId + '"}) {   \                                                                                                            \
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

    aavev3["arbitrum"] = {}
    aavev3["arbitrum"]["usdc"] = await fetchAndPrepareData("aave-v3-arbitrum", "0x625e7708f30ca75bfd92586e17077590c60eb4cd")

    aavev3["base"] = {}
    aavev3["base"]["usdc"] = await fetchAndPrepareData("aave-v3-base", "0x4e65fe4dba92790696d040ac24aa414708f5c0ab")

    aavev3["ethereum"] = {}
    aavev3["ethereum"]["usdc"] = await fetchAndPrepareData("aave-v3-ethereum", "0x98c23e9d8f34fefb1b7bd6a91b7ff122f4e16f5c")

    aavev3["optimism"] = {}
    aavev3["optimism"]["usdc"] = await fetchAndPrepareData("aave-v3-optimism", "0x625e7708f30ca75bfd92586e17077590c60eb4cd")

    aavev3["polygon"] = {}
    aavev3["polygon"]["usdc"] = await fetchAndPrepareData("aave-v3-polygon", "0x625e7708f30ca75bfd92586e17077590c60eb4cd")

    compoundv3["ethereum"] = {}
    compoundv3["ethereum"]["usdc"] = await fetchAndPrepareData("compound-v3-ethereum", "0xc3d688b66703497daa19211eedff47f25384cdc3a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")

    compoundv3["arbitrum"] = {}
    compoundv3["arbitrum"]["usdc"] = await fetchAndPrepareData("compound-v3-arbitrum", "0x9c4ec768c28520b50860ea7a15bd7213a9ff58bfaf88d065e77c8cc2239327c5edb3a432268e5831")

    compoundv3["polygon"] = {}
    compoundv3["polygon"]["usdc"] = await fetchAndPrepareData("compound-v3-polygon", "0xf25212e676d1f7f89cd72ffee66158f5412464452791bca1f2de4661ed88a30c99a7a9449aa84174")


    // aavev2["ethereum"] = {}
    // aavev2["ethereum"]["usdc"] = await fetchAndPrepareData("aave-v2-ethereum", "0xbcca60bb61934080951369a648fb03df4f96263c")

    // aavev2["polygon"] = {}
    // aavev2["polygon"]["usdc"] = await fetchAndPrepareData("aave-v2-polygon", "0x1a13f4ca1d028320a707d99520abfefca3998b7f")

    // aavev3["arbitrum"]["dai"] = await fetchAndPrepareData("aave-v3-arbitrum", "0x82e64f49ed5ec1bc6e43dad4fc8af9bb3a2312ee")

    // aavev3["ethereum"]["dai"] = await fetchAndPrepareData("aave-v3-ethereum", "0x018008bfb33d285247a21d44e50697654f754e63")

    // aavev3["optimism"]["dai"] = await fetchAndPrepareData("aave-v3-optimism", "0x82e64f49ed5ec1bc6e43dad4fc8af9bb3a2312ee")

    // aavev3["polygon"]["dai"] = await fetchAndPrepareData("aave-v3-polygon", "0x82e64f49ed5ec1bc6e43dad4fc8af9bb3a2312ee")

    // aavev2["ethereum"]["dai"] = await fetchAndPrepareData("aave-v2-ethereum", "0x028171bca77440897b824ca71d1c56cac55b68a3")

    // aavev2["polygon"]["dai"] = await fetchAndPrepareData("aave-v2-polygon", "0x27f8d03b3a2196956ed754badc28d73be8830a6e")


    const results = { "compound-v3": {}, "aave-v3": {}, "aave-v2": {} }
    const csv = {}

    Object.keys(aavev3).forEach(depo => {
        Object.keys(aavev3[depo]).forEach(asset => {
            csv["aave-v3-" + depo + '-' + asset] = {}
            let curROR = 0;

            if (aavev3[depo][asset]?.data) {
                aavev3[depo][asset].data.marketDailySnapshots.forEach(ins => {
                    const rate = (Number(ins.rates[0].rate))
                    csv["aave-v3-" + depo + '-' + asset][ins.days] = rate
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
            csv["compound-v3-" + depo + '-' + asset] = {}

            let curROR = 0;

            if (compoundv3[depo][asset]?.data) {
                compoundv3[depo][asset].data.marketDailySnapshots.forEach(ins => {
                    const rate = (Number(ins.rates[0].rate))
                    csv["compound-v3-" + depo + '-' + asset][ins.days] = rate

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
            csv["aave-v2-" + depo + '-' + asset] = {}

            let curROR = 0;
            if (aavev2[depo][asset]?.data) {
                aavev2[depo][asset].data.marketDailySnapshots.forEach(ins => {
                    const rate = (Number(ins?.rates[0]?.rate))
                    csv["aave-v2-" + depo + '-' + asset][ins.days] = rate

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
    // csv.chaser = highestRateByDay
    // writeAddressesToFile(JSON.stringify(csv), "json")
    // const csvToSave = jsonToCSV(csv)
    // writeAddressesToFile(csvToSave, "csv")

    console.log("DAILY HIGHEST MEAN: ", highMeanRor / Object.keys(highestRateByDay).length, pivots)

    return best;
}

const res = strategyCalculation();
res.then(x => console.log(x))

function jsonToCSV(json) {
    const indices = new Set();
    const headers = Object.keys(json);

    // Gather all indices and ensure sorting
    headers.forEach(header => {
        Object.keys(json[header]).forEach(index => indices.add(index));
    });
    const sortedIndices = Array.from(indices).sort((a, b) => a - b);

    // Start building the CSV content
    let csvContent = headers.join(',') + '\n';

    // Generate each row based on indices
    sortedIndices.forEach(index => {
        const row = headers.map(header => json[header][index] || '').join(',');
        csvContent += row + '\n';
    });

    return csvContent;
}


function writeAddressesToFile(results, type) {
    const fileName = './scripts/yieldDemonstrations/highYieldAllDeposResults.' + type;

    // Write the merged addresses back to the file
    // fs.writeFileSync(fileName, results, 'utf-8');
    // console.log(`Addresses written to ${fileName}`);
}
