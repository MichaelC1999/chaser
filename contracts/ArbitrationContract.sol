// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.9;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOptimisticOracleV3} from "./interfaces/IOptimisticOracleV3.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";

import {IPoolControl} from "./interfaces/IPoolControl.sol";
import {ISpokePool} from "./interfaces/ISpokePool.sol";
import {AncillaryData} from "./libraries/AncillaryData.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract ArbitrationContract is OwnableUpgradeable {
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
    mapping(bytes32 => uint256) public assertionToSettleTime;
    mapping(bytes32 => uint256) public assertionToOpeningTime;
    mapping(address => bool) public poolHasAssertionOpen;
    mapping(uint256 => string) public chainIdToName;
    mapping(bytes32 => DataAssertion) public assertionsData;

    struct DataAssertion {
        bytes data; // This could be an arbitrary data type.
        address asserter; // The address that made the assertion.
        bool resolved; // Whether the assertion has been resolved.
    }

    event TestBytes(bytes);

    event DataAsserted(
        bytes data,
        address indexed asserter,
        bytes32 indexed assertionId
    );

    event DataAssertionResolved(
        bytes data,
        address indexed asserter,
        bytes32 indexed assertionId
    );

    function initialize(
        address _registry,
        uint256 _chainId
    ) public initializer {
        __Ownable_init();
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
        address _sender,
        bytes memory _claim,
        bytes memory _requestMarketId,
        string memory _requestProtocol,
        uint256 _requestChainId,
        uint256 _bond
    ) external returns (bytes32) {
        require(
            registry.poolEnabled(msg.sender),
            "queryMovePosition() may only be called by a valid pool."
        );
        require(
            !poolHasAssertionOpen[msg.sender],
            "Assertion is already open on pool"
        );

        require(
            registry.protocolEnabled(_requestProtocol),
            "Protocol slug must be enabled to make proposal"
        );
        require(
            registry.chainIdToBridgeReceiver(_requestChainId) != address(0),
            "Chain must have a bridge receiver to request a pivot"
        );

        bool success = umaCurrency.transferFrom(_sender, address(this), _bond);
        require(success, "Failed token transfer");
        umaCurrency.approve(address(oo), _bond);
        bytes32 assertionId = openProposal(_claim, _sender, _bond);
        assertionToRequestedMarketId[assertionId] = _requestMarketId;
        assertionToRequestedProtocol[assertionId] = _requestProtocol;
        assertionToRequestedChainId[assertionId] = _requestChainId;
        assertionToPoolAddress[assertionId] = msg.sender;
        assertionToBlockTime[assertionId] =
            block.timestamp +
            ((assertionLiveness * 3) / 5);
        assertionToSettleTime[assertionId] =
            block.timestamp +
            assertionLiveness;
        assertionToOpeningTime[assertionId] = block.timestamp;
        poolHasAssertionOpen[msg.sender] = true;
        return assertionId;
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
                assertionsData[assertionId].data,
                assertionsData[assertionId].asserter,
                true
            );

            emit DataAssertionResolved(
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
            cancelAssertion(assertionId);
        }
    }

    function openProposal(
        bytes memory claim,
        address sender,
        uint256 bond
    ) internal returns (bytes32) {
        bytes32 assertionId = oo.assertTruth(
            claim,
            sender,
            address(this),
            address(0), // No sovereign security.
            assertionLiveness,
            umaCurrency,
            bond,
            defaultIdentifier,
            bytes32(0) // No domain.
        );
        assertionsData[assertionId] = DataAssertion(claim, sender, false);

        emit DataAsserted(claim, sender, assertionId);

        return assertionId;
    }

    // If assertion is disputed, do nothing and wait for resolution.
    // If the assertion is disputed, cancel the proposal for the pool pivot
    function assertionDisputedCallback(bytes32 assertionId) public {
        cancelAssertion(assertionId);
    }

    function cancelAssertion(bytes32 assertionId) internal {
        address poolAddress = assertionToPoolAddress[assertionId];
        delete assertionsData[assertionId];
        delete assertionToRequestedMarketId[assertionId];
        delete assertionToRequestedProtocol[assertionId];
        delete assertionToRequestedChainId[assertionId];
        delete assertionToPoolAddress[assertionId];
        delete assertionToBlockTime[assertionId];
        delete assertionToSettleTime[assertionId];
        delete assertionToOpeningTime[assertionId];
        delete poolHasAssertionOpen[poolAddress];
    }

    function readAssertionRequestedPosition(
        bytes32 assertionId
    ) external view returns (bytes memory, string memory, uint256, uint256) {
        return (
            assertionToRequestedMarketId[assertionId],
            assertionToRequestedProtocol[assertionId],
            assertionToRequestedChainId[assertionId],
            assertionToOpeningTime[assertionId]
        );
    }

    function generateClaim(
        uint256 requestChainId,
        string memory requestProtocol,
        bytes memory requestMarketId,
        uint256 currentDepositChainId,
        string memory currentPositionProtocol,
        bytes memory currentPositionMarketId
    ) public view returns (bytes memory) {
        return
            abi.encodePacked(
                "The market proposed in this assertion is currently a better investment than the market where pool 0x",
                AncillaryData.toUtf8BytesAddress(address(msg.sender)),
                " currently has deposits, as defined by the output of its strategy code. By accessing and executing the startegy script with the following instructions, ",
                "the script confirms this claim by returning true. 1) Call 'readStrategyCode()' on the pool contract. 2) Save the string output as `strategyScript.js` locally. 3) Confirm that the output of executing this script is `true` by running the following command: "
                "`node strategyScript.js ",
                abi.encodePacked(
                    AncillaryData.toUtf8BytesUint(currentDepositChainId),
                    " ",
                    AncillaryData.toUtf8BytesUint(requestChainId),
                    " ",
                    AncillaryData.toUtf8Bytes(bytes32(currentPositionMarketId)),
                    " ",
                    AncillaryData.toUtf8Bytes(bytes32(requestMarketId)),
                    " ",
                    currentPositionProtocol,
                    " ",
                    requestProtocol,
                    "`"
                )
            );
    }

    function inAssertionBlockWindow(
        bytes32 assertionId
    ) external view returns (bool) {
        return (assertionToBlockTime[assertionId] < block.timestamp);
    }
}
