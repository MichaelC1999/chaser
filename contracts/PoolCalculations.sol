// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/utils/math/Math.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);
    // Add other ERC20 functions as needed
}

contract PoolCalculations {
    mapping(bytes32 => address) public depositIdToDepositor;
    mapping(bytes32 => uint256) public depositIdToDepositAmount;
    mapping(bytes32 => bool) public depositIdToTokensMinted;

    mapping(bytes32 => address) public withdrawIdToDepositor;
    mapping(bytes32 => uint256) public withdrawIdToDepositAmount;

    event DepositRecorded(bytes32, uint256);
    event WithdrawRecorded(bytes32, uint256);

    function createWithdrawOrder(
        uint256 _amount,
        uint256 _poolNonce,
        address _poolToken,
        address _sender
    ) external returns (bytes memory) {
        // IMPORTANT - CHECK REGISTRY THAT msg.sender IS A VALID POOL

        bytes32 withdrawId = keccak256(
            abi.encode(msg.sender, _sender, _amount, block.timestamp)
        );

        withdrawIdToDepositor[withdrawId] = _sender;
        withdrawIdToDepositAmount[withdrawId] = _amount;

        emit WithdrawRecorded(withdrawId, _amount);

        uint256 scaledRatio = getScaledRatio(_poolToken, _sender);

        bytes memory data = abi.encode(
            withdrawId,
            _amount,
            _poolNonce,
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

        uint256 scaledRatio = (10 ** 18); // scaledRatio defaults to 1, if the user has all pool tokens IMPORTANT - SHOULD THIS BE 10 ** 19? As 1 ETH IS 10**19 WEI
        if (userPoolTokenBalance != poolTokenSupply) {
            scaledRatio =
                (userPoolTokenBalance * (10 ** 18)) /
                (poolTokenSupply);
        }
        return scaledRatio;
    }

    function getWithdrawOrderFulfillment(
        bytes32 withdrawId,
        uint256 totalAvailableForUser,
        uint256 amount,
        address _poolToken
    ) external view returns (address, uint256) {
        //amount gets passed from the BridgeLogic as the input amount, before bridging/protocol fees deduct from the received amount. This amount reflects the total amount of asset removed from the position
        address depositor = withdrawIdToDepositor[withdrawId];
        IERC20 poolToken = IERC20(_poolToken);

        uint256 userPoolTokenBalance = poolToken.balanceOf(depositor);

        // IMPORTANT - IF totalAvailableForUser IS VERY CLOSE TO amount, MAKE amount = totalAvailableForUser
        if (totalAvailableForUser < amount) {
            amount = totalAvailableForUser; // IMPORTANT - IF THE CALCULATED TOTAL AVAILABLE FOR USER IS LESS THAN THE AMOUNT BRIDGED BACK, ONLY TRANSFER THE CALCULATED AMOUNT TO USER
        }

        uint256 poolTokensToBurn = userPoolTokenBalance;
        if (totalAvailableForUser > 0) {
            uint256 ratio = (amount * (10 ** 18)) / (totalAvailableForUser);
            poolTokensToBurn = (ratio * userPoolTokenBalance) / (10 ** 18);
        }

        return (depositor, poolTokensToBurn);
    }

    function createDepositOrder(
        address _sender,
        uint256 _amount
    ) external returns (bytes32) {
        // Generate a deposit ID
        bytes32 depositId = bytes32(
            keccak256(abi.encode(msg.sender, _sender, _amount, block.timestamp))
        );

        // Map deposit ID to depositor and deposit amount
        depositIdToDepositor[depositId] = _sender;
        depositIdToDepositAmount[depositId] = _amount;
        depositIdToTokensMinted[depositId] = false;

        emit DepositRecorded(depositId, _amount);
        return depositId;
    }

    function updateDepositReceived(
        bytes32 _depositId,
        uint256 _depositAmountReceived
    ) external {
        depositIdToDepositAmount[_depositId] = _depositAmountReceived;
    }

    function depositIdMinted(bytes32 _depositId) external {
        depositIdToTokensMinted[_depositId] = true;
    }

    function calculatePoolTokensToMint(
        bytes32 _depositId,
        uint256 _totalPoolPositionAmount,
        uint256 _poolTokenSupply
    ) external view returns (uint256, address) {
        // IMPORTANT - THE assetAmount RECORDED LOCALLY IS DIFFERENT THAN THE ACTUAL DEPOSIT ON THE DESTINATION CHAIN, ACROSS FEES (COULD PASS THE AMOUNT ACTUALLY DEPOSITED IN MESSAGE TO FINALIZE DEPOSIT)

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
            poolTokensToMint = (ratio * _poolTokenSupply) / (10 ** 18);
        }

        return (poolTokensToMint, depositor);
    }

    // Add other helper functions as needed
}
