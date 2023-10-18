// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./interfaces/IExternalFunctionsIntegration.sol";

contract AaveIntegration is IExternalFunctionsIntegration {
    // Placeholder variables
    uint256[] public _supportedChains = [1]; // Example: Ethereum Mainnet as the only supported chain
    string public _protocolName = "Aave";

    constructor() {}

    function deposit(
        address asset,
        uint256 amount,
        address subconduitAddress
    ) external view override returns (bytes memory) {
        // subconduitAddress is the subconduit that is currently holding the funds to deposit into external protocol
        bytes4 selector = bytes4(
            keccak256(
                abi.encodePacked("supply(address,uint256,address,uint16)")
            )
        );

        bytes32 assetBytes32 = bytes32(uint256(uint160(asset)));
        bytes32 subconduitBytes32 = bytes32(
            uint256(uint160(subconduitAddress))
        );

        return
            abi.encodePacked(
                selector,
                assetBytes32,
                amount,
                subconduitBytes32,
                bytes32(0)
            );
    }

    function withdraw(
        address asset,
        uint256 amount,
        address subconduitAddress
    ) external view override returns (bytes memory) {
        // Placeholder implementation, returns empty bytes

        bytes4 selector = bytes4(
            keccak256(abi.encodePacked(("withdraw(address,uint256,address)")))
        );

        return abi.encodePacked(selector, asset, amount, subconduitAddress);
    }

    function getPoolAddress(
        bytes memory subgraphPoolId
    ) external override returns (address) {
        // Placeholder implementation, returns address(0)
        // if the pool id on the subgraph is same as pool contract with deposit/withdraw functions, return pool contract address
        // if not, use read calls/calculations to determine the correct contract address with these functions
        address pool = address(0);
        assembly {
            pool := mload(add(subgraphPoolId, 20))
        }

        return pool;
    }

    function supportedChains()
        external
        view
        override
        returns (uint256[] memory)
    {
        return _supportedChains;
    }

    function protocolName() external view override returns (string memory) {
        return _protocolName;
    }
}
