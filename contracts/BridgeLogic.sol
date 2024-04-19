// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {IChaserMessenger} from "./interfaces/IChaserMessenger.sol";
import {ISpokePool} from "./interfaces/ISpokePool.sol";
import {IPoolControl} from "./interfaces/IPoolControl.sol";
import {IIntegrator} from "./interfaces/IIntegrator.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BridgeLogic is OwnerIsCreator {
    uint256 managerChainId;

    IChaserRegistry public registry;
    IChaserMessenger public messenger;

    address public bridgeReceiverAddress;
    address public integratorAddress;

    mapping(address => address) public poolToCurrentPositionMarket;
    mapping(address => string) public poolToCurrentMarketId;
    mapping(address => bytes32) public poolToCurrentProtocolHash;
    mapping(address => uint256) public positionEntranceAmount;
    mapping(address => address) public poolToAsset;
    mapping(bytes32 => uint256) public userDepositNonce;
    mapping(bytes32 => uint256) public userCumulativeDeposits;
    mapping(bytes32 => uint256) public nonceToPositionValue; // key is hash of bytes of pool address and nonce
    mapping(address => uint256) public bridgeNonce; // pool address to the current nonce of all withdraws/deposits reflected in the position balance

    event PositionBalanceSent(
        uint256 indexed,
        address indexed,
        bytes32 indexed
    );
    event AcrossMessageSent(bytes);
    event LzMessageSent(bytes4, bytes);
    event Numbers(uint256, uint256);
    event ExecutionMessage(string);

    constructor(uint256 _managerChainId, address _registryAddress) {
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
        string memory _marketId,
        bytes32 _protocolHash
    ) external {
        require(
            msg.sender == bridgeReceiverAddress ||
                registry.poolEnabled(msg.sender),
            "Only callable by the BridgeReceiver or a valid pool"
        );
        bytes32 currentNonceHash = keccak256(abi.encode(_poolAddress, 0));
        bridgeNonce[_poolAddress] = 0;
        nonceToPositionValue[currentNonceHash] = 0;
        poolToCurrentPositionMarket[_poolAddress] = _marketAddress;
        poolToAsset[_poolAddress] = _tokenSent;

        enterPosition(
            _poolAddress,
            _protocolHash,
            _marketAddress,
            _marketId,
            _amount
        );

        bytes32 userPoolHash = keccak256(
            abi.encode(_userAddress, _poolAddress)
        );

        userDepositNonce[userPoolHash] += 1;
        userCumulativeDeposits[userPoolHash] += _amount;
        receiveDepositFromPool(_amount, _poolAddress);
        sendPositionInitialized(_poolAddress, _depositId, _amount);
    }

    function handleEnterPivot(
        address _tokenSent,
        uint256 _amount,
        address _poolAddress,
        bytes32 _protocolHash,
        address _marketAddress,
        string memory _targetMarketId,
        uint256 _poolNonce
    ) external {
        require(
            msg.sender == bridgeReceiverAddress,
            "Only callable by the BridgeReceiver"
        );

        poolToAsset[_poolAddress] = _tokenSent;

        bridgeNonce[_poolAddress] = _poolNonce;
        // nonceToPositionValue[currentNonceHash] = _amount;
        enterPosition(
            _poolAddress,
            _protocolHash,
            _marketAddress,
            _targetMarketId,
            _amount
        );
        uint256 currentChainId = registry.currentChainId();

        receiveDepositFromPool(_amount, _poolAddress);
        if (managerChainId == currentChainId) {
            // If the Pool is on this same chain, directly call the proper functions on this chain no CCIP
            IPoolControl(_poolAddress).pivotCompleted(
                _marketAddress,
                bridgeNonce[_poolAddress],
                _amount
            );
        } else {
            // If the Pool is on a different chain, use CCIP to notify the pool
            sendPivotCompleted(_poolAddress, _amount);
        }
    }

    function handleUserDeposit(
        address _poolAddress,
        address _userAddress,
        bytes32 _depositId,
        uint256 _amount
    ) external {
        require(
            msg.sender == bridgeReceiverAddress ||
                registry.poolEnabled(msg.sender),
            "Only callable by the BridgeReceiver"
        );
        bytes32 userPoolHash = keccak256(
            abi.encode(_userAddress, _poolAddress)
        );
        userDepositNonce[userPoolHash] += 1;
        userCumulativeDeposits[userPoolHash] += _amount;

        receiveDepositFromPool(_amount, _poolAddress);
        _sendPositionBalance(_poolAddress, _depositId, _amount);
    }

    /**
     * @notice Get the balance for a pool at a given nonce
     * @dev This function makes the pool + nonce hash and reads the value in the mapping
     * @dev The nonce pertains to deposits/withdraws on a given pool that have been reflected in the current position value on the pool
     * @param _poolAddress The address of the pool
     * @param _nonce The deposit/withdraw count for the pool
     */
    function readBalanceAtNonce(
        address _poolAddress,
        uint256 _nonce
    ) public view returns (uint256) {
        bytes32 valHash = keccak256(abi.encode(_poolAddress, _nonce));
        return nonceToPositionValue[valHash];
    }

    function sendPositionBalance(
        address _poolAddress,
        bytes32 _depositId,
        uint256 _amount
    ) external {
        require(msg.sender == address(messenger), "Only callable by messenger");
        _sendPositionBalance(_poolAddress, _depositId, _amount);
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
        uint256 _amount
    ) internal {
        bytes32 protocolHash = poolToCurrentProtocolHash[_poolAddress];
        address marketAddress = poolToCurrentPositionMarket[_poolAddress];
        uint256 positionAmount = IIntegrator(integratorAddress)
            .getCurrentPosition(
                _poolAddress,
                poolToAsset[_poolAddress],
                marketAddress,
                protocolHash
            );

        bytes4 method = bytes4(
            keccak256(abi.encode("BaMessagePositionBalance"))
        );

        bytes memory data = abi.encode(positionAmount, _amount, _depositId);

        emit PositionBalanceSent(positionAmount, _poolAddress, _depositId);

        if (managerChainId == registry.currentChainId()) {
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
        address currentPositionMarket = poolToCurrentPositionMarket[
            _poolAddress
        ];
        bytes32 protocolHash = poolToCurrentProtocolHash[_poolAddress];
        uint256 positionAmount = IIntegrator(integratorAddress)
            .getCurrentPosition(
                _poolAddress,
                poolToAsset[_poolAddress],
                currentPositionMarket,
                protocolHash
            );

        bytes4 method = bytes4(keccak256(abi.encode("BaPositionInitialized")));

        bytes memory data = abi.encode(
            positionAmount,
            _depositAmount,
            currentPositionMarket,
            _depositId
        );

        emit PositionBalanceSent(
            positionAmount,
            currentPositionMarket,
            _depositId
        );

        if (managerChainId == registry.currentChainId()) {
            IPoolControl(_poolAddress).receivePositionInitialized(data);
        } else {
            registry.sendMessage(managerChainId, method, _poolAddress, data);
        }
    }

    /**
     * @notice Send position data of a pool back to the pool contract
     */
    function sendPositionData(address _poolAddress) external {
        require(
            msg.sender == address(messenger),
            "SendPositionData invalid sender"
        );

        bytes memory data = abi.encode("TESTING THE CALLBACK");

        bytes4 method = bytes4(keccak256(abi.encode("BaMessagePositionData")));

        try registry.sendMessage(managerChainId, method, _poolAddress, data) {
            emit ExecutionMessage("sendMessage success");
        } catch Error(string memory reason) {
            emit ExecutionMessage(
                string(abi.encodePacked("BridgeLogic: ", reason))
            );
        }
    }

    /**
     * @notice Send an address back to the pool contract
     */
    function sendRegistryAddress(address _poolAddress) internal {
        bytes memory data;

        bytes4 method = bytes4(keccak256(abi.encode("sendRegistryAddress")));
        try registry.sendMessage(managerChainId, method, _poolAddress, data) {
            emit ExecutionMessage("sendMessage success");
        } catch Error(string memory reason) {
            emit ExecutionMessage(
                string(abi.encodePacked("BridgeLogic: ", reason))
            );
        }
    }

    function sendPivotCompleted(
        address _poolAddress,
        uint256 _amount
    ) internal {
        bytes4 method = bytes4(keccak256(abi.encode("BaPivotMovePosition")));
        address marketAddress = poolToCurrentPositionMarket[_poolAddress];
        bytes memory data = abi.encode(
            marketAddress,
            bridgeNonce[_poolAddress],
            _amount
        );

        try registry.sendMessage(managerChainId, method, _poolAddress, data) {
            emit ExecutionMessage("sendMessage success");
        } catch Error(string memory reason) {
            emit ExecutionMessage(
                string(abi.encodePacked("BridgeLogic: ", reason))
            );
        }
    }

    function enterPosition(
        address _poolAddress,
        bytes32 _protocolHash,
        address _marketAddress,
        string memory _targetMarketId,
        uint256 _amount
    ) internal {
        poolToCurrentMarketId[_poolAddress] = _targetMarketId;
        poolToCurrentPositionMarket[_poolAddress] = _marketAddress;
        poolToCurrentProtocolHash[_poolAddress] = _protocolHash;
        positionEntranceAmount[_poolAddress] = _amount;
    }

    function crossChainPivot(
        address _poolAddress,
        bytes32 _protocolHash,
        address _targetMarketAddress,
        string memory _targetMarketId,
        uint256 _destinationChainId,
        address _destinationBridgeReceiver,
        uint256 _amount
    ) internal {
        // Pool nonce should be maintained equally between different chains

        bytes4 method = bytes4(
            keccak256(abi.encode("BbPivotBridgeMovePosition"))
        );

        bytes memory message = abi.encode(
            method,
            _poolAddress,
            abi.encode(
                _protocolHash,
                _targetMarketAddress,
                _targetMarketId,
                bridgeNonce[_poolAddress]
            )
        );

        address acrossSpokePool = registry.chainIdToSpokePoolAddress(0);

        ERC20(poolToAsset[_poolAddress]).approve(acrossSpokePool, _amount);

        emit AcrossMessageSent(message);

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
            message
        );
    }

    function executeExitPivot(address _poolAddress, bytes memory _data) public {
        require(
            msg.sender == address(messenger) ||
                registry.poolEnabled(msg.sender),
            "Only callable by the Messenger or a valid pool"
        );
        // Withdraw from current position here, bringing funds back to this contract and updating state
        (
            bytes32 protocolHash,
            address targetMarketAddress,
            string memory targetMarketId,
            uint256 destinationChainId,
            address destinationBridgeReceiver
        ) = abi.decode(_data, (bytes32, address, string, uint256, address));

        uint256 amount = getPositionBalance(_poolAddress);

        uint256 currentChainId = registry.currentChainId();

        integratorWithdraw(_poolAddress, amount);

        if (currentChainId == destinationChainId) {
            // Position should be entered from here, to enable pivot when requested from pool on local chain or other chain through messenger contract
            enterPosition(
                _poolAddress,
                protocolHash,
                targetMarketAddress,
                targetMarketId,
                amount
            );
            receiveDepositFromPool(amount, _poolAddress);

            // Pivot was successful, now we need to notify the pool of this
            if (managerChainId == currentChainId) {
                // If the Pool is on this same chain, directly call the proper functions on this chain no CCIP
                address marketAddress = poolToCurrentPositionMarket[
                    _poolAddress
                ];
                IPoolControl(_poolAddress).pivotCompleted(
                    marketAddress,
                    bridgeNonce[_poolAddress],
                    amount
                );
            } else {
                // If the Pool is on a different chain, use CCIP to notify the pool
                sendPivotCompleted(_poolAddress, amount);
            }
        } else {
            // If the target pivot is on another chain, needs to besent through Across bridge
            crossChainPivot(
                _poolAddress,
                protocolHash,
                targetMarketAddress,
                targetMarketId,
                destinationChainId,
                destinationBridgeReceiver,
                amount
            );
        }
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
        //IMPORTANT - ORDERED LZ MESSAGING IRRELEVANT TO THIS ISSUE, AS IT IS AB-BA. The issue is when AB state is read before the BA sequence of another tx is executed
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

        (
            bytes32 withdrawId,
            uint256 amount,
            uint256 poolNonce,
            uint256 scaledRatio
        ) = abi.decode(_data, (bytes32, uint256, uint256, uint256));

        bytes32 protocolHash = poolToCurrentProtocolHash[_poolAddress];
        address marketAddress = poolToCurrentPositionMarket[_poolAddress];
        uint256 currentPositionValue = IIntegrator(integratorAddress)
            .getCurrentPosition(
                _poolAddress,
                poolToAsset[_poolAddress],
                marketAddress,
                protocolHash
            );

        uint256 userMaxWithdraw = getUserMaxWithdraw(
            currentPositionValue,
            scaledRatio,
            _poolAddress,
            poolNonce
        );

        require(
            userMaxWithdraw <= currentPositionValue,
            "Withdraw Amount Too High"
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
        address acrossSpokePool = registry.chainIdToSpokePoolAddress(0);
        require(acrossSpokePool != address(0), "Spokepool zero address");

        bytes4 method = bytes4(
            keccak256(abi.encode("BaBridgeWithdrawOrderUser"))
        );

        integratorWithdraw(_poolAddress, _amount);

        uint256 positionBalance = IIntegrator(integratorAddress)
            .getCurrentPosition(
                _poolAddress,
                poolToAsset[_poolAddress],
                poolToCurrentPositionMarket[_poolAddress],
                poolToCurrentProtocolHash[_poolAddress]
            );
        setBalanceAtNonce(_poolAddress, positionBalance);

        bytes memory message = abi.encode(
            method,
            _poolAddress,
            abi.encode(_withdrawId, _userMaxWithdraw, positionBalance, _amount)
        );

        if (managerChainId == registry.currentChainId()) {
            ERC20(poolToAsset[_poolAddress]).transfer(_poolAddress, _amount);
            IPoolControl(_poolAddress).finalizeWithdrawOrder(
                _withdrawId,
                _amount,
                _userMaxWithdraw,
                positionBalance,
                _amount
            );
        } else {
            emit AcrossMessageSent(message);
            ERC20(poolToAsset[_poolAddress]).approve(acrossSpokePool, _amount);
            try
                ISpokePool(acrossSpokePool).depositV3(
                    address(this),
                    _poolAddress,
                    poolToAsset[_poolAddress],
                    address(0),
                    _amount,
                    _amount - (_amount / 250),
                    managerChainId,
                    address(0),
                    uint32(block.timestamp),
                    uint32(block.timestamp + 30000),
                    0,
                    message
                )
            {
                emit ExecutionMessage("Successful Spokepool Deposit");
            } catch Error(string memory reason) {
                // IMPORTANT - Fund rescue logic
                emit ExecutionMessage(
                    string(abi.encode("Failed Spokepool Deposit: ", reason))
                );
            }
        }
    }

    function poolClosure() internal {
        //After disabling the pool, send all funds back to pool contract
        // Calls the spokePool deposit function to send all funds
        // ISpokePool(acrossSpokePool).deposit(
        //     bridgedConnector,
        //     assetAddress,
        //     amount,
        //     currentPositionChain,
        //     relayFeePct,
        //     uint32(block.timestamp),
        //     message,
        //     (2 ** 256 - 1)
        // );
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

        ERC20(poolToAsset[_poolAddress]).transfer(integratorAddress, _amount);

        // call the current market's deposit method
        IIntegrator(integratorAddress).routeExternalProtocolInteraction(
            protocolHash,
            operation,
            _amount,
            _poolAddress,
            poolToAsset[_poolAddress],
            marketAddress
        );

        uint256 updatedPositionBalance = IIntegrator(integratorAddress)
            .getCurrentPosition(
                _poolAddress,
                poolToAsset[_poolAddress],
                marketAddress,
                protocolHash
            );

        setBalanceAtNonce(_poolAddress, updatedPositionBalance);
    }

    function integratorWithdraw(
        address _poolAddress,
        uint256 _amount
    ) internal {
        IIntegrator(integratorAddress).routeExternalProtocolInteraction(
            poolToCurrentProtocolHash[_poolAddress],
            keccak256(abi.encode("withdraw")),
            _amount,
            _poolAddress,
            poolToAsset[_poolAddress],
            poolToCurrentPositionMarket[_poolAddress]
        );
    }

    /**
     * @notice Function for saving the value of a pool's position at a given deposit/withdraw nonce
     * @dev This position value nonce system is useful for determining mint/burn ratios of the pool
     * @dev If the current position value on the external protocol includes deposits that have not been minted/burnt on the pool chain, the ratio can be thrown off
     * @param _poolAddress The address of the pool
     * @param _currentPositionValue The value of the position, reflecting all deposits/withdraws that have completed the "A=>B" segment of interaction and interest gained
     */
    function setBalanceAtNonce(
        address _poolAddress,
        uint256 _currentPositionValue
    ) internal {
        uint256 nonce = bridgeNonce[_poolAddress];
        bytes32 currentNonceHash = keccak256(
            abi.encode(_poolAddress, nonce + 1)
        );
        bridgeNonce[_poolAddress] = nonce + 1;
        nonceToPositionValue[currentNonceHash] = _currentPositionValue;
    }

    function getMarketAddressFromId(
        string memory marketId,
        bytes32 protocolHash
    ) internal view returns (address) {
        // IMPORTANT - CHANGE TO READ FROM INTEGRATIONS CONTRACT
        return address(bytes20(keccak256(abi.encode(marketId, protocolHash))));
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
        if (
            poolToAsset[_poolAddress] == address(0) ||
            poolToCurrentProtocolHash[_poolAddress] == keccak256(abi.encode(""))
        ) {
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

    /**
     * @notice Function for getting the maximum amount of funds a user can withdraw from a pool's position, denominated in the pool's asset
     * @dev This function uses the balances of the position at given nonces in order to prevent ratio miscalculations due to interchain messaging delays
     * @dev The nonce system enforces that the user max withdraw is calculated with the same total position value as existed when the provided pool ratio was calculated
     * @param _currentPositionValue The value of the position, reflecting all deposits/withdraws that have completed the "A=>B" segment of interaction and interest gained
     * @param _scaledRatio The ratio provided by the pool giving the proportion (user pool token balance / pool token total supply), scaled by 10**18
     * @param _poolAddress The address of the pool
     * @param _poolNonce The nonce passed from the pool contract, which is incremented for each deposit/withdraw that has successfully minted/burned pool tokens
     * @return The amount of funds that a user my withdraw at a given time, based off of their pool token counts
     */
    function getUserMaxWithdraw(
        uint256 _currentPositionValue,
        uint256 _scaledRatio,
        address _poolAddress,
        uint256 _poolNonce
    ) public view returns (uint256) {
        // positionValue should just be positionValueAtNonce, leaving out any interest made since the withdraw request on pool chain (10 minute window of request, interest is negligible)
        // Also saves error from trying to calculate difference for interest gained in between pool chain request and bridge chain fulfillment
        // IN OTHER WORDS: The currentPositionValue would reflect depos/with that have not completed BA sequence

        // uint256 difference = 0;
        // uint256 calculatedPositionValue = _currentPositionValue; //799600255908568n

        // bytes32 currentPendingNonceHash = keccak256(
        //     abi.encode(_poolAddress, bridgeNonce[_poolAddress])
        // );

        // uint256 positionValueAtPendingNonce = nonceToPositionValue[    // Assume 799600255908568n
        //     currentPendingNonceHash
        // ];

        if (_scaledRatio == 100000000000000000) {
            return _currentPositionValue;
        }

        bytes32 poolCompletedNonceHash = keccak256(
            abi.encode(_poolAddress, _poolNonce)
        );

        uint256 positionValueAtPoolRatio = nonceToPositionValue[
            poolCompletedNonceHash
        ];

        require(
            positionValueAtPoolRatio > 0,
            "Position value for calculating max withdraw cannot be 0"
        );

        // if (positionValueAtPendingNonce >= positionValueAtPoolRatio) {    // positionValueAtPendingNonce =  799600255908568n, positionValueAtPoolRatio = 0
        //     difference = positionValueAtPendingNonce - positionValueAtPoolRatio; //0
        //     calculatedPositionValue = _currentPositionValue - difference;  //Somehow difference is equal to currentPositionValue AND posValPending >= posValPoolRa
        // } else {
        //     difference = positionValueAtPoolRatio - positionValueAtPendingNonce;
        //     calculatedPositionValue = _currentPositionValue + difference;
        // }

        // TotalAssetAvailableToUser = ratio * (valueAtPoolRatio + (currentPositionValue - positionValueAtLastDepoOrWith))
        uint256 userMaxWithdraw = (_scaledRatio * positionValueAtPoolRatio) / //If error with positionValueAtPendingNonce, this would be double than usual
            (10 ** 18);

        return userMaxWithdraw;
    }
}
