// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IChaserRegistry {
    function addInvestmentStrategyContract(address) external;
    function addBridgeLogic(address, address, address) external;
    function localCcipConfigs()
        external
        view
        returns (address, address, uint256);
    function enableProtocol(string memory) external;
    function disableProtocol(string memory) external;
    function protocolEnabled(string memory) external view returns (bool);
    function checkValidPool(address) external view returns (bool);
    function enablePool(address) external;
    function disablePool(address) external;
    function addBridgeReceiver(uint256, address) external;
    function addMessageReceiver(uint256, address) external;
    function addIntegrator(address) external;
    function addArbitrationContract(address) external;
    function deployPoolBroker(address, address) external returns (address);
    function sendMessage(uint256, bytes4, address, bytes memory) external;

    // External/Public State Variable Accessors
    function localEquivalent(address) external view returns (address);
    function poolEnabled(address) external view returns (bool);
    function chainIdToBridgeReceiver(uint256) external view returns (address);
    function chainIdToMessageReceiver(uint256) external view returns (address);
    function chainIdToSpokePoolAddress(uint256) external view returns (address);
    function chainIdToRouter(uint256) external view returns (address);
    function chainIdToLinkAddress(uint256) external view returns (address);
    function chainIdToSelector(uint256) external view returns (uint64);
    function chainIdToUmaAddress(uint256) external view returns (address);
    function hashToProtocol(bytes32) external view returns (string memory);
    function getDataFeed(address) external view returns (address);
    function poolCountToPool(uint256) external view returns (address);
    function poolAddressToBroker(address) external view returns (address);
    function addressUSDC(uint256) external view returns (address);
    function manager() external view returns (address);
    function uniswapRouter(uint256) external view returns (address);
    function uniswapFactory(uint256) external view returns (address);
    function treasuryAddress() external view returns (address);
    function bridgeLogicAddress() external view returns (address);
    function poolCalculationsAddress() external view returns (address);
    function receiverAddress() external view returns (address);
    function integratorAddress() external view returns (address);
    function arbitrationContract() external view returns (address);
    function investmentStrategyContract() external view returns (address);
    function currentChainId() external view returns (uint256);
    function managerChainId() external view returns (uint256);
    function poolCount() external view returns (uint256);
}
