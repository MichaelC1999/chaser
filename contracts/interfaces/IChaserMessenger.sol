pragma solidity ^0.8.9;
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

interface IChaserMessenger {
    // External view functions for mappings
    function allowlistedDestinationChains(uint64) external view returns (bool);

    function allowlistedSourceChains(uint64) external view returns (bool);

    function allowlistedSenders(address) external view returns (bool);

    function registry() external view returns (address);

    function bridgeFunctions() external view returns (address);

    function _buildCCIPMessage(
        address,
        bytes4,
        address,
        bytes memory,
        address
    ) external pure returns (bytes memory);

    function ccipReceiveManual(bytes memory) external;

    function ccipDecodeReceive(
        bytes32,
        bytes memory
    ) external view returns (bytes4, address, bytes memory);

    // Events
    event MessageSent(
        bytes32 indexed,
        uint64 indexed,
        address,
        bytes,
        address,
        uint256
    );
    event MessageReceived(bytes32 indexed, uint64 indexed, address, bytes);
    event ExecutionMessage(string);

    // Function signatures
    function allowlistDestinationChain(uint64, bool) external;

    function allowlistSourceChain(uint64, bool) external;

    function allowlistSender(address, bool) external;

    function sendMessagePayLINK(
        uint64,
        address,
        bytes4,
        address,
        bytes memory
    ) external returns (bytes32);
}
