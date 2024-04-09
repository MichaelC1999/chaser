# Chaser

Chaser revolutionizes DeFi investing by enabling efficient, novel strategies on chain. Chaser offers optimal yield by factoring in metrics like historical volatility and current position statistics. Using an automated process, Chaser moves deposits among different protocols and networks to the best possible market for the given strategy. Chaser offers new strategies that were previously impossible:

- Highest yield and lowest volatility over last 30 days 
- Has no deposits +10% of TVL (whale risk)
- Only markets on Optimism or Polygon
- Protocol has less than 20% of funds loaned out
- Any yield consistently above 3% over last year

Keep in mind, these strategies are accessing yields in known time tested protocols like Compound and Aave. Chaser allows for easy integration with lending platforms to move deposits into the best possible investment at any given moment. Having the results of calculating these strategies on chain, DAOs and other decentralized protocols can put unused liquidity in a more diverse set of options. Being able to consider a market's historical data and position statistics allow protocols more control over risk and exposure.       


Using the UMA Oracle, subgraph data is verified on-chain. In collaboration with the Across bridge and Chainlink CCIP, Chaser facilitates investments from mainnet to markets on multiple networks. The system is designed for simple integration with all protocols, assuming there are trusted, accessible data sources available such as Messari standardized subgraphs.


## Technical

Here are the essential tools that make Chaser work
- Across Bridge, for facilitating investments between different networks.
- Chainlink CCIP, for interacting and managing state between different networks
- UMA Oracle, for the system of proposing/moving deposits between markets
- The Graph, for access to decentralized, trusted data on DeFi protocols

### Investment Process

For an end user depositing into a pool, the only interaction needed is to make a deposit on the origin chain Pool contract. Chaser handles the cross-chain and cross-protocol routing behind the scenes

#### Mechanics of a deposit

- A DAO/user makes a deposit into a Chaser Pool
- The PoolControl calls the 'depositV3' function on the local Across V3 SpokePool to send these funds and data to the chain where this pool currently invests its position
- The BridgedReceiver contract handles the bridged funds and data. This gets forwarded to the BridgedLogic contract which then uses the Integrator contract to connect with the external protocol 
- The Integrator contract standardizes connections to external protocols like Aave and Compound. This routes deposits to the appropriate market, performs reads to get the current value of the position, and facilitates withdraws from the protocol
- After the Integrator and BridgedReceiver finish processing the deposit, a CCIP message is sent through the ChaserMessenger contract back to the origin chain
- The ChaserMessenger *on the origin chain* receives this CCIP message and calls functions on the PoolControl contract in order to finalize the deposit
- The PoolControl updates the pool state and mints the user tokens to denominate their position

#### Mechanics of a withdraw

As deposits are usually being invested in other protocols on other chains, liquidity is not instant. Liquidity varies based on Across bridging time and CCIP message finality. On testnet, this can take up to 30 minutes for a withdraw to finalize. On mainnet, this should be much quicker but still not instant.

- DAO/user interacts with the PoolControl contract to request a withdraw
- If the deposits are in a protocol on a different chain, the ChaserMessenger sends a CCIP to the appropriate chain requesting a withdraw
- This withdraw request includes the user's proportion of out of all the Pool's position tokens. As the origin chain does not have access to the investment's current value including interest, this is necessary to determine how much a user is actually entitled to.
- The BridgedMessenger *on the destination chain* processes this message and routes the function through the BridgedLogic contract
- BridgedLogic makes the withdraw using the Integrator contract to interact with the protocol that the funds are currently invested into
- The withdrawn funds are sent by BridgedLogic back to the origin chain by using the Across bridge
- The BridgedReceiver forwards the funds and data to the Pool which then updates state and sends the funds to the user  

#### Mechanics of deploying a pool

- A user selects and asset and a strategy
- PoolControl contract gets deployed with the user's parameters
- The user who deployed the new pool sends both a deposit and data to set the initial position by providing a protocol-market-chain combination on some other DeFi protocol that pays a yield on deposits
- The Chaser contracts on the destination chain handle the state updates and connections necessary to initialize the investment



### External Protocol Integration

- Chaser needs a few things to enable investments on other lending protocols. However there is no updating needed from the other protocols, Chaser is completely backwards compatible
- There must be a Messari subgraph for the protocol. The schema allows for comparing metrics between numerous protocols without worrying about different definitions or measurement methodology
- For now, these protocol integratons will be developed and maintained by the Chaser team for security purposes. However this will eventually be community developed with incentives to expand reach while maintaining quality
