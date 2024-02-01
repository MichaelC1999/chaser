// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./PoolToken.sol";
import {ISpokePool} from "./interfaces/ISpokePool.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {IChaserManager} from "./ChaserManager.sol";
import {IBridgeLogic} from "./interfaces/IBridgeLogic.sol";
import {IPoolCalculations} from "./interfaces/IPoolCalculations.sol";
import {IPoolToken} from "./interfaces/IPoolToken.sol";
import {IArbitrationContract} from "./interfaces/IArbitrationContract.sol";

contract PoolControl {
    uint256 localChain;
    bytes32 poolId;
    address deployingUser;
    address public poolToken;
    uint256 public poolNonce = 0;
    string public poolName;
    string public strategySource; // STRATEGY SOURCE CAN BE A REPO URL WITH CODE TO EXECUTE, OR THIS STRING COULD POINT TO AN ADDRESS/CHAIN/METHOD THAT RETURNS THE INSTRUCTIONS
    bool pivotPending = false;

    IBridgeLogic public localBridgeLogic;
    IChaserManager public manager;
    IChaserRegistry public registry;
    IPoolCalculations public poolCalculations;
    IArbitrationContract public arbitrationContract;
    IERC20 public asset;

    event AcrossMessageSent(bytes);
    event LzMessageSent(bytes4, bytes);
    event Numbers(uint256, uint256);
    event PivotCompleted(string, address, bytes32, uint256);

    mapping(address => bool) userHasPendingWithdraw;

    // POSITION STATE
    //State contains position target, current position location and last position location (for failed bridge handling)
    // target state is for holding the position to pivot to. This facilitates the new position to enter

    string public targetPositionMarketId; //THE MARKET ADDRESS THAT WILL BE PASSED TO BRIDGECONNECTION, NOT THE FINAL ADDRESS THAT FUNDS ARE ACTUALLY HELD IN
    uint256 public targetPositionChain;
    bytes32 public targetPositionProtocolHash;

    // current state holds the position that funds are currently deposited into. This facilitates withdraws. Current state gets set as chaser + address(this) when the bridge request to withdraw has been sent
    address public currentPositionAddress;
    string public currentPositionMarketId;
    uint256 public currentPositionChain; //IMPORTANT - CURRENT HARDCODED BEFORE PIVOT FUNCTIONALITY
    bytes32 public currentPositionProtocolHash;
    uint256 public currentRecordPositionValue; //This holds the most recently recorded value of the entire position sent from the current position chain.

    // last state holds the previous position data. In the case of error while bridging, this is to rescue funds
    address public lastPositionAddress;
    uint256 public lastPositionChain;
    bytes32 public lastPositionProtocolHash;

    /**
     * @notice Initial pool configurations and address caching
     * @param _deployingUser The address that called the pool deployment from the manager contract
     * @param _asset The asset that is being invested in this pool
     * @param _strategySource The source of the strategy for determining investment
     * @param _poolName The name of the pool
     * @param _localChain The integer Chain ID of this pool
     */
    constructor(
        address _deployingUser,
        address _asset,
        string memory _strategySource,
        string memory _poolName,
        uint256 _localChain,
        address _registry,
        address _poolCalculations
    ) {
        localChain = _localChain;
        currentPositionChain = localChain;
        poolId = keccak256(abi.encode(address(this), _poolName));
        poolName = _poolName;
        deployingUser = _deployingUser;
        asset = IERC20(_asset);
        strategySource = _strategySource;
        // manager = IChaserManager(address(msg.sender));
        registry = IChaserRegistry(_registry);
        poolCalculations = IPoolCalculations(_poolCalculations);
        localBridgeLogic = IBridgeLogic(registry.bridgeLogicAddress());
        arbitrationContract = IArbitrationContract(
            registry.arbitrationContract()
        );
    }

    function externalSetup() external {}

    function readPositionBalanceResult(bytes memory _data) external {
        // Decode the payload data
        (uint256 positionAmount, address marketAddress, bytes32 depositId) = abi
            .decode(_data, (uint256, address, bytes32));
        //Receives the current value of the entire position. Sets this to a contract wide state (or mapping with timestamp => uint balance, and save timestamp to contract wide state)

        currentRecordPositionValue = positionAmount;
        if (depositId != bytes32("")) {
            if (poolNonce == 0) {
                pivotCompleted(marketAddress, positionAmount);
            }
            mintUserPoolTokens(depositId, positionAmount);
        }

        //If depositId included in the payload data, mint position tokens for user
        //Check mapping if depositId has minted position tokens yet
    }

    /**
     * @notice The user-facing function for beginning the withdraw sequence
     * @dev This function is the "A" of the "A=>B=>A" sequence of withdraws
     * @dev On this chain we don't have access to the current position value after gains. If the amount specified is over the proportion available with user's pool tokens, withdraw the maximum proportion
     * @param _amount The amount to withdraw, denominated in the pool asset
     */
    function userWithdrawOrder(uint256 _amount) external {
        //IMPORTANT - Since we dont know the actual amount of pool tokens to be burnt from the withdraw, we should lock withdraws from the user until all pending withdraws are completed
        require(
            userHasPendingWithdraw[msg.sender] == false,
            "User may only open new withdraw order if they do not have a pending withdraw order"
        );
        require(
            pivotPending == false,
            "Withdraws are blocked until the Pivot is completed"
        );
        userHasPendingWithdraw[msg.sender] = true;

        bytes memory data = poolCalculations.createWithdrawOrder(
            _amount,
            poolNonce,
            poolToken,
            msg.sender
        );

        bytes memory options;
        bytes4 method = bytes4(
            keccak256(abi.encode("MessageUserWithdrawOrder"))
        );

        emit LzMessageSent(method, data);

        registry.sendMessage(
            80001, //IMPORTANT - CHANGE TO currentPositionChain
            method,
            address(this),
            data
        );
    }

    /**
     * @notice After pivot was successfully asserted, send the execution request for the pivot
     */
    function pivotPosition() external {
        // Send message to BridgeReceiver on new target position chain, with instructions to move funds to new position
        // Uses lzSend to send message with instructions on how to handle pivot

        bytes memory data;
        bytes memory options;

        registry.sendMessage(
            80001, //IMPORTANT - CHANGE TO currentPositionChain
            bytes4(keccak256(abi.encode("pivotPosition"))),
            address(this),
            data
        );
    }

    /**
     * @notice Send a request to the position chain for the up to date value of the position (including any gains)
     */
    function readPositionBalance() external {
        // Get the value of the entire position for the pool with gains
        // Uses lzSend to send message to request this data be sent back
        bytes4 method = bytes4(keccak256("MessageGetPositionBalance"));

        bytes memory data = abi.encode("TEST");

        registry.sendMessage(
            80001, //IMPORTANT - CHANGE TO currentPositionChain
            method,
            address(this),
            data
        );
    }

    /**
     * @notice Send a request to the position chain for arbitrary data about the position
     */
    function getPositionData() external {
        // Uses lzSend to request position data be sent back

        bytes memory data = abi.encode("TEST");

        registry.sendMessage(
            80001, //IMPORTANT - CHANGE TO currentPositionChain
            bytes4(keccak256(abi.encode("getPositionData"))),
            address(this),
            data
        );
    }

    /**
     * @notice Send a request to the position chain to get an address from its' registry
     */
    function getRegistryAddress() external {
        // Uses lzSend to request an address from the registry on another chain
        bytes memory data;
        registry.sendMessage(
            80001, //IMPORTANT - CHANGE TO currentPositionChain
            bytes4(keccak256(abi.encode("getRegistryAddress"))),
            address(this),
            data
        );
    }

    /**
     * @notice Make the first deposit on the pool and set up the first position. This is a function meant to be called from a user/investing entity.
     * @notice This function simultaneously sets the first position and deposits the first funds
     * @notice After executing, other functions are called withdata generated in this function, in order to direction the position entrance
     * @param _amount The amount of the initial deposit
     * @param _relayFeePct The Across Bridge relay fee %
     * @param _targetPositionMarketId The market Id to be processed by Logic/Integrator to derive the market address
     * @param _targetPositionChain The destination chain on which the first position exists
     * @param _targetPositionProtocol The protocol that the position is made on
     */
    function userDepositAndSetPosition(
        uint256 _amount,
        int64 _relayFeePct,
        string memory _targetPositionMarketId,
        uint256 _targetPositionChain,
        string memory _targetPositionProtocol
    ) external {
        // This is for the initial deposit and position set up after pool creation
        require(
            msg.sender == deployingUser,
            "Only deploying user can set position and deposit"
        );
        require(
            poolNonce == 0,
            "The position may only be set before the first deposit has settled"
        );

        // IMPORTANT - Check protocol enabled
        bytes32 _targetPositionProtocolHash = keccak256(
            abi.encode(_targetPositionProtocol)
        );

        targetPositionMarketId = _targetPositionMarketId;
        targetPositionChain = _targetPositionChain;
        targetPositionProtocolHash = _targetPositionProtocolHash;

        bytes32 depositId = poolCalculations.createDepositOrder(
            msg.sender,
            _amount
        );

        // Encode the data including position details
        bytes memory data = abi.encode(
            depositId,
            msg.sender,
            targetPositionMarketId,
            currentPositionProtocolHash
        );

        if (targetPositionChain == localChain) {
            localBridgeLogic.initializePoolPosition(
                address(this),
                address(asset),
                currentPositionProtocolHash,
                _targetPositionMarketId,
                poolNonce,
                _amount
            );
            enterFundsLocalChain(depositId, _amount, msg.sender);
            address marketAddress = localBridgeLogic
                .poolToCurrentPositionMarket(address(this));

            uint256 positionAmount = localBridgeLogic.getPositionBalance(
                address(this)
            );
            pivotCompleted(marketAddress, positionAmount);
        } else {
            bytes4 method = bytes4(
                keccak256(abi.encode("positionInitializer"))
            );
            bytes memory message = abi.encode(method, address(this), data);
            enterFundsCrossChain(
                depositId,
                _amount,
                msg.sender,
                _relayFeePct,
                message
            );
        }
    }

    /**
     * @notice Make a deposit on the pool
     * @dev This function creates the deposit data and routes the function call depending on whether or not the position is local or cross chain
     * @param _amount The amount of the deposit
     * @param _relayFeePct The Across Bridge relay fee % (irrelevant if local deposit)
     */
    function userDeposit(uint256 _amount, int64 _relayFeePct) external {
        // IMPORTANT - While assertion is open, user deposits sit in the pool rather than being sent.

        bytes32 depositId = poolCalculations.createDepositOrder(
            msg.sender,
            _amount
        );

        if (currentPositionChain == localChain) {
            enterFundsLocalChain(depositId, _amount, msg.sender);
        } else {
            bytes4 method = bytes4(keccak256(abi.encode("userDeposit")));

            bytes memory message = abi.encode(
                method,
                address(this),
                abi.encode(depositId, msg.sender)
            );
            enterFundsCrossChain(
                depositId,
                _amount,
                msg.sender,
                _relayFeePct,
                message
            );
        }
    }

    /**
     * @notice Complete the process of sending funds to a local BridgeReceiver fr entering the position
     * @dev This function does not use the Bridge or cross chain communication for execution
     * @param _depositId The id of the deposit, used for data lookup
     */
    function enterFundsLocalChain(
        bytes32 _depositId,
        uint256 _amount,
        address _sender
    ) internal {
        asset.transferFrom(_sender, address(localBridgeLogic), _amount);

        localBridgeLogic.receiveDepositFromPool(
            _amount,
            _depositId,
            address(this),
            _sender
        );

        currentRecordPositionValue = localBridgeLogic.getPositionBalance(
            address(this)
        );
        mintUserPoolTokens(_depositId, currentRecordPositionValue);
    }

    /**
     * @notice Complete the process of sending funds to the BridgeReceiver on another chain for entering the position
     * @dev This function is the first "A" step of the "A=>B=>A" deposit sequence
     * @param _depositId The id of the deposit, used for data lookup
     * @param _relayFeePct The Across Bridge relay fee %
     * @param _message Bytes that are passed in the Across "message" parameter, particularly to help set the position
     */
    function enterFundsCrossChain(
        bytes32 _depositId,
        uint256 _amount,
        address _sender,
        int64 _relayFeePct,
        bytes memory _message
    ) internal {
        require(
            pivotPending == false,
            "If a pivot proposal has been approved, no cross-chain position entrances are allowed"
        );

        // fund entrance can automatically bridge into position.
        address acrossSpokePool = registry.chainIdToSpokePoolAddress(
            currentPositionChain
        );

        // Take the sucessfully proposed position, input into a registry function to get Bridge Connection address for its chain
        address bridgeReceiver = registry.chainIdToBridgeReceiver(
            targetPositionChain
        );

        // Approval made from sender to this contract
        // spokePoolPreparation makes approval for spokePool
        spokePoolPreparation(_sender, _amount);

        emit AcrossMessageSent(_message);

        currentPositionChain = targetPositionChain; // REMOVE - TESTING. This simulates finalizing the new position, which normally occurs after LZ callback

        //When assertion is settled, pivotPending state is true and no deposits are allowed until new position is successfully engaged
        ISpokePool(acrossSpokePool).deposit(
            bridgeReceiver,
            address(asset),
            _amount,
            targetPositionChain,
            _relayFeePct,
            uint32(block.timestamp),
            _message,
            (2 ** 256 - 1)
        );
    }

    function queryMovePosition(
        string memory requestProtocolSlug,
        string memory requestMarketId,
        uint256 bond
    ) public {
        uint256 userAllowance = asset.allowance(
            msg.sender,
            address(arbitrationContract)
        );

        arbitrationContract.queryMovePosition(
            requestProtocolSlug,
            requestMarketId,
            bond,
            userAllowance,
            strategySource
        );
    }

    function sendPositionChange(
        string memory requestMarketId,
        bytes32 protocolHash
    ) external {
        uint256 destinationChainId = 1337;
        if (currentPositionChain == 1337) {
            destinationChainId = 80001; // REMOVE - TESTING
        }

        bytes memory pivotMessage = createPivotExitMessage(
            protocolHash,
            requestMarketId,
            destinationChainId
        );

        bytes memory options;

        targetPositionMarketId = requestMarketId;
        targetPositionChain = destinationChainId;
        targetPositionProtocolHash = protocolHash;

        pivotPending = true;

        emit Numbers(currentPositionChain, destinationChainId);

        // IF POSITION NEEDS TO PIVOT *FROM* THIS CHAIN (LOCAL/BRIDGE LOGIC)
        // THIS IF STATEMENT DETERMINES WHETHER TO ACTION THE EXITPIVOT LOCALLY OR THROUGH CROSS CHAIN
        //IMPORTANT - NEED TO REDO FOR CCIP AND NEW EXECUTEEXITPIVOT FUNCTIONALITY
        if (currentPositionChain == localChain) {
            address destinationBridgeReceiver = registry
                .chainIdToBridgeReceiver(destinationChainId);

            localBridgeLogic.executeExitPivot(address(this), pivotMessage);
        } else {
            bytes memory data = abi.encode("TEST");

            bytes4 method = bytes4(keccak256(abi.encode("MessageExitPivot")));
            emit LzMessageSent(method, pivotMessage);
            registry.sendMessage(
                80001, //IMPORTANT - CHANGE TO currentPositionChain
                method,
                address(this),
                data
            );
        }
    }

    function pivotCompleted(
        address marketAddress,
        uint256 positionAmount
    ) public {
        lastPositionAddress = currentPositionAddress;
        lastPositionChain = currentPositionChain;
        lastPositionProtocolHash = currentPositionProtocolHash;

        currentPositionAddress = marketAddress;
        currentPositionMarketId = targetPositionMarketId;
        currentPositionChain = targetPositionChain;
        currentPositionProtocolHash = targetPositionProtocolHash;
        currentRecordPositionValue = positionAmount;

        targetPositionMarketId = "";
        targetPositionChain = 0;
        targetPositionProtocolHash = bytes32("");

        pivotPending = false;

        emit PivotCompleted(
            currentPositionMarketId,
            marketAddress,
            currentPositionProtocolHash,
            positionAmount
        );
    }

    /**
     * @notice Called after receiving communication of successful position entrance on the BridgeLogic, minting tokens for the users proportional stake in the pool
     * @param _depositId The id of the deposit, for data lookup
     * @param _poolPositionAmount The amount of assets in the position, read recently from the BridgeLogic in the "B" step of the "A=>B=>A" deposit sequence
     */
    function mintUserPoolTokens(
        bytes32 _depositId,
        uint256 _poolPositionAmount
    ) internal {
        if (poolToken == address(0)) {
            poolToken = address(
                new PoolToken(deployingUser, _poolPositionAmount, poolName)
            );
        } else {
            uint256 poolTokenSupply = IPoolToken(poolToken).totalSupply();

            (uint256 poolTokensToMint, address depositor) = poolCalculations
                .calculatePoolTokensToMint(
                    _depositId,
                    _poolPositionAmount,
                    poolTokenSupply
                );

            poolNonce += 1;

            IPoolToken(poolToken).mint(depositor, poolTokensToMint);
        }
    }

    function finalizeWithdrawOrder(
        bytes32 _withdrawId,
        uint256 _amount,
        uint256 _totalAvailableForUser
    ) public {
        (address depositor, uint256 poolTokensToBurn) = poolCalculations
            .getWithdrawOrderFulfillment(
                _withdrawId,
                _totalAvailableForUser,
                _amount,
                poolToken
            );

        poolNonce += 1;
        userHasPendingWithdraw[depositor] = false;
        IPoolToken(poolToken).burn(depositor, poolTokensToBurn);
        asset.transfer(depositor, _amount);
    }

    /**
     * @notice Transfer deposit funds from user to pool, make approval for funds to the spokepool for moving the funds to the destination chain
     * @param _sender The address of the user who is making the deposit
     * @param _amount The amount of assets to deposit
     */
    function spokePoolPreparation(address _sender, uint256 _amount) internal {
        address acrossSpokePool = registry.chainIdToSpokePoolAddress(
            localChain
        );
        require(acrossSpokePool != address(0), "SPOKE ADDR");
        uint256 senderAssetBalance = asset.balanceOf(_sender);
        require(
            senderAssetBalance >= _amount,
            "Sender has insufficient asset balance"
        );
        asset.transferFrom(_sender, address(this), _amount);
        asset.approve(acrossSpokePool, _amount);
    }

    function createPivotExitMessage(
        bytes32 protocolHash,
        string memory requestMarketId,
        uint256 destinationChainId
    ) internal view returns (bytes memory) {
        address destinationBridgeReceiver = registry.chainIdToBridgeReceiver(
            destinationChainId
        );

        bytes memory data = abi.encode(
            poolNonce,
            protocolHash,
            requestMarketId,
            destinationChainId,
            destinationBridgeReceiver
        );

        return data;
    }
}
