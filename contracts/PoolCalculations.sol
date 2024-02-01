// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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

        withdrawIdToDepositor[withdrawId] = msg.sender;
        withdrawIdToDepositAmount[withdrawId] = _amount;

        emit WithdrawRecorded(withdrawId, _amount);

        IERC20 poolToken = IERC20(_poolToken);

        uint256 userPoolTokenBalance = poolToken.balanceOf(msg.sender);
        require(userPoolTokenBalance > 0, "User has no deposits in pool");
        uint256 poolTokenSupply = poolToken.totalSupply();

        uint256 scaledRatio = (10 ** 18); // scaledRatio defaults to 1, if the user has all pool tokens
        if (userPoolTokenBalance != poolTokenSupply) {
            scaledRatio =
                (userPoolTokenBalance * (10 ** 18)) /
                (poolTokenSupply);
        }

        bytes memory data = abi.encode(
            withdrawId,
            msg.sender,
            _amount,
            _poolNonce,
            scaledRatio
        );
        return data;
    }

    function getWithdrawOrderFulfillment(
        bytes32 withdrawId,
        uint256 totalAvailableForUser,
        uint256 amount,
        address _poolToken
    ) external view returns (address depositor, uint256 poolTokensToBurn) {
        address depositor = withdrawIdToDepositor[withdrawId];
        IERC20 poolToken = IERC20(_poolToken);

        uint256 userPoolTokenBalance = poolToken.balanceOf(depositor);
        // asset/totalAvailableForUser=x/userPoolTokenBalance

        // IMPORTANT - IF totalAvailableForUser IS VERY CLOSE TO amount, MAKE amount = totalAvailableForUser
        if (totalAvailableForUser < amount) {
            amount = totalAvailableForUser; // IMPORTANT - IF THE CALCULATED TOTAL AVAILABLE FOR USER IS LESS THAN THE AMOUNT BRIDGED BACK, ONLY TRANSFER THE CALCULATED AMOUNT TO USER
        }

        uint256 poolTokensToBurn = userPoolTokenBalance;
        if (totalAvailableForUser > 0) {
            uint256 ratio = (amount * (10 ** 18)) / (totalAvailableForUser);
            poolTokensToBurn = (ratio * userPoolTokenBalance) / (10 ** 18);
        }
    }

    function createDepositOrder(
        address _sender,
        uint256 _amount
    ) external returns (bytes32 depositId) {
        // Generate a deposit ID
        bytes32 depositId = keccak256(
            abi.encode(msg.sender, _sender, _amount, block.timestamp)
        );

        // Map deposit ID to depositor and deposit amount
        depositIdToDepositor[depositId] = msg.sender;
        depositIdToDepositAmount[depositId] = _amount;
        depositIdToTokensMinted[depositId] = false;

        emit DepositRecorded(depositId, _amount);
    }

    function calculatePoolTokensToMint(
        bytes32 _depositId,
        uint256 _poolPositionAmount,
        uint256 _poolTokenSupply
    ) external returns (uint256, address) {
        require(
            depositIdToTokensMinted[_depositId] == false,
            "Deposit has already minted tokens"
        );

        uint256 assetAmount = depositIdToDepositAmount[_depositId];

        uint256 ratio = (assetAmount * (10 ** 18)) /
            (_poolPositionAmount - assetAmount);

        // // Calculate the correct amount of pool tokens to mint
        uint256 poolTokensToMint = (ratio * _poolTokenSupply) / (10 ** 18);

        depositIdToTokensMinted[_depositId] = true;

        address depositor = depositIdToDepositor[_depositId];

        return (poolTokensToMint, depositor);
    }

    // Add other helper functions as needed
}
