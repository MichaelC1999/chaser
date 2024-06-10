const prepareData = async (protocol, network, marketId) => {
    const base = "https://api.thegraph.com/subgraphs/name/messari/";

    const makeQuery = (marketId) => {
        return '{\
            marketDailySnapshots(first: 365, skip: 1, orderBy: timestamp, orderDirection: desc, where: { market:"' + marketId + '"}) {\
                borrowingPositionCount\
                closedPositionCount\
                dailyBorrowCount\
                dailyBorrowUSD\
                dailyActiveDepositors\
                dailyActiveBorrowers\
                dailyLiquidateCount\
                dailyLiquidateUSD\
                dailyDepositUSD\
                dailyDepositCount\
                dailyTotalRevenueUSD\
                dailySupplySideRevenueUSD\
                dailyProtocolSideRevenueUSD\
                dailyRepayCount\
                dailyWithdrawCount\
                dailyWithdrawUSD\
                days\
                id\
                inputTokenBalance\
                inputTokenPriceUSD\
                lendingPositionCount\
                openPositionCount\
                outputTokenSupply\
                totalBorrowBalanceUSD\
                totalDepositBalanceUSD\
                totalValueLockedUSD\
                rates {\
                    rate\
                    side\
                    type\
                }\
            }\
            market(id:"'+ marketId + '") {\
                inputToken {\
                    id\
                }\
                totalValueLockedUSD\
                rates {\
                    rate\
                    side\
                    type\
                }\
                cumulativeBorrowUSD\
                cumulativeDepositUSD\
                cumulativeLiquidateUSD\
                cumulativeProtocolSideRevenueUSD\
                cumulativeSupplySideRevenueUSD\
                cumulativeTotalRevenueUSD\
                cumulativeTransferUSD\
                cumulativeUniqueBorrowers\
                cumulativeUniqueDepositors\
                cumulativeUniqueFlashloaners\
                cumulativeUniqueLiquidatees\
                cumulativeUniqueLiquidators\
                cumulativeUniqueTransferrers\
                cumulativeUniqueUsers\
                depositCount\
                inputTokenBalance\
                inputTokenPriceUSD\
                isActive\
                liquidationCount\
                lendingPositionCount\
                liquidationThreshold\
                maximumLTV\
                openPositionCount\
                outputTokenSupply\
                totalBorrowBalanceUSD\
                totalDepositBalanceUSD\
                transactionCount\
                withdrawCount\
            }\
        }';
    }

    let query = makeQuery(marketId);

    try {
        let req = await fetch(base + protocol + '-' + network, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
            },
            body: JSON.stringify({ query })
        });
        const json = await req.json();
        return json?.data || {};
    } catch (err) {
        console.log(err);
    }
}

const getReturnRate = (positionData) => {
    let ror = [];
    if (positionData) {
        ror = positionData.marketDailySnapshots.map(ins => (Number(ins.dailySupplySideRevenueUSD) * 365) / Number(ins.totalDepositBalanceUSD) || 0);
    }
    const meanROR = ror.reduce((acc, curr) => acc + curr, 0) / ror.length;
    const variance = ror.reduce((acc, curr) => acc + Math.pow(curr - meanROR, 2), 0) / ror.length;
    const standardDeviation = Math.sqrt(variance);
    return meanROR / standardDeviation || -1;
}

const checkConditions = async (positionData, protocol, chain, marketId) => {
    const supportedChainsAssets = {
        "ethereum": ["0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"],
        "base": ["0x4200000000000000000000000000000000000006"],
        "optimism": ["0x4200000000000000000000000000000000000006"],
        "arbitrum": ["0x82af49447d8a07e3bd95bd0d56f35241523fbab1"]
    }

    if (!supportedChainsAssets[chain].includes(positionData.market.inputToken.id)) {
        return false;
    }

    return true;
}

const strategyCalculation = async () => {
    const TESTNET_ANALOG_MARKETS = {
        '0x61490650abaa31393464c3f34e8b29cd1c44118ee4ab69c077896252fafbd49efd26b5d171a32410': "0x46e6b214b524310239732d51387075e0e70970bf4200000000000000000000000000000000000006",
        '0x2943ac1216979ad8db76d9147f64e61adc126e96e4ab69c077896252fafbd49efd26b5d171a32410': "0xa17581a9e3356d9a858b789d68b4d866e593ae94c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
        '0x96e32de4b1d1617b8c2ae13a88b9cc287239b13f': "0xd4a0e0b9149bcee3c920d2e00b5de09138fd8bb7",
        '0x5b071b590a59395fE4025A0Ccc1FcC931AAc1830': "0x4d5f47fa6a74757f35c14fd3a6ef8e3c9bc514e8",
        "0xf5f17EbE81E516Dc7cB38D61908EC252F150CE60": "0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8",
        "0x23e4E76D01B2002BE436CE8d6044b0aA2f68B68a": "0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8"
    }

    const networks = {
        "11155111": "ethereum",
        "84532": "base",
        "11155420": "optimism",
        "421614": "arbitrum"
    }

    const curChain = networks[process.argv[2]]
    const desChain = networks[process.argv[3]]
    const curMarketId = TESTNET_ANALOG_MARKETS[process.argv[4]] || process.argv[4]
    const desMarketId = TESTNET_ANALOG_MARKETS[process.argv[5]] || process.argv[5]
    const curProtocol = process.argv[6]
    const desProtocol = process.argv[7]

    if (!desMarketId) return (false);

    try {
        const curPositionData = await prepareData(curProtocol, curChain, curMarketId);
        const desPositionData = await prepareData(desProtocol, desChain, desMarketId);

        const desConditionsMet = await checkConditions(desPositionData, desProtocol, desChain, desMarketId);
        if (!desConditionsMet) return false;

        const curSharpeRatio = getReturnRate(curPositionData);
        const desSharpeRatio = getReturnRate(desPositionData);

        console.log(desSharpeRatio, curSharpeRatio);

        return (desSharpeRatio > curSharpeRatio);
    } catch (err) {
        console.log("Error caught - ", err.message);
        return false;
    }
}

strategyCalculation().then(x => console.log(x));

// Export functions for use in the monitor bot
module.exports = {
    getReturnRate,
    checkConditions
};
