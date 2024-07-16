// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {IPoolControl} from "./interfaces/IPoolControl.sol";
import {IArbitrationContract} from "./interfaces/IArbitrationContract.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title Pool Calculations
/// @notice Provides detailed calculations and state management for pool operations including deposits, withdrawals, and pivots
contract PoolCalculations is OwnableUpgradeable {
    uint256 public protocolFeePct; //Where 1000000 = 100%

    mapping(bytes32 => address) public depositIdToDepositor;
    mapping(bytes32 => uint256) public depositIdToDepositAmount;
    mapping(bytes32 => uint256) public depositIdToDepoNonce;
    mapping(bytes32 => bool) public depositIdToTokensMinted;

    mapping(bytes32 => address) public withdrawIdToDepositor;
    mapping(bytes32 => uint256) public withdrawIdToAmount;
    mapping(bytes32 => uint256) public withdrawIdToOutputAmount;
    mapping(bytes32 => uint256) public withdrawIdToUserPoolTokens;
    mapping(bytes32 => uint256) public withdrawIdToWithNonce;
    mapping(bytes32 => bool) public withdrawIdToTokensBurned;

    mapping(address => uint256) public poolToPendingDeposits;
    mapping(address => uint256) public poolToPendingWithdraws;
    mapping(address => uint256) public poolToTimeout;
    mapping(address => uint256) public poolDepositOpenedNonce;
    mapping(address => uint256) public poolDepositFinishedNonce;
    mapping(address => uint256) public poolWithdrawNonce;
    mapping(address => uint256) public poolPivotNonce;
    mapping(address => bool) public poolToPivotPending;

    mapping(address => bytes) public targetPositionMarketId; //Market address to be passed to BridgeLogic, Not final address that actually holds deposits
    mapping(address => uint256) public targetPositionChain;
    mapping(address => bytes32) public targetPositionProtocolHash;
    mapping(address => string) public targetPositionProtocol;

    mapping(address => address) public currentPositionAddress;
    mapping(address => bytes) public currentPositionMarketId;
    mapping(address => bytes32) public currentPositionProtocolHash;
    mapping(address => string) public currentPositionProtocol;
    mapping(address => uint256) public currentRecordPositionValue; //This holds the most recently position value as of the last finalized transaction, not real-time.
    mapping(address => uint256) public currentPositionValueTimestamp;

    mapping(address => mapping(address => uint256))
        public poolToUserWithdrawTimeout;

    event HandleUndo(string);

    IChaserRegistry public registry;

    /// @notice Initializes the PoolCalculations contract, replacing the constructor
    /// @param _registryAddress Address of the ChaserRegistry contract
    function initialize(address _registryAddress) public initializer {
        __Ownable_init();
        registry = IChaserRegistry(_registryAddress);
    }

    modifier onlyValidPool() {
        require(
            registry.poolEnabled(msg.sender),
            "Only valid pools may use this calculations contract"
        );
        _;
    }

    modifier noPending(address _sender, bytes32 _openAssertion) {
        require(
            !poolToPivotPending[msg.sender],
            "If a pivot proposal has been approved, no position entrances are allowed"
        );
        require(
            _openAssertion == bytes32("") ||
                !IArbitrationContract(registry.arbitrationContract())
                    .inAssertionBlockWindow(_openAssertion),
            "An open pivot proposal has passed position entrance window. Wait until this pivot settles."
        );
        _;
    }

    function setProtocolFeePct(uint256 feePct) public onlyOwner {
        protocolFeePct = feePct;
    }

    /// @notice Creates a withdrawal order in state
    /// @dev Marks a withdrawal as pending and records its details
    /// @param _amount Amount the user requests to withdraw
    /// @param _poolToken Address of the pool token
    /// @param _sender Address of the user initiating the withdrawal
    /// @param _openAssertion Assertion ID related to any active pivot proposals. Passed to check if assertion is in the block window
    /// @return Encoded data necessary for processing the withdrawal on BridgeLogic
    function createWithdrawOrder(
        uint256 _amount,
        address _poolToken,
        address _sender,
        bytes32 _openAssertion
    )
        external
        onlyValidPool
        noPending(_sender, _openAssertion)
        returns (bytes32, bytes memory)
    {
        require(
            poolToUserWithdrawTimeout[msg.sender][_sender] < block.timestamp,
            "Cannot open withdraw when user already has a valid withdraw open."
        );

        bytes32 withdrawId = keccak256(
            abi.encode(msg.sender, _sender, _amount, block.timestamp)
        );

        withdrawIdToDepositor[withdrawId] = _sender;
        withdrawIdToAmount[withdrawId] = _amount;
        withdrawIdToUserPoolTokens[withdrawId] = IERC20(_poolToken).balanceOf(
            _sender
        );
        poolToTimeout[msg.sender] = block.timestamp + 4200;
        poolToUserWithdrawTimeout[msg.sender][_sender] = block.timestamp + 4200;
        poolToPendingWithdraws[msg.sender] += 1;
        poolWithdrawNonce[msg.sender] += 1;
        withdrawIdToWithNonce[withdrawId] = poolWithdrawNonce[msg.sender];

        uint256 scaledRatio = getScaledRatio(_poolToken, _sender);

        bytes memory data = abi.encode(
            withdrawId,
            _amount,
            poolDepositFinishedNonce[msg.sender],
            poolWithdrawNonce[msg.sender],
            scaledRatio
        );
        return (withdrawId, data);
    }

    /// @notice Completes a withdrawal order, calculating pool tokens to burn
    /// @param _withdrawId Unique identifier of the withdrawal
    /// @param _positionValue Last recorded value of the pool's position
    /// @param _totalAvailableForUser Total funds available for the user to withdraw (denominated in asset)
    /// @return Address of the depositor and the number of pool tokens to burn
    function fulfillWithdrawOrder(
        bytes32 _withdrawId,
        uint256 _positionValue,
        uint256 _totalAvailableForUser
    ) external onlyValidPool returns (address, uint256) {
        require(
            !withdrawIdToTokensBurned[_withdrawId],
            "Tokens have already been burned for this withdraw"
        );
        address poolAddress = msg.sender;
        address depositor = withdrawIdToDepositor[_withdrawId];
        uint256 inputAmount = withdrawIdToAmount[_withdrawId];
        poolToPendingWithdraws[poolAddress] -= 1;
        currentPositionValueTimestamp[poolAddress] = block.timestamp;
        poolToUserWithdrawTimeout[msg.sender][depositor] = 0;
        currentRecordPositionValue[poolAddress] = _positionValue;

        if (_totalAvailableForUser < inputAmount) {
            inputAmount = _totalAvailableForUser;
        }
        uint256 poolTokensToBurn = withdrawIdToUserPoolTokens[_withdrawId];
        if (_totalAvailableForUser > 0) {
            uint256 ratio = (inputAmount * (10 ** 18)) /
                (_totalAvailableForUser);
            poolTokensToBurn =
                (ratio * withdrawIdToUserPoolTokens[_withdrawId]) /
                (10 ** 18);
        }

        withdrawIdToTokensBurned[_withdrawId] = true;

        return (depositor, poolTokensToBurn);
    }

    function setWithdrawReceived(
        bytes32 _withdrawId,
        uint256 _outputAmount
    ) external onlyValidPool returns (address) {
        withdrawIdToOutputAmount[_withdrawId] = _outputAmount;
        return withdrawIdToDepositor[_withdrawId];
    }

    /// @notice Opens a new position setup for the pool, initializing state for a pivot operation
    /// @param _targetPositionMarketId Market ID for the new position, used during pivot proposal to query the subgraph
    /// @param _targetProtocol Protocol under which the new position will be managed
    /// @param _targetChainId Chain ID where the new position will be set
    /// @return The market address derived from the provided market ID (will pass aditional conversion on the destination chain)
    function openSetPosition(
        bytes memory _targetPositionMarketId,
        string memory _targetProtocol,
        uint256 _targetChainId
    ) external onlyValidPool returns (address) {
        if (poolToPivotPending[msg.sender] == true) {
            currentPositionAddress[msg.sender] = address(0);
            currentPositionMarketId[msg.sender] = abi.encode(0);
            currentPositionProtocolHash[msg.sender] = bytes32("");
            currentPositionProtocol[msg.sender] = "";
        }
        poolTimeout();
        poolToPivotPending[msg.sender] = true;
        poolToTimeout[msg.sender] = block.timestamp + 7200;
        poolPivotNonce[msg.sender] += 1;
        targetPositionMarketId[msg.sender] = _targetPositionMarketId;
        targetPositionProtocolHash[msg.sender] = keccak256(
            abi.encode(_targetProtocol)
        );
        targetPositionProtocol[msg.sender] = _targetProtocol;
        targetPositionChain[msg.sender] = _targetChainId;

        return
            getMarketAddressFromId(
                _targetPositionMarketId,
                targetPositionProtocolHash[msg.sender]
            );
    }

    /// @notice Registers a new deposit order
    /// @param _sender Address of the user making the deposit
    /// @param _poolToken Address of the asset involved in the deposit
    /// @param _amount Amount being deposited
    /// @param _openAssertion Assertion ID related to any active pivot proposals
    /// @return Deposit ID and the current withdrawal nonce
    function createDepositOrder(
        address _sender,
        address _poolToken,
        uint256 _amount,
        bytes32 _openAssertion
    )
        external
        onlyValidPool
        noPending(_sender, _openAssertion)
        returns (bytes32, uint256, uint256)
    {
        bytes32 depositId = bytes32(
            keccak256(abi.encode(msg.sender, _sender, _amount, block.timestamp))
        );

        depositIdToDepositor[depositId] = _sender;
        depositIdToDepositAmount[depositId] = _amount;
        depositIdToTokensMinted[depositId] = false;
        poolToTimeout[msg.sender] = block.timestamp + 4200;
        poolToPendingDeposits[msg.sender] += 1;
        poolDepositOpenedNonce[msg.sender] += 1;
        depositIdToDepoNonce[depositId] = poolDepositOpenedNonce[msg.sender];

        return (
            depositId,
            poolWithdrawNonce[msg.sender],
            poolDepositOpenedNonce[msg.sender]
        );
    }

    /// @notice Callback for deposit processing. Updates pool state
    /// @param _depositId Unique identifier for the deposit
    /// @param _positionAmount Updated amount of the pool's total position
    /// @param _depositAmountReceived Actual amount deposited into the position, accounting for any fees during processing
    function updateDepositReceived(
        bytes32 _depositId,
        uint256 _positionAmount,
        uint256 _depositAmountReceived
    ) external onlyValidPool {
        require(
            depositIdToDepositor[_depositId] != address(0),
            "depositId must point to recorded depositor"
        );
        require(
            !depositIdToTokensMinted[_depositId],
            "Deposit has already minted tokens"
        );
        currentRecordPositionValue[msg.sender] = _positionAmount;
        currentPositionValueTimestamp[msg.sender] = block.timestamp;
        poolDepositFinishedNonce[msg.sender] = depositIdToDepoNonce[_depositId];
        if (poolToPendingDeposits[msg.sender] > 0) {
            poolToPendingDeposits[msg.sender] -= 1;
        }
        depositIdToDepositAmount[_depositId] = _depositAmountReceived;
        depositIdToTokensMinted[_depositId] = true;
    }

    /// @notice Finalizes a pivot operation, updating the current position state
    /// @param marketAddress Address of the new market where the position is now held (the address on which functions are called)
    /// @param positionAmount New total amount of the position
    function pivotCompleted(
        address marketAddress,
        uint256 positionAmount
    ) external onlyValidPool {
        currentPositionMarketId[msg.sender] = targetPositionMarketId[
            msg.sender
        ];
        currentPositionProtocolHash[msg.sender] = targetPositionProtocolHash[
            msg.sender
        ];
        currentPositionProtocol[msg.sender] = targetPositionProtocol[
            msg.sender
        ];

        targetPositionMarketId[msg.sender] = abi.encode(0);
        targetPositionChain[msg.sender] = 0;
        targetPositionProtocol[msg.sender] = "";
        targetPositionProtocolHash[msg.sender] = bytes32("");
        poolToPivotPending[msg.sender] = false;
        poolToTimeout[msg.sender] = 0;
        currentPositionAddress[msg.sender] = marketAddress;
        currentRecordPositionValue[msg.sender] = positionAmount;
        currentPositionValueTimestamp[msg.sender] = block.timestamp;
    }

    function poolTimeout() internal {
        uint256 pendCount = 0;
        pendCount += poolToPendingDeposits[msg.sender];
        pendCount += poolToPendingWithdraws[msg.sender];
        if (pendCount > 0 || poolToPivotPending[msg.sender] == true) {
            bool blocked = checkPivotBlock(msg.sender);
            require(blocked == false, "Still Awaiting Pending transactions.");
        }
        poolToPendingDeposits[msg.sender] = 0;
        poolToPendingWithdraws[msg.sender] = 0;
    }

    function checkPivotBlock(address _poolAddress) public view returns (bool) {
        bool pivotBlocked = false;
        // if ( // IMPORTANT - UNCOMMENT AFTER TESTING
        //     poolToPivotPending[_poolAddress] == true &&
        //     poolToTimeout[msg.sender] > block.timestamp
        // ) {
        //     pivotBlocked = true;
        // }
        return pivotBlocked;
    }

    /// @notice Provides the current position data of a pool
    /// @param _poolAddress Address of the pool
    /// @return Current position details including protocol, market ID, and pivot pending status
    function getCurrentPositionData(
        address _poolAddress
    )
        external
        view
        onlyValidPool
        returns (string memory, bytes memory, bool, bool)
    {
        bool pivotBlocked = checkPivotBlock(_poolAddress);
        return (
            currentPositionProtocol[_poolAddress],
            currentPositionMarketId[_poolAddress],
            poolToPivotPending[_poolAddress],
            pivotBlocked
        );
    }

    /// @notice Prepares the message data needed for setting an initial position
    /// @param _depositId Deposit identifier
    /// @param _sender Address of the user or entity
    /// @return Encoded data to send to BridgeLogic for setting up the position
    function createInitialSetPositionMessage(
        bytes32 _depositId,
        address _sender
    ) external view returns (bytes memory) {
        address marketAddress = getMarketAddressFromId(
            targetPositionMarketId[msg.sender],
            targetPositionProtocolHash[msg.sender]
        );
        return
            abi.encode(
                _depositId,
                _sender,
                marketAddress,
                targetPositionProtocolHash[msg.sender]
            );
    }

    /// @notice Creates the message data required for executing a pivot exit operation
    /// @param _destinationBridgeReceiver Address of the bridge receiver on the destination chain
    /// @return Encoded data including protocol hash, market address, destination chain ID and BridgeReceiver address on the destination chain
    function createPivotExitMessage(
        address _destinationBridgeReceiver,
        uint256 _proposalRewardUSDC,
        address _asset
    ) external view returns (bytes memory) {
        address marketAddress = getMarketAddressFromId(
            targetPositionMarketId[msg.sender],
            targetPositionProtocolHash[msg.sender]
        );
        bytes memory data = abi.encode(
            targetPositionProtocolHash[msg.sender],
            marketAddress,
            targetPositionChain[msg.sender],
            _destinationBridgeReceiver,
            protocolFeePct,
            _proposalRewardUSDC,
            _asset
        );
        return data;
    }

    /// @notice Derives the market address from a given market ID for different protocols
    /// @dev Further processing is done on destination chain, as it may need read calls on protocol contracts to derive the true interaction address
    /// @param _marketId Encoded ID of the market
    /// @param _protocolHash Protocol hash
    /// @return The resolved address of the market
    function getMarketAddressFromId(
        bytes memory _marketId,
        bytes32 _protocolHash
    ) public view returns (address) {
        address marketAddress;
        if (_protocolHash == keccak256(abi.encode("aave-v3"))) {
            (marketAddress, ) = IArbitrationContract(
                registry.arbitrationContract()
            ).extractAddressesFromBytes(_marketId);
        } else if (_protocolHash == keccak256(abi.encode("compound-v3"))) {
            (marketAddress, ) = IArbitrationContract(
                registry.arbitrationContract()
            ).extractAddressesFromBytes(_marketId);
        }

        return marketAddress;
    }

    /// @notice Calculates the amount of pool tokens to mint for a deposit
    /// @dev On the first deposit of a pool, mint 10**x tokens
    /// @param _depositId Identifier for the deposit
    /// @param _poolAddress Address of pool to calculate for
    /// @param _poolToken Address of token used on pool for accounting purposes
    /// @return Number of pool tokens to mint and the address of the depositor
    function calculatePoolTokensToMint(
        bytes32 _depositId,
        address _poolAddress,
        address _poolToken
    ) external view returns (uint256, address) {
        uint256 assetAmount = depositIdToDepositAmount[_depositId];
        address depositor = depositIdToDepositor[_depositId];
        uint256 poolTokensToMint;
        if (_poolToken == address(0)) {
            uint256 supplyFactor = (Math.log10(assetAmount));
            poolTokensToMint = 10 ** supplyFactor;
        } else {
            IERC20 poolToken = IERC20(_poolToken);
            uint256 ratio = (assetAmount * (10 ** 18)) /
                (currentRecordPositionValue[_poolAddress] - assetAmount);
            poolTokensToMint = (ratio * poolToken.totalSupply()) / (10 ** 18);
        }

        return (poolTokensToMint, depositor);
    }

    /// @notice Calculates the scaled ratio of user's pool tokens to the total supply
    /// @param _poolToken Address of the pool token
    /// @param _sender Address of the token holder
    /// @return Scaled ratio as a factor of 10^18
    function getScaledRatio(
        address _poolToken,
        address _sender
    ) public view returns (uint256) {
        IERC20 poolToken = IERC20(_poolToken);

        uint256 userPoolTokenBalance = poolToken.balanceOf(_sender);
        if (userPoolTokenBalance == 0) {
            return 0;
        }
        uint256 poolTokenSupply = poolToken.totalSupply();
        require(poolTokenSupply > 0, "Pool Token has no supply");

        uint256 scaledRatio = (10 ** 18);
        if (userPoolTokenBalance != poolTokenSupply) {
            scaledRatio =
                (userPoolTokenBalance * (10 ** 18)) /
                (poolTokenSupply);
        }
        return scaledRatio;
    }

    /// @notice Reads detailed data about the current position of the pool
    /// @param _poolAddress Address of the pool
    /// @return Current position details including address, protocol hash, market ID, and latest recorded values
    function readCurrentPositionData(
        address _poolAddress
    )
        external
        view
        returns (
            address,
            bytes32,
            uint256,
            uint256,
            string memory,
            bytes memory
        )
    {
        return (
            currentPositionAddress[_poolAddress],
            currentPositionProtocolHash[_poolAddress],
            currentRecordPositionValue[_poolAddress],
            currentPositionValueTimestamp[_poolAddress],
            currentPositionProtocol[_poolAddress],
            currentPositionMarketId[_poolAddress]
        );
    }

    /// @notice Provides transaction status details for a pool
    /// @param _poolAddress Address of the pool
    /// @return Current nonces for deposits and withdrawals, and whether a pivot is pending
    function poolTransactionStatus(
        address _poolAddress
    ) external view returns (uint256, uint256, bool) {
        return (
            poolDepositOpenedNonce[_poolAddress],
            poolWithdrawNonce[_poolAddress],
            poolToPivotPending[_poolAddress]
        );
    }
}
