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
    //IMPORTANT - POOL SHOULD NOT BE UPGRADEABLE, COULD CAUSE ISSUES WITH CROSS CHAIN IDENTIFICATION OF POOL, WHEN PROXY POINTS TO ONE ADDRESS ON HOME CHAIN AFTER UPGRADE, AND OTHER ADDRESS ON DESTINATION CHAIN

    bytes32 poolId;
    address deployingUser;
    uint256 public localChain;
    address public poolToken;
    uint256 public poolNonce = 0;
    string public poolName;
    string public strategySource; // STRATEGY SOURCE CAN BE A REPO URL WITH CODE TO EXECUTE, OR THIS STRING COULD POINT TO AN ADDRESS/CHAIN/METHOD THAT RETURNS THE INSTRUCTIONS
    bool public pivotPending = false;

    IBridgeLogic public localBridgeLogic;
    IChaserManager public manager;
    IChaserRegistry public registry;
    IPoolCalculations public poolCalculations;
    IArbitrationContract public arbitrationContract;
    IERC20 public asset;

    event AcrossMessageSent(bytes);
    event LzMessageSent(bytes4, bytes);
    event Numbers(uint256, uint256);
    event CheckId(bytes32);
    event PivotCompleted(string, address, bytes32, uint256);
    event ExecutionMessage(string);

    error WithdrawOrderFailure(string reason);

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
    uint256 public currentPositionChain;
    bytes32 public currentPositionProtocolHash;
    uint256 public currentRecordPositionValue; //This holds the most recently recorded value of the entire position sent from the current position chain.
    uint256 public currentPositionValueTimestamp;

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
    ) public {
        localChain = _localChain;
        currentPositionChain = 0;
        poolId = keccak256(abi.encode(address(this), _poolName));
        poolName = _poolName;
        deployingUser = _deployingUser;
        asset = IERC20(_asset);
        strategySource = _strategySource;
        registry = IChaserRegistry(_registry);
        poolCalculations = IPoolCalculations(_poolCalculations);
        localBridgeLogic = IBridgeLogic(registry.bridgeLogicAddress());
        arbitrationContract = IArbitrationContract(
            registry.arbitrationContract()
        );
    }

    function receivePositionInitialized(bytes memory _data) external {
        (
            uint256 positionAmount,
            uint256 depositAmountReceived,
            address marketAddress,
            bytes32 depositId
        ) = abi.decode(_data, (uint256, uint256, address, bytes32));
        //Receives the current value of the entire position. Sets this to a contract wide state (or mapping with timestamp => uint balance, and save timestamp to contract wide state)

        if (depositId != bytes32("")) {
            poolCalculations.updateDepositReceived(
                depositId,
                depositAmountReceived
            );

            pivotCompleted(marketAddress, positionAmount);
            require(
                poolCalculations.depositIdToTokensMinted(depositId) == false,
                "Deposit has already minted tokens"
            );

            poolCalculations.depositIdMinted(depositId);

            poolNonce += 1;
            if (poolToken == address(0)) {
                poolToken = address(
                    new PoolToken(deployingUser, positionAmount, poolName)
                );
            }
        }
    }

    function receivePositionBalance(bytes memory _data) external {
        // Decode the payload data
        (
            uint256 positionAmount,
            uint256 depositAmountReceived,
            bytes32 depositId
        ) = abi.decode(_data, (uint256, uint256, bytes32));
        //Receives the current value of the entire position. Sets this to a contract wide state (or mapping with timestamp => uint balance, and save timestamp to contract wide state)
        poolCalculations.updateDepositReceived(
            depositId,
            depositAmountReceived
        );

        currentRecordPositionValue = positionAmount;
        currentPositionValueTimestamp = block.timestamp;

        poolNonce += 1;

        if (depositId != bytes32("")) {
            require(
                poolCalculations.depositIdToTokensMinted(depositId) == false,
                "Deposit has already minted tokens"
            );

            poolCalculations.depositIdMinted(depositId);

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
        require(
            userHasPendingWithdraw[msg.sender] == false,
            "User may only open new withdraw order if they do not have a pending withdraw order"
        );
        require(
            pivotPending == false,
            "Withdraws are blocked until the Pivot is completed"
        );
        require(
            IPoolToken(poolToken).balanceOf(msg.sender) > 0,
            "User has no position"
        );
        userHasPendingWithdraw[msg.sender] = true;

        bytes memory data = poolCalculations.createWithdrawOrder(
            _amount,
            poolNonce,
            poolToken,
            msg.sender
        );

        bytes4 method = bytes4(keccak256(abi.encode("AbWithdrawOrderUser")));

        emit LzMessageSent(method, data);
        if (currentPositionChain == localChain) {
            localBridgeLogic.userWithdrawSequence(address(this), data);
        } else {
            registry.sendMessage(
                currentPositionChain,
                method,
                address(this),
                data
            );
        }
    }

    /**
     * @notice Send a request to the position chain for the up to date value of the position (including any gains)
     */
    function readPositionBalance() external {
        // Get the value of the entire position for the pool with gains
        // Uses lzSend to send message to request this data be sent back
        bytes4 method = bytes4(
            keccak256(abi.encode("AbMessagePositionBalance"))
        );

        bytes memory data = abi.encode("TEST");

        registry.sendMessage(80001, method, address(this), data);
    }

    /**
     * @notice Send a request to the position chain for arbitrary data about the position
     */
    function getPositionData() external {
        // Uses lzSend to request position data be sent back

        bytes memory data = abi.encode("TEST");
        bytes4 method = bytes4(keccak256(abi.encode("AbMessagePositionData")));

        registry.sendMessage(80001, method, address(this), data);
    }

    /**
     * @notice Send a request to the position chain to get an address from its' registry
     */
    function getRegistryAddress() external {
        // Uses lzSend to request an address from the registry on another chain
        bytes memory data;
        bytes4 method = bytes4(keccak256(abi.encode("getRegistryAddress")));
        registry.sendMessage(80001, method, address(this), data);
    }

    /**
     * @notice Make the first deposit on the pool and set up the first position. This is a function meant to be called from a user/investing entity.
     * @notice This function simultaneously sets the first position and deposits the first funds
     * @notice After executing, other functions are called withdata generated in this function, in order to direction the position entrance
     * @param _amount The amount of the initial deposit
     * @param _totalFee The Across Bridge relay fee
     * @param _targetPositionMarketId The market Id to be processed by Logic/Integrator to derive the market address
     * @param _targetPositionChain The destination chain on which the first position exists
     * @param _targetPositionProtocol The protocol that the position is made on
     */
    function userDepositAndSetPosition(
        uint256 _amount,
        uint256 _totalFee,
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
            address(0), // IMPORTANT - THIS ADDRESS MUST BE VALIDATED AND PROVIDED FROM UMA ORACLE, POINTS TO CONTRACT TO INVEST INTO
            targetPositionMarketId,
            targetPositionProtocolHash
        );

        if (targetPositionChain == localChain) {
            asset.transferFrom(msg.sender, address(localBridgeLogic), _amount);
            localBridgeLogic.handlePositionInitializer(
                _amount,
                address(this),
                address(asset),
                depositId,
                msg.sender,
                address(0),
                targetPositionMarketId,
                targetPositionProtocolHash
            );
        } else {
            bytes4 method = bytes4(
                keccak256(abi.encode("AbBridgePositionInitializer"))
            );
            bytes memory message = abi.encode(method, address(this), data);
            emit CheckId(depositId);
            enterFundsCrossChain(
                depositId,
                _amount,
                msg.sender,
                _totalFee,
                message
            );
        }
    }

    /**
     * @notice Make a deposit on the pool
     * @dev This function creates the deposit data and routes the function call depending on whether or not the position is local or cross chain
     * @param _amount The amount of the deposit
     * @param _totalFee The Across Bridge relay fee % (irrelevant if local deposit)
     */
    function userDeposit(uint256 _amount, uint256 _totalFee) external {
        bytes32 depositId = poolCalculations.createDepositOrder(
            msg.sender,
            _amount
        );

        if (currentPositionChain == localChain) {
            asset.transferFrom(msg.sender, address(localBridgeLogic), _amount);
            localBridgeLogic.handleUserDeposit(
                address(this),
                msg.sender,
                depositId,
                _amount
            );
        } else {
            bytes4 method = bytes4(
                keccak256(abi.encode("AbBridgeDepositUser"))
            );

            bytes memory message = abi.encode(
                method,
                address(this),
                abi.encode(depositId, msg.sender)
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

        currentRecordPositionValue = localBridgeLogic.getPositionBalance(
            address(this)
        );
        currentPositionValueTimestamp = block.timestamp;
        mintUserPoolTokens(_depositId, currentRecordPositionValue);
    }

    /**
     * @notice Complete the process of sending funds to the BridgeReceiver on another chain for entering the position
     * @dev This function is the first "A" step of the "A=>B=>A" deposit sequence
     * @param _depositId The id of the deposit, used for data lookup
     * @param _feeTotal The Across Bridge relay fee %
     * @param _message Bytes that are passed in the Across "message" parameter, particularly to help set the position
     */
    function enterFundsCrossChain(
        bytes32 _depositId,
        uint256 _amount,
        address _sender,
        uint256 _feeTotal,
        bytes memory _message
    ) internal {
        require(
            pivotPending == false,
            "If a pivot proposal has been approved, no cross-chain position entrances are allowed"
        );

        // fund entrance can automatically bridge into position.
        address acrossSpokePool = registry.chainIdToSpokePoolAddress(0);

        uint256 receivingChain = currentPositionChain;
        if (currentPositionChain == 0) {
            receivingChain = targetPositionChain;
        }

        require(receivingChain != 0, "Cannot bridge, invalid chain id");

        // Take the sucessfully proposed position, input into a registry function to get Bridge Connection address for its chain
        address bridgeReceiver = registry.chainIdToBridgeReceiver(
            receivingChain
        );

        // Approval made from sender to this contract
        // spokePoolPreparation makes approval for spokePool
        spokePoolPreparation(_sender, _amount);

        emit AcrossMessageSent(_message);

        crossChainBridge(
            _sender,
            acrossSpokePool,
            bridgeReceiver,
            _amount,
            _feeTotal,
            receivingChain,
            _message
        );

        //When assertion is settled, pivotPending state is true and no deposits are allowed until new position is successfully engaged
    }

    function crossChainBridge(
        address _sender,
        address acrossSpokePool,
        address bridgeReceiver,
        uint256 _amount,
        uint256 feeTotal,
        uint256 receivingChain,
        bytes memory _message
    ) internal {
        try
            ISpokePool(acrossSpokePool).depositV3(
                _sender,
                bridgeReceiver,
                address(asset),
                address(0),
                _amount,
                _amount - feeTotal, // IMPORTANT - SEEK ORACLE SOLUTION TO BRING API FEE CALC ON CHAIN
                receivingChain,
                address(0),
                uint32(block.timestamp),
                uint32(block.timestamp + 30000),
                0,
                _message
            )
        {
            emit ExecutionMessage("Successful Spokepool Deposit");
        } catch Error(string memory reason) {
            emit ExecutionMessage(
                string(abi.encode("Failed Spokepool Deposit: ", reason))
            );
        }
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
        string memory targetProtocol,
        uint256 destinationChainId
    ) external {
        bytes memory pivotMessage = createPivotExitMessage(
            keccak256(abi.encode(targetProtocol)),
            requestMarketId,
            destinationChainId
        );

        targetPositionMarketId = requestMarketId;
        targetPositionChain = destinationChainId;
        targetPositionProtocolHash = keccak256(abi.encode(targetProtocol));

        pivotPending = true;

        emit Numbers(currentPositionChain, destinationChainId);

        // IF POSITION NEEDS TO PIVOT *FROM* THIS CHAIN (LOCAL/BRIDGE LOGIC)
        // THIS IF STATEMENT DETERMINES WHETHER TO ACTION THE EXITPIVOT LOCALLY OR THROUGH CROSS CHAIN
        if (currentPositionChain == localChain) {
            localBridgeLogic.executeExitPivot(address(this), pivotMessage);
        } else {
            bytes4 method = bytes4(
                keccak256(abi.encode("AbPivotMovePosition"))
            );
            emit LzMessageSent(method, pivotMessage);
            registry.sendMessage(
                currentPositionChain,
                method,
                address(this),
                pivotMessage
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
        currentPositionValueTimestamp = block.timestamp;

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
        uint256 poolTokenSupply = IPoolToken(poolToken).totalSupply();

        (uint256 poolTokensToMint, address depositor) = poolCalculations
            .calculatePoolTokensToMint(
                _depositId,
                _poolPositionAmount,
                poolTokenSupply
            );
        IPoolToken(poolToken).mint(depositor, poolTokensToMint);
    }

    function finalizeWithdrawOrder(
        bytes32 _withdrawId,
        uint256 _amount,
        uint256 _totalAvailableForUser,
        uint256 _positionValue,
        uint256 _inputAmount
    ) public {
        (address depositor, uint256 poolTokensToBurn) = poolCalculations
            .getWithdrawOrderFulfillment(
                _withdrawId,
                _totalAvailableForUser,
                _inputAmount,
                poolToken
            );

        currentRecordPositionValue = _positionValue;
        currentPositionValueTimestamp = block.timestamp;

        poolNonce += 1;
        userHasPendingWithdraw[depositor] = false;

        try IPoolToken(poolToken).burn(depositor, poolTokensToBurn) {
            emit ExecutionMessage("Burn Success");
        } catch Error(string memory reason) {
            emit ExecutionMessage(string(abi.encode("BURN FAILURE: ", reason)));
        }

        try asset.transfer(depositor, _amount) {} catch Error(
            string memory reason
        ) {
            emit ExecutionMessage(
                string(abi.encode("Transfer Failure: ", reason))
            );
        }
    }

    /**
     * @notice Transfer deposit funds from user to pool, make approval for funds to the spokepool for moving the funds to the destination chain
     * @param _sender The address of the user who is making the deposit
     * @param _amount The amount of assets to deposit
     */
    function spokePoolPreparation(address _sender, uint256 _amount) internal {
        address acrossSpokePool = registry.chainIdToSpokePoolAddress(0);
        require(acrossSpokePool != address(0), "SPOKE ADDR");
        uint256 senderAssetBalance = asset.balanceOf(_sender);
        require(
            senderAssetBalance >= _amount,
            "Sender has insufficient asset balance"
        );
        asset.transferFrom(_sender, address(this), _amount);
        asset.approve(acrossSpokePool, _amount);
    }

    function receivePositionData(bytes memory _data) external {
        emit AcrossMessageSent(_data);
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
            address(0), // IMPORTANT - REPLACE WITH MARKET ADDRESS VALIDATED IN ARBITRATION
            requestMarketId,
            destinationChainId,
            destinationBridgeReceiver
        );

        return data;
    }
}
