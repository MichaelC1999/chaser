// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {IChaserMessenger} from "./interfaces/IChaserMessenger.sol";
import {ISpokePool} from "./interfaces/ISpokePool.sol";

import {BridgeReceiver} from "./BridgeReceiver.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BridgeLogic {
    //IMPORTANT - HOW TO HANDLE TWO POOLS DEPOSITING INTO THE SAME MARKET? When deposit into external protocol's market is made, read the a/c token amount and save in poolAddr => uint mapping
    uint256 managerChainId;

    IChaserRegistry public registry;
    IChaserMessenger public messenger;

    address public bridgeReceiverAddress;

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
        address _bridgeReceiverAddress
    ) external {
        messenger = IChaserMessenger(_messengerAddress);
        bridgeReceiverAddress = _bridgeReceiverAddress;
    }

    function handlePositionInitializer(
        uint256 amount,
        address poolAddress,
        address tokenSent,
        bytes32 depositId,
        address userAddress,
        string memory marketId,
        bytes32 protocolHash
    ) external {
        // IMPORTANT - DOES THIS ONLY GET INITIALIZED ON THE POOLS FIRST POSITION?
        bytes32 currentNonceHash = keccak256(abi.encode(poolAddress, 0));
        bridgeNonce[poolAddress] = 0;
        nonceToPositionValue[currentNonceHash] = 0;
        // IMPORTANT - SET THE PIVOT HERE BEFORE THE DEPOSIT IS RECEIVED AND TRANSFERED
        address pivotAddress = getMarketAddressFromId(marketId, protocolHash);
        poolToCurrentPositionMarket[poolAddress] = pivotAddress;
        poolToAsset[poolAddress] = tokenSent;

        enterPosition(poolAddress, protocolHash, marketId, amount);
        bytes32 userPoolHash = keccak256(abi.encode(userAddress, poolAddress));
        userDepositNonce[userPoolHash] += 1;
        userCumulativeDeposits[userPoolHash] += amount;
        receiveDepositFromPool(amount, poolAddress);
        sendPositionInitialized(poolAddress, depositId, amount);
    }

    function handleEnterPivot(
        address tokenSent,
        uint256 amount,
        address poolAddress,
        bytes32 protocolHash,
        string memory targetMarketId,
        uint256 poolNonce
    ) external {
        poolToAsset[poolAddress] = tokenSent;

        bytes32 currentNonceHash = keccak256(
            abi.encode(poolAddress, poolNonce)
        );
        bridgeNonce[poolAddress] = poolNonce;
        nonceToPositionValue[currentNonceHash] = amount;
        enterPosition(poolAddress, protocolHash, targetMarketId, amount);
        receiveDepositFromPool(amount, poolAddress);
        sendPivotCompleted(poolAddress, amount);
    }

    function handleUserDeposit(
        address poolAddress,
        address userAddress,
        bytes32 depositId,
        uint256 amount
    ) external {
        bytes32 userPoolHash = keccak256(abi.encode(userAddress, poolAddress));
        userDepositNonce[userPoolHash] += 1;
        userCumulativeDeposits[userPoolHash] += amount;

        receiveDepositFromPool(amount, poolAddress);
        sendPositionBalance(poolAddress, depositId, amount);
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

    /**
     * @notice Send the current position value of a pool back to the pool contract
     * @dev This is the "B=>A" segment of the "A=>B=>A" sequence for reading the current position value across chains
     * @param _poolAddress The address of the pool
     * @param _depositId If called as part of a deposit with the purpose of minting pool tokens, the deposit ID is passed here. It is optional, for falsey use bytes32 zero value
     */
    function sendPositionBalance(
        address _poolAddress,
        bytes32 _depositId,
        uint256 _amount
    ) public {
        uint256 positionAmount = getPositionBalance(_poolAddress);

        bytes4 method = bytes4(
            keccak256(abi.encode("BaMessagePositionBalance"))
        );

        bytes memory data = abi.encode(positionAmount, _amount, _depositId);

        emit PositionBalanceSent(positionAmount, _poolAddress, _depositId);
        emit LzMessageSent(method, data);

        try registry.sendMessage(managerChainId, method, _poolAddress, data) {
            emit ExecutionMessage("sendMessage success");
        } catch Error(string memory reason) {
            emit ExecutionMessage(
                string(abi.encodePacked("BridgeLogic: ", reason))
            );
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
    ) public {
        uint256 positionAmount = getPositionBalance(_poolAddress);
        address currentPositionMarket = poolToCurrentPositionMarket[
            _poolAddress
        ];

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
        emit LzMessageSent(method, data);

        try registry.sendMessage(managerChainId, method, _poolAddress, data) {
            emit ExecutionMessage("sendMessage success");
        } catch Error(string memory reason) {
            emit ExecutionMessage(
                string(abi.encodePacked("BridgeLogic: ", reason))
            );
        }
    }

    /**
     * @notice Send position data of a pool back to the pool contract
     */
    function sendPositionData(address _poolAddress) public {
        require(
            msg.sender == address(this) || msg.sender == address(messenger),
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
        bytes memory data = abi.encode(marketAddress, _amount);

        emit LzMessageSent(method, data);

        try registry.sendMessage(managerChainId, method, _poolAddress, data) {
            emit ExecutionMessage("sendMessage success");
        } catch Error(string memory reason) {
            emit ExecutionMessage(
                string(abi.encodePacked("BridgeLogic: ", reason))
            );
        }
    }

    function enterPosition(
        address poolAddress,
        bytes32 protocolHash,
        string memory targetMarketId,
        uint256 amount
    ) internal {
        poolToCurrentMarketId[poolAddress] = targetMarketId;
        poolToCurrentPositionMarket[poolAddress] = getMarketAddressFromId(
            targetMarketId,
            protocolHash
        );
        poolToCurrentProtocolHash[poolAddress] = protocolHash;
        positionEntranceAmount[poolAddress] = amount;
        // Approve this address for amount
        // Call the deposit function
    }

    function crossChainPivot(
        address poolAddress,
        bytes32 protocolHash,
        string memory targetMarketId,
        uint256 destinationChainId,
        address destinationBridgeReceiver,
        uint256 _amount
    ) internal {
        //IMPORTANT - SHOULD NONCE BE SENT TO THE OTHER CONNECTOR?
        // --Yes, pool nonce should be maintained equally between different chains

        bytes4 method = bytes4(
            keccak256(abi.encode("BbPivotBridgeMovePosition"))
        );

        bytes memory data = abi.encode(
            protocolHash,
            targetMarketId,
            bridgeNonce[poolAddress]
        );

        bytes memory message = abi.encode(method, poolAddress, data);

        emit AcrossMessageSent(message);

        uint256 currentChainId = registry.currentChainId();
        emit Numbers(currentChainId, destinationChainId);

        address acrossSpokePool = registry.chainIdToSpokePoolAddress(0);

        ERC20(poolToAsset[poolAddress]).approve(acrossSpokePool, _amount);

        // UPDATEV3

        //         try ISpokePool(acrossSpokePool).depositV3(
        //     address(this),
        //     destinationBridgeReceiver,
        //     poolToAsset[poolAddress],
        //     address(0),
        //     _amount,
        // (_amount / 5) * 4, // IMPORTANT - SEEK ORACLE SOLUTION TO BRING API FEE CALC ON CHAIN
        //     destinationChainId,
        //     address(0),
        //     uint32(block.timestamp),
        //     uint32(block.timestamp) * 2,
        //     0,
        //     message
        // )

        // ISpokePool(acrossSpokePool).deposit(
        //     destinationBridgeReceiver,
        //     poolToAsset[poolAddress],
        //     amount,
        //     destinationChainId,
        //     relayFeePct,
        //     uint32(block.timestamp),
        //     message,
        //     (2 ** 256 - 1)
        // );
    }

    function executeExitPivot(address _poolAddress, bytes memory _data) public {
        // Withdraw from current position here, bringing funds back to this contract and updating state
        (
            uint256 poolNonce,
            bytes32 protocolHash,
            string memory targetMarketId,
            uint256 destinationChainId,
            address destinationBridgeReceiver
        ) = abi.decode(_data, (uint256, bytes32, string, uint256, address));

        uint256 amount = getPositionBalance(_poolAddress);

        if (registry.currentChainId() == destinationChainId) {
            enterPosition(_poolAddress, protocolHash, targetMarketId, amount);
        } else {
            crossChainPivot(
                _poolAddress,
                protocolHash,
                targetMarketId,
                destinationChainId,
                destinationBridgeReceiver,
                amount
            );
        }
        // This function is to withdraw from current position and pivot to another investment market/chain
        // What data do we need to execute pool pivots?
        // - This contract already maintains state about the current pool
        // - Needs message with data from pool about the target position
        // - Data includes -Pool id that will be pivoting position,-Destination protocol, chain, pool-If any funds/data needs to be sent back to pool control
        // - exitPivot: bytes32 destinationProtocol, bytes20 destinationMarket, uint256 destinationChainId
        //Send funds and outward across message to next position
    }

    function userWithdrawSequence(
        address _poolAddress,
        bytes memory _data
    ) external {
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

        address assetAddress = poolToAsset[_poolAddress];

        uint256 currentPositionValue = getPositionBalance(_poolAddress);

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

        // IMPORTANT - IF amountToWithdraw IS VERY CLOSE TO userMaxWithdraw, MAKE amountToWithdraw = userMaxWithdraw

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
        // Calls the spokePool deposit function to send user deposit funds
        address acrossSpokePool = registry.chainIdToSpokePoolAddress(0);
        require(acrossSpokePool != address(0), "Spokepool zero address");

        bytes4 method = bytes4(
            keccak256(abi.encode("BaBridgeWithdrawOrderUser"))
        );
        bytes memory message = abi.encode(
            method,
            _poolAddress,
            abi.encode(_withdrawId, _userMaxWithdraw)
        );

        emit AcrossMessageSent(message);

        // address currentMarket = poolToCurrentPositionMarket[_poolAddress];

        setBalanceAtNonce(
            _poolAddress,
            getPositionBalance(_poolAddress) - _amount
        );
        //UPDATEV3 - EXPLORE REDUNDANT TRANSFERS WHERE depositV3 CAN SET THE SENDER, RATHER THAN NEEDING TO TRANSFER TO THIS CONTRACT?
        // IMPORTANT - CALL POSITION MARKET AND MAKE THE WITHDRAW

        try ERC20(poolToAsset[_poolAddress]).approve(acrossSpokePool, _amount) {
            emit ExecutionMessage("Successful Approval");
        } catch Error(string memory reason) {
            emit ExecutionMessage(
                string(abi.encode("Asset ERC20 Approval Error ", reason))
            );
        }

        // UPDATEV3

        // try
        //     ISpokePool(acrossSpokePool).deposit(
        //         _poolAddress,
        //         assetAddress,
        //         _amount,
        //         managerChainId,
        //         200000000000000000, // IMPORTANT - FIGURE OUT BEST WAY TO DETERMINE RELAYFEE IN BA BRIDGING
        //         uint32(block.timestamp),
        //         message,
        //         (2 ** 256 - 1)
        //     )
        try
            ISpokePool(acrossSpokePool).depositV3(
                address(this),
                _poolAddress,
                poolToAsset[_poolAddress],
                address(0),
                _amount,
                (_amount / 5) * 4, // IMPORTANT - SEEK ORACLE SOLUTION TO BRING API FEE CALC ON CHAIN
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
            emit ExecutionMessage(
                string(abi.encode("Failed Spokepool Deposit: ", reason))
            );
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
     * @notice Process a deposit made by a user
     * @dev This is the "B=>A" segment of the "A=>B=>A" sequence for deposits. This sends data to the pool about the proportion of the pool's position that this deposit makes.
     * @dev Data sent here through LZ determines ratio to mint pool tokens on the pool's chain
     * @param _amount The amount deposited into the pool, denominated in the pool's asset
     * @param _poolAddress The address of the pool that the deposit pertains to
     */
    function receiveDepositFromPool(
        uint256 _amount,
        address _poolAddress
    ) public {
        // approve amount to current market

        // ERC20(poolToAsset[_poolAddress]).approve(
        //     poolToCurrentPositionMarket[_poolAddress],
        //     _amount
        // ); //IMPORTANT - UNCOMMENT

        // ERC20(poolToAsset[_poolAddress]).transfer(
        //     address(0x1CA2b10c61D0d92f2096209385c6cB33E3691b5E),
        //     _amount
        // ); //REMOVE - TESTING

        // call the current market's deposit method
        // IIntegrations(integratorAddress).routeExternalProtocolInteraction(bytes32 protocolHash, bytes32 operation)

        uint256 updatedPositionBalance = getPositionBalance(_poolAddress);

        setBalanceAtNonce(_poolAddress, updatedPositionBalance);
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
        address positionMarket = poolToCurrentPositionMarket[_poolAddress];
        address asset = poolToAsset[_poolAddress];

        require(asset != address(0), "Invalid Asset Address");

        // IMPORTANT - TEMPORARY LOGIC, SHOULD LINK UP WITH EXTERNAL PROTOCOL FOR READING THE POSITION BALANCE
        return ERC20(asset).balanceOf(address(this));
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

        // uint256 difference = 0;
        // uint256 calculatedPositionValue = _currentPositionValue; //799600255908568n

        // bytes32 currentPendingNonceHash = keccak256(
        //     abi.encode(_poolAddress, bridgeNonce[_poolAddress])
        // );

        // uint256 positionValueAtPendingNonce = nonceToPositionValue[    // Assume 799600255908568n
        //     currentPendingNonceHash
        // ];

        bytes32 poolCompletedNonceHash = keccak256(
            abi.encode(_poolAddress, _poolNonce)
        );

        uint256 positionValueAtPoolRatio = nonceToPositionValue[ // 799600255908568n
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
        //     difference = positionValueAtPoolRatio - positionValueAtPendingNonce; //799600255908568n
        //     calculatedPositionValue = _currentPositionValue + difference;
        // }

        // TotalAssetAvailableToUser = ratio * (valueAtPoolRatio + (currentPositionValue - positionValueAtLastDepoOrWith))
        uint256 userMaxWithdraw = (_scaledRatio * positionValueAtPoolRatio) / //If error with positionValueAtPendingNonce, this would be double than usual
            (10 ** 18);

        return userMaxWithdraw;
    }
}
