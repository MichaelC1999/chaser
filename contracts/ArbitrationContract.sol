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
    uint64 public constant assertionLiveness = 360; // 7200;
    bytes32 public defaultIdentifier;
    IChaserRegistry public registry;

    mapping(bytes32 => bytes) public assertionToRequestedMarketId;
    mapping(bytes32 => string) public assertionToRequestedProtocol;
    mapping(bytes32 => uint256) public assertionToRequestedChainId;
    mapping(bytes32 => address) public assertionToPoolAddress;
    mapping(bytes32 => uint256) public assertionToBlockTime;
    mapping(address => bool) public poolHasAssertionOpen;
    mapping(uint256 => string) public chainIdToName;

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

    function inAssertionBlockWindow(
        bytes32 assertionId
    ) external view returns (bool) {
        return (assertionToBlockTime[assertionId] < block.timestamp);
    }

    // WHO MAY PROPOSE A PIVOT?
    // -Someone with a stake in the pool
    //-Pools may have very few users who are monitoring vrious yeilds
    //-Gives incentive for correct proposals
    // -Any user that is willing to put up the bond
    //-Needs a high bond value to prevent spam blocking  bridge proposals
    //-Needs a high reward to incentivize users to put up the bond and watch for pivots
    //-Hard to convince users to put up high bond right after launch
    // -Chaser bot that is responsible with putting up funds to make proposals
    //Central actor bringing execution on chain
    //Prevents spam from blocking withdraws on pools at crucial moments
    //May be good to start with
    // DO SUCCESSFUL PROPOSALS GET REWARDED?
    // WHAT HAPPENS IF THEIR IS A DISPUTE?
    //-How long does this take to resolve?
    //-Should a proposal cancel if there is a dispute? What happens for proposer if the assertion was valid but had been disputed unsuccessfully?
    // WHAT ARE THE ASSERTION PARAMETERS?
    // -7200 liveness
    // -1000 bond
    // -Variable bond amount depending on TVL, for greater asserter willingness on low TVL pools
    // -Variable bond so that larger pools do not need to worry about outsiders constantly freezing deposits/withdraws for a small bond amount
    // SHOULD DEPOS/WITHDRAWS BE BLOCKED UPON ASSERTION OR PIVOT EXECUTION?
    // -If the assertion bond is high, could be blocked upon assertion
    // -Could leave depos/withdraws open until assertion is settled. If there are pending transactions while assertion settles, the depos/withs are blocked and a bool on pool is set to true
    // -This true bool value allows anyone to call sendPositionChange on pool, which checks if there are still pending transactions before executing the pivot

    constructor(address _registry, uint256 _chainId) {
        // address _optimisticOracleV3
        registry = IChaserRegistry(_registry);
        ISpokePool spokePool = ISpokePool(
            registry.chainIdToSpokePoolAddress(0)
        );

        if (_chainId == 11155111) {
            umaCurrency = IERC20(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        } else {
            address umaCurrencyAddress = spokePool.wrappedNativeToken();
            umaCurrency = IERC20(umaCurrencyAddress);
        }
        oo = IOptimisticOracleV3(registry.chainIdToUmaAddress(_chainId));
        defaultIdentifier = oo.defaultIdentifier();

        chainIdToName[11155111] = "ethereum";
        chainIdToName[84532] = "base";
    }

    function queryMovePosition(
        address sender,
        uint256 requestChainId,
        string memory requestProtocol,
        bytes memory requestMarketId,
        uint256 currentDepositChainId,
        string memory currentPositionProtocol,
        bytes memory currentPositionMarketId,
        uint256 bond,
        uint256 strategyIndex
    ) external returns (bytes32) {
        require(
            registry.poolEnabled(msg.sender),
            "queryMovePosition() may only be called by a valid pool."
        );
        require(
            !poolHasAssertionOpen[msg.sender],
            "Assertion is already open on pool"
        );
        //IMPORTANT - WHO SHOULD BE ALLOWED TO OPEN A POSITION MOVE? ANYONE WITH A STAKE IN THE POOL?

        //IMPORTANT - BOND AMOUNT SHOULD BE A FUNCTION OF POOL TVL. A LOW BOND FOR A MULTI-MILLION POOL COULD BE SACRIFICED TO FRONTRUN, OR SPAMMED TO BLOCK DEPOSITS/WITH
        // require(bond >= 1000000, "Bond provided must be above 1 USDC"); // IMPORTANT - INCREASE THIS AMOUNT

        bool protocolEnabled = registry.protocolEnabled(requestProtocol);
        require(
            protocolEnabled,
            "Protocol slug must be enabled to make proposal"
        );
        address bridgeReceiver = registry.chainIdToBridgeReceiver(
            requestChainId
        );
        require(
            bridgeReceiver != address(0),
            "Chain must have a bridge receiver to request a pivot"
        );

        bytes memory data = abi.encode(
            "By accessing and executing the startegy script with the following instructions, the script returned a value of true. ",
            "Call 'readStrategyCode()' on pool at ",
            address(msg.sender),
            " and save the string as a .js file locally. ",
            "In the 'mainExecution()' function call, insert an array with the following values: ",
            chainIdToName[requestChainId],
            requestProtocol,
            requestMarketId,
            chainIdToName[currentDepositChainId],
            currentPositionProtocol,
            currentPositionMarketId
        );

        bytes32 assertionId = assertDataFor(data, sender, msg.sender, bond);

        assertionToRequestedMarketId[assertionId] = requestMarketId;
        assertionToRequestedProtocol[assertionId] = requestProtocol;
        assertionToRequestedChainId[assertionId] = requestChainId;
        assertionToPoolAddress[assertionId] = msg.sender;
        assertionToBlockTime[assertionId] =
            block.timestamp +
            ((assertionLiveness * 3) / 5);
        poolHasAssertionOpen[msg.sender] = true;

        return assertionId;
    }

    ///  @dev assertDataFor Opens the UMA assertion that must be verified using the strategy script provided
    function assertDataFor(
        bytes memory data,
        address asserter,
        address poolAddress,
        uint256 bond
    ) internal returns (bytes32 assertionId) {
        //IMPORTANT - IF POOL HAS NO CURRENT POSITION OR IF FUNDS ARE IN THE POOL CONTROL CONTRACT, APPROVE POSITION MOVEMENT IF THE DESTINATION POOL IS VALID. NO UMA ASSERTION NEEDED

        bytes32 dataId = bytes32(abi.encode(asserter));

        bool success = umaCurrency.transferFrom(asserter, address(this), bond);
        require(success, "Failed token transfer");
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

        address poolAddress = assertionToPoolAddress[assertionId];
        IPoolControl poolControl = IPoolControl(poolAddress);
        // If the assertion was true, then the data assertion is resolved.
        if (assertedTruthfully) {
            bytes memory requestMarketId = assertionToRequestedMarketId[
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

            poolHasAssertionOpen[poolAddress] = false;

            poolControl.sendPositionChange(
                requestMarketId,
                requestProtocol,
                requestChainId
            );
        } else {
            address poolAddress = assertionToPoolAddress[assertionId];
            delete assertionsData[assertionId];
            delete assertionToRequestedMarketId[assertionId];
            delete assertionToRequestedProtocol[assertionId];
            delete assertionToRequestedChainId[assertionId];
            delete assertionToPoolAddress[assertionId];
            delete assertionToBlockTime[assertionId];
            delete poolHasAssertionOpen[poolAddress];
            poolControl.handleClearPivotTarget();
        }
    }

    // If assertion is disputed, do nothing and wait for resolution.
    // This OptimisticOracleV3 callback function needs to be defined so the OOv3 doesn't revert when it tries to call it.
    function assertionDisputedCallback(bytes32 assertionId) public {
        //Clear up proposal
        //Even if the dispute was invalid, the proposal is cancelled
    }
}
