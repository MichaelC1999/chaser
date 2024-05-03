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

    /**
     * @notice Initial pool configurations and address caching
     * @param _deployingUser The address that called the pool deployment from the manager contract
     * @param _asset The asset that is being invested in this pool
     * @param _strategyIndex The index of the strategy for determining investment
     * @param _poolName The name of the pool
     * @param _localChain The integer Chain ID of this pool
     */
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

    function receivePositionInitialized(
        bytes memory _data
    ) external messageSource {
        (
            uint256 positionAmount,
            uint256 depositAmountReceived,
            address marketAddress,
            bytes32 depositId
        ) = abi.decode(_data, (uint256, uint256, address, bytes32));
        //Receives the current value of the entire position. Sets this to a contract wide state (or mapping with timestamp => uint balance, and save timestamp to contract wide state)

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

    function receivePositionBalance(bytes memory _data) external messageSource {
        // Decode the payload data
        (
            uint256 positionAmount,
            uint256 depositAmountReceived,
            bytes32 depositId
        ) = abi.decode(_data, (uint256, uint256, bytes32));
        //Receives the current value of the entire position. Sets this to a contract wide state (or mapping with timestamp => uint balance, and save timestamp to contract wide state)
        if (depositId != bytes32("")) {
            poolCalculations.updateDepositReceived(
                depositId,
                positionAmount,
                depositAmountReceived
            );
            mintUserPoolTokens(depositId, positionAmount);
        }
    }

    /**
     * @notice The user-facing function for beginning the withdraw sequence
     * @dev This function is the "A" of the "A=>B=>A" sequence of withdraws
     * @dev On this chain we don't have access to the current position value after gains. If the amount specified is over the proportion available with user's pool tokens, withdraw the maximum proportion
     * @param _amount The amount to withdraw, denominated in the pool asset
     */
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
            registry.sendMessage(
                currentPositionChain,
                method,
                address(this),
                data
            );
        }
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
        string memory _targetPositionProtocol,
        bytes memory _targetPositionMarketId,
        uint256 _targetPositionChain
    ) external {
        // This is for the initial deposit and position set up after pool creation
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

        // Encode the data including position details
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

    /**
     * @notice Make a deposit on the pool
     * @dev This function creates the deposit data and routes the function call depending on whether or not the position is local or cross chain
     * @param _amount The amount of the deposit
     * @param _totalFee The Across Bridge relay fee % (irrelevant if local deposit)
     */
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
        // fund entrance can automatically bridge into position.
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

        // Approval made from sender to this contract
        // spokePoolPreparation makes approval for spokePool
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
        openAssertion = arbitrationContract.queryMovePosition(
            msg.sender,
            _requestChainId,
            _requestProtocol,
            _requestMarketId,
            currentPositionChain,
            currentPositionProtocol,
            currentPositionMarketId,
            bond,
            strategyIndex
        );
    }

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

        address destinationBridgeReceiver = registry.chainIdToBridgeReceiver(
            _targetPositionChain
        );

        bytes memory pivotMessage = poolCalculations.createPivotExitMessage(
            destinationBridgeReceiver
        );

        if (currentPositionChain == localChain) {
            // IF POSITION NEEDS TO PIVOT *FROM* THIS CHAIN (LOCAL/BRIDGE LOGIC)
            // THIS IF STATEMENT DETERMINES WHETHER TO ACTION THE EXITPIVOT LOCALLY OR THROUGH CROSS CHAIN
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

    function pivotCompleted(
        address marketAddress,
        uint256 positionAmount
    ) external messageSource {
        _pivotCompleted(marketAddress, positionAmount);
    }

    function _pivotCompleted(
        address marketAddress,
        uint256 positionAmount
    ) internal {
        currentPositionChain = poolCalculations.pivotCompleted(
            marketAddress,
            positionAmount
        );
    }

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

    function handleUndoDeposit(
        bytes32 _depositId,
        uint256 _amount
    ) external callerSource {
        address originalSender = poolCalculations.undoDeposit(_depositId);
        bool success = asset.transferFrom(msg.sender, originalSender, _amount);
        require(success, "Token transfer failure");
    }

    function handleUndoPivot(
        uint256 _poolNonce,
        uint256 _positionAmount
    ) external callerSource {
        currentPositionChain = localChain;
        poolCalculations.undoPivot(_poolNonce, _positionAmount);
    }

    function handleClearPivotTarget() external callerSource {
        poolCalculations.clearPivotTarget();
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
        (uint256 poolTokensToMint, address depositor) = poolCalculations
            .calculatePoolTokensToMint(_depositId, _poolPositionAmount);
        IPoolToken(poolToken).mint(depositor, poolTokensToMint);
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
        bool success = asset.transferFrom(_sender, address(this), _amount);
        require(success, "Token transfer failure");

        asset.approve(acrossSpokePool, _amount);
    }

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

    function readStrategyCode() external view returns (string memory) {
        address strategyAddress = registry.investmentStrategyContract();
        bytes memory strategyBytes = IStrategy(strategyAddress).strategyCode(
            strategyIndex
        );
        return string(strategyBytes);
    }
}
