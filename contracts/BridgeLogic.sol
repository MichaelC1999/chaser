// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {IChaserMessenger} from "./interfaces/IChaserMessenger.sol";
import {ISpokePool} from "./interfaces/ISpokePool.sol";
import {IPoolControl} from "./interfaces/IPoolControl.sol";
import {IIntegrator} from "./interfaces/IIntegrator.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAToken} from "./interfaces/IAToken.sol";

/// @title Logic for Managing Positional State and processing interactions
/// @notice This contract manages handling deposits, withdrawals, and pivots for Chaser pools on the positional side
/// @dev When on the same chain as the pool, BridgeLogic and PoolControl directly call each other. When across chains, funds and data are moved through BridgeReceived and ChaserMessenger
contract BridgeLogic is OwnableUpgradeable {
    uint256 managerChainId;
    uint256 localChainId;

    IChaserRegistry public registry;
    IChaserMessenger public messenger;

    address public bridgeReceiverAddress;
    address public integratorAddress;

    mapping(address => address) public poolToCurrentPositionMarket;
    mapping(address => bytes32) public poolToCurrentProtocolHash;
    mapping(address => address) public poolToAsset;
    mapping(bytes32 => uint256) public userDepositNonce;
    mapping(bytes32 => uint256) public userCumulativeDeposits;
    mapping(address => uint256) public poolAddressToDepositNonce;
    mapping(address => uint256) public poolAddressToWithdrawNonce;
    mapping(address => bool) public poolInitialized;
    mapping(address => mapping(uint256 => uint256))
        public poolToNonceToCumulativeDeposits;
    mapping(address => mapping(uint256 => uint256))
        public poolToNonceToCumulativeWithdraw;

    /// @notice Initializes the BridgeLogic contract with chain IDs and the registry address, replacing the constructor
    /// @param _localChainId Chain ID of the chain a specific BridgeLogic instance is deployed to
    /// @param _managerChainId Chain ID where the manager that coordinates pools is located
    /// @param _registryAddress Address of the ChaserRegistry contract
    function initialize(
        uint256 _localChainId,
        uint256 _managerChainId,
        address _registryAddress
    ) public initializer {
        __Ownable_init();
        localChainId = _localChainId;
        managerChainId = _managerChainId;
        registry = IChaserRegistry(_registryAddress);
    }

    /// @notice Configures connections essential for the bridge logic operations
    /// @dev Sets messenger, bridge receiver, and integrator addresses used in cross-chain communications
    /// @param _messengerAddress Address of the cross-chain messenger service
    /// @param _bridgeReceiverAddress Address of the bridge receiver responsible for handling incoming messages
    /// @param _integratorAddress Address of the integrator for handling protocol-specific actions
    function addConnections(
        address _messengerAddress,
        address _bridgeReceiverAddress,
        address _integratorAddress
    ) external onlyOwner {
        messenger = IChaserMessenger(_messengerAddress);
        bridgeReceiverAddress = _bridgeReceiverAddress;
        integratorAddress = _integratorAddress;
    }

    // IMPORTANT - Need CCIP handler function to reset poolInitialized, poolToAsset on a pool where fraud has sent dummy data to BridgeLogic that has not been initialized yet

    /// @notice Handles the initialization of a pool's position with its first deposit BETWEEN ALL CHAINS
    /// @dev Initiated by the userDepositAndSetPosition() on the PoolControl, either called directly or from BridgeReceiver cross chain
    /// @param _amount Amount of tokens being deposited
    /// @param _poolAddress Address of the pool being initialized
    /// @param _tokenSent Address of the token transfered through Across
    /// @param _depositId Unique identifier for the deposit
    /// @param _userAddress Address of the user making the deposit
    /// @param _marketAddress Address of the market where assets will be invested in
    /// @param _protocolHash Hash identifying the protocol used
    function handlePositionInitializer(
        uint256 _amount,
        address _poolAddress,
        address _tokenSent,
        bytes32 _depositId,
        address _userAddress,
        address _marketAddress,
        bytes32 _protocolHash
    ) external {
        require(
            msg.sender == bridgeReceiverAddress ||
                registry.poolEnabled(msg.sender),
            "Only callable by the BridgeReceiver or a valid pool"
        );

        require(
            poolInitialized[_poolAddress] == false,
            "Pool can only be initialized once"
        );

        poolInitialized[_poolAddress] = true;
        poolToAsset[_poolAddress] = _tokenSent;
        poolToCurrentPositionMarket[_poolAddress] = _marketAddress;

        updatePositionState(_poolAddress, _protocolHash, _marketAddress);

        bytes32 userPoolHash = keccak256(
            abi.encode(_userAddress, _poolAddress)
        );

        userDepositNonce[userPoolHash] += 1;
        userCumulativeDeposits[userPoolHash] += _amount;
        setNonceCumulative(_poolAddress, _amount, true);
        receiveDepositFromPool(_amount, _poolAddress);
        sendPositionInitialized(_poolAddress, _depositId, _amount);
    }

    /// @notice Manages the transition of a pool's assets to a new market
    /// @dev This function handles the part of the pivot process for depositing all of a pool's funds into its new position
    /// @dev Could be called directly from PoolControl or BridgeReceiver
    /// @param _tokenSent Address of the token used by the pool
    /// @param _amount Amount of the asset pertaining to the pool, that is being pivoted
    /// @param _poolAddress Address of the pool undergoing the pivot
    /// @param _protocolHash Hash identifying the new protocol
    /// @param _marketAddress Address of the new market to pivot to
    function handleEnterPivot(
        address _tokenSent,
        uint256 _amount,
        address _poolAddress,
        bytes32 _protocolHash,
        address _marketAddress
    ) external {
        require(
            msg.sender == bridgeReceiverAddress,
            "Only callable by the BridgeReceiver"
        );

        if (poolToAsset[_poolAddress] == address(0)) {
            poolInitialized[_poolAddress] = true;
            poolToAsset[_poolAddress] = _tokenSent;
        }

        updatePositionState(_poolAddress, _protocolHash, _marketAddress);
        receiveDepositFromPool(_amount, _poolAddress);

        if (managerChainId == localChainId) {
            IPoolControl(_poolAddress).pivotCompleted(_marketAddress, _amount); // If the Pool is on this same chain, directly call the proper functions on this chain no CCIP
        } else {
            sendPivotCompleted(_poolAddress, _amount); // If the Pool is on a different chain, use CCIP to notify the pool
        }
    }

    /// @notice Processes a user's deposit into a position belonging to a pool
    /// @dev Handles deposits, recording them and adjusting the position state accordingly
    /// @param _poolAddress Address of the pool receiving the deposit
    /// @param _depositId Unique identifier for the deposit
    /// @param _withdrawNonce Withdrawal nonce currently on the Pool
    /// @param _amount Amount of the deposit
    function handleUserDeposit(
        address _poolAddress,
        bytes32 _depositId,
        uint256 _withdrawNonce,
        uint256 _amount
    ) external {
        require(
            msg.sender == bridgeReceiverAddress ||
                registry.poolEnabled(msg.sender),
            "Only callable by the BridgeReceiver"
        );

        setNonceCumulative(_poolAddress, _amount, true);
        receiveDepositFromPool(_amount, _poolAddress);
        uint256 currentPositionBalance = getNonPendingPositionBalance(
            _poolAddress,
            poolAddressToDepositNonce[_poolAddress],
            _withdrawNonce
        );
        _sendPositionBalance(
            _poolAddress,
            _depositId,
            _amount,
            currentPositionBalance
        );
    }

    /// @notice Send the current position value of a pool back to the pool contract
    /// @param _poolAddress The address of the pool
    /// @param _depositId If called as part of a deposit with the purpose of minting pool tokens, the deposit ID is passed here. It is optional, for falsey use bytes32 zero value
    /// @param _amount The amount deposited, if called after depositing
    /// @param _currentPositionBalance The non-pending balance of the entire position on a pool, including interest
    function _sendPositionBalance(
        address _poolAddress,
        bytes32 _depositId,
        uint256 _amount,
        uint256 _currentPositionBalance
    ) internal {
        bytes4 method = bytes4(
            keccak256(abi.encode("BaMessagePositionBalance"))
        );

        bytes memory data = abi.encode(
            _currentPositionBalance,
            _amount,
            _depositId
        );

        if (managerChainId == localChainId) {
            IPoolControl(_poolAddress).receivePositionBalance(data);
        } else {
            registry.sendMessage(managerChainId, method, _poolAddress, data);
        }
    }

    /// @notice Notifies a pool that a new position has been initialized
    /// @dev Internal function to send position initialization data back to the pool
    /// @param _poolAddress Address of the pool
    /// @param _depositId Deposit identifier linked to the position initialization
    /// @param _depositAmount Amount of the deposit linked to the initialization
    function sendPositionInitialized(
        address _poolAddress,
        bytes32 _depositId,
        uint256 _depositAmount
    ) internal {
        uint256 positionAmount = getPositionBalance(_poolAddress);
        bytes4 method = bytes4(keccak256(abi.encode("BaPositionInitialized")));
        address currentPositionMarket = poolToCurrentPositionMarket[
            _poolAddress
        ];

        bytes memory data = abi.encode(
            positionAmount,
            _depositAmount,
            currentPositionMarket,
            _depositId
        );

        if (managerChainId == localChainId) {
            IPoolControl(_poolAddress).receivePositionInitialized(data);
        } else {
            registry.sendMessage(managerChainId, method, _poolAddress, data);
        }
    }

    /// @notice Sends a callback to the pool that a pivot has completed
    /// @param _poolAddress Address of the pool where the pivot was completed
    /// @param _amount Amount involved in the pivot operation
    function sendPivotCompleted(
        address _poolAddress,
        uint256 _amount
    ) internal {
        bytes4 method = bytes4(keccak256(abi.encode("BaPivotMovePosition")));
        address marketAddress = poolToCurrentPositionMarket[_poolAddress];
        bytes memory data = abi.encode(marketAddress, _amount);

        registry.sendMessage(managerChainId, method, _poolAddress, data);
    }

    /// @notice Updates the internal state related to a pool's current position
    /// @dev Adjusts records of a pool's current market and protocol based on new data
    /// @param _poolAddress Address of the pool
    /// @param _protocolHash New protocol hash
    /// @param _marketAddress New market address
    function updatePositionState(
        address _poolAddress,
        bytes32 _protocolHash,
        address _marketAddress
    ) internal {
        if (_protocolHash == keccak256(abi.encode("aave-v3"))) {
            _marketAddress = IAToken(_marketAddress).POOL();
        }
        poolToCurrentPositionMarket[_poolAddress] = _marketAddress;
        poolToCurrentProtocolHash[_poolAddress] = _protocolHash;
    }

    /// @notice Manages the transition of a pool's position across chains
    /// @dev Clears internal position state on the local chain, calls bridge and sets up the bridging
    /// @param _poolAddress Address of the pool undergoing the pivot
    /// @param _protocolHash Protocol hash of the target position
    /// @param _targetMarketAddress Market address on the destination chain
    /// @param _destinationChainId Chain ID to bridge to
    /// @param _destinationBridgeReceiver Address of the bridge receiver on the destination chain
    /// @param _amount Amount of assets belonging to the pool/position
    function crossChainPivot(
        address _poolAddress,
        bytes32 _protocolHash,
        address _targetMarketAddress,
        uint256 _destinationChainId,
        address _destinationBridgeReceiver,
        uint256 _amount
    ) internal {
        bytes4 method = bytes4(
            keccak256(abi.encode("BbPivotBridgeMovePosition"))
        );

        bytes memory message = abi.encode(
            method,
            _poolAddress,
            abi.encode(_protocolHash, _targetMarketAddress)
        );

        updatePositionState(_poolAddress, bytes32(""), address(0));

        crossChainBridge(
            _amount,
            poolToAsset[_poolAddress],
            _destinationBridgeReceiver,
            _destinationChainId,
            message
        );
    }

    /// @notice Executes the unwinding of a position and pivots assets
    /// @dev Withdraws all funds from the position, begins process to move funds to new location
    /// @param _poolAddress Address of the pool executing the pivot
    /// @param _data Encoded data containing pivot details such as target protocol and market
    function executeExitPivot(
        address _poolAddress,
        bytes memory _data
    ) external {
        require(
            msg.sender == address(messenger) ||
                registry.poolEnabled(msg.sender),
            "Only callable by the Messenger or a valid pool"
        );
        (
            bytes32 targetProtocolHash,
            address targetMarketAddress,
            uint256 destinationChainId,
            address destinationBridgeReceiver
        ) = abi.decode(_data, (bytes32, address, uint256, address));

        uint256 amount = getPositionBalance(_poolAddress);
        integratorWithdraw(_poolAddress, amount);

        if (localChainId == destinationChainId) {
            updatePositionState(
                _poolAddress,
                targetProtocolHash,
                targetMarketAddress
            );
            localPivot(_poolAddress, amount);
        } else {
            crossChainPivot(
                _poolAddress,
                targetProtocolHash,
                targetMarketAddress,
                destinationChainId,
                destinationBridgeReceiver,
                amount
            );
        }
    }

    /// @notice Handles the local aspects of a pivot operation within the same chain
    /// @dev Internal function to complete a pivot operation where the position being entered is on the same chain as the position exited
    /// @dev If the Pool is on a different chain, use CCIP to notify the pool
    /// @param _poolAddress Address of the pool
    /// @param _amount Amount of assets involved in the pivot
    function localPivot(address _poolAddress, uint256 _amount) internal {
        receiveDepositFromPool(_amount, _poolAddress);
        if (managerChainId == localChainId) {
            address marketAddress = poolToCurrentPositionMarket[_poolAddress];
            IPoolControl(_poolAddress).pivotCompleted(marketAddress, _amount);
        } else {
            sendPivotCompleted(_poolAddress, _amount);
        }
    }

    /// @notice Manages the return of assets to a pool following a failed operation
    /// @dev Called from the BridgeReceiver when an error is caught during executing involving transfer of assets
    /// @param _originalMethod Original method identifier that triggered the return process
    /// @param _poolAddress Address of the pool receiving the returned assets
    /// @param _tokenSent Asset being returned
    /// @param _depositId Deposit identifier associated with the return
    /// @param _amount Amount of asset being returned
    function returnToPool(
        bytes4 _originalMethod,
        address _poolAddress,
        address _tokenSent,
        bytes32 _depositId,
        uint256 _amount
    ) external {
        require(
            msg.sender == bridgeReceiverAddress,
            "Only callable by the BridgeReceiver"
        );

        bytes4 method = bytes4(keccak256(abi.encode("BaReturnToPool")));
        bytes memory message = abi.encode(
            method,
            _poolAddress,
            abi.encode(_originalMethod, _depositId)
        );
        address destinationBridgeReceiver = registry.chainIdToBridgeReceiver(
            managerChainId
        );
        if (
            _originalMethod ==
            bytes4(keccak256(abi.encode("AbBridgeDepositUser")))
        ) {
            poolAddressToDepositNonce[_poolAddress] += 1;
        }
        if (localChainId == managerChainId) {
            //In cases of deposit, depositSetPosition, and Ab pivot to market on same chain as manager, never goes through bridge and will fail out of try/catch
            if (
                _originalMethod ==
                bytes4(keccak256(abi.encode("BbPivotBridgeMovePosition")))
            ) {
                IPoolControl(_poolAddress).handleUndoPivot(_amount);
                bool success = IERC20(_tokenSent).transfer(
                    _poolAddress,
                    _amount
                );
                require(success, "Token transfer failure");
            }
        } else {
            crossChainBridge(
                _amount,
                _tokenSent,
                destinationBridgeReceiver,
                managerChainId,
                message
            );
        }
    }

    /// @notice Handles the bridging of assets across chains using a designated bridge
    /// @dev Internal function that approves transfer and calls bridging functions on Across V3
    /// @param _amount Amount of assets to transfer
    /// @param _asset Token address of the assets being transferred
    /// @param _destinationBridgeReceiver Receiver address on the destination chain
    /// @param _destinationChainId Destination chain ID
    /// @param _message Encoded message containing transfer details
    function crossChainBridge(
        uint256 _amount,
        address _asset,
        address _destinationBridgeReceiver,
        uint256 _destinationChainId,
        bytes memory _message
    ) internal {
        address acrossSpokePool = registry.chainIdToSpokePoolAddress(0);
        IERC20(_asset).approve(acrossSpokePool, _amount);
        ISpokePool(acrossSpokePool).depositV3(
            address(this),
            _destinationBridgeReceiver,
            _asset,
            address(0),
            _amount,
            _amount - (_amount / 250),
            _destinationChainId,
            address(0),
            uint32(block.timestamp),
            uint32(block.timestamp + 30000),
            0,
            _message
        );
    }

    /// @notice Executes a user withdrawal process, including cross-chain interactions if necessary
    /// @dev Manages the sequence of actions for a user's withdrawal from a pool
    /// @param _poolAddress Address of the pool from which withdrawal is requested
    /// @param _data Encoded data relevant to the withdrawal process
    function userWithdrawSequence(
        address _poolAddress,
        bytes memory _data
    ) external {
        require(
            msg.sender == address(messenger) ||
                registry.poolEnabled(msg.sender),
            "Only callable by the Messenger or a valid pool"
        );

        (
            bytes32 withdrawId,
            uint256 amount,
            uint256 poolDepositNonce,
            uint256 poolWithdrawNonce,
            uint256 scaledRatio
        ) = abi.decode(_data, (bytes32, uint256, uint256, uint256, uint256));

        uint256 currentPositionValue = getNonPendingPositionBalance(
            _poolAddress,
            poolDepositNonce,
            poolWithdrawNonce
        );

        uint256 userMaxWithdraw = getUserMaxWithdraw(
            currentPositionValue,
            scaledRatio
        );

        uint256 amountToWithdraw = amount;
        if (userMaxWithdraw < amount) {
            amountToWithdraw = userMaxWithdraw;
        }

        userWithdraw(
            amountToWithdraw,
            currentPositionValue,
            userMaxWithdraw,
            _poolAddress,
            withdrawId
        );
    }

    /// @notice Executes the withdrawal of funds for a user, handling asset transfers and notifications
    /// @dev Internal function that calls integrator to send back position funds, updates states, and puts into motion the deposit callback
    /// @param _amount Amount to be withdrawn
    /// @param _currentPositionValue Current total value of the pool's position
    /// @param _userMaxWithdraw Maximum amount the user can withdraw based on their pool token ratio
    /// @param _poolAddress Address of the pool
    /// @param _withdrawId Withdrawal identifier
    function userWithdraw(
        uint256 _amount,
        uint256 _currentPositionValue,
        uint256 _userMaxWithdraw,
        address _poolAddress,
        bytes32 _withdrawId
    ) internal {
        address destinationBridgeReceiver = registry.chainIdToBridgeReceiver(
            managerChainId
        );

        bytes4 method = bytes4(
            keccak256(abi.encode("BaBridgeWithdrawOrderUser"))
        );

        integratorWithdraw(_poolAddress, _amount);
        setNonceCumulative(_poolAddress, _amount, false);

        uint256 positionBalance = _currentPositionValue - _amount;

        bytes memory message = abi.encode(
            method,
            _poolAddress,
            abi.encode(_withdrawId, _userMaxWithdraw, positionBalance, _amount)
        );

        if (managerChainId == localChainId) {
            bool success = IERC20(poolToAsset[_poolAddress]).transfer(
                _poolAddress,
                _amount
            );
            require(success, "Token transfer failure");
            IPoolControl(_poolAddress).finalizeWithdrawOrder(
                _withdrawId,
                _amount,
                _userMaxWithdraw,
                positionBalance,
                _amount
            );
        } else {
            crossChainBridge(
                _amount,
                poolToAsset[_poolAddress],
                destinationBridgeReceiver,
                managerChainId,
                message
            );
        }
    }

    /// @notice Processes incoming deposits and pivot entry, routing them through the integrator to external protocols
    /// @dev Transfer funds to the integrator and saves the position state
    /// @param _amount Amount of the deposit
    /// @param _poolAddress Address of the pool making the deposit
    function receiveDepositFromPool(
        uint256 _amount,
        address _poolAddress
    ) internal {
        bytes32 operation = keccak256(abi.encode("deposit"));

        address marketAddress = poolToCurrentPositionMarket[_poolAddress];
        bytes32 protocolHash = poolToCurrentProtocolHash[_poolAddress];

        bool success = IERC20(poolToAsset[_poolAddress]).transfer(
            integratorAddress,
            _amount
        );
        require(success, "Token transfer failure");

        IIntegrator(integratorAddress).routeExternalProtocolInteraction(
            protocolHash,
            operation,
            _amount,
            _poolAddress,
            poolToAsset[_poolAddress],
            marketAddress
        );
    }

    /// @notice Manages the withdrawal of funds from external protocols
    /// @dev Internal function to initiate withdrawals from external protocols by calling the integrator contract
    /// @param _poolAddress Address of the pool
    /// @param _amount Amount to be withdrawn
    function integratorWithdraw(
        address _poolAddress,
        uint256 _amount
    ) internal {
        if (poolToCurrentProtocolHash[_poolAddress] != bytes32("")) {
            IIntegrator(integratorAddress).routeExternalProtocolInteraction(
                poolToCurrentProtocolHash[_poolAddress],
                keccak256(abi.encode("withdraw")),
                _amount,
                _poolAddress,
                poolToAsset[_poolAddress],
                poolToCurrentPositionMarket[_poolAddress]
            );
        }
    }

    /// @notice Updates cumulative deposit or withdrawal totals for a pool based on transaction nonces
    /// @dev Manages the nonce accounting for deposits and withdrawals to ensure correct transaction sequencing and record-keeping
    /// @param _poolAddress Address of the pool
    /// @param _txAmount Transaction amount to add to the cumulative total
    /// @param _isDepo Boolean indicating if the transaction is a deposit (true) or withdrawal (false)
    function setNonceCumulative(
        address _poolAddress,
        uint256 _txAmount,
        bool _isDepo
    ) internal {
        if (_isDepo) {
            uint256 oldNonce = poolAddressToDepositNonce[_poolAddress];
            poolAddressToDepositNonce[_poolAddress] += 1;
            poolToNonceToCumulativeDeposits[_poolAddress][oldNonce + 1] =
                poolToNonceToCumulativeDeposits[_poolAddress][oldNonce] +
                _txAmount;
        } else {
            uint256 oldNonce = poolAddressToWithdrawNonce[_poolAddress];
            poolAddressToWithdrawNonce[_poolAddress] += 1;
            poolToNonceToCumulativeWithdraw[_poolAddress][oldNonce + 1] =
                poolToNonceToCumulativeWithdraw[_poolAddress][oldNonce] +
                _txAmount;
        }
    }

    /// @notice Fetches the real-time balance of a pool's deployed assets from the Integrator, including accrued interest
    /// @dev This function does not account for pending transactions (ex funds already withdrawn from the position, but pool tokens have not burned on the pool yet)
    /// @dev Use this function in situations where you do not need to compare the position amount to amounts of pool tokens
    /// @dev For front ends displaying Pool TVL or user balances, do not use this function. use getNonPendingPositionBalance()
    /// @param _poolAddress Address of the pool
    /// @return The current balance of the pool's position
    function getPositionBalance(
        address _poolAddress
    ) public view returns (uint256) {
        if (poolToAsset[_poolAddress] == address(0)) {
            return 0;
        }
        if (poolToCurrentProtocolHash[_poolAddress] == bytes32("")) {
            return IERC20(poolToAsset[_poolAddress]).balanceOf(address(this));
        }
        return
            IIntegrator(integratorAddress).getCurrentPosition(
                _poolAddress,
                poolToAsset[_poolAddress],
                poolToCurrentPositionMarket[_poolAddress],
                poolToCurrentProtocolHash[_poolAddress]
            );
    }

    /// @notice Calculates the available balance of a pool's position, accounting for pending transactions
    /// @dev Derives the balance of a pool's position by subtracting pending deposits and adding pending withdrawals
    /// @dev Compares the nonces measured on the pool when an interaction was opened on the pool chain to the nonces when reached on the local BridgeLogic chain
    /// @dev Need to measure proportions based on state when the same number of interactions had happened
    /// @param _poolAddress Address of the pool
    /// @param _poolDepoNonce Nonce of the last deposit recorded on the pool at the time of sending a given transaction
    /// @param _poolWithNonce Nonce of the last withdrawal recorded on the pool at the time of sending a given transaction
    /// @return The non-pending balance of the pool's position
    function getNonPendingPositionBalance(
        address _poolAddress,
        uint256 _poolDepoNonce,
        uint256 _poolWithNonce
    ) public view returns (uint256) {
        uint256 bridgeDepoNonce = poolAddressToDepositNonce[_poolAddress];
        uint256 bridgeWithNonce = poolAddressToWithdrawNonce[_poolAddress];

        uint256 cumulativeDeposAtPoolNonce = poolToNonceToCumulativeDeposits[
            _poolAddress
        ][_poolDepoNonce];
        uint256 cumulativeWithsAtPoolNonce = poolToNonceToCumulativeWithdraw[
            _poolAddress
        ][_poolWithNonce];
        uint256 cumulativeDeposAtBridgeNonce = poolToNonceToCumulativeDeposits[
            _poolAddress
        ][bridgeDepoNonce];
        uint256 cumulativeWithsAtBridgeNonce = poolToNonceToCumulativeWithdraw[
            _poolAddress
        ][bridgeWithNonce];

        uint256 pendingDeposits = 0;
        uint256 pendingWithdraws = 0;

        if (bridgeDepoNonce > _poolDepoNonce) {
            pendingDeposits =
                cumulativeDeposAtBridgeNonce -
                cumulativeDeposAtPoolNonce;
        }

        if (bridgeWithNonce > _poolWithNonce) {
            //IMPORTANT! - Test to attempt to enter condition. This would mean withdraw order made after deposit opened, but withdraw reached bridge logic first
            pendingWithdraws =
                cumulativeWithsAtBridgeNonce -
                cumulativeWithsAtPoolNonce;
        }

        uint256 currentBalance = getPositionBalance(_poolAddress);
        return currentBalance - pendingDeposits + pendingWithdraws;

        //poolWithdrawNonce can be higher than bridgeWithdrawNonce in deposits, if the deposit opens after with and reaches here faster than withdraw opening
        //In this case, the positionBalance is not affected by pending withdraws, since the value has not been deducted here yet
        //poolWithdrawNonce can be lower than bridgeWithdrawNonce in deposits, if the withdraw opens after depo opening and reaches here faster
        //In this case, the pendingWithdrawAmount = balAtBridgeWithdrawNonce - balAtPoolWithdrawNonce, getting the amount withrawn since the withdraw was opened on the pool
        //poolDepositNonce is always higher than bridgeDepositNonce in deposits, the nonce is incremented on opening and should reach here chronologically
    }

    /// @notice Calculates the maximum amount a user can withdraw from a pool based on their share of the pool
    /// @dev Uses the pool's current position value and the user's scaled ratio to determine the allowable withdrawal amount
    /// @dev _currentPositionValue must be measured with the same nonces that were saved on the pool at the time of measuring _scaledRatio
    /// @param _currentPositionValue The total non pending value of the pool's position.
    /// @param _scaledRatio The user's deposit ratio in the pool, scaled by 10^18. Measured by their pool token balance out of all total pool tokens
    /// @return Maximum withdrawable amount for the user
    function getUserMaxWithdraw(
        uint256 _currentPositionValue,
        uint256 _scaledRatio
    ) public view returns (uint256) {
        if (_scaledRatio == 1e17) {
            return _currentPositionValue;
        }

        uint256 userMaxWithdraw = (_scaledRatio * _currentPositionValue) /
            (10 ** 18);

        return userMaxWithdraw;
    }
}
