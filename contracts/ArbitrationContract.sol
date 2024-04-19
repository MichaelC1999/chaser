// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.9;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOptimisticOracleV3} from "./interfaces/IOptimisticOracleV3.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {IPoolControl} from "./interfaces/IPoolControl.sol";
import {ISpokePool} from "./interfaces/ISpokePool.sol";
import {AncillaryData} from "./libraries/AncillaryData.sol";

contract ArbitrationContract {
    IERC20 public umaCurrency; // umaCurrency is the asset used for UMA bond, not a pool's currency
    IOptimisticOracleV3 public oo;
    uint64 public constant assertionLiveness = 240;
    bytes32 public defaultIdentifier;
    IChaserRegistry public registry;

    mapping(bytes32 => string) public assertionToRequestedMarketId;
    mapping(bytes32 => string) public assertionToRequestedProtocol;
    mapping(bytes32 => uint256) public assertionToRequestedChainId;
    mapping(bytes32 => address) public assertionToPoolAddress;
    mapping(uint256 => string) public chainIdToName;

    bytes32 currentPositionAssertion;

    struct DataAssertion {
        bytes32 dataId; // The dataId that was asserted.
        bytes data; // This could be an arbitrary data type.
        address asserter; // The address that made the assertion.
        bool resolved; // Whether the assertion has been resolved.
    }

    mapping(bytes32 => DataAssertion) public assertionsData;

    event DataAsserted(
        bytes32 indexed dataId,
        bytes data,
        address indexed asserter,
        bytes32 indexed assertionId
    );

    event DataAssertionResolved(
        bytes32 indexed dataId,
        bytes data,
        address indexed asserter,
        bytes32 indexed assertionId
    );

    //IMPORTANT - dispute resolved callback?
    //IMPORTANT - BLOCK MOVE PROPOSALS IF A POOL CURRENTLY HAS PROPOSAL PENDING

    constructor(address _registry, uint256 chainId) {
        // address _optimisticOracleV3
        registry = IChaserRegistry(_registry);

        ISpokePool spokePool = ISpokePool(
            registry.chainIdToSpokePoolAddress(0)
        );

        // address umaCurrencyAddress = spokePool.wrappedNativeToken();
        // umaCurrency = IERC20(umaCurrencyAddress);
        umaCurrency = IERC20(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        oo = IOptimisticOracleV3(registry.chainIdToUmaAddress(chainId));
        defaultIdentifier = oo.defaultIdentifier();

        chainIdToName[11155111] = "ethereum";
        chainIdToName[84532] = "base";
    }

    // For a given assertionId, returns a boolean indicating whether the data is accessible and the data itself.
    function getData(
        bytes32 assertionId
    ) public view returns (bool, bytes memory) {
        if (!assertionsData[assertionId].resolved)
            return (false, abi.encode(0));
        return (true, assertionsData[assertionId].data);
    }

    //THIS FUNCTION queryMovePosition() IS THE FIRST STEP IN THE PROCESS TO PIVOT MARKETS. ANY USER CALLS THIS FUNCTION, WHICH OPENS AN ASSERTION
    //IN ORDER TO CALL THIS FUNCTION, USER MUST APPROVE TOKEN TO THIS ADDRESS FOR BOND
    function queryMovePosition(
        address sender,
        uint256 requestChainId,
        string memory requestProtocol,
        string memory requestMarketId,
        uint256 currentDepoitChainId,
        string memory currentProtocol,
        string memory currentMarketId,
        uint256 bond,
        uint256 strategyIndex
    ) public {
        //IMPORTANT - BOND AMOUNT SHOULD BE A FUNCTION OF POOL TVL. A LOW BOND FOR A MULTI-MILLION POOL COULD BE SACRIFICED TO FRONTRUN, OR SPAMMED TO BLOCK DEPOSITS/WITH
        // require(bond >= 1000000, "Bond provided must be above 1 USDC"); // IMPORTANT - INCREASE THIS AMOUNT

        bool protocolEnabled = registry.protocolEnabled(requestProtocol);
        require(
            protocolEnabled == true,
            "Protocol-Chain slug must be enabled to make proposal"
        );

        // Turn this into a function view call to PoolCalculations, cpassing in user and address(this) to see user allowance for arb contract

        //IMPORTANT - ASSERTION MUST ALSO INCLUDE THE CORRECT ASSET THAT CORRESPONDS TO THIS POOL. ie THE PROPOSED MARKET MUST BE FOR THE ASSET USED ON THIS POOL

        // add view call to pool to get currewntProtocolSlug, currentMarketId, strategy source

        // Assertion should use protocol-chain slugs and subgraph id for dispute UX
        // string memory currentDepositProtocolSlug = assertionToRequestedProtocol[
        //     currentPositionAssertion
        // ];
        // string memory currentDepositMarketId = assertionToRequestedMarketId[
        //     currentPositionAssertion
        // ];

        // By accessing and executing the startegy script with the following instructions, the script returned a value of true
        // Call strategyCode() on pool at 0x... and save the string as a .js file locally
        // In the 'mainExecution()' function call, insert an array with the following values
        //  -requestProtocol, requestMarketId, currentDepositProtocolSlug, currentDepositMarketId
        // Using Node.js (version 18 or above), execute the script, and view the return value

        // By converting the bytes held in strategy contracts' strategyCode mapping with key ${index} to ASCII, placing this content into a node js environment (v > 18), and executing it with the arguments listed out below, the script returned true.
        // Here are the arguments, to be placed in the array argument of mainExecution() within the script
        // -requestProtocol, requestMarketId, currentDepositProtocolSlug, currentDepositMarketId

        //The javascript code itself will use messari/subgraphs deployments.json to find the subgraph URI
        //Regardless of what resources the user uses to execute/analyze strategy, the inputs remain the same. The inputs come from chaser contracts for standardization

        bytes memory data = abi.encode(
            "By accessing and executing the startegy script with the following instructions, the script returned a value of true. ",
            "Call 'readStrategyCode()' on pool at ",
            address(msg.sender),
            " and save the string as a .js file locally. ",
            "In the 'mainExecution()' function call, insert an array with the following values: ",
            chainIdToName[requestChainId],
            requestProtocol,
            requestMarketId,
            chainIdToName[currentDepoitChainId],
            currentProtocol,
            currentMarketId
        ); // This message must be rewritten to be very exacting/measurable. Check for uint/address byte conversion breaking the value
        //Switch this message to use different strategy mechanism, not contract string based strategy

        // Submit UMA assertion proposing the move
        bytes32 assertionId = assertDataFor(data, sender, msg.sender, bond);

        // add state function to pool to add these to state

        //DOES THIS VIOLATE CEI?
        assertionToRequestedMarketId[assertionId] = requestMarketId;
        assertionToRequestedProtocol[assertionId] = requestProtocol;
        assertionToRequestedChainId[assertionId] = requestChainId;
        assertionToPoolAddress[assertionId] = msg.sender;
    }

    ///  @dev assertDataFor Opens the UMA assertion that must be verified using the strategy script provided
    /// THIS FUNCTION GETS CALLED FROM queryMovePosition ON THE POOL CONTROL
    function assertDataFor(
        bytes memory data,
        address asserter,
        address poolAddress,
        uint256 bond
    ) internal returns (bytes32 assertionId) {
        // THIS IS FOR PROPOSING A POOL MOVE THEIR INVESTMENTS FOR A GIVEN STRATEGY

        // Confirm msg.sender is a pool in the registry
        bool isPool = registry.poolEnabled(poolAddress);
        require(
            isPool == true,
            "assertDataFor() may only be called by a valid pool."
        );

        //IMPORTANT - IF POOL HAS NO CURRENT POSITION OR IF FUNDS ARE IN THE POOL CONTROL CONTRACT, APPROVE POSITION MOVEMENT IF THE DESTINATION POOL IS VALID. NO UMA ASSERTION NEEDED
        // IMPORTANT - NEED TO VERIFY marketAddress ACTUALLY PERTAINS TO THE PROTOCOL RATHER THAN A DUMMY CLONE OF THE PROTOCOL. MAYBE CAN BE VERIFIED IN ASSERTION?

        bytes32 dataId = bytes32(abi.encode(asserter));

        umaCurrency.transferFrom(asserter, address(this), bond);
        umaCurrency.approve(address(oo), bond);

        //SHOULD THE TEXT IN assertTruth FOLLOW TEMPLATE?
        assertionId = oo.assertTruth(
            abi.encodePacked(
                "Data asserted: ",
                data,
                " for using the startegy logic located at: ",
                AncillaryData.toUtf8Bytes(dataId),
                " and asserter: 0x",
                AncillaryData.toUtf8BytesAddress(asserter),
                " at timestamp: ",
                AncillaryData.toUtf8BytesUint(block.timestamp),
                " in the DataAsserter contract at 0x",
                AncillaryData.toUtf8BytesAddress(address(this)),
                " is valid."
            ),
            asserter,
            address(this),
            address(0), // No sovereign security.
            assertionLiveness,
            umaCurrency,
            bond,
            defaultIdentifier,
            bytes32(0) // No domain.
        );
        assertionsData[assertionId] = DataAssertion(
            dataId,
            data,
            asserter,
            false
        );

        emit DataAsserted(dataId, data, asserter, assertionId);
    }

    // OptimisticOracleV3 resolve callback.
    function assertionResolvedCallback(
        bytes32 assertionId,
        bool assertedTruthfully
    ) public {
        // require(msg.sender == address(oo));

        // If the assertion was true, then the data assertion is resolved.
        if (assertedTruthfully == true) {
            string memory requestMarketId = assertionToRequestedMarketId[
                assertionId
            ];
            string memory requestProtocol = assertionToRequestedProtocol[
                assertionId
            ];

            uint256 requestChainId = assertionToRequestedChainId[assertionId];

            DataAssertion memory dataAssertion = DataAssertion(
                assertionsData[assertionId].dataId,
                assertionsData[assertionId].data,
                assertionsData[assertionId].asserter,
                true
            );

            emit DataAssertionResolved(
                dataAssertion.dataId,
                dataAssertion.data,
                dataAssertion.asserter,
                assertionId
            );
            IPoolControl poolControl = IPoolControl(
                assertionToPoolAddress[assertionId]
            );

            poolControl.sendPositionChange(
                requestMarketId,
                requestProtocol,
                requestChainId
            );
            //Execute callback on PoolControl sendPositionChange()

            // This gets executed open callback of the position pivot assertion resolving

            //SInce withdraws use  LZ ordered messaging, can be made uninterrupted up until the exitPivot is executed
            //Block withdraws once exitPivot is executed, until the new target position is entered and sends message to pool
        } else delete assertionsData[assertionId];
    }

    // If assertion is disputed, do nothing and wait for resolution.
    // This OptimisticOracleV3 callback function needs to be defined so the OOv3 doesn't revert when it tries to call it.
    function assertionDisputedCallback(bytes32 assertionId) public {
        //Clear up proposal
        //Even if the dispute was invalid, the proposal is cancelled
    }
}
