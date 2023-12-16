//This strategy is for detected conditions met for executing internal processes
//protocolWhaleCondition checks positional data to see what % of TVL is made up of top depositors 
// -Gets market TVL (from market id)
// -Gets position count
// -Gets top 100 positions and their balances
// -if the top 10% of positions balance is greater than 50% of the market TVL, return true
// -Then protocol contracts could enact actions that help mitigate risks of whale vulnerability
//      -Disincentivize borrowing with higher rates
//      -Enable a mode where liquidity will be automatically pulled from Spark/Maker if one of these whales withdraws


const strategyCalculation = async (args) => {
    const marketId = args[0]; //The id of the market on the subgraph that is being checked for whale risk
    try {
        const protocolSlug = args[1]
        const subgraphURL = `https://api.thegraph.com/subgraphs/name/messari/` + protocolSlug;

        const body = JSON.stringify({
            query: `{
                market(id: "${marketId}") {
                    id
                    inputToken {
                      name
                      id
                      decimals
                    }
                    inputTokenBalance
                    openPositionCount
                  }
                  positions(
                    orderBy: balance
                    orderDirection: desc
                    first: 12
                    where: {market: "${marketId}"}
                  ) {
                    balance
                    account {
                      id
                    }
                  }            }`
        })
        console.log(body)
        const marketQueryResponse = await fetch(subgraphURL, {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
            },
            body
        });

        const marketPositionData = await marketQueryResponse.json();

        //Map through marketPositionData position results
        //Get a sum of the balance for the top 20 positions
        //Get ratio of this sum/inputTokenBalance
        //If this ratio > 50% return true 

        let whaleBalanceSum = 0;

        console.log(marketPositionData)
        marketPositionData.data.positions.forEach((instance, index) => {
            whaleBalanceSum += Number(instance.balance);
        });
        const marketBalance = marketPositionData.data.market.inputTokenBalance
        console.log(whaleBalanceSum.toString(), marketBalance, whaleBalanceSum / Number(marketBalance))
        if (whaleBalanceSum / Number(marketBalance) > .5) {
            return true
        }
    } catch (err) {
        console.log("Error caught - ", err.message);
    }
    return false
}

// INPUT THE FOLLOWING TO THE ARGUMENT ARRAY IN THE SAME ORDER
// - The current pool ID where deposits are currently located
// - The subgraph slug of the protocol / network that funds are currently deposited
// - The proposed pool ID that the assertion says is a better investment
// - The subgraph slug of the protocol-network that the proposed investment is located

strategyCalculation(["0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8", "aave-v3-arbitrum"]);
