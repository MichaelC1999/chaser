// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ExternalFunctionConstructor {
    // THIS WILL BE DEPLOYED ON MAINNET
    // ASSUMES ALL DEPLOYMENTS ON VARIOUS CHAINS HAVE THE SAME FUNCTION SIGNATURES TO DEPOSIT/WITHDRAW
    // THIS ALSO ALLOWS FOR PROCESSING POOL IDS BEFORE SAVING TO STATE

    constructor() {}

    // function deposit() external view returns (memory bytes) {
    //     // Implementation

    // }

    // function withdraw() external view returns (memory bytes) {
    //     // Implementation
    // }

    // function getPoolAddress(bytes subgraphPoolId) public returns (address) {
    //     // This function takes in the bytes for the market/pool id on the subgraph and returns the address of the smart contract involved with deposit/withdraw operations
    // }

    // function updateDepositInputs() external {
    //     // This function updates the hardcoded inputs saved to make the interactions depositing from external protocol
    // }

    // function updateWithdrawInputs() external {
    //     // This function updates the hardcoded inputs saved to make the interactions depositing from external protocol
    // }
}
