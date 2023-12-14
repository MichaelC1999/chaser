// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";

contract Registry {
    //Addresses managed in registry
    //Contains supported protocols/chains
    // Functions for making sure that a proposal assertion is actually supported

    address public acrossAddress =
        address(0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5);

    mapping(address => bool) public poolEnabled;

    mapping(uint256 => address) public chainIdToBridgeConnection; //This uses CrossDeploy to create inter-chain registry of connection addresses

    mapping(bytes32 => uint256) private hashedSlugToChainId;

    mapping(bytes32 => bool) private hashedSlugToEnabled;

    mapping(bytes32 => bool) private hashedProtocolToEnabled;

    mapping(bytes32 => bytes32) private hashedSlugToProtocolHash;

    function enableProtocol(string memory protocol) external {
        //IMPORTANT - NEEDS ACCESS CONTROL

        bytes32 protocolHash = keccak256(abi.encode(protocol));
        hashedProtocolToEnabled[protocolHash] = true;
    }

    function disableProtocol(string memory protocol) external {
        //IMPORTANT - NEEDS ACCESS CONTROL

        bytes32 protocolHash = keccak256(abi.encode(protocol));
        hashedProtocolToEnabled[protocolHash] = false;
    }

    function enableSlug(
        string memory slug,
        string memory protocol,
        uint256 chainId
    ) external {
        //IMPORTANT - NEEDS ACCESS CONTROL
        bytes32 protocolHash = keccak256(abi.encode(protocol));
        require(
            hashedProtocolToEnabled[protocolHash] == true,
            "Slug must pertain to an enabled protocol"
        );

        bytes32 hash = keccak256(abi.encode(slug));
        hashedSlugToChainId[hash] = chainId;
        hashedSlugToEnabled[hash] = true;
        hashedSlugToProtocolHash[hash] = protocolHash;
    }

    function disableSlug(string memory slug) public {
        //IMPORTANT - NEEDS ACCESS CONTROL
        bytes32 hash = keccak256(abi.encode(slug));
        hashedSlugToEnabled[hash] = false;
    }

    function slugToChainId(string memory slug) external view returns (uint256) {
        bytes32 hash = keccak256(abi.encode(slug));
        return hashedSlugToChainId[hash];
    }

    function protocolEnabled(
        string memory protocol
    ) external view returns (bool) {
        bytes32 protocolHash = keccak256(abi.encode(protocol));
        return hashedProtocolToEnabled[protocolHash];
    }

    function slugEnabled(string memory slug) external view returns (bool) {
        bytes32 hash = keccak256(abi.encode(slug));
        return hashedSlugToEnabled[hash];
    }

    function slugToProtocolHash(
        string memory slug
    ) external view returns (bytes32) {
        bytes32 hash = keccak256(abi.encode(slug));
        return hashedSlugToProtocolHash[hash];
    }

    function addPoolEnabled(address poolAddress) external {
        //IMPORTANT - NEEDS ACCESS CONTROL
        poolEnabled[poolAddress] = true;
    }

    function disablePool(address poolAddress) public {
        //IMPORTANT - NEEDS ACCESS CONTROL
        poolEnabled[poolAddress] = false;
    }

    //HOW SHOULD CROSS CHAIN DEPLOYMENT ADDRESSES BE STORED? CONNECTIONS FOR AAVE ON MAINNET ARBITRUM ETC, WHILE THE REGISTRY IS ONLY ON ARB
    // -Could keep storage on registry and pass the correct address in the bridge interaction
    // -hardcode/set/configure on the connection contract to add support for an external on another chain
}
