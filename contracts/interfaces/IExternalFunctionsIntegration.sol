// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IExternalFunctionsIntegration {
    /**
     * @notice Function to obtain the encoded data for depositing.
     * @return A bytes array representing the encoded data.
     */
    function deposit(
        address asset,
        uint256 amount,
        address subconduitAddress
    ) external view returns (bytes memory);

    /**
     * @notice Function to obtain the encoded data for withdrawing.
     * @return A bytes array representing the encoded data.
     */
    function withdraw(
        address asset,
        uint256 amount,
        address subconduitAddress
    ) external view returns (bytes memory);

    /**
     * @notice Function to get the contract address involved with deposit/withdraw operations for a specific market/pool id.
     * @param subgraphPoolId The bytes representing the market/pool id on the subgraph.
     * @return The address of the associated smart contract.
     */
    function getPoolAddress(
        bytes memory subgraphPoolId
    ) external returns (address);

    /**
     * @notice Function to get a list of supported chains.
     * @return An array of uint256 representing supported chains.
     */
    function supportedChains() external view returns (uint256[] memory);

    /**
     * @notice Function to get the name of the protocol.
     * @return A string representing the protocol name.
     */
    function protocolName() external view returns (string memory);
}
