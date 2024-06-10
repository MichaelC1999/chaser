// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {IArbitrationContract} from "./interfaces/IArbitrationContract.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title Pool Calculations
/// @notice Provides detailed calculations and state management for pool operations including deposits, withdrawals, and pivots
contract PoolCalculations is OwnableUpgradeable {
    uint256 public protocolFeePct; //Where 1000000 = 100%

    mapping(bytes32 => address) public depositIdToDepositor;
    mapping(bytes32 => uint256) public depositIdToDepositAmount;
    mapping(bytes32 => bool) public depositIdToTokensMinted;
    mapping(bytes32 => uint256) public depositIdToPoolTokenSupply;
    mapping(address => uint256) public poolToPendingDeposits;

    mapping(bytes32 => address) public withdrawIdToDepositor;
    mapping(bytes32 => uint256) public withdrawIdToAmount;
    mapping(bytes32 => uint256) public withdrawIdToUserPoolTokens;
    mapping(bytes32 => bool) public withdrawIdToTokensBurned;
    mapping(address => uint256) public poolToPendingWithdraws;

    mapping(address => uint256) public poolDepositNonce;
    mapping(address => uint256) public poolWithdrawNonce;
    mapping(address => uint256) public poolPivotNonce;
    mapping(address => bool) public poolToPivotPending;

    mapping(address => mapping(address => bool))
        public poolToUserPendingWithdraw;
    mapping(address => mapping(address => bool))
        public poolToUserPendingDeposit;

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

    event DepositRecorded(bytes32, uint256);
    event WithdrawRecorded(bytes32, uint256);
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
        require(
            !poolToUserPendingDeposit[msg.sender][_sender],
            "User cannot have deposit pending on this pool"
        );
        require(
            !poolToUserPendingWithdraw[msg.sender][_sender],
            "User cannot have withdraw pending on this pool"
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
        returns (bytes memory)
    {
        poolToUserPendingWithdraw[msg.sender][_sender] = true;

        bytes32 withdrawId = keccak256(
            abi.encode(msg.sender, _sender, _amount, block.timestamp)
        );

        withdrawIdToDepositor[withdrawId] = _sender;
        withdrawIdToAmount[withdrawId] = _amount;
        withdrawIdToUserPoolTokens[withdrawId] = IERC20(_poolToken).balanceOf(
            _sender
        );
        poolToPendingWithdraws[msg.sender] += _amount;
        poolWithdrawNonce[msg.sender] += 1;
        emit WithdrawRecorded(withdrawId, _amount);

        uint256 scaledRatio = getScaledRatio(_poolToken, _sender);

        bytes memory data = abi.encode(
            withdrawId,
            _amount,
            poolDepositNonce[msg.sender],
            poolWithdrawNonce[msg.sender],
            scaledRatio
        );
        return data;
    }

    /// @notice Completes a withdrawal order, calculating pool tokens to burn
    /// @param _withdrawId Unique identifier of the withdrawal
    /// @param _positionValue Last recorded value of the pool's position
    /// @param _totalAvailableForUser Total funds available for the user to withdraw (denominated in asset)
    /// @param _amount Amount fully deducted from pool, including fees (inputAmount)
    /// @param _poolToken Address of the pool token contract
    /// @return Address of the depositor and the number of pool tokens to burn
    function fulfillWithdrawOrder(
        bytes32 _withdrawId,
        uint256 _positionValue,
        uint256 _totalAvailableForUser,
        uint256 _amount,
        address _poolToken
    ) external onlyValidPool returns (address, uint256) {
        require(
            !withdrawIdToTokensBurned[_withdrawId],
            "Tokens have already been burned for this withdraw"
        );
        address depositor = withdrawIdToDepositor[_withdrawId];
        address poolAddress = msg.sender;

        currentRecordPositionValue[poolAddress] = _positionValue;
        currentPositionValueTimestamp[poolAddress] = block.timestamp;

        if (_totalAvailableForUser < _amount) {
            _amount = _totalAvailableForUser;
        }
        uint256 poolTokensToBurn = withdrawIdToUserPoolTokens[_withdrawId];
        if (_totalAvailableForUser > 0) {
            uint256 ratio = (_amount * (10 ** 18)) / (_totalAvailableForUser);
            poolTokensToBurn =
                (ratio * withdrawIdToUserPoolTokens[_withdrawId]) /
                (10 ** 18);
        }

        poolToUserPendingWithdraw[poolAddress][depositor] = false;
        poolToPendingWithdraws[poolAddress] -= withdrawIdToAmount[_withdrawId];
        withdrawIdToAmount[_withdrawId] = _amount;
        withdrawIdToTokensBurned[_withdrawId] = true;

        return (depositor, poolTokensToBurn);
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
        poolToPivotPending[msg.sender] = true;
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
        returns (bytes32, uint256)
    {
        IERC20 poolToken = IERC20(_poolToken);
        bytes32 depositId = bytes32(
            keccak256(abi.encode(msg.sender, _sender, _amount, block.timestamp))
        );

        poolToUserPendingDeposit[msg.sender][_sender] = true;
        depositIdToDepositor[depositId] = _sender;
        depositIdToDepositAmount[depositId] = _amount;
        depositIdToTokensMinted[depositId] = false;
        poolToPendingDeposits[msg.sender] += _amount;
        poolDepositNonce[msg.sender] += 1;

        if (_poolToken != address(0)) {
            depositIdToPoolTokenSupply[depositId] = poolToken.totalSupply();
        }

        emit DepositRecorded(depositId, _amount);
        return (depositId, poolWithdrawNonce[msg.sender]);
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

        poolToUserPendingDeposit[msg.sender][
            depositIdToDepositor[_depositId]
        ] = false;
        poolToPendingDeposits[msg.sender] -= depositIdToDepositAmount[
            _depositId
        ];
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

        clearPivotTarget();

        currentPositionAddress[msg.sender] = marketAddress;
        currentRecordPositionValue[msg.sender] = positionAmount;
        currentPositionValueTimestamp[msg.sender] = block.timestamp;
    }

    /// @notice Reverts an initial position setup in case of an error
    /// @param _depositId Identifier for the deposit linked to the position setup
    /// @return Address of the original depositor
    function undoPositionInitializer(
        bytes32 _depositId
    ) external onlyValidPool returns (address) {
        emit HandleUndo("HandleUndo - Initialize");
        address originalSender = depositIdToDepositor[_depositId];
        poolToUserPendingDeposit[msg.sender][originalSender] = false;
        targetPositionMarketId[msg.sender] = abi.encode(0);
        targetPositionChain[msg.sender] = 0;
        targetPositionProtocol[msg.sender] = "";
        targetPositionProtocolHash[msg.sender] = bytes32("");

        poolToPivotPending[msg.sender] = false;
        depositIdToDepositor[_depositId] = address(0);
        depositIdToDepositAmount[_depositId] = 0;
        poolDepositNonce[msg.sender] = 0;
        return originalSender;
    }

    /// @notice Cancels a deposit order, clearing any associated pending states
    /// @param _depositId Identifier of the deposit to be undone
    /// @return Address of the depositor
    function undoDeposit(
        bytes32 _depositId
    ) external onlyValidPool returns (address) {
        emit HandleUndo("HandleUndo - Deposit");
        address originalSender = depositIdToDepositor[_depositId];
        poolToUserPendingDeposit[msg.sender][originalSender] = false;
        depositIdToDepositor[_depositId] = address(0);
        depositIdToDepositAmount[_depositId] = 0;
        return originalSender;
    }

    /// @notice Reverts a pivot operation, resetting related state
    /// @param _positionAmount Amount of the position before the pivot was attempted
    function undoPivot(uint256 _positionAmount) external onlyValidPool {
        emit HandleUndo("HandleUndo - Pivot");
        currentPositionAddress[msg.sender] = msg.sender;
        currentPositionMarketId[msg.sender] = abi.encode(0);
        currentPositionProtocol[msg.sender] = "";
        currentPositionProtocolHash[msg.sender] = bytes32("");
        currentRecordPositionValue[msg.sender] = _positionAmount;
        currentPositionValueTimestamp[msg.sender] = block.timestamp;
        clearPivotTarget();
    }

    /// @dev Clears the target position data after a pivot operation or failure
    function clearPivotTarget() internal {
        targetPositionMarketId[msg.sender] = abi.encode(0);
        targetPositionChain[msg.sender] = 0;
        targetPositionProtocol[msg.sender] = "";
        targetPositionProtocolHash[msg.sender] = bytes32("");
        poolToPivotPending[msg.sender] = false;
    }

    /// @notice Provides the current position data of a pool
    /// @param _poolAddress Address of the pool
    /// @return Current position details including protocol, market ID, and pivot pending status
    function getCurrentPositionData(
        address _poolAddress
    ) external view onlyValidPool returns (string memory, bytes memory, bool) {
        return (
            currentPositionProtocol[_poolAddress],
            currentPositionMarketId[_poolAddress],
            poolToPivotPending[_poolAddress]
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
        uint256 _proposalRewardUSDC
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
            _proposalRewardUSDC
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
    /// @param _totalPoolPositionAmount Total amount of the pool's position post-deposit
    /// @return Number of pool tokens to mint and the address of the depositor
    function calculatePoolTokensToMint(
        bytes32 _depositId,
        uint256 _totalPoolPositionAmount
    ) external view returns (uint256, address) {
        uint256 assetAmount = depositIdToDepositAmount[_depositId];
        address depositor = depositIdToDepositor[_depositId];
        uint256 poolTokensToMint;
        if (_totalPoolPositionAmount == assetAmount) {
            uint256 supplyFactor = (Math.log10(assetAmount));
            poolTokensToMint = 10 ** supplyFactor;
        } else {
            uint256 ratio = (assetAmount * (10 ** 18)) /
                (_totalPoolPositionAmount - assetAmount);
            poolTokensToMint =
                (ratio * depositIdToPoolTokenSupply[_depositId]) /
                (10 ** 18);
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
            poolDepositNonce[_poolAddress],
            poolWithdrawNonce[_poolAddress],
            poolToPivotPending[_poolAddress]
        );
    }
}
