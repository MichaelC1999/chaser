// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IChaserRegistry {
    function managerChainId() external view returns (uint256);

    function currentChainId() external view returns (uint256);

    function poolEnabled(address) external returns (bool);

    function addPoolEnabled(address) external;

    function disablePool(address) external;

    function getPoolBroker(address, address) external returns (address);

    function addIntegrator(address) external;

    function sendMessage(uint, bytes4, address, bytes memory) external;

    function routerAddress() external view returns (address);

    function investmentStrategyContract() external view returns (address);

    function bridgeLogicAddress() external view returns (address);

    function localCcipConfigs()
        external
        view
        returns (address, address, uint64);

    function poolAddressToBroker(address) external view returns (address);

    function chainIdToBridgeReceiver(uint256) external view returns (address);

    function chainIdToSpokePoolAddress(uint256) external view returns (address);

    function chainIdToUmaAddress(uint256) external view returns (address);

    function chainIdToEndpointId(uint256) external view returns (uint32);

    function acrossAddress() external view returns (address);

    function arbitrationContract() external view returns (address);

    function protocolEnabled(string memory) external view returns (bool);

    function hashToProtocol(bytes32) external view returns (string memory);

    function checkValidPool(address) external view returns (bool);
}
