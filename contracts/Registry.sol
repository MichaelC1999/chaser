// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IBridgeLogic} from "./interfaces/IBridgeLogic.sol";
import {IChaserMessenger} from "./interfaces/IChaserMessenger.sol";
import {PoolBroker} from "./PoolBroker.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";

contract Registry is OwnerIsCreator {
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

    address public manager;

    address public bridgeLogicAddress;

    address public receiverAddress;

    address public integratorAddress;

    address public arbitrationContract; // The address of the arbitrationContract on the pool chain

    address public investmentStrategyContract;

    uint256 public immutable currentChainId;

    uint256 public immutable managerChainId;

    uint256 public poolCount;

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

        // TESTNET ADDRESSES

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

        chainIdToUmaAddress[80001] = address(
            0x263351499f82C107e540B01F0Ca959843e22464a
        );

        chainIdToUmaAddress[11155111] = address(
            0xFd9e2642a170aDD10F53Ee14a93FcF2F31924944
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
        require(
            chainIdToBridgeReceiver[_chainId] == address(0),
            "Cannot change a receiver address that has already been set"
        );
        chainIdToBridgeReceiver[_chainId] = _receiver;
    }

    function addMessageReceiver(
        uint _chainId,
        address _receiver
    ) external onlyOwner {
        _addMessageReceiver(_chainId, _receiver);
    }

    function _addMessageReceiver(uint _chainId, address _receiver) internal {
        require(
            chainIdToMessageReceiver[_chainId] == address(0),
            "Cannot change a receiver address that has already been set"
        );
        chainIdToMessageReceiver[_chainId] = _receiver;
        address messengerAddress = chainIdToMessageReceiver[currentChainId]; // Could this be failing on polygon? currentChainId invalid or points to invalid messenger for polygon
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
        require(
            arbitrationContract == address(0),
            "Cannot change the arbitration address once its been set"
        );
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

        uint64 currentChainSelector = chainIdToSelector[currentChainId];
        uint64 destinationChainSelector = chainIdToSelector[_chainId];
        address messengerAddress = chainIdToMessageReceiver[currentChainId];
        address messageReceiver = chainIdToMessageReceiver[_chainId];

        bytes memory data = abi.encode(_method, _poolAddress, _data);
        bytes32 messageId = bytes32(keccak256(abi.encode("CCIPMESSAGE")));
        if (destinationChainSelector == 0 || currentChainSelector == 0) {
            // TESTING - CAN REMOVE
            //FOR CHAINS UNSUPPORTED BY CCIP, TEMPORARILY JUST GENERATE THE MESSAGE OBJECT FOR USER TO MANUALLY PASS

            require(_poolAddress != address(0), "POOL");

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
            return;
        }

        require(messageReceiver != address(0), "RECEIVER");
        require(destinationChainSelector != 0, "Invalid Chain Selector");
        emit CCIPMessageSent(messageId, data);

        IChaserMessenger(messengerAddress).sendMessagePayLINK(
            destinationChainSelector,
            messageReceiver,
            _method,
            _poolAddress,
            _data
        );
    }
}
