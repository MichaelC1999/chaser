# Chaser

Chaser revolutionizes DeFi investing by enabling efficient, novel strategies on chain. Chaser offers optimal yield by factoring in metrics like historical volatility and current position statistics. Using an automated process, Chaser moves deposits among different protocols and networks to the best possible market for the given strategy. Chaser offers new strategies that were previously impossible:

- Highest yield and lowest volatility over last 30 days 
- Has no deposits +10% of TVL (whale risk)
- Only markets on Optimism or Polygon
- Protocol has less than 20% of funds loaned out
- Any yield consistently above 3% over last year

Keep in mind, these strategies are accessing yields in known time tested protocols like Compound and Aave. Chaser allows for easy integration with lending platforms to move deposits into the best possible investment at any given moment. Having the results of calculating these strtategies on chain, DAOs and other decentralized protocols can put unused liquidity in a more diverse set of options. Being able to consider a market's historical data and position statistics allow protocols more control over risk and exposure.       


Using the UMA Oracle, subgraph data is verified on-chain, and in collaboration with the Across bridge and Chainlink CCIP, Chaser facilitates investments from the mainnet to markets on multiple networks. The system is designed for seamless integration with all protocols, granted a Messari standardized subgraph is available on the Graph Decentralized network.


## Technical

Here are the essential tools that make Chaser work
- The Graph, for access to decentralized, trusted data on DeFi protocols
- UMA Oracle, for the system of proposing/moving deposits between markets
- Chainlink functions, for near instant analysis of subgraph data to calculate investment viability
- Across Bridge, for facilitating investments between different networks.
- Chainlink CCIP, for interacting and managing state between different networks

### Investment Process

- A BridgingConduit contract is deployed on Mainnet with a given strategy (predefined in a "strategy contract", more on this below)
-SubDAOs deposit Maker liquidity / users deposit their funds  
- A user proposes that a different market is a better investment than the market funds are currently deposited in, according to the current strategy (example: The Liquity-Mainnet ETH market returns a higher yield with lower 30 day volatility than the current market on AAVE-V3-Optimism WETH) 
- This proposal is made on the front end by inserting a protocol + network combination and the id of the pool to move to. This calls the "queryMovePosition()" function on the BridgingConduit contract, opening up an UMA assertion with a hardcoded proposal complete with instructions on how disputers can verify the proposal
- The proposal can be verified by reading the Javascript code saved on the strategy contract and executing it locally. Alternatively, Chainlink functions can execute this code and verify the investment proposal immediately
- This code saved in the strategy contract does two things; queries the subgraphs of the lending markets in question and analyzes their data. This code returns the pool id of the better investment. If the pool id of the market currently holding the deposits is returned, the assertion should be rejected and the funds do not move.
- If the assertion is successful, the "executeMovePosition()" callback is executed. This function unwinds the current position and sends the funds through the Across bridge to whatever network the new, better investment is on. This function also sends a CCIP message to the destination network with instructions on how and where to deposit the funds
- The bridged funds and CCIP instructions are received by a SubConduit contract on the L2. This contract handles entering and exiting positions and sending funds back to mainnet.
- All SubConduits possess a "returnToSpark()" function, enabling immediate bridging back to Spark/Maker on the mainnet when liquidity is needed. This includes a high relay fee for faster bridging directly back to Spark

### External Protocol Integration

- Chaser needs a few things to enable investments on other lending protocols. However there is no updating needed from the other protocols, Chaser is completely backwards compatible
- There must be a Messari subgraph for the protocol. The schema allows for comparing metrics between numerous protocols without worrying about different definitions or measurement methodology
- There must be a user/community developed contract deployed to mainnet implementing the "IExternalFunctionsIntegration" interface. This contract gets deployed for each protocol and contains view functions creating the transaction calldata customized for each protocol. This calldata will be executed by the SubConduit to make deposits/withdraws to the external protocol. This contract must be approved in an UMA vote before a strategy can interact with this protocol.
- CCIP allows this Integration contract to be deployed on mainnet yet pass the deposit/withdraw instructions to many networks. Unless the transaction logic is different on each chain, the integration contract can enable positions on any network that the protocol is deployed on

