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
    uint64 public constant assertionLiveness = 30;
    bytes32 public defaultIdentifier;
    address public bridgingConduit;
    IChaserRegistry public registry;

    mapping(bytes32 => string) public assertionToRequestedMarketId;
    mapping(bytes32 => string) public assertionToRequestedProtocol;

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

    constructor(address _registry, uint256 chainId) {
        // address _optimisticOracleV3
        registry = IChaserRegistry(_registry);

        if (chainId != 1337) {
            ISpokePool spokePool = ISpokePool(
                registry.chainIdToSpokePoolAddress(chainId)
            );

            address umaCurrencyAddress = spokePool.wrappedNativeToken();
            umaCurrency = IERC20(umaCurrencyAddress);
            oo = IOptimisticOracleV3(registry.chainIdToUmaAddress(chainId));
            defaultIdentifier = oo.defaultIdentifier();
        }

        bridgingConduit = msg.sender;
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
        string memory requestProtocolSlug,
        string memory requestMarketId,
        uint256 bond,
        uint256 userAllowance,
        string memory strategySource
    ) public {
        require(bond >= 1000000000, "Bond provided must be above 1000 USDC");

        bool slugEnabled = registry.slugEnabled(requestProtocolSlug);
        require(
            slugEnabled == true,
            "Protocol-Chain slug must be enabled to make proposal"
        );

        // Turn this into a function view call to PoolCalculations, cpassing in user and address(this) to see user allowance for arb contract

        require(
            bond <= userAllowance,
            "User must approve bond amount for PoolControl to spend"
        );
        //IMPORTANT - ASSERTION MUST ALSO INCLUDE THE CORRECT ASSET THAT CORRESPONDS TO THIS POOL. ie THE PROPOSED MARKET MUST BE FOR THE ASSET USED ON THIS POOL

        // add view call to pool to get currewntProtocolSlug, currentMarketId, strategy source

        // Assertion should use protocol-chain slugs and subgraph id for dispute UX
        string memory currentDepositProtocolSlug = assertionToRequestedProtocol[
            currentPositionAssertion
        ];
        string memory currentDepositMarketId = assertionToRequestedMarketId[
            currentPositionAssertion
        ];

        bytes memory data = abi.encode(
            "The market on ",
            requestProtocolSlug,
            " for pool with an id of ",
            requestMarketId,
            " yields a better investment than the current market on ",
            currentDepositProtocolSlug,
            " with an id of ",
            currentDepositMarketId,
            ". This is according to the current strategy whose Javascript logic that can be read from ",
            strategySource,
            " as of block ",
            block.number
        ); // This message must be rewritten to be very exacting/measurable. Check for uint/address byte conversion breaking the value
        //Switch this message to use different strategy mechanism, not contract string based strategy

        // Submit UMA assertion proposing the move
        bytes32 assertionId = assertDataForInternal(data, msg.sender, bond);

        // add state function to pool to add these to state

        //DOES THIS VIOLATE CEI?
        assertionToRequestedMarketId[assertionId] = requestMarketId;
        assertionToRequestedProtocol[assertionId] = requestProtocolSlug;
    }

    ///  @dev assertDataFor Opens the UMA assertion that must be verified using the strategy script provided
    /// THIS FUNCTION GETS CALLED FROM queryMovePosition ON THE POOL CONTROL
    function assertDataFor(
        bytes memory data,
        address asserter,
        uint256 bond
    ) public returns (bytes32 assertionId) {
        // THIS IS FOR PROPOSING A POOL MOVE THEIR INVESTMENTS FOR A GIVEN STRATEGY

        // Confirm msg.sender is a pool in the registry
        bool isPool = registry.poolEnabled(msg.sender);
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

    ///  @dev assertDataForInternal Opens the UMA assertion that must be verified using the strategy script provided
    /// THIS FUNCTION GETS CALLED WHEN A USER ASSERTS THAT A CERTAIN CONDITION TO TRIGGER A PROTOCOL INTERNAL PROCESS HAS BEEN MET
    /// THIS CONDITION IS MEASURABLE/VERIFIABLE BY SUBGRAPH DATA
    function assertDataForInternal(
        bytes memory data,
        address asserter,
        uint256 bond
    ) public returns (bytes32 assertionId) {
        // THIS IS FOR PROPOSING THE PROTOCOL TO EXECUTE SOME INTERNAL ACTIONS
        // THE ASSERTION SAYS THAT A PREVIOUSLY SPECIFIED CONDITION HAS BEEN MET, TO BE VERIFIED BY UMA DISPUTERS EXECUTING STRATEGY LOGIC

        // Confirm msg.sender is a pool in the registry
        bool isPool = registry.poolEnabled(msg.sender);
        require(
            isPool == true,
            "assertDataFor() may only be called by a valid pool."
        );

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
        require(msg.sender == address(oo));

        // If the assertion was true, then the data assertion is resolved.
        if (assertedTruthfully) {
            assertionsData[assertionId].resolved = true;
            DataAssertion memory dataAssertion = assertionsData[assertionId];
            emit DataAssertionResolved(
                dataAssertion.dataId,
                dataAssertion.data,
                dataAssertion.asserter,
                assertionId
            );
            //Execute callback on PoolControl sendPositionChange()

            IPoolControl poolControl = IPoolControl(dataAssertion.asserter);

            //IMPORTANT - CHANGE TO LZ SEND
            // This gets executed open callback of the position pivot assertion resolving
            // This send lz message to the Router to make the transition

            //Can only be called by Arbitration contract
            currentPositionAssertion = assertionId;
            // require(
            //     msg.sender == arbitrationContract,
            //     "sendPositionChange() may only be called by the arbitration contract"
            // ); IMPORTANT - UNCOMMENT

            //SInce withdraws use  LZ ordered messaging, can be made uninterrupted up until the exitPivot is executed
            //Block withdraws once exitPivot is executed, until the new target position is entered and sends message to pool

            string memory requestMarketId = assertionToRequestedMarketId[
                assertionId
            ];
            string memory requestProtocolSlug = assertionToRequestedProtocol[
                assertionId
            ];

            requestMarketId = string(
                abi.encodePacked(assertionId, abi.encode("0xTEST"))
            ); // REMOVE - TESTING
            requestProtocolSlug = string(
                abi.encodePacked(assertionId, abi.encode("SLUG"))
            ); //REMOVE - TESTING

            bytes32 protocolHash = registry.slugToProtocolHash(
                requestProtocolSlug
            );

            poolControl.sendPositionChange(requestMarketId, protocolHash);
        } else delete assertionsData[assertionId];
    }

    // If assertion is disputed, do nothing and wait for resolution.
    // This OptimisticOracleV3 callback function needs to be defined so the OOv3 doesn't revert when it tries to call it.
    function assertionDisputedCallback(bytes32 assertionId) public {
        //Clear up proposal
        //Even if the dispute was invalid, the proposal is cancelled
    }
}
