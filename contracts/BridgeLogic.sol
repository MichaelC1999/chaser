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
    mapping(address => mapping(uint256 => uint256))
        public poolToNonceToCumulativeDeposits;
    mapping(address => mapping(uint256 => uint256))
        public poolToNonceToCumulativeWithdraw;

    event AcrossMessageSent(bytes);
    event Numbers(uint256, uint256);
    event ExecutionMessage(string);

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

    function addConnections(
        address _messengerAddress,
        address _bridgeReceiverAddress,
        address _integratorAddress
    ) external onlyOwner {
        messenger = IChaserMessenger(_messengerAddress);
        bridgeReceiverAddress = _bridgeReceiverAddress;
        integratorAddress = _integratorAddress;
    }

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
        bytes32 currentNonceHash = keccak256(abi.encode(_poolAddress, 0));
        poolToCurrentPositionMarket[_poolAddress] = _marketAddress;
        poolToAsset[_poolAddress] = _tokenSent;

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

    function handleEnterPivot(
        address _tokenSent,
        uint256 _amount,
        address _poolAddress,
        bytes32 _protocolHash,
        address _marketAddress,
        uint256 _poolNonce
    ) external {
        require(
            msg.sender == bridgeReceiverAddress,
            "Only callable by the BridgeReceiver"
        );

        poolToAsset[_poolAddress] = _tokenSent;

        updatePositionState(_poolAddress, _protocolHash, _marketAddress);

        receiveDepositFromPool(_amount, _poolAddress);
        if (managerChainId == localChainId) {
            // If the Pool is on this same chain, directly call the proper functions on this chain no CCIP
            IPoolControl(_poolAddress).pivotCompleted(_marketAddress, _amount);
        } else {
            // If the Pool is on a different chain, use CCIP to notify the pool
            sendPivotCompleted(_poolAddress, _amount);
        }
    }

    function handleUserDeposit(
        address _poolAddress,
        bytes32 _depositId,
        uint256 _withdrawNonce,
        uint256 _amount
    ) external {
        // IMPORTANT - !!! Does the user need to factor in pending deposits/withdraws when minting pool tokens?
        // If all depos/withdraws finalize in order, this would not be issue
        // Maybe get poolToken ratio of outputAmount/(currentPositionValue-pending) before bridging? CANT, THE RATIO/AMOUNT COULD BE MANIPULATED IN ACROSS MESSAGE
        // Also, currentPositionValue would be based on outdated value. Wouldnt include interest (not applicable) and could be affected by tx that are started after but finalize before
        // If ratio is recorded here, pending amounts to positionBalance arent an issue, but poolToken supply is
        // If the deposit callback with ratio in its data gets executed on pool before a withdraw that had been deducted from positionBalance before the deposit, pool tokens would be disporportionate

        // Why not on the callback? This way we are getting the poolToken supplies of finalized transactions and the ratio at moment of depo/with?

        // IMPORTANT - !!! Why not keep poolTokens on here, separate off of pool? NO, PROPORTIONS WILL NOT TRANSFER TO OTHER CHAINS/STATE WILL NOT UPDATE ACROSS CHAINS
        // - Can track proportions without worrying about bridging, pending transactions
        // - burns/mints on here
        // - !!! If no across sender/origin validation, users could fake being other addresses to withdraw
        // - But could combine existing poolToken system with this in order to

        // IMPORTANT - COULD MAYBE HAVE PREDEFINED 'CHASER RELAYER' IN BRIDGERECEIVER THAT IS THE ONLY ONE PERMITTED TO HANDLE MESSAGES, BUT ALSO GUARANTEES THEM IN ORDER
        // But would require(relayerAddress = 0x...) revert yet fulfill the transaction? As in the transaction is considered fulfilled and cannot be relayed?
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

    function sendPositionBalance(bytes memory _data) external {
        require(msg.sender == address(messenger), "Only callable by messenger");
    }

    /**
     * @notice Send the current position value of a pool back to the pool contract
     * @dev This is the "B=>A" segment of the "A=>B=>A" sequence for reading the current position value across chains
     * @param _poolAddress The address of the pool
     * @param _depositId If called as part of a deposit with the purpose of minting pool tokens, the deposit ID is passed here. It is optional, for falsey use bytes32 zero value
     */
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

    /**
     * @notice Send the current position value of a pool back to the pool contract
     * @dev This is the "B=>A" segment of the "A=>B=>A" sequence for reading the current position value across chains
     * @param _poolAddress The address of the pool
     * @param _depositId If called as part of a deposit with the purpose of minting pool tokens, the deposit ID is passed here. It is optional, for falsey use bytes32 zero value
     */
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

    function sendPivotCompleted(
        address _poolAddress,
        uint256 _amount
    ) internal {
        bytes4 method = bytes4(keccak256(abi.encode("BaPivotMovePosition")));
        address marketAddress = poolToCurrentPositionMarket[_poolAddress];
        bytes memory data = abi.encode(marketAddress, _amount);

        registry.sendMessage(managerChainId, method, _poolAddress, data);
    }

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
            _destinationBridgeReceiver,
            _poolAddress,
            _destinationChainId,
            message
        );
    }

    function executeExitPivot(
        address _poolAddress,
        bytes memory _data
    ) external {
        require(
            msg.sender == address(messenger) ||
                registry.poolEnabled(msg.sender),
            "Only callable by the Messenger or a valid pool"
        );
        // Withdraw from current position here, bringing funds back to this contract and updating state
        (
            bytes32 targetProtocolHash,
            address targetMarketAddress,
            uint256 destinationChainId,
            address destinationBridgeReceiver
        ) = abi.decode(_data, (bytes32, address, uint256, address));

        uint256 amount = getPositionBalance(_poolAddress);
        integratorWithdraw(_poolAddress, amount);

        if (localChainId == destinationChainId) {
            // Position should be entered from here, to enable pivot when requested from pool on local chain or other chain through messenger contract
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

    function localPivot(address _poolAddress, uint256 _amount) internal {
        receiveDepositFromPool(_amount, _poolAddress);
        // Pivot was successful, now we need to notify the pool of this
        if (managerChainId == localChainId) {
            // If the Pool is on this same chain, directly call the proper functions on this chain no CCIP
            address marketAddress = poolToCurrentPositionMarket[_poolAddress];
            IPoolControl(_poolAddress).pivotCompleted(marketAddress, _amount);
        } else {
            // If the Manager is on a different chain, use CCIP to notify the pool
            sendPivotCompleted(_poolAddress, _amount);
        }
    }

    function returnToPool(
        bytes4 _originalMethod,
        address _poolAddress,
        bytes32 _depositId,
        uint256 _amount,
        uint256 _poolNonce
    ) external {
        require(
            msg.sender == bridgeReceiverAddress,
            "Only callable by the BridgeReceiver"
        );
        // takes a failed BridgeReceiver function call, and sends it through across back to the pool
        bytes4 method = bytes4(keccak256(abi.encode("BaReturnToPool")));

        bytes memory message = abi.encode(
            method,
            _poolAddress,
            abi.encode(_originalMethod, _depositId, _poolNonce)
        );
        address destinationBridgeReceiver = registry.chainIdToBridgeReceiver(
            managerChainId
        );
        updatePositionState(_poolAddress, bytes32(""), address(0));
        if (localChainId == managerChainId) {
            if (
                _originalMethod ==
                bytes4(keccak256(abi.encode("AbBridgePositionInitializer")))
            ) {
                IERC20(poolToAsset[_poolAddress]).approve(
                    _poolAddress,
                    _amount
                );

                IPoolControl(_poolAddress).handleUndoPositionInitializer(
                    _depositId,
                    _amount
                );
            }

            if (
                _originalMethod ==
                bytes4(keccak256(abi.encode("AbBridgeDepositUser")))
            ) {
                IERC20(poolToAsset[_poolAddress]).approve(
                    _poolAddress,
                    _amount
                );

                IPoolControl(_poolAddress).handleUndoDeposit(
                    _depositId,
                    _amount
                );
            }

            if (
                _originalMethod ==
                bytes4(keccak256(abi.encode("BbPivotBridgeMovePosition")))
            ) {
                IPoolControl(_poolAddress).handleUndoPivot(_poolNonce, _amount);
                bool success = IERC20(poolToAsset[_poolAddress]).transfer(
                    _poolAddress,
                    _amount
                );
                require(success, "Token transfer failure");
            }
        } else {
            crossChainBridge(
                _amount,
                destinationBridgeReceiver,
                _poolAddress,
                managerChainId,
                message
            );
        }
    }

    function crossChainBridge(
        uint256 _amount,
        address _destinationBridgeReceiver,
        address _poolAddress,
        uint256 _destinationChainId,
        bytes memory _message
    ) internal {
        address acrossSpokePool = registry.chainIdToSpokePoolAddress(0);
        IERC20(poolToAsset[_poolAddress]).approve(acrossSpokePool, _amount);
        ISpokePool(acrossSpokePool).depositV3(
            address(this),
            _destinationBridgeReceiver,
            poolToAsset[_poolAddress],
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

    function userWithdrawSequence(
        address _poolAddress,
        bytes memory _data
    ) external {
        require(
            msg.sender == address(messenger) ||
                registry.poolEnabled(msg.sender),
            "Only callable by the Messenger or a valid pool"
        );
        // - userWithdraw: bytes 20 userAddress, uint256 amountToWithdraw, uint256 userProportionRatio
        // Pulls out the appropriate amount of asset from position
        // Sends the withdrawn asset through Across back to pool to be sent to user
        // IMPORTANT - MUST RECEIVE + VERIFY USER SIGNED MESSAGE FROM POOLCONTROL
        //If the requested amount is over the actual asset amount user can withdraw, just withdraw the max

        // IMPORTANT - WHAT HAPPENS IF POOLTOKENSUPPLY HAS NOT BEEN UPDATED, BUT THE POSITION BALANCE HAS? WE SHOULD MEASURE PROPORTION BEFORE EITHER ARE UPDATED FROM OTHER PENDING ORDERS
        // IMPORTANT - WE NEED TO HAVE THE USER'S POOL TOKEN PROPORTION AT THE TIME OF WITHDRAW, AS WELL AS THE USERS ASSET PROPORTION FROM THAT SAME MOMENT
        // IMPORTANT - MAINTAIN POOL DEPOSITS/WITHDRAWS NONCES ON THE POOL CONTRACT, ON THE POSITION CONTRACT KEEP SNAPSHOTS OF BALANCES AT THESE NONCES
        // IMPORTANT - ORDERED CCIP MESSAGING IRRELEVANT TO THIS ISSUE, AS IT IS AB-BA. The issue is when AB state is read before the BA sequence of another tx is executed
        // IMPORTANT - IF THE PoolControl SAYS USER PORTION IS 1/100, BUT THERE IS A PENDING USER DEPOSIT (FROM OTHER USER) OF 100, THE USER WILL HAVE ACCESS TO 2 UINTS (2/200)
        // Example: Currently posBal is 10 - user has 20 pool tokens in a total of 200. The user can withdraw 1 asset
        // Issue:   PosBal is 10 - user has 20 pool tokens in a total of 100, meanwhile the total should be 200 tokens because PosBal reflects a recent 5 asset deposit. The user can withdraw 2 asset
        // Solution: If we take proportion before pending deposit, the proportions are fixed
        //          PosBal is 5 - user has 20 pool tokens in a total of 100, the user can withdraw 1 asset

        // IMPORTANT - BUT WITH POSITION VALUE SNPASHOTS, THE VALUE DOES NOT INCLUDE INTEREST GAINED SINCE SNAPSHOT
        // Does this give depositor a higher stake than deserved, lower stake, or just disclude recently gained interest from user?
        // POSBAL FROM SNAPSHOT: PosBal is 5 - user has 20 pool tokens in a total of 100, the user can withdraw 1 asset
        // POSBAL GAINED 1 YIELD: PosBal is 6 - user has 20 pool tokens in a total of 100, the user can withdraw 1.2 asset
        // WE ALSO TAKE THE SNAPSHOT FROM MOST RECENT PROCESSING TX, GET THE DIFFERENCE BETWEEN THIS SNAPSHOT AND LAST COMPLETE SNAPSHOT. SUBTRACT THIS VALUE FROM CURRENT POSITION VALUE
        // POSBAL PENDING: PosBal is 5 with +5 pendng (most recent snapshot shows 10) - user has 20 pool tokens in a total of 100, the user can withdraw 1 asset
        // POSBAL GAINED 1 YIELD: PosBal from completed snap is 5, pending snap is 10, current pos is 11. Get Pos bal from currentPos - (pending - completed) = 6 - user has 20 pool tokens in a total of 100, the user can withdraw 1.2 asset

        // POSBAL PENDING: PosBal is 5 with -3 pendng (most recent snapshot shows 2) - user has 20 pool tokens in a total of 100, the user can withdraw 1 asset
        // POSBAL GAINED 1 YIELD: PosBal from completed snap is 5, pending snap is 2, current pos is 3. Get Pos bal from currentPos - (pending - completed) = 6 - user has 20 pool tokens in a total of 100, the user can withdraw 1.2 asset
        // The ratio to get maxAssetToWithdraw (x) is as follows: x/(currentPositionValue - (nonceToPositionValue[bridgeNonce] - nonceToPositionValue[poolNonce])) = userPoolTokenBalance/poolTokenSupply
        // IMPORTANT - DOES THIS RATIO WORK IF THERE IS A PIVOT TO ANOTHER CONNECTOR, THEN BACK TO THIS ONE

        // IMPORTANT - CAN THIS BE SOLVED BY PROVIDING THE PENDING DEPO AND WITHDRAW FROM THE POOLCALC?
        // PoolCalc can record the outputAmount's passed to Across V3, and calculate pending values based on this
        // Pending values then are the exact amounts contributed to the investment
        // Can remove the nonce based balance system, less confusing crossing between chains
        // Does this solve the yield lost issue where withdraws dont include interest gained since the last interaction?
        // -Yield lost issue occurs because the withdraw portion reads from the balance at the nonce before pending transactions were made
        // -The interest gained from the most recent depo/wthdraw until current moment is not included, nor is interest gained between the nonce of last completed transaction and the first currently pending transaction
        // -The withdraw system now includes the interest in the total portion, because it takes getPositionBalance() - pendingDepos + pendingWithdraws
        // -No issues with manipulative bridging, as this data is only passed through CCIP
        // -The pending depos/withdraws are not included in poolToken supply/balance when the scaledRatio was taken

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
            _poolAddress,
            withdrawId
        );
    }

    /**
     * @notice Send the withdraw funds requested through the Across bridge back to the pool contract for fulfillment
     * @dev This is the "B=>A" segment of the "A=>B=>A" sequence for withdraws
     * @param _amount The amount to be sent in the bridge for the user to receive, denominated in the pool's asset
     * @param _userMaxWithdraw The total amount of funds in a position that pertain to a given user. The maximum that they could withdraw at this point
     * @param _poolAddress The address of the pool being interacted with
     * @param _withdrawId The withdraw ID used for data lookup on the pool
     */
    function userWithdraw(
        uint256 _amount,
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
        uint256 positionBalance = getPositionBalance(_poolAddress);

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
                destinationBridgeReceiver,
                _poolAddress,
                managerChainId,
                message
            );
        }
    }

    /**
     * @notice Process a deposit whether by a user or from pivoting an entire pool's funds
     * @dev This is the "B=>A" segment of the "A=>B=>A" sequence for deposits. This sends data to the pool about the proportion of the pool's position that this deposit makes.
     * @dev Data sent here through LZ determines ratio to mint pool tokens on the pool's chain
     * @param _amount The amount deposited into the pool, denominated in the pool's asset
     * @param _poolAddress The address of the pool that the deposit pertains to
     */
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

    /**
     * @notice Function for saving the value of a pool's position at a given deposit/withdraw nonce
     * @dev This position value nonce system is useful for determining mint/burn ratios of the pool
     * @dev If the current position value on the external protocol includes deposits that have not been minted/burnt on the pool chain, the ratio can be thrown off
     * @param _poolAddress The address of the pool
     * @param _txAmount The value of the position, reflecting all deposits/withdraws that have completed the "A=>B" segment of interaction and interest gained
     */
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

    /**
     * @notice Function for reading the value of a pool's current position on an external protocol
     * @dev This functions links into other protocol's contracts for reading the true current value
     * @param _poolAddress The address of the pool
     * @return The value of a pool's position including interest gained
     */
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

    function getNonPendingPositionBalance(
        address _poolAddress,
        uint256 _poolDepoNonce,
        uint256 _poolWithNonce
    ) public view returns (uint256) {
        // The cumulativeDepo/Withdraw mappings need to account for skipped nonces (if current withdraw nonce is 6, but nonce 8 arrives before nonce 7)
        uint256 bridgeDepoNonce = poolAddressToDepositNonce[_poolAddress];
        uint256 bridgeWithNonce = poolAddressToWithdrawNonce[_poolAddress];

        uint256 cumulativeDeposAtPoolNonce = poolToNonceToCumulativeDeposits[
            _poolAddress
        ][_poolDepoNonce];
        uint256 cumualtiveWithsAtPoolNonce = poolToNonceToCumulativeWithdraw[
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
            pendingWithdraws =
                cumulativeWithsAtBridgeNonce -
                cumualtiveWithsAtPoolNonce;
        }

        uint256 currentBalance = getPositionBalance(_poolAddress);
        return currentBalance - pendingDeposits + pendingWithdraws;

        //poolWithdrawNonce can be higher than bridgeWithdrawNonce in deposits, if the deposit opens after with and reaches here faster than withdraw opening
        //In this case, the positionBalance is not affected by pending withdraws, since the value has not been deducted here yet
        //poolWithdrawNonce can be lower than bridgeWithdrawNonce in deposits, if the withdraw opens after depo opening and reaches here faster
        //In this case, the pendingWithdrawAmount = balAtBridgeWithdrawNonce - balAtPoolWithdrawNonce, getting the amount withrawn since the withdraw was opened on the pool
        //poolDepositNonce is always higher than bridgeDepositNonce in deposits, the nonce is incremented on opening and should reach here chronologically
        //There are no pending deposits in this case
    }

    /**
     * @notice Function for getting the maximum amount of funds a user can withdraw from a pool's position, denominated in the pool's asset
     * @dev This function uses the balances of the position at given nonces in order to prevent ratio miscalculations due to interchain messaging delays
     * @dev The nonce system enforces that the user max withdraw is calculated with the same total position value as existed when the provided pool ratio was calculated
     * @param _currentPositionValue The value of the position, reflecting all deposits/withdraws that have completed the "A=>B" segment of interaction and interest gained
     * @param _scaledRatio The ratio provided by the pool giving the proportion (user pool token balance / pool token total supply), scaled by 10**18
     * @return The amount of funds that a user my withdraw at a given time, based off of their pool token counts
     */
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
