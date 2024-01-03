// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {ChaserRouter} from "./ChaserRouter.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BridgedConnector {
    //IMPORTANT - HOW TO HANDLE TWO POOLS DEPOSITING INTO THE SAME MARKET? When deposit into external protocol's market is made, read the a/c token amount and save in poolAddr => uint mapping
    uint256 managerChainId;

    IChaserRegistry public registry;
    ChaserRouter public chaserRouter;

    mapping(address => address) poolToCurrentPositionMarket;
    mapping(address => address) poolToAsset;
    mapping(bytes32 => uint256) userDepositNonce;
    mapping(bytes32 => uint256) userCumulativeDeposits;
    mapping(bytes32 => uint256) nonceToPositionValue; // key is hash of bytes of pool address and nonce
    mapping(address => uint256) connectorNonce; // pool address to the current nonce of all withdraws/deposits reflected in the position balance

    event PositionBalanceSent(uint256, address);
    event AcrossMessageSent(bytes);
    event LzMessageSent(bytes4, bytes);
    event Numbers(uint256, uint256);

    constructor(uint256 _managerChainId) {
        registry = IChaserRegistry(msg.sender);
        managerChainId = _managerChainId;
        chaserRouter = new ChaserRouter(
            address(0x464570adA09869d8741132183721B4f0769a0287),
            msg.sender
        ); // IMPORTANT - first arg should be the endpoint address
    }

    /**
     * @notice Handles methods called from another chain through LZ. Router contract receives the message and calls pool methods through this function
     * @param _method The name of the method that was called from the other chain
     * @param _data The data to be calculated upon in the method
     */
    function receiveHandler(bytes4 _method, bytes memory _data) external {
        if (_method == bytes4(keccak256(abi.encode("exitPivot")))) {
            // This function is to withdraw from current position and pivot to another investment market/chain
            // What data do we need to execute pool pivots?
            // - This contract already maintains state about the current pool
            // - Needs message with data from pool about the target position
            // - Data includes -Pool id that will be pivoting position,-Destination protocol, chain, pool-If any funds/data needs to be sent back to pool control
            // - exitPivot: bytes32 destinationProtocol, bytes20 destinationMarket, uint256 destinationChainId
            //Send funds and outward across message to next position
        }

        if (_method == bytes4(keccak256(abi.encode("userWithdrawOrder")))) {
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
            // The ratio to get maxAssetToWithdraw (x) is as follows: x/(currentPositionValue - (nonceToPositionValue[connectorNonce] - nonceToPositionValue[poolNonce])) = userPoolTokenBalance/poolTokenSupply
            // IMPORTANT - DOES THIS RATIO WORK IF THERE IS A PIVOT TO ANOTHER CONNECTOR, THEN BACK TO THIS ONE

            (
                bytes32 withdrawId,
                address poolAddress,
                uint256 amount,
                uint256 poolNonce,
                uint256 scaledRatio
            ) = abi.decode(
                    _data,
                    (bytes32, address, uint256, uint256, uint256)
                );

            address assetAddress = poolToAsset[poolAddress];

            uint256 currentPositionValue = getPositionBalance(poolAddress);

            uint256 userMaxWithdraw = getUserMaxWithdraw(
                currentPositionValue,
                scaledRatio,
                poolAddress,
                poolNonce
            );

            // IMPORTANT - IF amountToWithdraw IS VERY CLOSE TO userMaxWithdraw, MAKE amountToWithdraw = userMaxWithdraw

            uint256 amountToWithdraw = amount;
            if (userMaxWithdraw < amount) {
                amountToWithdraw = userMaxWithdraw;
            }

            userWithdraw(
                amountToWithdraw,
                userMaxWithdraw,
                poolAddress,
                withdrawId
            );
        }

        if (_method == bytes4(keccak256(abi.encode("readPositionBalance")))) {
            // Checks the external protocol that is currently holding the assets of the pool making the request
            // Reads from this contract's state as to the proportion of assets that pertain to the pool
            // Send this value through sendPositionBalance()
            address poolAddress = abi.decode(_data, (address));
            sendPositionBalance(poolAddress, bytes32(""));
        }

        if (_method == bytes4(keccak256(abi.encode("readPositionData")))) {
            //Reads data to be sent back to pool
        }

        if (_method == bytes4(keccak256(abi.encode("readRegistryAddress")))) {
            //Reads address from the regitry to be sent back to pool
        }
    }

    /**
     * @notice Standard Across Message reception
     * @dev This function separates messages by method and executes the different logic for each based off of the first 4 bytes of the message
     */
    function handleAcrossMessage(
        address tokenSent,
        uint256 amount,
        bool fillCompleted,
        address relayer,
        bytes memory message
    ) public {
        (bytes4 method, address poolAddress, bytes memory data) = abi.decode(
            message,
            (bytes4, address, bytes)
        );

        if (tokenSent == poolToAsset[poolAddress]) {
            // IMPORTANT - HANDLE ERROR FOR WRONG ASSET BRIDGED, UNLESS METHOD IS "positionInitializer"
        }

        emit LzMessageSent(method, data);

        if (method == bytes4(keccak256(abi.encode("enterPivot")))) {
            // - enterPivot: bytes32 destinationProtocol, bytes20 destinationMarket
            //What data do we need to execute pool pivots?
            // -Pool id that will be pivoting position
            // -Destination protocol, chain, pool
        }

        if (method == bytes4(keccak256(abi.encode("userDeposit")))) {
            (bytes32 depositId, address userAddress) = abi.decode(
                data,
                (bytes32, address)
            );

            receiveDepositFromPool(amount, depositId, poolAddress, userAddress);
        }

        if (method == bytes4(keccak256(abi.encode("positionInitializer")))) {
            // Make initial deposit and set the current position
            (
                bytes32 depositId,
                address userAddress,
                address pivotAddress,
                bytes32 pivotProtocolHash
            ) = abi.decode(data, (bytes32, address, address, bytes32));

            // IMPORTANT - DOES THIS ONLY GET INITIALIZED ON THE POOLS FIRST POSITION?
            bytes32 currentNonceHash = keccak256(abi.encode(poolAddress, 0));
            connectorNonce[poolAddress] = 0;
            nonceToPositionValue[currentNonceHash] = 0;

            // IMPORTANT - SET THE PIVOT HERE BEFORE THE DEPOSIT IS RECEIVED AND TRANSFERED
            poolToCurrentPositionMarket[poolAddress] = pivotAddress;
            poolToAsset[poolAddress] = tokenSent;

            receiveDepositFromPool(amount, depositId, poolAddress, userAddress);
        }
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
    ) external view returns (uint256) {
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
        bytes32 _depositId
    ) internal {
        uint256 positionAmount = getPositionBalance(_poolAddress);
        address currentPositionMarket = poolToCurrentPositionMarket[
            _poolAddress
        ];

        bytes4 method = bytes4(
            keccak256(abi.encode("readPositionBalanceResult"))
        );
        bytes memory data = abi.encode(positionAmount, _depositId);

        bytes memory options;

        emit PositionBalanceSent(positionAmount, _poolAddress);
        emit LzMessageSent(method, data);

        chaserRouter.send(
            managerChainId,
            method,
            true,
            address(this),
            data,
            options
        );
    }

    /**
     * @notice Send position data of a pool back to the pool contract
     */
    function sendPositionData() internal {
        // Uses lzSend to send position data requested by pool
        bytes memory data;
        bytes memory options;

        chaserRouter.send(
            managerChainId,
            bytes4(keccak256(abi.encode("sendPositionData"))),
            true,
            address(this),
            data,
            options
        );
    }

    /**
     * @notice Send an address back to the pool contract
     */
    function sendRegistryAddress() internal {
        bytes memory data;
        bytes memory options;

        chaserRouter.send(
            managerChainId,
            bytes4(keccak256(abi.encode("sendRegistryAddress"))),
            true,
            address(this),
            data,
            options
        );
    }

    function exitPivot() internal {
        //Current position has been withdrawn and sitting in this connector
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
        uint256 currentChainId = registry.currentChainId();
        address acrossSpokePool = registry.chainIdToSpokePoolAddress(
            currentChainId
        );

        bytes4 method = bytes4(keccak256(abi.encode("userWithdrawOrder")));
        bytes memory data = abi.encode(_withdrawId, _userMaxWithdraw);
        bytes memory message = abi.encode(method, data);

        emit AcrossMessageSent(message);

        address assetAddress = poolToAsset[_poolAddress];

        address currentMarket = poolToCurrentPositionMarket[_poolAddress];

        uint256 updatedPositionBalance = getPositionBalance(_poolAddress) -
            _amount; //Position balance AFTER the withdraw

        setBalanceAtNonce(_poolAddress, updatedPositionBalance);

        // IMPORTANT - CALL POSITION MARKET AND MAKE THE WITHDRAW

        ERC20(assetAddress).transfer(_poolAddress, _amount); //IMPORTANT - JUST TESTING, REMOVE WHEN POSITION INTEGRATION

        ERC20(assetAddress).approve(acrossSpokePool, _amount);

        // ISpokePool(acrossSpokePool).deposit(
        //     _poolAddress,
        //     assetAddress,
        //     _amount,
        //     currentPositionChain,
        //     relayFeePct,
        //     uint32(block.timestamp),
        //     message,
        //     (2 ** 256 - 1)
        // );
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
     * @param _depositId The deposit ID used for creating the message to send to the pool for minting pool tokens
     * @param _poolAddress The address of the pool that the deposit pertains to
     * @param _userAddress The address of the depositing user
     */
    function receiveDepositFromPool(
        uint256 _amount,
        bytes32 _depositId,
        address _poolAddress,
        address _userAddress
    ) internal {
        bytes32 userPoolHash = keccak256(
            abi.encode(_userAddress, _poolAddress)
        );
        userDepositNonce[userPoolHash] += 1;
        userCumulativeDeposits[userPoolHash] += _amount;

        // approve amount to current market

        ERC20(poolToAsset[_poolAddress]).approve(
            poolToCurrentPositionMarket[_poolAddress],
            _amount
        );

        // call the current market's deposit method
        uint256 updatedPositionBalance = getPositionBalance(_poolAddress);

        setBalanceAtNonce(_poolAddress, updatedPositionBalance);
        sendPositionBalance(_poolAddress, _depositId);
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
        uint256 nonce = connectorNonce[_poolAddress];
        bytes32 currentNonceHash = keccak256(
            abi.encode(_poolAddress, nonce + 1)
        );
        connectorNonce[_poolAddress] = nonce + 1;
        nonceToPositionValue[currentNonceHash] = _currentPositionValue;
    }

    /**
     * @notice Function for reading the value of a pool's current position on an external protocol
     * @dev This functions links into other protocol's contracts for reading the true current value
     * @param _poolAddress The address of the pool
     * @return The value of a pool's position including interest gained
     */
    function getPositionBalance(
        address _poolAddress
    ) internal view returns (uint256) {
        address positionMarket = poolToCurrentPositionMarket[_poolAddress];
        address asset = poolToAsset[_poolAddress];

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
    ) internal view returns (uint256) {
        uint256 difference = 0;
        uint256 calculatedPositionValue = _currentPositionValue;

        bytes32 currentPendingNonceHash = keccak256(
            abi.encode(_poolAddress, connectorNonce[_poolAddress])
        );

        uint256 positionValueAtPendingNonce = nonceToPositionValue[
            currentPendingNonceHash
        ];

        bytes32 poolCompletedNonceHash = keccak256(
            abi.encode(_poolAddress, _poolNonce)
        );

        uint256 positionValueAtPoolRatio = nonceToPositionValue[
            poolCompletedNonceHash
        ];

        if (positionValueAtPendingNonce >= positionValueAtPoolRatio) {
            difference = positionValueAtPendingNonce - positionValueAtPoolRatio;
            calculatedPositionValue = _currentPositionValue - difference;
        } else {
            difference = positionValueAtPoolRatio - positionValueAtPendingNonce;
            calculatedPositionValue = _currentPositionValue + difference;
        }

        uint256 userMaxWithdraw = (_scaledRatio * calculatedPositionValue) /
            (10 ** 18);

        return userMaxWithdraw;
    }
}
