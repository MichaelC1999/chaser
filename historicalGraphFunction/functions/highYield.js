const curPoolId = args[0];
try {
    const marketTokenAddress = args[3];
    const base = `https://api.thegraph.com/subgraphs/name/messari/`;
    const curSubgraphURL = base + args[1];
    const desSubgraphURL = base + args[2];

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
                markets (where: {inputToken:"${marketTokenAddress}"}) {
                    id
                } 
                \x09\x6D\x61\x72\x6B\x65\x74\x44\x61\x69\x6C\x79\x53\x6E\x61\x70\x73\x68\x6F\x74\x73\x28\x66\x69\x72\x73\x74\x3A\x20\x33\x30\x2C\x20\x6F\x72\x64\x65\x72\x42\x79\x3A\x20\x74\x69\x6D\x65\x73\x74\x61\x6D\x70\x2C\x20\x6F\x72\x64\x65\x72\x44\x69\x72\x65\x63\x74\x69\x6F\x6E\x3A\x20\x64\x65\x73\x63\x2C\x20\x77\x68\x65\x72\x65\x3A\x20\x7B\x6D\x61\x72\x6B\x65\x74\x5F\x3A\x7B\x69\x6E\x70\x75\x74\x54\x6F\x6B\x65\x6E\x3A\x22\x24\x7B\x6D\x61\x72\x6B\x65\x74\x54\x6F\x6B\x65\x6E\x41\x64\x64\x72\x65\x73\x73\x7D\x22\x7D\x7D\x29\x20\x7B\x0A
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

    const desPoolId = positionDesData?.data?.data?.markets?.[0]?.id;
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
