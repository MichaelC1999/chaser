// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.9;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOptimisticOracleV3} from "./interfaces/IOptimisticOracleV3.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {IChaserTreasury} from "./interfaces/IChaserTreasury.sol";
import {IPoolControl} from "./interfaces/IPoolControl.sol";
import {ISpokePool} from "./interfaces/ISpokePool.sol";
import {AncillaryData} from "./libraries/AncillaryData.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IPoolCalculations} from "./interfaces/IPoolCalculations.sol";

/// @title ArbitrationContract
/// @dev This contract integrates with UMA Optimistic Oracle and handles assertion behaviors
/// @notice This contract utilizes UMA's Optimistic Oracle for judging proposed movements of Chaser pool investments
contract ArbitrationContract is OwnableUpgradeable {
    address public umaCurrency;
    IOptimisticOracleV3 public oo;
    bytes32 public defaultIdentifier;
    IChaserRegistry public registry;
    uint256 currentChainId;

    mapping(bytes32 => bytes) public assertionToRequestedMarketId;
    mapping(bytes32 => string) public assertionToRequestedProtocol;
    mapping(bytes32 => uint256) public assertionToRequestedChainId;
    mapping(bytes32 => address) public assertionToPoolAddress;
    mapping(bytes32 => uint256) public assertionToBlockTime;
    mapping(bytes32 => uint256) public assertionToSettleTime;
    mapping(bytes32 => uint256) public assertionToOpeningTime;
    mapping(bytes32 => uint256) public assertionToReward;
    mapping(address => uint256) public poolPivotedTimestamp;
    mapping(address => bool) public poolHasAssertionOpen;
    mapping(address => uint256) public poolBondUSDC;
    mapping(address => uint64) public poolLiveness;
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

    /// @notice Initializes the contract upon initial deployment, replacing the constructor
    /// @param _registry Address of the registry contract
    /// @param _chainId Local Chain ID that this contract is deployed on, to set up specific parameters
    function initialize(
        address _registry,
        uint256 _chainId
    ) public initializer {
        __Ownable_init();
        registry = IChaserRegistry(_registry);
        ISpokePool spokePool = ISpokePool(
            registry.chainIdToSpokePoolAddress(0)
        );

        addConfigsUMA(_chainId);
        currentChainId = _chainId;
    }

    function addConfigsUMA(uint256 _chainId) public onlyOwner {
        umaCurrency = registry.addressUSDC(_chainId);

        address localOOaddress = registry.chainIdToUmaAddress(_chainId);
        if (localOOaddress != address(0)) {
            oo = IOptimisticOracleV3(localOOaddress);
            // defaultIdentifier = oo.defaultIdentifier(); // IMPORTANT - UNDO
        }
    }

    /// @notice Requests a position move through the Optimistic Oracle
    /// @dev Transfers the bond, makes call to open up an assertion, adds values for the new assertion
    /// @param _sender The address initiating the position move request
    /// @param _claim Data associated with the claim (generated by generateClaim())
    /// @param _requestMarketId Market ID for the requested position
    /// @param _requestProtocol Protocol name for the requested position
    /// @param _requestChainId Requested position Chain ID to bridge to
    /// @param _proposalRewardUSDC Amount of currency rewarded for the proposal
    /// @return assertionId Generated identifier for the new assertion
    function queryMovePosition(
        address _sender,
        bytes memory _claim,
        bytes memory _requestMarketId,
        string memory _requestProtocol,
        uint256 _requestChainId,
        uint256 _proposalRewardUSDC
    ) external returns (bytes32) {
        uint256 poolDepoNonce = IPoolCalculations(
            registry.poolCalculationsAddress()
        ).poolDepositFinishedNonce(msg.sender);
        require(
            poolDepoNonce > 0,
            "The initial deposit and position set must be the first position interaction on a pool"
        );

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

        require(
            block.timestamp - 10800 >= poolPivotedTimestamp[msg.sender],
            "A new pivot may only be proposed 3 hours after resolving the previous pivot"
        );

        uint256 rewardDebt = IChaserTreasury(registry.treasuryAddress())
            .poolToRewardDebt(msg.sender);

        uint64 liveness = 360; //IMPORTANT - PRODUCTION 7200
        if (poolLiveness[msg.sender] > 0) {
            liveness = poolLiveness[msg.sender];
        }

        if (address(oo) != address(0)) {
            bool success = IERC20(umaCurrency).transferFrom(
                _sender,
                address(this),
                poolBondUSDC[msg.sender]
            );
            require(success, "Failed token transfer");
            IERC20(umaCurrency).approve(address(oo), poolBondUSDC[msg.sender]);
        }
        bytes32 assertionId = openProposal(
            _claim,
            _sender,
            poolBondUSDC[msg.sender],
            liveness
        );
        assertionToRequestedMarketId[assertionId] = _requestMarketId;
        assertionToRequestedProtocol[assertionId] = _requestProtocol;
        assertionToRequestedChainId[assertionId] = _requestChainId;
        assertionToPoolAddress[assertionId] = msg.sender;
        assertionToBlockTime[assertionId] =
            block.timestamp +
            ((liveness * 3) / 5);
        assertionToSettleTime[assertionId] = block.timestamp + liveness;
        assertionToOpeningTime[assertionId] = block.timestamp;
        assertionToReward[assertionId] = _proposalRewardUSDC + rewardDebt;
        poolHasAssertionOpen[msg.sender] = true;
        return assertionId;
    }

    /// @dev Internal function to open proposal on the Optimistic Oracle
    /// @param claim The claim generated to propose the pivot
    /// @param asserter The address making the claim
    /// @param bond The amount of bond posted for the claim
    /// @return assertionId Identifier for the created assertion
    function openProposal(
        bytes memory claim,
        address asserter,
        uint256 bond,
        uint64 liveness
    ) internal returns (bytes32) {
        bytes32 assertionId = keccak256(
            abi.encodePacked(claim, block.timestamp)
        );
        if (address(oo) != address(0)) {
            assertionId = oo.assertTruth(
                claim,
                asserter,
                address(this),
                address(0), // No sovereign security.
                liveness,
                IERC20(umaCurrency),
                bond,
                defaultIdentifier,
                bytes32(0) // No domain.
            );
        }
        assertionsData[assertionId] = DataAssertion(claim, asserter, false);

        emit DataAsserted(claim, asserter, assertionId);

        return assertionId;
    }

    /// @notice Callback function for handling resolved assertions from the Optimistic Oracle
    /// @notice If the assertion resolves to true, execute the pivot. If false cancel and delete all position entries saved in mappings
    /// @dev Called directly by oracle upon resolution
    /// @param assertionId Identifier of the assertion
    /// @param assertedTruthfully Boolean indicating if the assertion was resolved as true
    function assertionResolvedCallback(
        bytes32 assertionId,
        bool assertedTruthfully
    ) external {
        if (address(oo) != address(0)) {
            require(
                msg.sender == address(oo),
                "Callback may only be called by UMA oracle"
            );
        }
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
            poolPivotedTimestamp[poolAddress] = block.timestamp;

            poolControl.sendPositionChange(
                requestMarketId,
                requestProtocol,
                requestChainId
            );
        } else {
            cancelAssertion(assertionId);
        }
    }

    /// @notice Handles the callback for disputed assertions
    /// @dev Called by the Optimistic Oracle when an assertion is disputed
    /// @dev  If the assertion is disputed, cancel the proposal for the pool pivot. Open back up interactions on the pool.
    /// @param assertionId The identifier of the disputed assertion
    function assertionDisputedCallback(bytes32 assertionId) public {
        cancelAssertion(assertionId);
    }

    /// @dev Internal function to cancel an assertion and clean up related data
    /// @param assertionId Identifier of the assertion to cancel
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

    function setArbitrationConfigs(
        address _poolAddress,
        uint256 _bondUSDC,
        uint256 _livenessLevel
    ) external {
        poolBondUSDC[_poolAddress] = _bondUSDC;
        uint64 liveness = 7200;
        if (_livenessLevel == 1) {
            liveness = 3600 * 12;
        }
        if (_livenessLevel == 2) {
            liveness = 3600 * 24;
        }
        poolLiveness[_poolAddress] = liveness;
    }

    /// @notice Retrieves details of a requested position change
    /// @param assertionId The identifier of the assertion to query
    /// @return Tuple containing details of the requested position change
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

    /// @notice Generates a claim data packet to be reviewed by the UMA Oracle. Called by the pool before calling queryMovePosition()
    /// @dev Encodes current and requested position data, inserts it into a hardcoded proposal template and returns the bytes to be sent as the claim
    /// @param requestChainId The target chain ID for the position change
    /// @param requestProtocol Protocol identifier for the position change
    /// @param requestMarketId Market ID for the position change
    /// @param currentDepositChainId Current chain ID where deposits are held
    /// @param currentPositionProtocol Current protocol for the pool
    /// @param currentPositionMarketId Current market ID for the pool
    /// @return bytes Encoded claim data
    function generateClaim(
        uint256 requestChainId,
        string memory requestProtocol,
        bytes memory requestMarketId,
        uint256 currentDepositChainId,
        string memory currentPositionProtocol,
        bytes memory currentPositionMarketId
    ) public view returns (bytes memory) {
        (bytes memory curMarket, bytes memory reqMarket) = getMarketBytes(
            currentPositionMarketId,
            requestMarketId
        );

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
                    " 0x",
                    curMarket,
                    " 0x",
                    reqMarket,
                    " ",
                    currentPositionProtocol,
                    " ",
                    requestProtocol,
                    "`"
                )
            );
    }

    /// @dev Helper function to convert market IDs into a byte format compatible for use in subgraph queries
    /// @param currentPositionMarketId Current market ID in byte format
    /// @param requestMarketId Requested market ID in byte format
    /// @return Tuple of bytes for current and requested market addresses
    function getMarketBytes(
        bytes memory currentPositionMarketId,
        bytes memory requestMarketId
    ) public view returns (bytes memory, bytes memory) {
        (address curAddr1, address curAddr2) = extractAddressesFromBytes(
            currentPositionMarketId
        );
        (address reqAddr1, address reqAddr2) = extractAddressesFromBytes(
            requestMarketId
        );

        bytes memory curMarket = AncillaryData.toUtf8BytesAddress(curAddr1);
        if (curAddr2 != address(0)) {
            curMarket = abi.encodePacked(
                curMarket,
                AncillaryData.toUtf8BytesAddress(curAddr2)
            );
        }

        bytes memory reqMarket = AncillaryData.toUtf8BytesAddress(reqAddr1);
        if (reqAddr2 != address(0)) {
            reqMarket = abi.encodePacked(
                reqMarket,
                AncillaryData.toUtf8BytesAddress(reqAddr2)
            );
        }

        return (curMarket, reqMarket);
    }

    /// @notice Extracts two Ethereum addresses from a market ID in the form of bytes input
    /// @dev Splits a bytes input into two address parts, handling cases with one or two addresses
    /// @param input Bytes input containing up to two Ethereum addresses
    /// @return addr1 The first extracted address
    /// @return addr2 The second extracted address (or zero if not present)
    function extractAddressesFromBytes(
        bytes memory input
    ) public pure returns (address addr1, address addr2) {
        assembly {
            addr1 := mload(add(input, 20))
        }

        if (input.length == 40) {
            assembly {
                addr2 := mload(add(input, 40))
            }
        } else {
            addr2 = address(0);
        }
    }

    /// @notice Checks if the current timestamp is within the assertion block window
    /// @dev Compares the current block timestamp against the stored assertion block time
    /// @param assertionId The identifier of the assertion to check
    /// @return bool True if current time is within the block window, false otherwise
    function inAssertionBlockWindow(
        bytes32 assertionId
    ) external view returns (bool) {
        bool assertionTimedOut = (assertionToBlockTime[assertionId] + 360000) <
            block.timestamp;
        return (assertionToBlockTime[assertionId] < block.timestamp &&
            !assertionTimedOut);
    }
}
