# Chaser

Chaser revolutionizes DeFi investing by enabling efficient, novel investment strategies on chain. Chaser offers optimal yield by factoring in metrics like historical volatility and current position statistics. Using an decentralized process, Chaser moves deposits among different protocols and networks to the best possible market for the given strategy. Chaser offers new strategies that were previously impossible:

- Highest yield and lowest volatility over last 30 days 
- Has no deposits worth +10% of TVL (whale risk)
- Only markets on Optimism or Polygon
- Protocol has less than 20% of funds loaned out
- Any yield consistently above 3% over last year

These strategies access yields in well known protocols like Compound and Aave. Chaser allows for easy integration with lending platforms to move deposits into the best possible investment at any given moment. By calculating these strategies on chain, DAOs and other decentralized protocols can enhance liquidity utilization and maximize returns while gaining greater control over risk and exposure.       

Chaser is built with tools like the Across Bridge for cross-chain transactions, Chainlink CCIP for cross-network state management, and the UMA Oracle for decentralized verification of investment propositions. This architecture simplifies the process for DAOs and end users by managing all aspects of cross-chain and cross-protocol routing, significantly reducing the complexities involved in more dynamic DeFi investments.

Through its smart contract architecture, Chaser ensures that all transaction processes—from deposits to withdrawals and strategic pivots—are efficiently executed, providing users with a transparent, reliable, and high-performing investment platform. Whether it's deploying new pools, pivoting investments, or integrating with external protocols, Chaser is engineered to enhance liquidity utilization and maximize returns for decentralized finance investors.

## Demo

The Chaser demo is live:

As of April, this demo is to show the current functionality of Chaser. The following operations are demonstrated:

- User pool deployment
- User deposits into a pool
- Deposit funcitonality on multiple chains through Across bridging
- Cross chain withdraw requests and callbacks using Chainlink CCIP
- Pivoting a pool's funds from a protocol to different protocol on a different chain
- Aave and Compound integration

All of the user interactions are made on Base Sepolia. While the demo has a tutorial mode that walks through some different functions, you can disable this to play around with interacting with a pool. With Aave and Compound integration, you can set your pool to invest in these two protocols on Base Sepolia or Ethereum Sepolia.

This demonstration exhibits how Chaser uses the Across bridge and CCIP to interact directly with lending protocols on numerous chains. These tools are used to develop the cross chain functions that take on sequences such as
- Chaser receives deposit on Base Sepolia
- Across sends deposit to Ethereum Sepolia, investing these funds directly into Compound
- CCIP sends a callback message from Ethereum Sepolia to the Chaser pool to confirm that the investment was successful.

On a Pool's page, you will see numerous metrics. The 'TVL' value calls a function on Chaser to make reads to the deposited market to get the current value of the position including interest. On Aave, this is done by getting the PoolBroker contract's current balance of aTokens. On Compound, we call 'balanceOf' on the Comet contract, passing in the address of the PoolBroker. During development, the demo may show wierd or inconsistent values for the TVL or APY during cross chain interactions. The balances for the pool's investments are updated on the destination network as soon as the Across bridge fulfills the transaction, but the front end calculations do not make sense until the entirety of a deposit/withdraw/pivot sequence is finalized by the CCIP callback. 

### Investigating Transaction Failures

As Chaser is still in development using newer technologies, the contracts are still prone to bugs. Before the production stage, the contracts will have rescue mechanisms in the event of failure on a cross chain transaction. While failures on the user-signed transaction on the PoolControl contract would be bugs that indicate errors in the contract logic, there can be failures on the bridged transaction that are not visible on the front end. Most failures can be linked to:

- Low test token balances on Chaser contracts (Compound Test WETH, Link, etc)
- Across relayer transaction fails on the destination chain
- Lost CCIP/Across message where the function call on thedestination chain doesnt seem to execute
- Gas issues

Give up to 30 minutes total for a transaction to finalize. If after this time your deposit/withdraw/pivot is not reflected on the frontend, you can assume something went wrong. Of course, reach out to the Chaser team to notify us in these cases. If you would like to debug this yourself, there are many ways to get some insights into issues.

#### Investigating Across Fulfillment

Check if the Across Bridge fulfillment failed. Look at the event history of the SpokePool on the source chain (this is Base Sepolia for deposits) and search for your transaction's deposit ID on the 'V3FundsDeposited' event. Then look on the destination chain SpokePool for the corresponding fulfillment transaction with the same deposit ID in the 'FilledV3Relay' event. If the corresponding fulfillment transaction has not appeared after a 30 minute window, its safe to assume there was a failure within the Chaser 'BridgeReceiver' contract or the bridge relayer. To further diagnose this, in the `scripts/deploy.js` file you can uncomment `manualAcrossMessageHandle(...)` in the `mainExecution()` execution function. Paste the *OUTPUT AMOUNT* of the token that the bridge was attempting to transfer, and then for the next argument paste `0x` + the bytes of the message (both available in the original  'V3FundsDeposited' event). Make sure you have the output amount of tokens on the destination chain, as this function will simulate the relayer transfering tokens and then calling the Chaser functions. Then run this script in node and check whether or not the transaction was successful. 

#### Investingating CCIP fulfillment

In the case of withdraws and pivots where funds are *currently* on a different chain, the CCIP message ID should be in the initial user-signed transaction. For deposits and pivots originating from Base Sepolia, the CCIP message ID should be on the destination chain transaction that was initiated by the Across relayers (see above on how to find this transaction). In this transaction, get the `messageId` on the `MessageSent` event. With this message ID, you can see the status of this message at https://ccip.chain.link/

## Technical

Here are the essential tools that make Chaser work
- Across Bridge, for facilitating investments between different networks.
- Chainlink CCIP, for interacting and managing state between different networks
- UMA Oracle, for the system of proposing/moving deposits between markets
- The Graph, for access to decentralized, trusted data on DeFi protocols

### Investment Process

For an end user or DAO depositing into a pool, the only interaction needed is to make a deposit on the origin chain Pool contract. Chaser handles the cross-chain and cross-protocol routing behind the scenes. 

#### Mechanics of custom investment strategies

Strategy contracts help UMA OO disputers make an objective, data-based determination as to whether or not a proposed investment is "better" for the given strategy. Before moving investments, a pool must go through a process of determining whether or not to move  

- A user proposes that a given market is a better investment than the market where funds are currently deposited into, according to the current strategy (example: The Compound-Mainnet ETH market returns a higher yield with lower 30 day volatility than the current market on AAVE-V3-Optimism WETH) 
- This proposal is made by opening up an UMA assertion with a combination of the target protocol + network + market address and a hardcoded proposal complete with instructions on how disputers can verify the proposal.
- The proposal can be verified by reading the Javascript code saved on the strategy contract and executing it locally. Alternatively, Chainlink functions can execute this code and verify the investment proposal immediately
- This code saved in the strategy contract does two things; queries the subgraphs of the lending markets in question and analyzes their data. This code returns the pool id of the better investment. If the pool id of the market currently holding the deposits is returned, the assertion should be rejected and the funds do not move.
- If the assertion is successful, the "sendPositionChange()" callback is executed. This function unwinds the current position and sends the funds through the Across bridge to whatever network the new, better investment is on. This function also sends a CCIP message to the destination network with instructions on how and where to deposit the funds


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
- The ChaserMessenger *on the destination chain* processes this message and routes the function through the BridgedLogic contract
- BridgedLogic makes the withdraw using the Integrator contract to interact with the protocol that the funds are currently invested into
- The withdrawn funds are sent by BridgedLogic back to the origin chain by using the Across bridge
- The BridgedReceiver forwards the funds and data to the Pool which then updates state and sends the funds to the user

#### Mechanics of pivoting investment

The strategy aspect of determining when a pool should move investment based on custom metrics is much simpler from an engineering perspective. This will involve installing the UMA OO to callback the 'sendPositionChange()' function on the PoolControl contract rather than letting a user call this whenever.


#### Mechanics of deploying a pool

- A user selects and asset and a strategy
- PoolControl contract gets deployed with the user's parameters
- The user who deployed the new pool sends both a deposit and data to set the initial position by providing a protocol-market-chain combination on some other DeFi protocol that pays a yield on deposits
- The Chaser contracts on the destination chain handle the state updates and connections necessary to initialize the investment
- On a pool's first pivot to a chain, the registry deploys a PoolBroker contract to hold the position for this pool separated from the funds of other pools.  



### External Protocol Integration

- In order to enable Chaser access to other protocols such as Compound or Spark, the Integration contract needs to be upgraded with interfaces and logic to execute the following operations on the protocol's smart contracts
    - Depositing on behalf of a provided address
    - Withdraws
    - Reading the position value of a given liquidity provider, denominated in the asset deposited. This value should be current and including yield.
- There is no updating needed from the other protocols, Chaser is completely backwards compatible
- For now, these protocol integratons will be developed and maintained by the Chaser team for security purposes. However this will eventually be community developed with incentives to expand reach while maintaining quality
- The integration contract receives input from other Chaser contracts as to what protocol/market/asset is being invested into. With this input, the integration contract routes deposits and withdraw requests using specialized logic to account for particularities of each protocol.  
- Deposits are credited to the PoolBroker contract for the sake of keeping revenues, balances, and data separated and individual for each pool
- All withdraw requests have the PoolBroker receive the deposits, then pass them through the Integration contract to wherever the funds reach their destination (pool, other protocol, bridging, etc)
- NOTE: During development, the Integration contract logic has sections where assetAddresses are changed to hardcoded values. This is because the testnet versions of some assets are different by protocol. The WETH used by Across is different than the WETH used by Aave, for example. 