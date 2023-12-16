const strategyCalculation = async (args) => {
    const curPoolId = args[0];
    try {
        const desPoolId = args[2];
        const base = `https://api.thegraph.com/subgraphs/name/messari/`;
        const curSubgraphURL = base + args[1];
        const desSubgraphURL = base + args[3];

        const curPositionDataResponse = await fetch(curSubgraphURL, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                query: `{
                	marketDailySnapshots(first: 30, orderBy: timestamp, orderDirection: desc, where: {market:"${curPoolId}"}) {
                        totalDepositBalanceUSD
                        dailySupplySideRevenueUSD
                    }
                }`
            })
        });
        const curPositionData = await curPositionDataResponse.json();

        const positionDesDataResponse = await fetch(desSubgraphURL, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                query: `{
                	marketDailySnapshots(first: 30, orderBy: timestamp, orderDirection: desc, where: {market:"${desPoolId}"}) {
                        totalDepositBalanceUSD
                        dailySupplySideRevenueUSD
                    }
                }`
            })
        });
        const positionDesData = await positionDesDataResponse.json();

        let currentCumulative = 0;
        let currentRate = 0;
        curPositionData.data.marketDailySnapshots.forEach((instance, index) => {
            const instanceApy = Number(((Number(instance.dailySupplySideRevenueUSD) * 365) / Number(Number(instance.totalDepositBalanceUSD)).toFixed(4)));
            if (instanceApy) {
                currentRate = (currentCumulative + instanceApy) / (index + 1);
                currentCumulative += instanceApy;
            }
        }
        );

        if (!desPoolId) return (curPoolId);
        let destinationCumulative = 0;
        let destinationRate = 0;
        positionDesData.data.marketDailySnapshots.forEach((instance, index) => {
            const instanceApy = Number(((Number(instance.dailySupplySideRevenueUSD) * 365) / Number(Number(instance.totalDepositBalanceUSD)).toFixed(4)));
            if (instanceApy) {
                destinationRate = (destinationCumulative + instanceApy) / (index + 1)
                destinationCumulative += instanceApy;
            }
        }
        );

        console.log(currentRate, destinationRate)

        if (destinationRate > currentRate && destinationRate > 0) return (desPoolId);
        return curPoolId;

    } catch (err) {
        console.log("Error caught - ", err.message);
    }

    return (curPoolId);

}

// INPUT THE FOLLOWING TO THE ARGUMENT ARRAY IN THE SAME ORDER
// - The current pool ID where deposits are currently located
// - The subgraph slug of the protocol / network that funds are currently deposited
// - The proposed pool ID that the assertion says is a better investment
// - The subgraph slug of the protocol-network that the proposed investment is located


// We have the aave-v3-arbitrum WETH market as the current position that our pool has investments in
// The proposal states that the compound-v3-arbitrum WETH market yields a better investment 
// The return valu is the pool id that is a better investment 

strategyCalculation([
    "0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8",
    "aave-v3-arbitrum",
    "0x9c4ec768c28520b50860ea7a15bd7213a9ff58bf82af49447d8a07e3bd95bd0d56f35241523fbab1",
    "compound-v3-arbitrum"
]).then(betterInvestment => console.log(betterInvestment));

