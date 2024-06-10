pragma solidity ^0.8.9;

interface IChaserTreasury {
    function separateProtocolFeeAndReward(
        uint256,
        uint256,
        address,
        address
    ) external;
}
