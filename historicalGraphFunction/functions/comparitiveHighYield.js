const strategyCalculation = async (args) => {

    //Asset address by chain
    //Subgraph slug by chain
    //query to subgraph for each chain, getting the market where asset is input token
    //Get yield for each of these markets over 21 days period

    //Indexes in each array correspond. assets[0] is the asset of the market to lookup on subgraph with slug networkSlugs[0] 
    const networkSlugs = args[0]
    const assets = args[1]

    try {

        const reqs = [];
        networkSlugs.forEach((slug, idx) => {
            const URI = `https://api.thegraph.com/subgraphs/name/messari/` + slug;

            const fetchForNetwork = fetch(URI, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                },
                body: JSON.stringify({
                    query: `{
                        protocols {
                            slug
                            network
                        }
                        marketDailySnapshots(first: 21, orderBy: timestamp, orderDirection: desc, where: {market_: {inputToken: "${assets[idx]}"}}) {
                            totalDepositBalanceUSD
                            dailySupplySideRevenueUSD
                        }
                    }`
                })
            });

            reqs.push(fetchForNetwork)
        })

        const resps = await Promise.all(reqs)

        const jsonResp = resps.map(response => response.json())

        const data = await Promise.all(jsonResp)

        const marketMetrics = {}

        data.forEach((curPositionData, idx) => {
            if (curPositionData?.data) {
                console.log(curPositionData)
                let currentCumulative = 0;
                let currentRate = 0;
                curPositionData.data.marketDailySnapshots.forEach((instance, index) => {
                    const instanceApy = Number(((Number(instance.dailySupplySideRevenueUSD) * 365) / Number(Number(instance.totalDepositBalanceUSD)).toFixed(4)));
                    if (instanceApy) {
                        currentRate = (currentCumulative + instanceApy) / (index + 1);
                        currentCumulative += instanceApy;
                    }
                });
                marketMetrics[networkSlugs[idx]] = currentRate * 100
            }
        })

        const sorted = sortByLowestYield(marketMetrics)
        console.log(marketMetrics, sorted)

        return sorted[0]
    } catch (err) {
        console.log("Error caught - ", err.message);
    }
}

function sortByLowestYield(obj) {
    const entries = Object.keys(obj);
    const sortedEntries = entries.sort((a, b) => obj[b] - obj[a]);
    return sortedEntries;
}

// THE ASSERTION WILL HAVE THE INPUTS PREPARED FOR DISPUTERS
// args[0] is an array of subgraph slugs representing the aave deployments of different networks
// args[1] is an array of ERC20 addresses pointing to the asset of a market on the deployment with corresponding index 

strategyCalculation([
    ["aave-v3-base", "aave-v3-arbitrum", "aave-v3-ethereum", "aave-v3-optimism", "aave-v3-polygon"],
    ["0x4200000000000000000000000000000000000006", "0x82af49447d8a07e3bd95bd0d56f35241523fbab1", "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", "0x4200000000000000000000000000000000000006"]
]).then(betterInvestment => console.log("The market on " + betterInvestment + " has the best yield over the last 21 days for the given filters."));

