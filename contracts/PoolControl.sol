// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./PoolToken.sol";
import {ISpokePool} from "./interfaces/ISpokePool.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {IChaserManager} from "./ChaserManager.sol";
import {IBridgeLogic} from "./interfaces/IBridgeLogic.sol";
import {IPoolCalculations} from "./interfaces/IPoolCalculations.sol";
import {IPoolToken} from "./interfaces/IPoolToken.sol";
import {IArbitrationContract} from "./interfaces/IArbitrationContract.sol";

/// @title Contract for each Chaser pool deployed
/// @notice Manages investment pool operations including deposits, withdrawals, and cross-chain asset transfers
/// @dev All user facing interactions on Chaser are made on this contract
/// @dev Interfaces with various external contracts for managing pool strategies, calculations, and cross-chain movements
contract PoolControl {
    address deployingUser;
    uint256 public localChain;
    address public poolToken;
    string public poolName;
    uint256 public strategyIndex; // Index in mapping pointing to the strategy code on InvestmentStrategy contract
    bytes32 public openAssertion = bytes32("");
    uint256 public currentPositionChain;

    address public localBridgeReceiver;
    IBridgeLogic public localBridgeLogic;
    IChaserManager public manager;
    IChaserRegistry public registry;
    IPoolCalculations public poolCalculations;
    IArbitrationContract public arbitrationContract;
    IERC20 public asset;

    event ExecutionMessage(string);
    event ExecutePivot(uint256, uint256);
    event DepositCrossChain(address);
    event WithdrawCrossChain(address);

    /// @notice Initializes a new pool control instance with necessary configuration
    /// @param _deployingUser Address of the user deploying the pool
    /// @param _asset Address of the asset used in the pool
    /// @param _strategyIndex Index identifying the investment strategy in the strategy contract
    /// @param _poolName Descriptive name of the pool
    /// @param _localChain Chain ID where the pool is deployed to and operates
    /// @param _registry Address of the registry for accessing other contract addresses and configurations
    /// @param _poolCalculations Address of the pool calculations contract used for state and other calculations
    constructor(
        address _deployingUser,
        address _asset,
        uint256 _strategyIndex,
        string memory _poolName,
        uint256 _localChain,
        address _registry,
        address _poolCalculations
    ) {
        localChain = _localChain;
        currentPositionChain = 0;
        poolName = _poolName;
        deployingUser = _deployingUser;
        strategyIndex = _strategyIndex;
        asset = IERC20(_asset);
        registry = IChaserRegistry(_registry);
        poolCalculations = IPoolCalculations(_poolCalculations);
        localBridgeLogic = IBridgeLogic(registry.bridgeLogicAddress());
        localBridgeReceiver = registry.chainIdToBridgeReceiver(localChain);
        arbitrationContract = IArbitrationContract(
            registry.arbitrationContract()
        );
    }

    modifier callerSource() {
        require(
            msg.sender == address(localBridgeLogic) ||
                msg.sender == localBridgeReceiver ||
                msg.sender == address(arbitrationContract),
            "Only bridgeLogic or bridgeReceiver may undo deposit"
        );
        _;
    }

    modifier messageSource() {
        address messageReceiver = registry.chainIdToMessageReceiver(localChain);
        require(
            msg.sender == messageReceiver ||
                msg.sender == address(localBridgeLogic),
            "This function may only be called by the messengerReceiver or bridgeLogic"
        );
        _;
    }

    /// @notice Callback to process the initial position data from cross-chain or local transactions
    /// @dev Decodes and updates the position state based on the data received; initializes the pool token if not already done
    /// @param _data Encoded data containing position details including the market address and deposit amounts
    function receivePositionInitialized(
        bytes memory _data
    ) external messageSource {
        (
            uint256 positionAmount,
            uint256 depositAmountReceived,
            address marketAddress,
            bytes32 depositId
        ) = abi.decode(_data, (uint256, uint256, address, bytes32));

        poolCalculations.updateDepositReceived(
            depositId,
            positionAmount,
            depositAmountReceived
        );
        _pivotCompleted(marketAddress, positionAmount);

        if (poolToken == address(0)) {
            poolToken = address(
                new PoolToken(deployingUser, positionAmount, poolName)
            );
        }
    }

    /// @notice Updates the current position's valuation based on data received
    /// @param _data Encoded data detailing the current position value and associated deposit ID
    function receivePositionBalance(bytes memory _data) external messageSource {
        (
            uint256 positionAmount,
            uint256 depositAmountReceived,
            bytes32 depositId
        ) = abi.decode(_data, (uint256, uint256, bytes32));
        if (depositId != bytes32("")) {
            poolCalculations.updateDepositReceived(
                depositId,
                positionAmount,
                depositAmountReceived
            );
            mintUserPoolTokens(depositId, positionAmount);
        }
    }

    /// @notice Initiates a withdrawal order for a user, handling local or cross-chain processes
    /// @param _amount The amount the user wishes to withdraw, denominated in the pool's asset
    /// @dev Creates withdrawal data and sends it to the appropriate bridge logic through CCIP
    function userWithdrawOrder(uint256 _amount) external {
        require(
            IPoolToken(poolToken).balanceOf(msg.sender) > 0,
            "User has no position"
        );

        bytes memory data = poolCalculations.createWithdrawOrder(
            _amount,
            poolToken,
            msg.sender,
            openAssertion
        );

        bytes4 method = bytes4(keccak256(abi.encode("AbWithdrawOrderUser")));

        if (currentPositionChain == localChain) {
            localBridgeLogic.userWithdrawSequence(address(this), data);
        } else {
            emit WithdrawCrossChain(msg.sender);
            registry.sendMessage(
                currentPositionChain,
                method,
                address(this),
                data
            );
        }
    }

    /// @notice Allows the deploying user to make an initial deposit and establish the first position of the pool
    /// @param _amount Amount of the asset to deposit
    /// @param _totalFee Total fee to cover cross-chain message relaying
    /// @param _targetPositionProtocol Protocol of the first position
    /// @param _targetPositionMarketId Market ID targeted for the investment
    /// @param _targetPositionChain Chain ID of the target position's location
    function userDepositAndSetPosition(
        uint256 _amount,
        uint256 _totalFee,
        string memory _targetPositionProtocol,
        bytes memory _targetPositionMarketId,
        uint256 _targetPositionChain
    ) external {
        require(
            msg.sender == deployingUser,
            "Only deploying user can set position and deposit"
        );
        require(
            poolCalculations.poolDepositNonce(address(this)) == 0,
            "The position may only be set before the first deposit has settled"
        );

        (bytes32 depositId, ) = poolCalculations.createDepositOrder(
            msg.sender,
            poolToken,
            _amount,
            openAssertion
        );

        address targetMarketAddress = poolCalculations.openSetPosition(
            _targetPositionMarketId,
            _targetPositionProtocol,
            _targetPositionChain
        );

        bytes memory data = poolCalculations.createInitialSetPositionMessage(
            depositId,
            msg.sender
        );

        if (_targetPositionChain == localChain) {
            bool success = asset.transferFrom(
                msg.sender,
                address(localBridgeLogic),
                _amount
            );
            require(success, "Token transfer failure");

            localBridgeLogic.handlePositionInitializer(
                _amount,
                address(this),
                address(asset),
                depositId,
                msg.sender,
                targetMarketAddress,
                keccak256(abi.encode(_targetPositionProtocol))
            );
        } else {
            bytes4 method = bytes4(
                keccak256(abi.encode("AbBridgePositionInitializer"))
            );
            bytes memory message = abi.encode(method, address(this), data);
            enterFundsCrossChain(
                depositId,
                _amount,
                msg.sender,
                _totalFee,
                message
            );
        }
    }

    /// @notice Handles user deposits into the pool
    /// @param _amount Amount of the asset to deposit
    /// @param _totalFee Across Bridging fee calculated off chain to handle cross-chain transfers, set to 0 if local
    function userDeposit(uint256 _amount, uint256 _totalFee) external {
        require(
            poolCalculations.poolDepositNonce(address(this)) > 0,
            "The deosits can only be made after the first deposit + position set has settled"
        );

        (bytes32 depositId, uint256 withdrawNonce) = poolCalculations
            .createDepositOrder(msg.sender, poolToken, _amount, openAssertion);

        if (currentPositionChain == localChain) {
            bool success = asset.transferFrom(
                msg.sender,
                address(localBridgeLogic),
                _amount
            );
            require(success, "Token transfer failure");

            localBridgeLogic.handleUserDeposit(
                address(this),
                depositId,
                withdrawNonce,
                _amount
            );
        } else {
            bytes4 method = bytes4(
                keccak256(abi.encode("AbBridgeDepositUser"))
            );

            bytes memory message = abi.encode(
                method,
                address(this),
                abi.encode(depositId, withdrawNonce)
            );

            enterFundsCrossChain(
                depositId,
                _amount,
                msg.sender,
                _totalFee,
                message
            );
        }
    }

    /// @notice Manages the transfer of funds across chains for deposit or position initialization
    /// @param _depositId Identifier for the deposit transaction
    /// @param _amount Amount of assets to be transferred
    /// @param _sender Address of the user making the transaction
    /// @param _feeTotal Total fee percentage for the cross-chain bridging paid to Across
    /// @param _message Encoded message details needed by BridgeLogic cross chain
    function enterFundsCrossChain(
        bytes32 _depositId,
        uint256 _amount,
        address _sender,
        uint256 _feeTotal,
        bytes memory _message
    ) internal {
        emit DepositCrossChain(_sender);
        address acrossSpokePool = registry.chainIdToSpokePoolAddress(0);
        uint256 receivingChain = currentPositionChain;
        if (receivingChain == 0) {
            receivingChain = poolCalculations.targetPositionChain(
                address(this)
            );
        }

        require(receivingChain != 0, "Cannot bridge, invalid chain id");
        address destinationBridgeReceiver = registry.chainIdToBridgeReceiver(
            receivingChain
        );

        spokePoolPreparation(_sender, _amount);

        crossChainBridge(
            _sender,
            acrossSpokePool,
            destinationBridgeReceiver,
            _amount,
            _feeTotal,
            receivingChain,
            _message
        );
    }

    /// @notice Executes the Across V3 bridging
    /// @param _sender Address of the user initiating the transfer
    /// @param _acrossSpokePool Address of the Across spoke pool
    /// @param _bridgeReceiver Address of the Chaser BridgeReceiver contract on the destination chain
    /// @param _amount Amount of the asset to transfer
    /// @param _feeTotal Fee deducted for the bridge service
    /// @param _receivingChain Chain ID where the assets are being transferred
    /// @param _message Encoded message containing additional instructions for the BridgeLogic to process the bridged funds
    function crossChainBridge(
        address _sender,
        address _acrossSpokePool,
        address _bridgeReceiver,
        uint256 _amount,
        uint256 _feeTotal,
        uint256 _receivingChain,
        bytes memory _message
    ) internal {
        ISpokePool(_acrossSpokePool).depositV3(
            _sender,
            _bridgeReceiver,
            address(asset),
            address(0),
            _amount,
            _amount - _feeTotal,
            _receivingChain,
            address(0),
            uint32(block.timestamp),
            uint32(block.timestamp + 30000),
            0,
            _message
        );
    }

    /// @notice Proposes a pivot of the pool position to a new market by generating an UMA claim and opening an assertion through the arbitration contract
    /// @param _requestProtocol The protocol for the new position
    /// @param _requestMarketId Market identifier for the new position
    /// @param _requestChainId Chain ID where the new position will be established
    function queryMovePosition(
        string memory _requestProtocol,
        bytes memory _requestMarketId,
        uint256 _requestChainId
    ) external {
        (
            string memory currentPositionProtocol,
            bytes memory currentPositionMarketId,
            bool pivotPending
        ) = poolCalculations.getCurrentPositionData(address(this));
        uint256 bond = poolCalculations.getPivotBond(address(asset));
        require(
            !pivotPending,
            "Cannot propose new move while pivot is pending"
        );
        bytes memory claim = arbitrationContract.generateClaim(
            _requestChainId,
            _requestProtocol,
            _requestMarketId,
            currentPositionChain,
            currentPositionProtocol,
            currentPositionMarketId
        );
        openAssertion = arbitrationContract.queryMovePosition(
            msg.sender,
            claim,
            _requestMarketId,
            _requestProtocol,
            _requestChainId,
            bond
        );
    }

    /// @notice Executes a change in the pool's position following a successful pivot proposal
    /// @dev Only callable from the Abritration contract
    /// @param _targetPositionMarketId Market ID of the new target position
    /// @param _targetPositionProtocol Protocol of the new target position
    /// @param _targetPositionChain Chain ID of the new target position
    function sendPositionChange(
        bytes memory _targetPositionMarketId,
        string memory _targetPositionProtocol,
        uint256 _targetPositionChain
    ) external {
        // IMPORTANT - THIS SHOULD REQUIRE MSG.SENDER TO BE THE ARBITRATION CONTRACT
        openAssertion = bytes32("");
        uint256 currentPendingDeposits = poolCalculations.poolToPendingDeposits(
            address(this)
        );
        uint256 currentPendingWithdraws = poolCalculations
            .poolToPendingWithdraws(address(this));

        require(
            currentPendingDeposits == 0 && currentPendingWithdraws == 0,
            "Transactions still pending on this pool, try to resolve the pivot again soon"
        );

        poolCalculations.openSetPosition(
            _targetPositionMarketId,
            _targetPositionProtocol,
            _targetPositionChain
        );

        uint256 pivotNonce = poolCalculations.poolPivotNonce(address(this));

        emit ExecutePivot(currentPositionChain, pivotNonce);

        address destinationBridgeReceiver = registry.chainIdToBridgeReceiver(
            _targetPositionChain
        );

        bytes memory pivotMessage = poolCalculations.createPivotExitMessage(
            destinationBridgeReceiver
        );

        if (currentPositionChain == localChain) {
            uint256 amount = asset.balanceOf(address(this));
            if (amount > 0) {
                bool success = asset.transfer(
                    address(localBridgeLogic),
                    amount
                );
                require(success, "Token transfer failure");
            }

            localBridgeLogic.executeExitPivot(address(this), pivotMessage);
        } else {
            bytes4 method = bytes4(
                keccak256(abi.encode("AbPivotMovePosition"))
            );
            registry.sendMessage(
                currentPositionChain,
                method,
                address(this),
                pivotMessage
            );
        }
    }

    /// @notice Finalizes the pivot process
    /// @dev Called externally to execute _pivotCompleted
    /// @param marketAddress Address of the market where the new position is held
    /// @param positionAmount The amount involved in the new position
    function pivotCompleted(
        address marketAddress,
        uint256 positionAmount
    ) external messageSource {
        _pivotCompleted(marketAddress, positionAmount);
    }

    /// @dev Internal helper function of common logic for completing a pivot
    /// @param marketAddress Address of the market where the new position is held
    /// @param positionAmount The amount involved in the new position
    function _pivotCompleted(
        address marketAddress,
        uint256 positionAmount
    ) internal {
        currentPositionChain = poolCalculations.targetPositionChain(
            address(this)
        );
        poolCalculations.pivotCompleted(marketAddress, positionAmount);
    }

    /// @notice Reverts the initialization of a position in case of failures on the target chain
    /// @param _depositId Identifier of the deposit associated with the position
    /// @param _amount Amount of the asset to revert
    function handleUndoPositionInitializer(
        bytes32 _depositId,
        uint256 _amount
    ) external callerSource {
        address originalSender = poolCalculations.undoPositionInitializer(
            _depositId
        );
        bool success = asset.transferFrom(msg.sender, originalSender, _amount);
        require(success, "Token transfer failure");
    }

    /// @notice Handles the undoing of a deposit operation in case of a failed transaction
    /// @param _depositId Identifier of the failed deposit
    /// @param _amount Amount of the deposit to revert
    function handleUndoDeposit(
        bytes32 _depositId,
        uint256 _amount
    ) external callerSource {
        address originalSender = poolCalculations.undoDeposit(_depositId);
        bool success = asset.transferFrom(msg.sender, originalSender, _amount);
        require(success, "Token transfer failure");
    }

    /// @notice Reverts a pivot operation, resetting the position to its original state before the pivot
    /// @param _positionAmount Amount involved in the pivot to be reverted
    function handleUndoPivot(uint256 _positionAmount) external callerSource {
        currentPositionChain = localChain;
        poolCalculations.undoPivot(_positionAmount);
    }

    /// @notice Mints pool tokens for a user based on their deposit and the current pool position value
    /// @param _depositId Identifier of the deposit for which tokens are minted
    /// @param _poolPositionAmount Current value of the pool's position used to calculate the minting amount
    function mintUserPoolTokens(
        bytes32 _depositId,
        uint256 _poolPositionAmount
    ) internal {
        (uint256 poolTokensToMint, address depositor) = poolCalculations
            .calculatePoolTokensToMint(_depositId, _poolPositionAmount);
        IPoolToken(poolToken).mint(depositor, poolTokensToMint);
    }

    /// @notice Prepares and approves the transfer of funds to a spoke pool for cross-chain operations
    /// @param _sender Address of the user initiating the deposit
    /// @param _amount Amount of the asset to be transferred and approved
    function spokePoolPreparation(address _sender, uint256 _amount) internal {
        address acrossSpokePool = registry.chainIdToSpokePoolAddress(0);
        require(acrossSpokePool != address(0), "SPOKE ADDR");
        uint256 senderAssetBalance = asset.balanceOf(_sender);
        require(
            senderAssetBalance >= _amount,
            "Sender has insufficient asset balance"
        );
        bool success = asset.transferFrom(_sender, address(this), _amount);
        require(success, "Token transfer failure");

        asset.approve(acrossSpokePool, _amount);
    }

    /// @notice Finalizes a withdrawal order, transferring the specified amount to the user and burning the corresponding pool tokens
    /// @param _withdrawId Identifier of the withdrawal
    /// @param _amount Amount of assets to transfer to the user. The outputAmount on this side of the bridge
    /// @param _totalAvailableForUser Maximum amount available for the user to withdraw
    /// @param _positionValue Current total value of the pool's position
    /// @param _inputAmount Initial amount requested for withdrawal
    function finalizeWithdrawOrder(
        bytes32 _withdrawId,
        uint256 _amount,
        uint256 _totalAvailableForUser,
        uint256 _positionValue,
        uint256 _inputAmount
    ) external callerSource {
        (address depositor, uint256 poolTokensToBurn) = poolCalculations
            .fulfillWithdrawOrder(
                _withdrawId,
                _positionValue,
                _totalAvailableForUser,
                _inputAmount,
                poolToken
            );

        IPoolToken(poolToken).burn(depositor, poolTokensToBurn);
        bool success = asset.transfer(depositor, _amount);
        require(success, "Token transfer failure");
    }

    /// @notice Reads the strategy code associated with the current investment strategy of the pool
    /// @return A string representing the executable strategy code
    function readStrategyCode() external view returns (string memory) {
        address strategyAddress = registry.investmentStrategyContract();
        bytes memory strategyBytes = IStrategy(strategyAddress).strategyCode(
            strategyIndex
        );
        return string(strategyBytes);
    }

    /// @notice Provides metadata about the pool including the pool token address, asset address, and pool name
    /// @return Tuple containing the pool token address, asset address, and the pool name
    function poolMetaData()
        external
        view
        returns (address, address, string memory)
    {
        return (poolToken, address(asset), poolName);
    }

    /// @notice Retrieves detailed data about the current position of the pool including market, protocol, and valuation
    /// @return Comprehensive data set including position address, protocol hash, valuation, and related timestamps
    function readPoolCurrentPositionData()
        external
        view
        returns (
            address,
            bytes32,
            uint256,
            uint256,
            uint256,
            string memory,
            bytes memory
        )
    {
        (
            address currentPositionAddress,
            bytes32 currentPositionProtocolHash,
            uint256 currentRecordPositionValue,
            uint256 currentPositionValueTimestamp,
            string memory currentPositionProtocol,
            bytes memory currentPositionMarketId
        ) = poolCalculations.readCurrentPositionData(address(this));

        return (
            currentPositionAddress,
            currentPositionProtocolHash,
            currentRecordPositionValue,
            currentPositionValueTimestamp,
            currentPositionChain,
            currentPositionProtocol,
            currentPositionMarketId
        );
    }

    /// @notice Fetches details of a position change requested through the arbitration process
    /// @return Details including the requested market ID, protocol, chain ID, and the time of request initiation
    function readAssertionRequestedPosition()
        external
        view
        returns (bytes memory, string memory, uint256, uint256)
    {
        (
            bytes memory requestedMarketId,
            string memory requestedProtocol,
            uint256 requestedChainId,
            uint256 openingTime
        ) = arbitrationContract.readAssertionRequestedPosition(openAssertion);
        return (
            requestedMarketId,
            requestedProtocol,
            requestedChainId,
            openingTime
        );
    }

    /// @notice Provides the current transaction status of the pool including nonce for deposits and withdrawals and pivot pending status
    /// @return Current transaction statuses including nonces for deposits and withdrawals, pivot pending flag, and the current open assertion
    function transactionStatus()
        external
        view
        returns (uint256, uint256, bool, bytes32)
    {
        (
            uint256 poolDepositNonce,
            uint256 poolWithdrawNonce,
            bool poolToPivotPending
        ) = poolCalculations.poolTransactionStatus(address(this));

        return (
            poolDepositNonce,
            poolWithdrawNonce,
            poolToPivotPending,
            openAssertion
        );
    }
}
