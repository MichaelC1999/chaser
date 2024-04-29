// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";

contract PoolCalculations {
    mapping(bytes32 => address) public depositIdToDepositor;
    mapping(bytes32 => uint256) public depositIdToDepositAmount;
    mapping(bytes32 => bool) public depositIdToTokensMinted;
    mapping(bytes32 => uint256) public depositIdToPoolTokenSupply;
    mapping(address => uint256) public poolToPendingDeposits;

    mapping(bytes32 => address) public withdrawIdToDepositor;
    mapping(bytes32 => uint256) public withdrawIdToAmount;
    mapping(bytes32 => bool) public withdrawIdToTokensBurned;
    mapping(address => uint256) public poolToPendingWithdraws;

    mapping(address => uint256) public poolNonce;
    mapping(address => uint256) public poolDepositNonce;
    mapping(address => uint256) public poolWithdrawNonce;
    mapping(address => bool) public poolToPivotPending;

    mapping(address => mapping(address => bool)) poolToUserPendingWithdraw;
    mapping(address => mapping(address => bool)) poolToUserPendingDeposit;

    mapping(address => string) public targetPositionMarketId; //THE MARKET ADDRESS THAT WILL BE PASSED TO BRIDGECONNECTION, NOT THE FINAL ADDRESS THAT FUNDS ARE ACTUALLY HELD IN
    mapping(address => uint256) public targetPositionChain;
    mapping(address => bytes32) public targetPositionProtocolHash;
    mapping(address => string) public targetPositionProtocol;

    mapping(address => address) public currentPositionAddress;
    mapping(address => string) public currentPositionMarketId;
    mapping(address => bytes32) public currentPositionProtocolHash;
    mapping(address => string) public currentPositionProtocol;
    mapping(address => uint256) public currentRecordPositionValue; //This holds the most recently recorded value of the entire position sent from the current position chain.
    mapping(address => uint256) public currentPositionValueTimestamp;

    event DepositRecorded(bytes32, uint256);
    event WithdrawRecorded(bytes32, uint256);

    IChaserRegistry public registry;

    constructor(address _registryAddress) {
        registry = IChaserRegistry(_registryAddress);
    }
    //IMPORTANT - NEED FUNCTION FOR RESETTING STATE WHEN DEPOSIT FAILS ON DESTINATION NETWORK

    modifier onlyValidPool() {
        require(
            registry.poolEnabled(msg.sender),
            "Only valid pools may use this calculations contract"
        );
        _;
    }

    modifier noPending(address _sender) {
        require(
            !poolToPivotPending[msg.sender],
            "If a pivot proposal has been approved, no position entrances are allowed"
        );
        require(
            !poolToUserPendingDeposit[msg.sender][_sender],
            "User cannot have deposit pending on this pool"
        );
        require(
            !poolToUserPendingWithdraw[msg.sender][_sender],
            "User cannot have withdraw pending on this pool"
        );
        _;
    }

    function createWithdrawOrder(
        uint256 _amount,
        address _poolToken,
        address _sender
    ) external onlyValidPool noPending(_sender) returns (bytes memory) {
        poolToUserPendingWithdraw[msg.sender][_sender] = true;

        bytes32 withdrawId = keccak256(
            abi.encode(msg.sender, _sender, _amount, block.timestamp)
        );

        withdrawIdToDepositor[withdrawId] = _sender;
        withdrawIdToAmount[withdrawId] = _amount;
        poolToPendingWithdraws[msg.sender] += _amount;
        poolWithdrawNonce[msg.sender] += 1;
        emit WithdrawRecorded(withdrawId, _amount);

        uint256 scaledRatio = getScaledRatio(_poolToken, _sender);

        bytes memory data = abi.encode(
            withdrawId,
            _amount,
            poolDepositNonce[msg.sender],
            poolWithdrawNonce[msg.sender],
            scaledRatio
        );
        return data;
    }

    function getScaledRatio(
        address _poolToken,
        address _sender
    ) public view returns (uint256) {
        IERC20 poolToken = IERC20(_poolToken);

        uint256 userPoolTokenBalance = poolToken.balanceOf(_sender);
        if (userPoolTokenBalance == 0) {
            return 0;
        }
        uint256 poolTokenSupply = poolToken.totalSupply();
        require(poolTokenSupply > 0, "Pool Token has no supply");

        uint256 scaledRatio = (10 ** 18);
        if (userPoolTokenBalance != poolTokenSupply) {
            scaledRatio =
                (userPoolTokenBalance * (10 ** 18)) /
                (poolTokenSupply);
        }
        return scaledRatio;
    }

    function fulfillWithdrawOrder(
        bytes32 _withdrawId,
        uint256 _positionValue,
        uint256 _totalAvailableForUser,
        uint256 _amount,
        address _poolToken
    ) external onlyValidPool returns (address, uint256) {
        require(
            !withdrawIdToTokensBurned[_withdrawId],
            "Tokens have already been burned for this withdraw"
        );
        //amount gets passed from the BridgeLogic as the input amount, before bridging/protocol fees deduct from the received amount. This amount reflects the total amount of asset removed from the position
        address depositor = withdrawIdToDepositor[_withdrawId];
        address poolAddress = msg.sender;

        poolNonce[poolAddress] += 1;

        currentRecordPositionValue[poolAddress] = _positionValue;
        currentPositionValueTimestamp[poolAddress] = block.timestamp;

        uint256 userPoolTokenBalance = IERC20(_poolToken).balanceOf(depositor);

        if (_totalAvailableForUser < _amount) {
            _amount = _totalAvailableForUser;
        }
        uint256 poolTokensToBurn = userPoolTokenBalance;
        if (_totalAvailableForUser > 0) {
            uint256 ratio = (_amount * (10 ** 18)) / (_totalAvailableForUser);
            poolTokensToBurn = (ratio * userPoolTokenBalance) / (10 ** 18);
        }

        poolToUserPendingWithdraw[poolAddress][depositor] = false;
        poolToPendingWithdraws[poolAddress] -= withdrawIdToAmount[_withdrawId];
        withdrawIdToAmount[_withdrawId] = _amount;
        withdrawIdToTokensBurned[_withdrawId] = true;

        return (depositor, poolTokensToBurn);
    }

    function openSetPosition(
        string memory _targetPositionMarketId,
        string memory _targetProtocol,
        uint256 _targetChainId
    ) external onlyValidPool {
        poolToPivotPending[msg.sender] = true;
        targetPositionMarketId[msg.sender] = _targetPositionMarketId;
        targetPositionProtocolHash[msg.sender] = keccak256(
            abi.encode(_targetProtocol)
        );
        targetPositionProtocol[msg.sender] = _targetProtocol;
        targetPositionChain[msg.sender] = _targetChainId;
    }

    function createDepositOrder(
        address _sender,
        address _poolToken,
        uint256 _amount
    ) external onlyValidPool noPending(_sender) returns (bytes32, uint256) {
        IERC20 poolToken = IERC20(_poolToken);
        bytes32 depositId = bytes32(
            keccak256(abi.encode(msg.sender, _sender, _amount, block.timestamp))
        );

        poolToUserPendingDeposit[msg.sender][_sender] = true;
        depositIdToDepositor[depositId] = _sender;
        depositIdToDepositAmount[depositId] = _amount;
        depositIdToTokensMinted[depositId] = false;
        poolToPendingDeposits[msg.sender] += _amount;
        poolDepositNonce[msg.sender] += 1;

        if (_poolToken != address(0)) {
            depositIdToPoolTokenSupply[depositId] = poolToken.totalSupply();
        }

        emit DepositRecorded(depositId, _amount);
        return (depositId, poolWithdrawNonce[msg.sender]);
    }

    function updateDepositReceived(
        bytes32 _depositId,
        uint256 _positionAmount,
        uint256 _depositAmountReceived
    ) external onlyValidPool returns (address) {
        require(
            depositIdToDepositor[_depositId] != address(0),
            "depositId must point to recorded depositor"
        );
        require(
            !depositIdToTokensMinted[_depositId],
            "Deposit has already minted tokens"
        );
        currentRecordPositionValue[msg.sender] = _positionAmount;
        currentPositionValueTimestamp[msg.sender] = block.timestamp;

        poolNonce[msg.sender] += 1;
        poolToUserPendingDeposit[msg.sender][
            depositIdToDepositor[_depositId]
        ] = false;
        poolToPendingDeposits[msg.sender] -= depositIdToDepositAmount[
            _depositId
        ];
        depositIdToDepositAmount[_depositId] = _depositAmountReceived;
        depositIdToTokensMinted[_depositId] = true;
    }

    function pivotCompleted(
        address marketAddress,
        uint256 nonce,
        uint256 positionAmount
    ) external onlyValidPool returns (uint256) {
        currentPositionMarketId[msg.sender] = targetPositionMarketId[
            msg.sender
        ];
        currentPositionProtocolHash[msg.sender] = targetPositionProtocolHash[
            msg.sender
        ];
        currentPositionProtocol[msg.sender] = targetPositionProtocol[
            msg.sender
        ];

        uint256 currentPositionChain = targetPositionChain[msg.sender];
        clearPivotTarget();

        currentPositionAddress[msg.sender] = marketAddress;
        poolNonce[msg.sender] = nonce;
        currentRecordPositionValue[msg.sender] = positionAmount;
        currentPositionValueTimestamp[msg.sender] = block.timestamp;
        return currentPositionChain;
    }

    function undoPositionInitializer(
        bytes32 _depositId
    ) external onlyValidPool returns (address) {
        address originalSender = depositIdToDepositor[_depositId];
        poolToUserPendingDeposit[msg.sender][originalSender] = false;
        targetPositionMarketId[msg.sender] = "";
        targetPositionChain[msg.sender] = 0;
        targetPositionProtocol[msg.sender] = "";
        targetPositionProtocolHash[msg.sender] = bytes32("");

        poolNonce[msg.sender] = 0;
        poolToPivotPending[msg.sender] = false;
        depositIdToDepositor[_depositId] = address(0);
        depositIdToDepositAmount[_depositId] = 0;
        return originalSender;
    }

    function undoDeposit(
        bytes32 _depositId
    ) external onlyValidPool returns (address) {
        address originalSender = depositIdToDepositor[_depositId];
        poolToUserPendingDeposit[msg.sender][originalSender] = false;
        depositIdToDepositor[_depositId] = address(0);
        depositIdToDepositAmount[_depositId] = 0;
        return originalSender;
    }

    function undoPivot(
        uint256 _nonce,
        uint256 _positionAmount
    ) external onlyValidPool {
        currentPositionAddress[msg.sender] = msg.sender;
        currentPositionMarketId[msg.sender] = "";
        currentPositionProtocol[msg.sender] = "";
        currentPositionProtocolHash[msg.sender] = bytes32("");
        currentRecordPositionValue[msg.sender] = _positionAmount;
        currentPositionValueTimestamp[msg.sender] = block.timestamp;
        poolNonce[msg.sender] = _nonce;
        clearPivotTarget();
    }

    function clearPivotTarget() public onlyValidPool {
        targetPositionMarketId[msg.sender] = "";
        targetPositionChain[msg.sender] = 0;
        targetPositionProtocol[msg.sender] = "";
        targetPositionProtocolHash[msg.sender] = bytes32("");
        poolToPivotPending[msg.sender] = false;
    }

    function getCurrentPositionData(
        address _poolAddress
    ) external view onlyValidPool returns (string memory, string memory) {
        return (
            currentPositionProtocol[_poolAddress],
            currentPositionMarketId[_poolAddress]
        );
    }

    function createPivotExitMessage(
        address _destinationBridgeReceiver
    ) external view returns (bytes memory) {
        bytes memory data = abi.encode(
            targetPositionProtocolHash[msg.sender],
            address(0), // IMPORTANT - REPLACE WITH MARKET ADDRESS VALIDATED IN ARBITRATION
            targetPositionMarketId[msg.sender],
            targetPositionChain[msg.sender],
            _destinationBridgeReceiver
        );

        return data;
    }

    function calculatePoolTokensToMint(
        bytes32 _depositId,
        uint256 _totalPoolPositionAmount
    ) external view returns (uint256, address) {
        uint256 assetAmount = depositIdToDepositAmount[_depositId];
        address depositor = depositIdToDepositor[_depositId];
        uint256 poolTokensToMint;
        if (_totalPoolPositionAmount == assetAmount) {
            // Take the rounded down base 10 log of total supplied tokens by user
            // Make the initial supply 10 ^ (18 + base10 log)
            uint256 supplyFactor = (Math.log10(assetAmount));
            poolTokensToMint = 10 ** supplyFactor;
        } else {
            uint256 ratio = (assetAmount * (10 ** 18)) /
                (_totalPoolPositionAmount - assetAmount);
            poolTokensToMint =
                (ratio * depositIdToPoolTokenSupply[_depositId]) /
                (10 ** 18);
        }

        return (poolTokensToMint, depositor);
    }
}
