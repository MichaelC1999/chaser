
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
    const prepareData = async (protocol, network, data, isSecondary) => {
        const base = "https://api.thegraph.com/subgraphs/name/messari/";
        let query = ''
        if (isSecondary) {
            query = makeSecondaryQuery(data)
        } else {
            query = makeQuery(data)
        }
        try {
            let req = await fetch(base + protocol + '-' + network, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                },
                body: JSON.stringify({ query })
            });
            const json = await req.json()
            return { ...json?.data, depo: protocol + "-" + network } || {};
        } catch (err) {
            console.log(err)
        }
    }

    const makeQuery = (marketId) => {
        return '{\
            positions(\
              orderBy: balance\
              orderDirection: desc\
              first: 200\
              where: {market: "'+ marketId + '", side: "COLLATERAL", hashClosed: null, account_: {openPositionCount_gt: 0}}\
            ) {\
              balance\
              hashClosed\
              type\
              side\
                  account {\
                id\
              }    type\
              asset {\
                id\
                name\
                lastPriceUSD\
                decimals\
              }\
            }\
            market(id: "'+ marketId + '") {\
                id\
                inputToken {\
                    id\
                  }\
                  totalValueLockedUSD\
                  rates {\
                    rate\
                    side\
                    type\
                  }\
                name\
                liquidationThreshold\
                maximumLTV\
              }\
          }'
    }

    const makeSecondaryQuery = (accounts) => {
        const accountsList = accounts.map(x => '"' + x + '"')
        return '{\
            BORROWS: positions(\
                orderBy: balance\
                orderDirection: desc\
                first: 1000\
                where: {account_in: ['+ accountsList.join(",") + '], side: "BORROWER", hashClosed: null, account_: {openPositionCount_gt: 0}}\
              ) {\
                    account {\
                  id\
                }\
                balance\
                hashClosed\
                type\
                side\
                type\
                asset {\
                  id\
                  name\
                  lastPriceUSD\
                  decimals\
                }\
              }\
            COLLATERALS: positions(\
                orderBy: balance\
                orderDirection: desc\
                first: 1000\
                where: {account_in: ['+ accountsList.join(",") + '], side: "COLLATERAL", hashClosed: null, account_: {openPositionCount_gt: 0}}\
              ) {\
                    account {\
                  id\
                }\
                balance\
                hashClosed\
                type\
                side\
                type\
                asset {\
                  id\
                  name\
                  lastPriceUSD\
                  decimals\
                }\
              }\
        }'
    }

    function calculateWeightedAverageRisk(data) {
        let totalRiskCollateral = 0;
        let totalCollateral = 0;

        data.forEach(item => {
            if (item.risk * item.collateral) {
                totalRiskCollateral += item.risk * item.collateral;
            }
            totalCollateral += item.collateral;
        });
        if (!totalRiskCollateral / totalCollateral) {
        }
        return totalRiskCollateral / totalCollateral;
    }

    // Calculate the total amount of 'collateral' for objects with 'risk' above 0.5
    function calculateTotalCollateralAboveThreshold(data, threshold = 0.5) {
        return data
            .filter(item => item.risk > threshold)
            .reduce((total, item) => total + item.collateral, 0);
    }

    const marketData = {}
    aavev3["arbitrum"] = {}
    aavev3["arbitrum"]["weth"] = await prepareData("aave-v3", "arbitrum", "0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8", false)
    marketData["aave-v3-arbitrum"] = aavev3["arbitrum"]["weth"].market
    aavev3["base"] = {}
    aavev3["base"]["weth"] = await prepareData("aave-v3", "base", "0xd4a0e0b9149bcee3c920d2e00b5de09138fd8bb7", false)
    marketData["aave-v3-base"] = aavev3["base"]["weth"].market
    aavev3["ethereum"] = {}
    aavev3["ethereum"]["weth"] = await prepareData("aave-v3", "ethereum", "0x4d5f47fa6a74757f35c14fd3a6ef8e3c9bc514e8", false)
    marketData["aave-v3-ethereum"] = aavev3["ethereum"]["weth"].market
    aavev3["optimism"] = {}
    aavev3["optimism"]["weth"] = await prepareData("aave-v3", "optimism", "0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8", false)
    marketData["aave-v3-optimism"] = aavev3["optimism"]["weth"].market
    aavev3["polygon"] = {}
    aavev3["polygon"]["weth"] = await prepareData("aave-v3", "polygon", "0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8", false)
    marketData["aave-v3-polygon"] = aavev3["polygon"]["weth"].market
    compoundv3["ethereum"] = {}
    compoundv3["ethereum"]["weth"] = await prepareData("compound-v3", "ethereum", "0xc3d688b66703497daa19211eedff47f25384cdc3c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", false)
    marketData["compound-v3-ethereum"] = compoundv3["ethereum"]["weth"].market
    compoundv3["arbitrum"] = {}
    compoundv3["arbitrum"]["weth"] = await prepareData("compound-v3", "arbitrum", "0x9c4ec768c28520b50860ea7a15bd7213a9ff58bf82af49447d8a07e3bd95bd0d56f35241523fbab1", false)
    marketData["compound-v3-arbitrum"] = compoundv3["arbitrum"]["weth"].market
    compoundv3["polygon"] = {}
    compoundv3["polygon"]["weth"] = await prepareData("compound-v3", "polygon", "0xf25212e676d1f7f89cd72ffee66158f5412464457ceb23fd6bc0add59e62ac25578270cff1b9f619", false)
    marketData["compound-v3-polygon"] = compoundv3["polygon"]["weth"].market


    const results = { "compound-v3": {}, "aave-v3": {} }
    const csv = {}

    const secondaryPrepares = []
    Object.keys(aavev3).forEach(depo => {
        Object.keys(aavev3[depo]).forEach(asset => {
            csv["aave-v3-" + depo + '-' + asset] = {}
            let curROR = 0;

            if (aavev3[depo][asset]) {
                const collateralAccounts = {}
                // console.log(desPositionDatapositions.map(x => x.positions.account.id))
                aavev3[depo][asset].positions.forEach(collateralPosition => {
                    collateralAccounts[collateralPosition.account.id] = 0
                })
                secondaryPrepares.push(prepareData("aave-v3", depo, Object.keys(collateralAccounts), true))
            }
        })
    })



    Object.keys(compoundv3).forEach(depo => {
        Object.keys(compoundv3[depo]).forEach(asset => {
            csv["compound-v3-" + depo + '-' + asset] = {}

            let curROR = 0;

            if (compoundv3[depo][asset]) {
                const collateralAccounts = {}
                // console.log(desPositionDatapositions.map(x => x.positions.account.id))
                compoundv3[depo][asset].positions.forEach(collateralPosition => {
                    collateralAccounts[collateralPosition.account.id] = 0
                })
                secondaryPrepares.push(prepareData("compound-v3", depo, Object.keys(collateralAccounts), true))
            }
        })
    })

    const risk = {}
    const positionalData = await Promise.all(secondaryPrepares)
    positionalData.forEach(market => {
        const collateralAccounts = {}
        const borrowAccounts = {}
        market.BORROWS.forEach(position => {
            let currentVal = borrowAccounts[position.account.id] || 0
            borrowAccounts[position.account.id] = currentVal + (Number(position.balance) / (10 ** Number(position.asset.decimals))) * Number(position.asset.lastPriceUSD)
        })
        market.COLLATERALS.forEach(position => {
            let currentVal = collateralAccounts[position.account.id] || 0
            collateralAccounts[position.account.id] = currentVal + (Number(position.balance) / (10 ** Number(position.asset.decimals))) * Number(position.asset.lastPriceUSD)
        })

        const marketId = market.depo
        risk[marketId] = Object.keys(borrowAccounts).map(x => ({ "account": x, borrow: borrowAccounts[x], collateral: collateralAccounts[x], risk: borrowAccounts[x] / (collateralAccounts[x] / 100 * Number(marketData[marketId].liquidationThreshold)) }))
        const weightedAverageRisk = calculateWeightedAverageRisk(risk[marketId]);
        const totalCollateralAboveThreshold = calculateTotalCollateralAboveThreshold(risk[marketId]);
        risk[marketId] = { weightedAverageRisk, totalCollateralAboveThreshold, atRiskRatio: totalCollateralAboveThreshold / marketData[marketId].totalValueLockedUSD }

    })

    console.log(risk)


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
    // console.log(results)

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

    return best;
}

const res = strategyCalculation();
res.then(x => console.log(x))


