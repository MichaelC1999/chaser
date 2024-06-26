// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {IChaserMessenger} from "./interfaces/IChaserMessenger.sol";
import {ISpokePool} from "./interfaces/ISpokePool.sol";
import {IPoolControl} from "./interfaces/IPoolControl.sol";
import {IChaserTreasury} from "./interfaces/IChaserTreasury.sol";
import {IIntegrator} from "./interfaces/IIntegrator.sol";
import {IPoolCalculations} from "./interfaces/IPoolCalculations.sol";
import {IPoolBroker} from "./interfaces/IPoolBroker.sol";
import {AggregatorV3Interface} from "./interfaces/IAggregatorV3.sol";
import {IAToken} from "./interfaces/IAToken.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Logic for Managing Positional State and processing interactions
/// @notice This contract manages handling deposits, withdrawals, and pivots for Chaser pools on the positional side
/// @dev When on the same chain as the pool, BridgeLogic and PoolControl directly call each other. When across chains, funds and data are moved through BridgeReceived and ChaserMessenger
contract BridgeLogic is OwnableUpgradeable {
    uint256 managerChainId;
    uint256 currentChainId;

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
    mapping(address => uint256) public poolToDepositNonceAtEntrance;
    mapping(address => uint256) public poolToWithdrawNonceAtEntrance;
    mapping(address => mapping(address => uint256)) public poolToEscrowAmount;
    mapping(address => bool) public poolInitialized;
    mapping(address => mapping(uint256 => uint256))
        public poolToNonceToCumulativeDeposits;
    mapping(address => mapping(uint256 => uint256))
        public poolToNonceToCumulativeWithdraw;
    mapping(address => uint256) public poolToPositionAtEntrance;

    /// @notice Initializes the BridgeLogic contract with chain IDs and the registry address, replacing the constructor
    /// @param _currentChainId Chain ID of the chain a specific BridgeLogic instance is deployed to
    /// @param _managerChainId Chain ID where the manager that coordinates pools is located
    /// @param _registryAddress Address of the ChaserRegistry contract
    function initialize(
        uint256 _currentChainId,
        uint256 _managerChainId,
        address _registryAddress
    ) public initializer {
        __Ownable_init();
        currentChainId = _currentChainId;
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
        setNonceCumulative(_poolAddress, _amount, 1, true);
        receiveDepositFromPool(_amount, _poolAddress, true);
        sendPositionInitialized(_poolAddress, _depositId, _amount);
    }

    function receivePivotEntranceFunds(
        uint256 _amount,
        address _poolAddress,
        address _tokenSent
    ) external {
        require(
            msg.sender == bridgeReceiverAddress,
            "Only callable by the BridgeReceiver"
        );

        IERC20(_tokenSent).transferFrom(
            bridgeReceiverAddress,
            address(this),
            _amount
        );

        if (poolToAsset[_poolAddress] == address(0)) {
            poolToAsset[_poolAddress] = _tokenSent;
        }

        poolToEscrowAmount[_tokenSent][_poolAddress] += _amount;

        if (currentChainId == managerChainId) {
            localPositionSetting(_poolAddress);
        }

        uint256 usableEscrowAmount = poolToEscrowAmount[
            poolToAsset[_poolAddress]
        ][_poolAddress];

        if (
            poolToCurrentPositionMarket[_poolAddress] != address(0) &&
            usableEscrowAmount > 0
        ) {
            setPivotEntranceFundsToPosition(_poolAddress);
        } else {
            address poolBroker = registry.poolAddressToBroker(_poolAddress);
            IERC20(_tokenSent).transfer(poolBroker, _amount);
        }
    }

    /// @notice Manages the transition of a pool's assets to a new market
    /// @dev This function handles the part of the pivot process for depositing all of a pool's funds into its new position
    /// @dev Could be called directly from PoolControl or BridgeReceiver
    /// @param _poolAddress Address of the pool undergoing the pivot
    /// @param _data Holds bytes with position data
    function handleEnterPositionState(
        address _poolAddress,
        bytes memory _data
    ) external {
        require(
            msg.sender == address(messenger),
            "Only callable by the Messenger"
        );

        (
            address asset,
            bytes32 protocolHash,
            address marketAddress,
            uint256 depositNonce,
            uint256 withdrawNonce
        ) = abi.decode(_data, (address, bytes32, address, uint256, uint256));
        poolAddressToDepositNonce[_poolAddress] = depositNonce;
        poolAddressToWithdrawNonce[_poolAddress] = withdrawNonce;
        //ccip message from pool sends the asset address
        //Registry convert this address to the local equivalent
        if (poolToAsset[_poolAddress] == address(0)) {
            poolInitialized[_poolAddress] = true;
        }
        poolToAsset[_poolAddress] = registry.localEquivalent(asset);

        updatePositionState(_poolAddress, protocolHash, marketAddress);
        if (poolToEscrowAmount[poolToAsset[_poolAddress]][_poolAddress] > 0) {
            setPivotEntranceFundsToPosition(_poolAddress);
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
        uint256 _depositNonce,
        uint256 _amount
    ) external {
        //IMPORTANT - simply going off of the withdraw nonce passed in the bridge is vulnerable to user manipulation
        // SOLUTION - In most normal cases, the withdraw nonce passed from the pool is the same as the withdraw nonce on bridge, since bridges are faster than ccip.
        // Optimistically assume that the withdraw nonces are equal, if they are not because of some bridging delay, it either is a timeout or a malicious attempt to change the current balance.
        //
        //BUT IN CASE A WITHDRAW iS REQUESTED, THEN A DEPOSIT IS MADE, AND THE DEPOSIT REACHES HERE BEFORE WITHDRAW - THE POOL WITHDRAW NONCE IS HIGHER THAN HERE
        // ISSUE IS THAT IF A USER FRONT RUNS A BRIDGE HANDLE, THEY COULD PUT A WITHDRAW NONCE HIGHER THAN THE POOL
        //IF THEY PUT A HIGHER NONCE, THERE IS NO PENDING BALANCE. THIS WOULD MAKE THE CURRENT BALANCE HIGHER, MINTING LESS POOL TOKENS THEN DESERVED
        //THIS MEANS NOT VULNERABLE TO MANIPULATION, WOULD ONLY BE A NEGATIVE FOR THE MALICIOUS USER
        require(
            _withdrawNonce >= poolAddressToWithdrawNonce[_poolAddress] ||
                _withdrawNonce == 0,
            "PoolControl and BridgeLogic withdraw nonce mismatch. The bridge transaction timed out."
        );

        require(
            _depositNonce > poolAddressToDepositNonce[_poolAddress],
            "PoolControl and BridgeLogic deposit nonce mismatch. The deposit nonce must be higher than previous"
        );

        require(
            msg.sender == bridgeReceiverAddress ||
                registry.poolEnabled(msg.sender),
            "Only callable by the BridgeReceiver"
        );

        setNonceCumulative(_poolAddress, _amount, _depositNonce, true);
        receiveDepositFromPool(_amount, _poolAddress, false);
        uint256 currentPositionBalance = getNonPendingPositionBalance(
            _poolAddress,
            poolAddressToDepositNonce[_poolAddress],
            _withdrawNonce
        );

        bytes memory data = abi.encode(
            currentPositionBalance,
            _amount,
            0,
            _depositId
        );
        if (managerChainId == currentChainId) {
            IPoolControl(_poolAddress).receivePositionBalanceDeposit(data);
        } else {
            registry.sendMessage(
                managerChainId,
                bytes4(
                    keccak256(abi.encode("BaMessagePositionBalanceDeposit"))
                ),
                _poolAddress,
                data
            );
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

        if (managerChainId == currentChainId) {
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

    function localPositionSetting(address _poolAddress) internal {
        IPoolControl pool = IPoolControl(_poolAddress);
        poolToAsset[_poolAddress] = pool.asset();

        IPoolCalculations poolCalc = IPoolCalculations(pool.poolCalculations());
        //PIVOT CASE 2, if position to enter is on same chain as manager, get the target position from poolCalc and set position here, then enter
        bytes32 protocolHash = poolCalc.targetPositionProtocolHash(
            _poolAddress
        );
        bytes memory marketId = poolCalc.targetPositionMarketId(_poolAddress);
        address marketAddress = poolCalc.getMarketAddressFromId(
            marketId,
            protocolHash
        );
        poolAddressToDepositNonce[_poolAddress] = poolCalc
            .poolDepositFinishedNonce(_poolAddress);
        poolAddressToWithdrawNonce[_poolAddress] = poolCalc.poolWithdrawNonce(
            _poolAddress
        );

        updatePositionState(_poolAddress, protocolHash, marketAddress);
    }

    function setPivotEntranceFundsToPosition(address _poolAddress) internal {
        uint256 escrowAmount = poolToEscrowAmount[poolToAsset[_poolAddress]][
            _poolAddress
        ];
        poolToEscrowAmount[poolToAsset[_poolAddress]][_poolAddress] = 0;
        setEntranceState(escrowAmount, _poolAddress);
        address poolBroker = registry.poolAddressToBroker(_poolAddress);
        uint256 poolBrokerBalance = IERC20(poolToAsset[_poolAddress]).balanceOf(
            poolBroker
        );

        IPoolBroker(poolBroker).forwardHeldFunds(poolBrokerBalance);
        receiveDepositFromPool(escrowAmount, _poolAddress, true);

        if (managerChainId == currentChainId) {
            IPoolControl(_poolAddress).pivotCompleted(
                poolToCurrentPositionMarket[_poolAddress],
                escrowAmount
            );
        } else {
            sendPivotCompleted(_poolAddress, escrowAmount);
        }
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
            try IAToken(_marketAddress).POOL() returns (address aavePool) {
                _marketAddress = aavePool;
            } catch {
                _marketAddress = address(0);
                _protocolHash = bytes32("");
            }
        }
        poolToCurrentPositionMarket[_poolAddress] = _marketAddress;
        poolToCurrentProtocolHash[_poolAddress] = _protocolHash;
    }

    /// @notice Manages the transition of a pool's position across chains
    /// @dev Clears internal position state on the local chain, calls bridge and sets up the bridging
    /// @param _poolAddress Address of the pool undergoing the pivot
    /// @param _destinationChainId Chain ID to bridge to
    /// @param _destinationBridgeReceiver Address of the bridge receiver on the destination chain
    /// @param _amount Amount of assets belonging to the pool/position
    function crossChainPivot(
        address _poolAddress,
        uint256 _destinationChainId,
        address _destinationBridgeReceiver,
        uint256 _amount
    ) internal {
        bytes4 method = bytes4(
            keccak256(abi.encode("BbPivotBridgeMovePosition"))
        );

        bytes memory message = abi.encode(method, _poolAddress, abi.encode(0));

        updatePositionState(_poolAddress, bytes32(""), address(0));

        crossChainBridge(
            _amount,
            poolToAsset[_poolAddress],
            _poolAddress,
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
            address destinationBridgeReceiver,
            uint256 protocolFeePct,
            uint256 proposerRewardUSDC,
            address asset
        ) = abi.decode(
                _data,
                (bytes32, address, uint256, address, uint256, uint256, address)
            );

        poolToAsset[_poolAddress] = registry.localEquivalent(asset);

        uint256 amount = getPositionBalance(_poolAddress);
        integratorWithdraw(_poolAddress, amount);

        amount = protocolDeductionCalculations(
            amount,
            protocolFeePct,
            proposerRewardUSDC,
            _poolAddress
        );

        if (currentChainId == destinationChainId) {
            updatePositionState(
                _poolAddress,
                targetProtocolHash,
                targetMarketAddress
            );
            setEntranceState(amount, _poolAddress);
            localPivot(_poolAddress, amount);
        } else {
            crossChainPivot(
                _poolAddress,
                destinationChainId,
                destinationBridgeReceiver,
                amount
            );
        }
    }

    function protocolDeductionCalculations(
        uint256 _amount,
        uint256 _protocolFeePct,
        uint256 _proposerRewardUSDC,
        address _poolAddress
    ) internal returns (uint256) {
        uint256 cumulativeDepositsSincePivot = poolToNonceToCumulativeDeposits[
            _poolAddress
        ][poolAddressToDepositNonce[_poolAddress]] -
            poolToNonceToCumulativeDeposits[_poolAddress][
                poolToDepositNonceAtEntrance[_poolAddress]
            ];

        uint256 cumulativeWithdrawsSincePivot = poolToNonceToCumulativeWithdraw[
            _poolAddress
        ][poolAddressToWithdrawNonce[_poolAddress]] -
            poolToNonceToCumulativeWithdraw[_poolAddress][
                poolToWithdrawNonceAtEntrance[_poolAddress]
            ];
        uint256 revenue = (_amount +
            cumulativeWithdrawsSincePivot -
            (cumulativeDepositsSincePivot +
                poolToPositionAtEntrance[_poolAddress]));

        uint256 protocolFee = 0;
        if (revenue > 0) {
            protocolFee = (revenue * _protocolFeePct) / 1000000; //1000000 is 100% in the protocolFee Scale
        }
        uint256 assetPrice = assetPricePerUSDCOracle(_poolAddress);
        if (assetPrice == 0) {
            assetPrice = 1e12;
        }

        uint256 rewardFactor = _proposerRewardUSDC * 1e20; // Convert 100 USDC to same USD decimals as returned by chainlink with 1e2. Then 1e18 to scale
        uint256 rewardAmountInAsset = (rewardFactor) / (assetPrice);
        //REWARD AMOUNT GETS TAKEN REGARDLESS OF THE PROFIT
        protocolDeduction(protocolFee, rewardAmountInAsset, _poolAddress);
        //If _amount < fee+reward, prevent the pivot. Keep the deposit where it currently is and send callback to Pool saying the position did not move
        return _amount - (protocolFee + rewardAmountInAsset);
    }

    function protocolDeduction(
        uint256 _protocolFee,
        uint256 _rewardAmountInAsset,
        address _poolAddress
    ) internal {
        bytes4 method = bytes4(keccak256(abi.encode("BaProtocolDeduction")));

        bytes memory message = abi.encode(
            method,
            _poolAddress,
            abi.encode(_protocolFee, _rewardAmountInAsset)
        );
        uint256 amount = _protocolFee + _rewardAmountInAsset;

        if (currentChainId == managerChainId) {
            address treasuryAddress = registry.treasuryAddress();
            bool success = IERC20(poolToAsset[_poolAddress]).transfer(
                treasuryAddress,
                amount
            );
            IChaserTreasury(treasuryAddress).separateProtocolFeeAndReward(
                _rewardAmountInAsset,
                _protocolFee,
                _poolAddress,
                poolToAsset[_poolAddress]
            );
        } else {
            address destinationBridgeReceiver = registry
                .chainIdToBridgeReceiver(managerChainId);
            crossChainBridge(
                amount,
                poolToAsset[_poolAddress],
                _poolAddress,
                destinationBridgeReceiver,
                managerChainId,
                message
            );
        }
    }

    /// @notice Handles the local aspects of a pivot operation within the same chain
    /// @dev Internal function to complete a pivot operation where the position being entered is on the same chain as the position exited
    /// @dev If the Pool is on a different chain, use CCIP to notify the pool
    /// @param _poolAddress Address of the pool
    /// @param _amount Amount of assets involved in the pivot
    function localPivot(address _poolAddress, uint256 _amount) internal {
        receiveDepositFromPool(_amount, _poolAddress, true);
        if (managerChainId == currentChainId) {
            address marketAddress = poolToCurrentPositionMarket[_poolAddress];
            IPoolControl(_poolAddress).pivotCompleted(marketAddress, _amount);
        } else {
            sendPivotCompleted(_poolAddress, _amount);
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
        address _poolAddress,
        address _destinationBridgeReceiver,
        uint256 _destinationChainId,
        bytes memory _message
    ) internal {
        address acrossSpokePool = registry.chainIdToSpokePoolAddress(0);
        IERC20(_asset).approve(acrossSpokePool, _amount);
        address poolBroker = registry.poolAddressToBroker(_poolAddress);
        ISpokePool(acrossSpokePool).depositV3(
            poolBroker,
            _destinationBridgeReceiver,
            _asset,
            address(0),
            _amount,
            _amount - (_amount / 250),
            _destinationChainId,
            address(0),
            uint32(block.timestamp),
            uint32(block.timestamp + 7200),
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
            userMaxWithdraw,
            poolWithdrawNonce,
            _poolAddress,
            withdrawId
        );
    }

    /// @notice Executes the withdrawal of funds for a user, handling asset transfers and notifications
    /// @dev Internal function that calls integrator to send back position funds, updates states, and puts into motion the deposit callback
    /// @param _amount Amount to be withdrawn
    /// @param _userMaxWithdraw Maximum amount the user can withdraw based on their pool token ratio
    /// @param _poolAddress Address of the pool
    /// @param _withdrawId Withdrawal identifier
    function userWithdraw(
        uint256 _amount,
        uint256 _userMaxWithdraw,
        uint256 _poolWithdrawNonce,
        address _poolAddress,
        bytes32 _withdrawId
    ) internal {
        address destinationBridgeReceiver = registry.chainIdToBridgeReceiver(
            managerChainId
        );

        bytes4 method = bytes4(keccak256(abi.encode("BaBridgeWithdrawFunds")));

        integratorWithdraw(_poolAddress, _amount);
        setNonceCumulative(_poolAddress, _amount, _poolWithdrawNonce, false);

        uint256 positionBalance = getPositionBalance(_poolAddress);

        bytes memory message = abi.encode(
            method,
            _poolAddress,
            abi.encode(_withdrawId)
        );

        bytes memory data = abi.encode(
            positionBalance,
            _amount,
            _userMaxWithdraw,
            _withdrawId
        );

        if (managerChainId == currentChainId) {
            bool success = IERC20(poolToAsset[_poolAddress]).transfer(
                _poolAddress,
                _amount
            );
            require(success, "Token transfer failure");
            IPoolControl(_poolAddress).setWithdrawReceived(
                _withdrawId,
                _amount
            );
            IPoolControl(_poolAddress).receivePositionBalanceWithdraw(data);
        } else {
            crossChainBridge(
                _amount,
                poolToAsset[_poolAddress],
                _poolAddress,
                destinationBridgeReceiver,
                managerChainId,
                message
            );
            registry.sendMessage(
                managerChainId,
                bytes4(
                    keccak256(abi.encode("BaMessagePositionBalanceWithdraw"))
                ),
                _poolAddress,
                data
            );
        }
    }

    /// @notice Processes incoming deposits and pivot entry, routing them through the integrator to external protocols
    /// @dev Transfer funds to the integrator and saves the position state
    /// @param _amount Amount of the deposit
    /// @param _poolAddress Address of the pool making the deposit
    function receiveDepositFromPool(
        uint256 _amount,
        address _poolAddress,
        bool _positionEntrance
    ) internal returns (bool) {
        bytes32 operation = keccak256(abi.encode("deposit"));

        address marketAddress = poolToCurrentPositionMarket[_poolAddress];
        bytes32 protocolHash = poolToCurrentProtocolHash[_poolAddress];
        address poolBroker = registry.poolAddressToBroker(_poolAddress);
        if (poolBroker == address(0)) {
            poolBroker = registry.deployPoolBroker(
                _poolAddress,
                poolToAsset[_poolAddress]
            );
        }

        if (marketAddress != address(0)) {
            IERC20(poolToAsset[_poolAddress]).approve(
                integratorAddress,
                _amount
            );

            try
                IIntegrator(integratorAddress).routeExternalProtocolInteraction(
                    protocolHash,
                    operation,
                    _amount,
                    _poolAddress,
                    poolToAsset[_poolAddress],
                    marketAddress
                )
            {
                return true;
            } catch {}
        }
        handleInvalidMarketDeposit(
            _amount,
            _poolAddress,
            poolBroker,
            _positionEntrance
        );
        return false;
    }

    function handleInvalidMarketDeposit(
        uint256 _amount,
        address _poolAddress,
        address _poolBroker,
        bool _positionEntrance
    ) internal {
        IERC20(poolToAsset[_poolAddress]).transfer(_poolBroker, _amount);
        if (_positionEntrance == true) {
            updatePositionState(_poolAddress, bytes32(""), address(0));
        }
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
        address poolBroker = registry.poolAddressToBroker(_poolAddress);
        uint256 poolBrokerBalance = IERC20(poolToAsset[_poolAddress]).balanceOf(
            poolBroker
        );
        if (poolBrokerBalance > 0) {
            IPoolBroker(poolBroker).forwardHeldFunds(_amount);
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
        uint256 _newNonce,
        bool _isDepo
    ) internal {
        if (_isDepo) {
            uint256 oldNonce = poolAddressToDepositNonce[_poolAddress];
            poolAddressToDepositNonce[_poolAddress] = _newNonce;
            poolToNonceToCumulativeDeposits[_poolAddress][_newNonce] =
                poolToNonceToCumulativeDeposits[_poolAddress][oldNonce] +
                _txAmount;
        } else {
            uint256 oldNonce = poolAddressToWithdrawNonce[_poolAddress];
            poolAddressToWithdrawNonce[_poolAddress] = _newNonce;
            poolToNonceToCumulativeWithdraw[_poolAddress][_newNonce] =
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

    function assetPricePerUSDCOracle(
        address _poolAddress
    ) public view returns (uint256) {
        address usdc = registry.addressUSDC(currentChainId);
        if (poolToAsset[_poolAddress] == usdc) {
            return 1;
        }
        return getChainlinkPrice(poolToAsset[_poolAddress]);
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

    function setEntranceState(uint256 _amount, address _poolAddress) internal {
        poolToDepositNonceAtEntrance[_poolAddress] = poolAddressToDepositNonce[
            _poolAddress
        ];
        poolToWithdrawNonceAtEntrance[
            _poolAddress
        ] = poolAddressToWithdrawNonce[_poolAddress];
        poolToPositionAtEntrance[_poolAddress] = _amount;
    }

    function getChainlinkPrice(address asset) public view returns (uint256) {
        address dataFeed = registry.getDataFeed(asset);
        (, int answer, , , ) = AggregatorV3Interface(dataFeed)
            .latestRoundData();
        return uint256(uint(answer));
    }
}
