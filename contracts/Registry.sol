// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IBridgeLogic} from "./interfaces/IBridgeLogic.sol";
import {IChaserMessenger} from "./interfaces/IChaserMessenger.sol";
import {ISpokePool} from "./interfaces/ISpokePool.sol";
import {PoolBroker} from "./PoolBroker.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Registry is OwnableUpgradeable {
    event CCIPMessageSent(bytes32 indexed, bytes);
    event Marker(string);

    mapping(address => bool) public poolEnabled;

    mapping(uint256 => address) public chainIdToBridgeReceiver;

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

    mapping(uint256 => address) public addressUSDC;

    mapping(uint256 => address) public uniswapRouter;

    mapping(uint256 => address) public uniswapFactory;

    address public manager;

    address public treasuryAddress;

    address public bridgeLogicAddress;

    address public receiverAddress;

    address public integratorAddress;

    address public arbitrationContract; // The address of the arbitrationContract on the pool chain

    address public investmentStrategyContract;

    uint256 public currentChainId;

    uint256 public managerChainId;

    uint256 public poolCount;

    function initialize(
        uint256 _currentChainId,
        uint256 _managerChainId,
        address _managerAddress,
        address _treasuryAddress
    ) public initializer {
        __Ownable_init();

        //_currentChainId is the chain that this registry is currently deployed on
        //_managerChainId is the chain that has the manager contract and all of the pools
        manager = _managerAddress;

        currentChainId = _currentChainId;

        managerChainId = _managerChainId;

        treasuryAddress = _treasuryAddress;

        chainIdToUmaAddress[11155111] = address(
            0xFd9e2642a170aDD10F53Ee14a93FcF2F31924944
        );
        chainIdToUmaAddress[42161] = address(
            0xa6147867264374F324524E30C02C331cF28aa879
        );

        chainIdToSpokePoolAddress[1] = address(
            0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5
        );

        chainIdToSpokePoolAddress[42161] = address(
            0xe35e9842fceaCA96570B734083f4a58e8F7C5f2A
        );
        chainIdToSpokePoolAddress[84532] = address(
            0x82B564983aE7274c86695917BBf8C99ECb6F0F8F
        );
        chainIdToSpokePoolAddress[421614] = address(
            0x7E63A5f1a8F0B4d0934B2f2327DAED3F6bb2ee75
        );

        chainIdToSpokePoolAddress[11155111] = address(
            0x5ef6C01E11889d86803e0B23e3cB3F9E9d97B662
        );
        chainIdToSpokePoolAddress[11155420] = address(
            0x4e8E101924eDE233C13e2D8622DC8aED2872d505
        );
        chainIdToSpokePoolAddress[0] = chainIdToSpokePoolAddress[
            currentChainId
        ];

        chainIdToSelector[84532] = 10344971235874465080;
        chainIdToSelector[421614] = 3478487238524512106;
        chainIdToSelector[11155111] = 16015286601757825753;
        chainIdToSelector[11155420] = 5224473277236331295;

        chainIdToRouter[84532] = address(
            0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93
        );
        chainIdToRouter[421614] = address(
            0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165
        );
        chainIdToRouter[11155111] = address(
            0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59
        );
        chainIdToRouter[11155420] = address(
            0x114A20A10b43D4115e5aeef7345a1A71d2a60C57
        );

        chainIdToLinkAddress[84532] = address(
            0xE4aB69C077896252FAFBD49EFD26B5D171A32410
        );
        chainIdToLinkAddress[421614] = address(
            0xb1D4538B4571d411F07960EF2838Ce337FE1E80E
        );
        chainIdToLinkAddress[11155111] = address(
            0x779877A7B0D9E8603169DdbD7836e478b4624789
        );
        chainIdToLinkAddress[11155420] = address(
            0xE4aB69C077896252FAFBD49EFD26B5D171A32410
        );

        uniswapRouter[1] = address(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        uniswapRouter[42161] = address(
            0xE592427A0AEce92De3Edee1F18E0157C05861564
        );

        uniswapFactory[1] = address(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        uniswapFactory[42161] = address(
            0x1F98431c8aD98523631AE4a59f267346ea31F984
        );

        addressUSDC[1] = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

        addressUSDC[42161] = address(
            0xaf88d065e77c8cC2239327C5EDb3A432268e5831
        );
        addressUSDC[84532] = address(
            0x036CbD53842c5426634e7929541eC2318f3dCF7e
        );
        addressUSDC[421614] = address(
            0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d
        );
        addressUSDC[11155420] = address(
            0x5fd84259d66Cd46123540766Be93DFE6D43130D7
        );
        addressUSDC[11155111] = address(
            0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
        );
        addressUSDC[0] = addressUSDC[currentChainId];
    }

    function localEquivalent(
        address managerChainAssetAddress
    ) external view returns (address) {
        if (
            managerChainAssetAddress ==
            address(0x980B62Da83eFf3D4576C647993b0c1D7faf17c73)
        ) {
            return
                ISpokePool(chainIdToSpokePoolAddress[0]).wrappedNativeToken();
        }
        if (managerChainAssetAddress == addressUSDC[managerChainId]) {
            return addressUSDC[0];
        }
        return address(0);
    }

    function getDataFeed(address asset) external view returns (address) {
        if (currentChainId == 84532) {
            if (asset == address(0x4200000000000000000000000000000000000006))
                return address(0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1);
        }
        if (currentChainId == 1) {
            if (asset == address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2))
                return address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        }
        if (currentChainId == 42161) {
            if (asset == address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1))
                return address(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);
        }
        if (currentChainId == 421614) {
            if (asset == address(0x980B62Da83eFf3D4576C647993b0c1D7faf17c73))
                return address(0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165);
        }
        if (currentChainId == 11155420) {
            if (asset == address(0x4200000000000000000000000000000000000006))
                return address(0x61Ec26aA57019C486B10502285c5A3D4A4750AD7);
        }
        if (currentChainId == 11155111) {
            if (asset == address(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14))
                return address(0x694AA1769357215DE4FAC081bf1f309aDC325306);
        }
        return address(0);
    }

    function addInvestmentStrategyContract(
        address _investmentStrategyContract
    ) external onlyOwner {
        investmentStrategyContract = _investmentStrategyContract;
    }

    function addBridgeLogic(
        address _bridgeLogicAddress,
        address _messengerAddress,
        address _bridgeReceiverAddress
    ) external onlyOwner {
        bridgeLogicAddress = _bridgeLogicAddress;
        receiverAddress = _bridgeReceiverAddress;

        require(_messengerAddress != address(0), "Invalid messenger");

        _addBridgeReceiver(currentChainId, receiverAddress);
        _addMessageReceiver(currentChainId, _messengerAddress);
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

    function enableProtocol(string memory _protocol) external onlyOwner {
        bytes32 protocolHash = keccak256(abi.encode(_protocol));
        hashedProtocolToEnabled[protocolHash] = true;
        hashToProtocol[protocolHash] = _protocol;
    }

    function disableProtocol(string memory _protocol) external onlyOwner {
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
        if (managerChainId == currentChainId) {
            return poolEnabled[_poolAddress];
        }
        return true;
    }

    function enablePool(address _poolAddress) external {
        require(
            msg.sender == manager,
            "Only the manager contract may enable pools"
        );

        poolCountToPool[poolCount] = _poolAddress;
        poolCount += 1;
        poolEnabled[_poolAddress] = true;
    }

    function disablePool(address _poolAddress) external {
        require(
            msg.sender == manager,
            "Only the manager contract may enable pools"
        );
        poolEnabled[_poolAddress] = false;
    }

    function addBridgeReceiver(
        uint _chainId,
        address _receiver
    ) external onlyOwner {
        _addBridgeReceiver(_chainId, _receiver);
    }

    function _addBridgeReceiver(uint _chainId, address _receiver) internal {
        chainIdToBridgeReceiver[_chainId] = _receiver;
    }

    function addMessageReceiver(
        uint _chainId,
        address _receiver
    ) external onlyOwner {
        _addMessageReceiver(_chainId, _receiver);
    }

    function _addMessageReceiver(uint _chainId, address _receiver) internal {
        chainIdToMessageReceiver[_chainId] = _receiver;
        address messengerAddress = chainIdToMessageReceiver[currentChainId];
        IChaserMessenger(messengerAddress).allowlistSender(_receiver, true);
    }

    function addIntegrator(address _integratorAddress) external {
        require(
            msg.sender == _integratorAddress,
            "You cannot add the integrator"
        );
        require(
            integratorAddress == address(0),
            "Cannot change the integrator address once its been set"
        );
        integratorAddress = _integratorAddress;
    }

    function addArbitrationContract(
        address _arbitrationContract
    ) external onlyOwner {
        arbitrationContract = _arbitrationContract;
    }

    function deployPoolBroker(
        address _poolAddress,
        address _assetAddress
    ) external returns (address) {
        require(
            poolAddressToBroker[_poolAddress] == address(0),
            "Pool already has a broker on this chain"
        );
        require(
            msg.sender == integratorAddress,
            "Only the integrator may deploy a broker"
        );

        PoolBroker poolBroker = new PoolBroker();
        poolBroker.addConfig(_poolAddress, _assetAddress, integratorAddress);
        poolAddressToBroker[_poolAddress] = address(poolBroker);

        return poolAddressToBroker[_poolAddress];
    }

    function sendMessage(
        uint256 _chainId,
        bytes4 _method,
        address _poolAddress,
        bytes memory _data
    ) external {
        require(
            poolEnabled[msg.sender] || msg.sender == bridgeLogicAddress,
            "sendMessage function call only be actioned by a valid pool or the bridgeLogic contract"
        );

        uint64 destinationChainSelector = chainIdToSelector[_chainId];
        address localMessengerAddress = chainIdToMessageReceiver[
            currentChainId
        ];
        address messageReceiver = chainIdToMessageReceiver[_chainId];

        bytes memory data = abi.encode(_method, _poolAddress, _data);
        bytes32 messageId = bytes32(keccak256(abi.encode("CCIPMESSAGE")));

        require(messageReceiver != address(0), "RECEIVER");
        require(destinationChainSelector != 0, "Invalid Chain Selector");
        emit CCIPMessageSent(messageId, data);

        IChaserMessenger(localMessengerAddress).sendMessagePayLINK(
            destinationChainSelector,
            messageReceiver,
            _method,
            _poolAddress,
            _data
        );
    }
}
