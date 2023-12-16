// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";

contract Registry {
    //Addresses managed in registry
    //Contains supported protocols/chains
    // Functions for making sure that a proposal assertion is actually supported

    constructor() {
        chainIdToSpokePoolAddress[1] = address(
            0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5
        );
        chainIdToSpokePoolAddress[10] = address(
            0x6f26Bf09B1C792e3228e5467807a900A503c0281
        );
        chainIdToSpokePoolAddress[137] = address(
            0x9295ee1d8C5b022Be115A2AD3c30C72E34e7F096
        );
        chainIdToSpokePoolAddress[324] = address(
            0xE0B015E54d54fc84a6cB9B666099c46adE9335FF
        );
        chainIdToSpokePoolAddress[8453] = address(
            0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64
        );
        chainIdToSpokePoolAddress[42161] = address(
            0xe35e9842fceaCA96570B734083f4a58e8F7C5f2A
        );

        chainIdToUmaAddress[1] = address(
            0xfb55F43fB9F48F63f9269DB7Dde3BbBe1ebDC0dE
        );
        chainIdToUmaAddress[10] = address(
            0x072819Bb43B50E7A251c64411e7aA362ce82803B
        );
        chainIdToUmaAddress[137] = address(
            0x5953f2538F613E05bAED8A5AeFa8e6622467AD3D
        );
        chainIdToUmaAddress[42161] = address(
            0xa6147867264374F324524E30C02C331cF28aa879
        );

        // TESTNET ADDRESSES
        chainIdToSpokePoolAddress[5] = address(
            0x063fFa6C9748e3f0b9bA8ee3bbbCEe98d92651f7
        ); // Can bridge 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6 to 421613
        chainIdToSpokePoolAddress[80001] = address(
            0x4589Fbf26C6a456f075b5628178AF68abE03C5fF
        );
        chainIdToSpokePoolAddress[421613] = address(
            0xd08baaE74D6d2eAb1F3320B2E1a53eeb391ce8e5
        );

        chainIdToSpokePoolAddress[11155111] = address(
            0x3baD7AD0728f9917d1Bf08af5782dCbD516cDd96
        ); // Can bridge 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9 to 421613

        chainIdToUmaAddress[5] = address(
            0x9923D42eF695B5dd9911D05Ac944d4cAca3c4EAB
        );
        chainIdToUmaAddress[80001] = address(
            0x263351499f82C107e540B01F0Ca959843e22464a
        );
    }

    mapping(address => bool) public poolEnabled;

    mapping(uint256 => address) public chainIdToBridgeConnection; //This uses CrossDeploy to create inter-chain registry of connection addresses

    mapping(uint256 => address) public chainIdToSpokePoolAddress;

    mapping(uint256 => address) public chainIdToUmaAddress;

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
