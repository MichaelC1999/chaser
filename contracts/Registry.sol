// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {BridgeReceiver} from "./BridgeReceiver.sol";
import {BridgeLogic} from "./BridgeLogic.sol";
import {IBridgeLogic} from "./interfaces/IBridgeLogic.sol";
import {IChaserMessenger} from "./interfaces/IChaserMessenger.sol";
import {PoolBroker} from "./PoolBroker.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

contract Registry is OwnerIsCreator {
    //Contains supported protocols/chains
    // Functions for making sure that a proposal assertion is actually supported

    event CCIPMessageSent(bytes32 indexed, bytes);
    event Marker(string);
    event MessageMethod(bytes4);

    constructor(
        uint256 _currentChainId,
        uint256 _managerChainId,
        address _managerAddress
    ) {
        //_currentChainId is the chain that this registry is currently deployed on
        //_managerChainId is the chain that has the manager contract and all of the pools
        if (_currentChainId == _managerChainId) {
            manager = _managerAddress;
        }

        currentChainId = _currentChainId;

        managerChainId = _managerChainId;

        // chainIdToSpokePoolAddress[1] = address(
        //     0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5
        // );
        // chainIdToSpokePoolAddress[10] = address(
        //     0x6f26Bf09B1C792e3228e5467807a900A503c0281
        // );
        // chainIdToSpokePoolAddress[137] = address(
        //     0x9295ee1d8C5b022Be115A2AD3c30C72E34e7F096
        // );
        // chainIdToSpokePoolAddress[324] = address(
        //     0xE0B015E54d54fc84a6cB9B666099c46adE9335FF
        // );
        // chainIdToSpokePoolAddress[8453] = address(
        //     0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64
        // );
        // chainIdToSpokePoolAddress[42161] = address(
        //     0xe35e9842fceaCA96570B734083f4a58e8F7C5f2A
        // );

        // chainIdToUmaAddress[1] = address(
        //     0xfb55F43fB9F48F63f9269DB7Dde3BbBe1ebDC0dE
        // );
        // chainIdToUmaAddress[10] = address(
        //     0x072819Bb43B50E7A251c64411e7aA362ce82803B
        // );
        // chainIdToUmaAddress[137] = address(
        //     0x5953f2538F613E05bAED8A5AeFa8e6622467AD3D
        // );
        chainIdToUmaAddress[11155111] = address(
            0xFd9e2642a170aDD10F53Ee14a93FcF2F31924944
        );

        // TESTNET ADDRESSES
        chainIdToSpokePoolAddress[1337] = address(
            0x063fFa6C9748e3f0b9bA8ee3bbbCEe98d92651f7
        );

        chainIdToSpokePoolAddress[5] = address(
            0x063fFa6C9748e3f0b9bA8ee3bbbCEe98d92651f7
        ); // Can bridge 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6 to 421613
        chainIdToSpokePoolAddress[80001] = address(
            0x4589Fbf26C6a456f075b5628178AF68abE03C5fF
        );

        chainIdToSpokePoolAddress[84532] = address(
            0x82B564983aE7274c86695917BBf8C99ECb6F0F8F
        );
        chainIdToSpokePoolAddress[421613] = address(
            0xd08baaE74D6d2eAb1F3320B2E1a53eeb391ce8e5
        );

        chainIdToSpokePoolAddress[11155111] = address(
            0x5ef6C01E11889d86803e0B23e3cB3F9E9d97B662
        );

        chainIdToSpokePoolAddress[0] = chainIdToSpokePoolAddress[
            currentChainId
        ];

        chainIdToUmaAddress[5] = address(
            0x9923D42eF695B5dd9911D05Ac944d4cAca3c4EAB
        );
        chainIdToUmaAddress[80001] = address(
            0x263351499f82C107e540B01F0Ca959843e22464a
        );

        chainIdToSelector[84532] = 10344971235874465080;

        chainIdToSelector[11155111] = 16015286601757825753;

        chainIdToSelector[80001] = 12532609583862916517;

        chainIdToRouter[11155111] = address(
            0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59
        );
        chainIdToRouter[80001] = address(
            0x1035CabC275068e0F4b745A29CEDf38E13aF41b1
        );
        chainIdToRouter[84532] = address(
            0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93
        );

        chainIdToLinkAddress[11155111] = address(
            0x779877A7B0D9E8603169DdbD7836e478b4624789
        );
        chainIdToLinkAddress[80001] = address(
            0x326C977E6efc84E512bB9C30f76E30c160eD06FB
        );

        chainIdToLinkAddress[84532] = address(
            0xE4aB69C077896252FAFBD49EFD26B5D171A32410
        );
    }

    mapping(address => bool) public poolEnabled;

    mapping(uint256 => address) public chainIdToBridgeReceiver; //This uses CrossDeploy to create inter-chain registry of connection addresses

    mapping(uint256 => address) public chainIdToMessageReceiver;

    mapping(uint256 => address) public chainIdToSpokePoolAddress;

    mapping(uint256 => address) public chainIdToRouter;

    mapping(uint256 => address) public chainIdToLinkAddress;

    mapping(uint256 => uint64) public chainIdToSelector; // Chain Id to the LayerZero endpoint Id

    mapping(uint256 => address) public chainIdToUmaAddress;

    mapping(bytes32 => bool) private hashedProtocolToEnabled;

    mapping(bytes32 => string) public hashToProtocol;

    mapping(uint256 => address) public poolCountToPool;

    mapping(address => address) public poolAddressToBroker;

    address public manager;

    address public bridgeLogicAddress;

    address public receiverAddress;

    address public integratorAddress;

    address public arbitrationContract; // The address of the arbitrationContract on the pool chain

    address public investmentStrategyContract;

    uint256 public currentChainId;

    uint256 public managerChainId;

    uint256 public poolCount = 0;

    function addInvestmentStrategyContract(
        address _investmentStrategyContract
    ) external {
        investmentStrategyContract = _investmentStrategyContract;
    }

    function addBridgeLogic(
        address _bridgeLogicAddress,
        address _messengerAddress,
        address _bridgeReceiverAddress
    ) external onlyOwner {
        // require(
        //     msg.sender == manager,
        //     "Only Manager may call deployBridgeReceiver"
        // );

        bridgeLogicAddress = _bridgeLogicAddress;

        receiverAddress = _bridgeReceiverAddress;

        require(_messengerAddress != address(0), "Invalid messenger");

        addMessageReceiver(currentChainId, _messengerAddress);
        addBridgeReceiver(currentChainId, receiverAddress);
    }

    function localCcipConfigs()
        external
        view
        returns (address, address, uint256)
    {
        address chainlinkRouter = chainIdToRouter[currentChainId];
        address linkAddress = chainIdToLinkAddress[currentChainId];
        uint64 selector = chainIdToSelector[currentChainId];

        return (chainlinkRouter, linkAddress, selector);
    }

    function enableProtocol(string memory _protocol) external {
        //IMPORTANT - NEEDS ACCESS CONTROL

        bytes32 protocolHash = keccak256(abi.encode(_protocol));
        hashedProtocolToEnabled[protocolHash] = true;
        hashToProtocol[protocolHash] = _protocol;
    }

    function disableProtocol(string memory _protocol) external {
        //IMPORTANT - NEEDS ACCESS CONTROL

        bytes32 protocolHash = keccak256(abi.encode(_protocol));
        hashedProtocolToEnabled[protocolHash] = false;
    }

    function protocolEnabled(
        string memory _protocol
    ) external view returns (bool) {
        bytes32 protocolHash = keccak256(abi.encode(_protocol));
        return hashedProtocolToEnabled[protocolHash];
    }

    function checkValidPool(address _poolAddress) external view returns (bool) {
        // If chain is not the manager chain, assume the pool is valid
        if (managerChainId == currentChainId) {
            return poolEnabled[_poolAddress];
        }
        return true;
    }

    function addPoolEnabled(address _poolAddress) external {
        //IMPORTANT - NEEDS ACCESS CONTROL
        poolCountToPool[poolCount] = _poolAddress;
        poolCount += 1;
        poolEnabled[_poolAddress] = true;
    }

    function disablePool(address _poolAddress) public {
        //IMPORTANT - NEEDS ACCESS CONTROL
        poolEnabled[_poolAddress] = false;
    }

    function addBridgeReceiver(uint _chainId, address _receiver) public {
        //IMPORTANT - NEEDS ACCESS CONTROL

        chainIdToBridgeReceiver[_chainId] = _receiver;
    }

    function addMessageReceiver(uint _chainId, address _receiver) public {
        //IMPORTANT - NEEDS ACCESS CONTROL

        chainIdToMessageReceiver[_chainId] = _receiver;
        address messengerAddress = chainIdToMessageReceiver[currentChainId]; // Could this be failing on polygon? currentChainId invalid or points to invalid messenger for polygon
        IChaserMessenger(messengerAddress).allowlistSender(_receiver, true);
    }

    function addIntegrator(address _integratorAddress) external {
        //IMPORTANT - NEEDS ACCESS CONTROL

        integratorAddress = _integratorAddress;
    }

    function sendMessage(
        uint256 _chainId,
        bytes4 _method,
        address _poolAddress,
        bytes memory _data
    ) external {
        //Pool/BridgeLogic calls this function to send message, letting the registry verify that the Pool/Logic contract is legitimate
        // IMPORTANT - PERFORM ACCESS CONTROL HERE
        address poolAddress = msg.sender;
        if (msg.sender == bridgeLogicAddress) {
            poolAddress = _poolAddress;
        } else {
            require(
                poolEnabled[poolAddress] == true,
                "SendMessage may only be actioned by a valid pool"
            );
        }

        uint64 currentChainSelector = chainIdToSelector[currentChainId];
        uint64 destinationChainSelector = chainIdToSelector[_chainId];
        address messengerAddress = chainIdToMessageReceiver[currentChainId];
        address messageReceiver = chainIdToMessageReceiver[_chainId];

        bytes memory data = abi.encode(_method, _poolAddress, _data);
        bytes32 messageId = bytes32(keccak256(abi.encode("CCIPMESSAGE")));
        if (destinationChainSelector == 0 || currentChainSelector == 0) {
            // TESTING - CAN REMOVE
            //FOR CHAINS UNSUPPORTED BY CCIP, TEMPORARILY JUST GENERATE THE MESSAGE OBJECT FOR USER TO MANUALLY PASS

            require(poolAddress != address(0), "POOL");

            emit CCIPMessageSent(messageId, data);
            emit Marker("Above Log is CCIP Message, below is method sent");
            (
                bytes4 decmethod,
                address decpoolAddress,
                bytes memory decdata
            ) = IChaserMessenger(messengerAddress).ccipDecodeReceive(
                    messageId,
                    data
                );
            emit MessageMethod(decmethod);
            return;
        }

        require(messageReceiver != address(0), "RECEIVER");
        require(destinationChainSelector != 0, "Invalid Chain Selector");
        emit CCIPMessageSent(messageId, data);

        IChaserMessenger(messengerAddress).sendMessagePayLINK(
            destinationChainSelector,
            messageReceiver,
            _method,
            poolAddress,
            _data
        );
    }

    function getPoolBroker(
        address _poolAddress,
        address _assetAddress
    ) public returns (address) {
        address instance;
        // poolBroker lookup function
        //If _poolAddress does not have its equivalent on this chain, deploy a broker
        if (poolAddressToBroker[_poolAddress] == address(0)) {
            PoolBroker poolBroker = new PoolBroker();
            poolBroker.addConfig(
                _poolAddress,
                _assetAddress,
                integratorAddress
            );
            poolAddressToBroker[_poolAddress] = address(poolBroker);
        }

        return poolAddressToBroker[_poolAddress];
    }

    function addArbitrationContract(address _arbitrationContract) external {
        arbitrationContract = _arbitrationContract;
    }
}
