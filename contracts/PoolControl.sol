// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./PoolToken.sol";
import {ISpokePool} from "./interfaces/ISpokePool.sol";
import {IPivotPoolRegistry} from "./interfaces/IPivotPoolRegistry.sol";
import {IPivotPoolManager} from "./PivotPoolManager.sol";
import {IBridgeConnection} from "./BridgeConnection.sol";
import {ArbitrationContract} from "./ArbitrationContract.sol";

contract PoolControl {
    //Gives ERC20 for pool position proportions

    // TWO TYPES OF POOLS: BRIDGING/INTRACHAIN
    // Bridging is less liquid but can access wider range of investments
    // Intrachain is instant liquidity

    //Operates as a local treasury for the pool, managing balances, deposits, withdraws.

    // All funds pertaining to this pool are passed through here for deposits and withdraws
    //Bridging functionality to spokes
    // Holds strategy state. Points to a strategy to use
    // oSnap voting for pool permissions
    //Assertion calls originate here
    uint256 LOCAL_CHAIN;
    address public assetAddress;
    ERC20 asset;
    IPivotPoolManager public manager;
    IPivotPoolRegistry public registry;
    PoolToken public poolToken;

    string public strategySource; // STRATEGY SOURCE CAN BE A REPO URL WITH CODE TO EXECUTE, OR THIS STRING COULD POINT TO AN ADDRESS/CHAIN/METHOD THAT RETURNS THE INSTRUCTIONS

    mapping(bytes32 => address) depositIdToDepositor;
    mapping(bytes32 => uint256) depositIdToDepositAmount;

    mapping(bytes32 => string) public assertionToRequestedPoolId;
    mapping(bytes32 => string) public assertionToRequestedProtocol;

    // POSITION STATE
    //State contains position target, current position location and last position location (for failed bridge handling)
    // target state is for holding the position to pivot to. This facilitates the new position to enter

    address targetPositionAddress; //THE MARKET ADDRESS THAT WILL BE PASSED TO BRIDGECONNECTION, NOT THE FINAL ADDRESS THAT FUNDS ARE ACTUALLY HELD IN
    uint256 targetPositionChain;
    bytes32 targetPositionProtocolHash;

    // current state holds the position that funds are currently deposited into. This facilitates withdraws. Current state gets set as chaser + address(this) when the bridge request to withdraw has been sent
    address currentPositionAddress;
    uint256 currentPositionChain;
    bytes32 currentPositionProtocolHash;

    // last state holds the previous position data. In the case of error while bridging, this is to rescue funds
    address lastPositionAddress;
    uint256 lastPositionChain;
    bytes32 lastPositionProtocolHash;

    bytes32 currentPositionAssertion;

    constructor(
        address initialDepositor,
        address initialAsset,
        uint initialDepositAmount,
        string memory strategy,
        string memory poolName,
        uint256 deploymentChain
    ) {
        manager = IPivotPoolManager(address(msg.sender));
        registry = IPivotPoolRegistry(manager.viewRegistryAddress());
        LOCAL_CHAIN = deploymentChain;
        assetAddress = initialAsset;
        asset = ERC20(initialAsset);
        strategySource = strategy;

        poolToken = new PoolToken(
            initialDepositor,
            initialDepositAmount,
            poolName
        );

        asset.transferFrom(
            initialDepositor,
            address(this),
            initialDepositAmount
        );
    }

    function updateAsset(address) public {
        // NEEDS ACCESS CONTROL. Perhaps upon oSnap vote of users who have pool tokens
    }

    function enterFunds(uint256 amount) public {
        bytes32 depositId = keccak256(
            abi.encode(msg.sender, amount, block.timestamp)
        );

        depositIdToDepositor[depositId] = msg.sender;
        depositIdToDepositAmount[depositId] = amount;

        if (currentPositionChain == LOCAL_CHAIN) {
            enterFundsLocalChain(depositId);
        } else {
            enterFundsCrossChain(depositId);
        }
    }

    function enterFundsLocalChain(bytes32 depositId) internal {
        address sender = depositIdToDepositor[depositId];
        delete depositIdToDepositor[depositId];
        uint256 amount = depositIdToDepositAmount[depositId];
        delete depositIdToDepositAmount[depositId];

        uint256 poolPositionAmount = 0;
        address currentConnectionAddress = registry.chainIdToBridgeConnection(
            currentPositionChain
        );
        if (currentPositionAddress == address(this)) {
            // -funds are currently in this pool
            // --TransferFrom sender to address(this)
            asset.transferFrom(sender, address(this), amount);
            // --Measure ERC20(asset).balanceOf(address(this)), get proportion of amount to the full balance of this pool
            poolPositionAmount = asset.balanceOf(address(this));
        } else {
            // -funds are in a connection/external on same chain
            uint256 positionValueBeforeDeposit = IBridgeConnection(
                currentConnectionAddress
            ).readPositionValue();

            // --read full position amount, get proportion of deposit to full position
            poolPositionAmount = positionValueBeforeDeposit + amount;

            // --deposit funds into position
            asset.transferFrom(sender, currentConnectionAddress, amount);
            // --Call function on connection to deposit funds into external protocol
        }
        // -Perform checks that the funds were transfered (wouldnt the tx fail if user didnt actually transfer?)
        // -mint tokens according to proportion
        mintUserPoolTokens(depositId, poolPositionAmount);
    }

    function enterFundsCrossChain(bytes32 depositId) internal {
        address sender = depositIdToDepositor[depositId];
        uint256 amount = depositIdToDepositAmount[depositId];

        //user made permit/approval for across
        // fund entrance can automatically bridge into position.
        address acrossSpokePool = registry.acrossAddress();

        // Take the sucessfully proposed position, input into a registry function to get Bridge Connection address for its chain
        address bridgeConnection = registry.chainIdToBridgeConnection(
            currentPositionChain
        );

        int64 relayerFeePct = 0; // SHOULD THIS BE HARDCODED OR INPUT?

        bytes32 method = keccak256("enterFunds()");
        bytes32 userAddress = bytes32(
            uint256(uint160(address(msg.sender))) << 96
        );
        bytes32 poolAddress = bytes32(uint256(uint160(address(this))) << 96);
        bytes memory message = new bytes(96);

        assembly {
            mstore(add(message, 32), method)
            mstore(add(message, 64), userAddress)
            mstore(add(message, 96), poolAddress)
        }

        ISpokePool(acrossSpokePool).deposit(
            bridgeConnection,
            assetAddress,
            amount,
            currentPositionChain,
            relayerFeePct,
            uint32(block.timestamp),
            message,
            0
        );

        //Relay fee while assertion is open w/ no dispute is set higher for rapid fulfillment
        //When assertion is settled, pivotPending state is true and no deposits are allowed until new position is successfully engaged
        //Pool tokens are complicated because we cannot immediately get the position size after interest on the L2 bridge connection and figure out a deposit's proportion of the pool
        // On the pool, user deposit is recorded as proportionate to the total funds pivoted into the position
        // On the bridge connection whenever a user deposit is received, take a snapshot of how much interest has been gained since the pivot.
        //
        //
        //
        // user/DAO signs permit and then calls this function to deposit funds into this pool
        // When funds are entered, they are no longer liquid to the depositor, as they are exchanged for position tokens for user who made withdraw request
        // Pool tokens are not given to depositor until their funds are in the position. Either after a pivot and funds are moved to correct position, or a withdraw request gets fulfilled
        // Pool token proportions should be calculated and minted on pivot
        //how can we do this without a loop?
        //Each entered funds between pivots gets recorded in a mapping, pivotNonce => address => amount
        //Each entered funds mints erc20/721 for the pivot nonce, recording how proportional a users entered funds were when added to a pivot
        //The pivot adds entered funds to the position, then mints pool tokens for the entered funds proportionate to the current deposits
        //The minted pool tokens are given to the pool
        // The depositor can call a function to burn their nonce tokens in exchange for the pool tokens
        //if depositor still has nonce tokens and attempts to withdraw, the nonce tokens + pool tokns get burnt
        //
        // asset.transferFrom(msg.sender, address(this), amount);
        // update balances/ledger
    }

    function mintUserPoolTokens(
        bytes32 depositId,
        uint256 poolPositionAmount
    ) internal {
        address depositor = depositIdToDepositor[depositId];
        delete depositIdToDepositor[depositId];
        uint256 userAssetDepositAmount = depositIdToDepositAmount[depositId];
        delete depositIdToDepositAmount[depositId];
        //Could there just be a depositor argument and get rid of userAssetDepositAmount?
        // upon deposit set mapping user=>depositedAmountPending
        // Once the full position amount is calcd, this function gets called
        //Function has access to mapping
        // IMPORTANT - IF USER MAKES MULTIPLE SUCCESSIVE BRIDGED DEPOSITS, THE TOTAL POSITION VALUE DOES NOT REFLECT ALL DEPOSITS UNTIL THEY HAVE ALL BEEN BRIDGED.
        // WHERAS THE CALLBACK FOR MINTING TOKENS HERE IN POOL, THE MAPPING DEPOSIT AMOUNT REFLECTS ALL DEPOSITS MADE. GIVING USER A HIGHER POOL TOKEN PROPORTION THAN THEY REALLY SHOULD
        // Could have 2 mappings, depositId => depoAddr and depositId => amount. Each callback returns the depositId which gives access to the depositor and depoamount.
        // User can have multiple pending deposits and the proportion reflects at time of user deposit
        // Is poolTokenSupplySnapshot necessary? If a later deposit returns callback quicker, the pool tokens that are minted could be disproportionate
        // But the snapshot wouldnt reflect the pool tokens of deposits that came before deposit but have not settled yet
        // The poolToken supply should be based on the amount at the time of minting

        uint256 largeFactorUserAssetAmount = userAssetDepositAmount *
            (10 ** 18);
        uint256 ratio = largeFactorUserAssetAmount / poolPositionAmount;
        uint256 poolTokenSupply = poolToken.totalSupply();
        uint256 largeFactorPoolTokensToMint = largeFactorUserAssetAmount *
            poolTokenSupply;
        uint256 poolTokensToMint = largeFactorPoolTokensToMint / (10 ** 18);

        poolToken.mint(depositor, poolTokensToMint);

        //What is needed to mint pool tokens?
        // -Proportion of deposit to current pool position
        // -address of depositor
        // -current amount of pooltokens in existence
        // THREE CASES
        // -funds are currently in this pool
        // -funds are in a connection/external om same chain

        // -funds are in a connection/external on other chain
        // --Pooltokens are minted and distributed to depositors on the soonest pivot
        // --State on pool holds the recent depositors who do not have tokens yet. The position size is now available after bridging from connection back to pool
        // --Loop through the recent depositors and give their pool tokens
        // --create additional function for users who need instant liquidity to pay higher gas fees and do the bridge + bridge back method
    }

    function orderWithdraw(uint amount) external {
        // Withdraws for Bridging pools cannot be immediately fulfilled
        // Record withdraw requests in order
        //approves (address(this)) for their pool/nonce tokens
        // If there are funds in this pool and no withdraw orders in front of this, burn the pool tokens proportionate and mint the depositors their pool tokens
        //
        //user withdraw directly from pool forfeits any interest earned for user during that position
    }

    //Should fund transfer transactions be initiated on manager or pool? Wherever funds are held must approve spoke pool for transfer of assets
    //manager: prevent fraudulent pools, depo/with functionality with better upgradeability (all logic on single contract),Uniformity in how transactions are executed
    //pool: calls to function on manager with msg.sender access control, better enables specific roles/users on a pool to execute certain actions
    // Should deposits be held in the PoolControl or manager?
    //manager: keeps all pools funds together, can still measure proportions to allocate for each pool
    // pool: allows greater security, in the case of a hack it is easier to freeze/disable fund movement before entire deposits are drained. Contract holds only a single asset rather than manager holding various assets for each pool
    //

    //How should unfulfilled withdraw orders be paid out during a pivot to avoid unbounded loops?
    // -Withdraw request keeps funds liquid in the pool for the user to withdraw in another transaction

    //Is there a way (using across composable bridging) without sending funds, to request a withdraw from BridgeConnection on L2?
    // -poses security issue to attempt to wait for bridge transaction to process + send the transaction. Could a conflict arise if a pivot executes in between bridge fulfillment?
    // -Could block direct withdraws (removing from BridgeConnection) when an assertion is open. Defaulting to withdraw order instead
    // -If assertion closes from dispute, depositor can change the order to a direct withdraw request
    // -

    //State contains position target, current position location and last position location (for failed bridge handling)
    // When a pivot is accepted, the inter chain request to bridged position is sent. Locally, the current position is set to address(this), and last position

    function handleAcrossMessage(
        address tokenSent,
        uint256 amount,
        bool fillCompleted,
        address relayer,
        bytes memory message
    ) external {
        // IMPORTANT: HOW CAN I ACCESS CONTROL THIS FUNCTION TO ONLY BE CALLABLE BY SPOKE POOL? require msg.sender == spoke pool address
        bytes32 methodHash = extractBytes32(message, 0);
        if (methodHash == keccak256("passDepositProportion()")) {
            // If the message indicates a pool mint, call mintUserPoolTokens()
            // extract the total position value from message bytes
            bytes32 depositId = extractBytes32(message, 1);
            bytes32 poolPositionSupplyBytes32 = extractBytes32(message, 2);
            uint256 poolPositionAmount = uint256(poolPositionSupplyBytes32);
            mintUserPoolTokens(depositId, poolPositionAmount);
        }
    }

    function pivotPoolPosition(bytes32 assertionId) external {
        // This function makes the call to the BridgeConnection that is holding pool deposits, passing in the new chain/pool to move deposits to
        //Can only be called by Arbitration contract
        currentPositionAssertion = assertionId;
        address arbitrationContract = registry.arbitrationContract();
        require(
            msg.sender == arbitrationContract,
            "pivotPoolPosition() may only be called by the arbitration contract"
        );

        string memory requestPoolId = assertionToRequestedPoolId[assertionId];
        string memory requestProtocolSlug = assertionToRequestedProtocol[
            assertionId
        ];

        uint256 destinationChainId = registry.slugToChainId(
            requestProtocolSlug
        );

        bytes32 protocolHash = registry.slugToProtocolHash(requestProtocolSlug);

        //Construct across message with instructions for BridgeConnection to process the pivot
        //What does this message need?
        // -Pool id/addr
        // -New position protocol name, market id/addr, chain
        // -User deposit info???
        // -New position method bytes???

        //CALL ACROSS DEPOSIT FOR EXECUTING THE PIVOT

        //marketAddress is user address for user methods, pivot this is the destination market address
        address marketAddress = address(bytes20(bytes(requestPoolId)));
        // IMPORTANT - The market id in the subgraph could be different than the address of market contract. The subgraph market id is needed for assertion,

        bytes memory bridgingMessage = createPivotBridgingMessage(
            protocolHash,
            marketAddress,
            destinationChainId
        );

        // TEST-CEI REORDER IN PRODUCTION***********************
        // uint256 wethBalance = IERC20(wethAddress).balanceOf(address(this));
        // require(
        //     wethBalance >= transferAmount,
        //     "Deployer has insufficient asset balance"
        // );

        //How do we handle amounts/transfer in a pivot?
        //No value needs to be transfered, but relayers still need to be paid
        //Could this be sourced by the user signing off the assertionSettled callback?
        //Doesnt need to be a high amount. However need funds on this network in order to pay these fees

        //*************************************** */
        // IERC20(wethAddress).approve(acrossSpokePool, transferAmount);

        address acrossSpokePool = registry.acrossAddress();

        address destinationBridgeConnection = registry
            .chainIdToBridgeConnection(destinationChainId);

        uint256 transferAmount = 0;

        // The amount bridged is protocol fee
        ISpokePool(acrossSpokePool).deposit(
            destinationBridgeConnection,
            assetAddress,
            transferAmount,
            destinationChainId,
            250000000000000000,
            uint32(block.timestamp),
            bridgingMessage,
            (2 ** 256 - 1)
        );
    }

    //THIS FUNCTION queryMovePosition() IS THE FIRST STEP IN THE PROCESS TO PIVOT MARKETS. ANY USER CALLS THIS FUNCTION, WHICH OPENS AN ASSERTION
    //IN ORDER TO CALL THIS FUNCTION, USER MUST APPROVE TOKEN TO THIS ADDRESS FOR BOND
    function queryMovePosition(
        string memory requestProtocolSlug,
        string memory requestPoolId,
        uint256 bond
    ) public {
        require(bond >= 1000000000, "Bond provided must be above 1000 USDC");

        bool slugEnabled = registry.slugEnabled(requestProtocolSlug);
        require(
            slugEnabled == true,
            "Protocol-Chain slug must be enabled to make proposal"
        );

        ArbitrationContract arbitrationContract = ArbitrationContract(
            registry.arbitrationContract()
        );

        uint256 userAllowance = IERC20(assetAddress).allowance(
            msg.sender,
            address(arbitrationContract)
        );

        require(
            bond <= userAllowance,
            "User must approve bond amount for PoolControl to spend"
        );
        //IMPORTANT - ASSERTION MUST ALSO INCLUDE THE CORRECT ASSET THAT CORRESPONDS TO THIS POOL. ie THE PROPOSED MARKET MUST BE FOR THE ASSET USED ON THIS POOL

        // Assertion should use protocol-chain slugs and subgraph id for dispute UX
        string memory currentDepositProtocolSlug = assertionToRequestedProtocol[
            currentPositionAssertion
        ];
        string memory currentDepositPoolId = assertionToRequestedPoolId[
            currentPositionAssertion
        ];

        bytes memory data = abi.encode(
            "The market on ",
            requestProtocolSlug,
            " for pool with an id of ",
            requestPoolId,
            " yields a better investment than the current market on ",
            currentDepositProtocolSlug,
            " with an id of ",
            currentDepositPoolId,
            ". This is according to the current strategy whose Javascript logic that can be read from ",
            strategySource,
            " as of block ",
            block.number
        ); // This message must be rewritten to be very exacting/measurable. Check for uint/address byte conversion breaking the value
        //Switch this message to use different strategy mechanism, not contract string based strategy

        // Submit UMA assertion proposing the move
        bytes32 assertionId = arbitrationContract.assertDataFor(
            data,
            msg.sender,
            bond
        );

        //DOES THIS VIOLATE CEI?
        assertionToRequestedPoolId[assertionId] = requestPoolId;
        assertionToRequestedProtocol[assertionId] = requestProtocolSlug;
    }

    function createPivotBridgingMessage(
        bytes32 protocolHash,
        address marketAddress,
        uint256 destinationChainId
    ) internal view returns (bytes memory) {
        bytes4 method = bytes4(keccak256("exitPivot"));
        bytes memory message = abi.encode(
            method,
            address(this),
            protocolHash,
            marketAddress,
            destinationChainId,
            0
        );

        return message;
    }

    function createUserBridgingMessage(
        bool isDepo,
        bytes32 protocol,
        address userAddress,
        uint256 amountToWithdraw
    ) internal view returns (bytes memory) {
        bytes4 method = bytes4(keccak256("userWithdraw"));
        if (isDepo == true) {
            method = bytes4(keccak256("userDeposit"));
        }

        // userProportionRatio calculated from (user address balanceOf pool tokens)/(total supply pool tokens)
        uint256 userProportionRatio = 0;

        bytes memory message = abi.encode(
            method,
            address(this),
            protocol,
            userAddress,
            amountToWithdraw,
            userProportionRatio
        );

        return message;
    }

    function extractBytes32(
        bytes memory data,
        uint256 index
    ) internal pure returns (bytes32) {
        require(data.length >= (index + 1) * 32, "Insufficient data length");

        bytes32 result;

        assembly {
            // Calculate the offset in bytes
            let offset := mul(index, 32)

            // Copy 32 bytes from data[offset] to result
            mstore(result, mload(add(data, add(0x20, offset))))
        }

        return result;
    }
}

// Biggest design roadblock is weighing balance of UX/Liquidity and interchain use
// How can we handle user positions when bridging actions are taking place? State on main chain changes while L2/spoke is in the middle of transfering funds
//Ex. User deposits USDC in mainnet pool, sending to the current position at ABC. While the funds are being bridged to current position, the pivot is being executed and the rest of the position has already bean removed from 'last' position located

//Is there any way to execute a callback on origin chain after destination chain receives bridging req
