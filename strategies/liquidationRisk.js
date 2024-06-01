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
            return json?.data || {};
        } catch (err) {
            console.log(err)
        }
    }

    const makeQuery = (marketId) => {
        return '{\
            positions(\
              orderBy: balance\
              orderDirection: desc\
              first: 100\
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
                  rates(where: {side: "LENDER"}) {\
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
        console.log('reached', accounts.length)
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
        return totalRiskCollateral / totalCollateral;
    }

    // Calculate the total amount of 'collateral' for objects with 'risk' above 0.5
    function calculateTotalCollateralAboveThreshold(data, threshold = 0.5) {
        return data
            .filter(item => item.risk > threshold)
            .reduce((total, item) => total + item.collateral, 0);
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

        const curPositionData = await prepareData(curProtocol, curChain, curMarketId, false);
        const desPositionData = await prepareData(reqProtocol, reqChain, reqMarketId, false);

        if (!supportedChainsAssets[reqChain].includes(desPositionData.market.inputToken.id)) {
            return false
        }

        // BEGIN CUSTOMIZABLE SECTION - THIS IS WHERE YOU WRITE YOUR CUSTOM STRATEGY LOGIC
        // Read the Chaser docs for requirements and instructions for writing a custom strategy
        // const accounts = ["0xce672de0d2d38944716c21bca7db1164685af2ac", "0x7444efd31d6d451372fdd340de3612be7679fabd", "0x2d25167fc9f981a43c4acaf507eb68472fe13bf7", "0x81f01fed84a5bb03813aade01c6182a0ad8e57f6", "0x19cb448123e74b07a1c04533165915dcd782d4ca", "0x297044775948f17148814f959b42915fd8502089", "0xf36e0f6989353d115862220112c3c05db7833754", "0x8d3771b0913497d4492d6444f50b9e4872cb4238", "0xd2f02b8edaf9d8768c34e3001295015d935279c4", "0x8f4a0bec5414ae6fc7eba6a5e3a682dede7bf1e7"]
        const RISK_LIMIT = 0.75
        const collateralAccounts = {}
        desPositionData.positions.forEach(collateralPosition => {
            collateralAccounts[collateralPosition.account.id] = 0
        })
        const secondaryPositionData = await prepareData(reqProtocol, reqChain, Object.keys(collateralAccounts), true);
        const borrowAccounts = {}
        secondaryPositionData.BORROWS.forEach(position => {
            let currentVal = borrowAccounts[position.account.id] || 0
            borrowAccounts[position.account.id] = currentVal + (Number(position.balance) / (10 ** Number(position.asset.decimals))) * Number(position.asset.lastPriceUSD)
        })
        secondaryPositionData.COLLATERALS.forEach(position => {
            let currentVal = collateralAccounts[position.account.id] || 0
            collateralAccounts[position.account.id] = currentVal + (Number(position.balance) / (10 ** Number(position.asset.decimals))) * Number(position.asset.lastPriceUSD)
        })


        const riskData = Object.keys(borrowAccounts).map(x => {
            return ({ "account": x, borrow: borrowAccounts[x], collateral: collateralAccounts[x], risk: borrowAccounts[x] / (collateralAccounts[x] / 100 * Number(desPositionData.market.liquidationThreshold)) })
        })
        const weightedAverageRisk = calculateWeightedAverageRisk(riskData);
        const totalCollateralAboveThreshold = calculateTotalCollateralAboveThreshold(riskData);

        const risk = { weightedAverageRisk, totalCollateralAboveThreshold, atRiskRatio: totalCollateralAboveThreshold / Number(desPositionData.market.totalValueLockedUSD) }

        if (risk.weightedAverageRisk > RISK_LIMIT) {
            return false
        }


        let curROR = 0;
        if (curPositionData) {
            curROR = curPositionData.market.rates[0].rate

        }

        let desROR = 0;
        if (desPositionData) {
            desROR = desPositionData.market.rates[0].rate

        }

        console.log(curROR, desROR)

        // END CUSTOMIZABLE SECTION
        return (desROR > curROR);
    } catch (err) {
        console.log("Error caught - ", err.message);
        return false;
    }
}

strategyCalculation().then(x => console.log(x));
