const strategyCalculation = async () => {
    // This object converts Sepolia/Base testnet markets to their mainnet addresses for the subgraph query
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
    const reqChain = networks[process.argv[3]]
    const curMarketId = TESTNET_ANALOG_MARKETS[process.argv[4]] || process.argv[4]
    const reqMarketId = TESTNET_ANALOG_MARKETS[process.argv[5]] || process.argv[5]
    const curProtocol = process.argv[6]
    const reqProtocol = process.argv[7]

    if (!reqMarketId) return (false);

    const prepareData = async (protocol, network, marketId) => {
        const base = "https://api.thegraph.com/subgraphs/name/messari/";

        let req = await fetch(base + protocol + '-' + network, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                query: makeQuery(marketId)
            })
        });
        return (await req.json())?.data || {};
    }

    const makeQuery = (marketId) => {
        return '{\
marketDailySnapshots(first: 365, skip: 1, orderBy: timestamp, orderDirection: desc, where: { market:"' + marketId + '"}) {   \                                                                                                            \
    dailyTotalRevenueUSD\
    dailySupplySideRevenueUSD\
    dailyProtocolSideRevenueUSD\
    days\
    id\
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
    depositCount\
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
}}'
    }

    try {

        // EDIT THIS OBJECT TO HAVE THE ADDRESSES OF THE ASSETS THAT YOUR STRATEGY SUPPORTS ON EACH CHAIN. 
        // example - if your strategy is only for stable coins on Base and Arbitrum, make the "arbitrum" value an array of USDC, DAI, USDT addresses on Arbitrum 
        const supportedChainsAssets = {
            "ethereum": ["0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"],
            "base": ["0x4200000000000000000000000000000000000006"],
            "optimism": ["0x4200000000000000000000000000000000000006"],
            "arbitrum": ["0x82af49447d8a07e3bd95bd0d56f35241523fbab1"]
        }

        const supportedProtocols = ["aave-v3", "aave-v2", "compound-v3"]

        if (!supportedProtocols.includes(reqProtocol)) {
            return false
        }

        const curPositionData = await prepareData(curProtocol, curChain, curMarketId);
        const desPositionData = await prepareData(reqProtocol, reqChain, reqMarketId);

        if (!supportedChainsAssets[reqChain].includes(desPositionData.market.inputToken.id)) {
            return false
        }

        // BEGIN CUSTOMIZABLE SECTION - THIS IS WHERE YOU WRITE YOUR CUSTOM STRATEGY LOGIC
        // Read the Chaser docs for requirements and instructions for writing a custom strategy

        let curROR = 0;
        if (curPositionData) {
            curPositionData.marketDailySnapshots.forEach(ins => {
                curROR += (Number(ins.rates[0].rate))
            });
        }
        const curMeanROR = curROR / curPositionData.marketDailySnapshots.length;

        let desROR = 0;
        if (desPositionData) {
            desPositionData.marketDailySnapshots.forEach(ins => {
                desROR += (Number(ins.rates[0].rate))
            });
        }
        const desMeanROR = desROR / desPositionData.marketDailySnapshots.length;

        console.log(curMeanROR, desMeanROR)

        return (desMeanROR > curMeanROR);
        // END CUSTOMIZABLE SECTION
    } catch (err) {
        console.log("Error caught - ", err.message);
        return false;
    }
}

strategyCalculation().then(x => console.log(x));
