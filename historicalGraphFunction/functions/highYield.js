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
                \x09\x6D\x61\x72\x6B\x65\x74\x44\x61\x69\x6C\x79\x53\x6E\x61\x70\x73\x68\x6F\x74\x73\x28\x66\x69\x72\x73\x74\x3A\x20\x33\x30\x2C\x20\x6F\x72\x64\x65\x72\x42\x79\x3A\x20\x74\x69\x6D\x65\x73\x74\x61\x6D\x70\x2C\x20\x6F\x72\x64\x65\x72\x44\x69\x72\x65\x63\x74\x69\x6F\x6E\x3A\x20\x64\x65\x73\x63\x2C\x20\x77\x68\x65\x72\x65\x3A\x20\x7B\x6D\x61\x72\x6B\x65\x74\x3A\x22\x24\x7B\x63\x75\x72\x50\x6F\x6F\x6C\x49\x64\x7D\x22\x7D\x29\x20\x7B\x0A
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
                \x09\x6D\x61\x72\x6B\x65\x74\x44\x61\x69\x6C\x79\x53\x6E\x61\x70\x73\x68\x6F\x74\x73\x28\x66\x69\x72\x73\x74\x3A\x20\x33\x30\x2C\x20\x6F\x72\x64\x65\x72\x42\x79\x3A\x20\x74\x69\x6D\x65\x73\x74\x61\x6D\x70\x2C\x20\x6F\x72\x64\x65\x72\x44\x69\x72\x65\x63\x74\x69\x6F\x6E\x3A\x20\x64\x65\x73\x63\x2C\x20\x77\x68\x65\x72\x65\x3A\x20\x7B\x6D\x61\x72\x6B\x65\x74\x3A\x22\x24\x7B\x64\x65\x73\x50\x6F\x6F\x6C\x49\x64\x7D\x22\x7D\x29\x20\x7B\x0A
            totalDepositBalanceUSD
            dailySupplySideRevenueUSD
        }
    }`
            })
        });
        const positionDesData = await positionDesDataResponse.json();

        let currentCumulative = 0;
        let currentRate = 0;
        curPositionData.data.data.marketDailySnapshots.forEach((instance, index) => {
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
        positionDesData.data.data.marketDailySnapshots.forEach((instance, index) => {
            const instanceApy = Number(((Number(instance.dailySupplySideRevenueUSD) * 365) / Number(Number(instance.totalDepositBalanceUSD)).toFixed(4)));
            if (instanceApy) {
                destinationRate = (destinationCumulative + instanceApy) / (index + 1)
                destinationCumulative += instanceApy;
            }
        }
        );

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

strategyCalculation([]);
