// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {IBridgeLogic} from "./interfaces/IBridgeLogic.sol";
import {IPoolControl} from "./interfaces/IPoolControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title - A simple messenger contract for sending/receving string data across chains.
contract ChaserMessenger is CCIPReceiver, Ownable {
    // Custom errors to provide more descriptive revert messages.
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); // Used to make sure contract has enough balance.
    error NothingToWithdraw(); // Used when trying to withdraw Ether but there's nothing to withdraw.
    error FailedToWithdrawEth(address owner, address target, uint256 value); // Used when the withdrawal of Ether fails.
    error DestinationChainNotAllowlisted(uint64 destinationChainSelector); // Used when the destination chain has not been allowlisted by the contract owner.
    error SourceChainNotAllowlisted(uint64 sourceChainSelector); // Used when the source chain has not been allowlisted by the contract owner.
    error SenderNotAllowlisted(address sender); // Used when the sender has not been allowlisted by the contract owner.

    // Event emitted when a message is sent to another chain.
    event MessageSent(
        bytes32 indexed messageId, // The unique ID of the CCIP message.
        uint64 indexed destinationChainSelector, // The chain selector of the destination chain.
        address receiver, // The address of the receiver on the destination chain.
        bytes data, // The data bytes being sent.
        address feeToken, // the token address used to pay CCIP fees.
        uint256 fees // The fees paid for sending the CCIP message.
    );

    // Event emitted when a message is received from another chain.
    event MessageReceived(
        bytes32 indexed messageId, // The unique ID of the CCIP message.
        uint64 indexed sourceChainSelector, // The chain selector of the source chain.
        address sender, // The address of the sender from the source chain.
        bytes data // The data that was received.
    );

    event ExecutionMessage(string);

    // Mapping to keep track of allowlisted destination chains.
    mapping(uint64 => bool) public allowlistedDestinationChains;

    // Mapping to keep track of allowlisted source chains.
    mapping(uint64 => bool) public allowlistedSourceChains;

    // Mapping to keep track of allowlisted senders.
    mapping(address => bool) public allowlistedSenders;

    IChaserRegistry public registry;
    IBridgeLogic public bridgeFunctions;

    IERC20 private linkToken;

    /// @notice Constructor initializes the contract with the router address.
    /// @param _router The address of the router contract.
    /// @param _link The address of the link contract.
    constructor(
        address _router,
        address _link,
        address _registry,
        address _bridgeLogicAddress,
        uint64 _sourceChainSelector
    ) CCIPReceiver(_router) {
        if (_link != address(0)) {
            linkToken = IERC20(_link);
        }
        registry = IChaserRegistry(_registry);
        bridgeFunctions = IBridgeLogic(_bridgeLogicAddress);

        allowlistSourceChain(16015286601757825753, true);
        allowlistSourceChain(12532609583862916517, true);
        allowlistSourceChain(10344971235874465080, true);
        allowlistDestinationChain(16015286601757825753, true);
        allowlistDestinationChain(12532609583862916517, true);
        allowlistDestinationChain(10344971235874465080, true);
        transferOwnership(_registry);
    }

    /// @dev Modifier that checks if the chain with the given destinationChainSelector is allowlisted.
    /// @param _destinationChainSelector The selector of the destination chain.
    modifier onlyAllowlistedDestinationChain(uint64 _destinationChainSelector) {
        if (!allowlistedDestinationChains[_destinationChainSelector])
            revert DestinationChainNotAllowlisted(_destinationChainSelector);
        _;
    }

    /// @dev Modifier that checks if the chain with the given sourceChainSelector is allowlisted and if the sender is allowlisted.
    /// @param _sourceChainSelector The selector of the destination chain.
    /// @param _sender The address of the sender.
    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (!allowlistedSourceChains[_sourceChainSelector])
            revert SourceChainNotAllowlisted(_sourceChainSelector);
        if (!allowlistedSenders[_sender]) revert SenderNotAllowlisted(_sender);
        _;
    }

    /// @dev Updates the allowlist status of a destination chain for transactions.
    function allowlistDestinationChain(
        uint64 _destinationChainSelector,
        bool _allowed
    ) internal {
        allowlistedDestinationChains[_destinationChainSelector] = _allowed;
    }

    /// @dev Updates the allowlist status of a source chain for transactions.
    function allowlistSourceChain(
        uint64 _sourceChainSelector,
        bool _allowed
    ) internal {
        allowlistedSourceChains[_sourceChainSelector] = _allowed;
    }

    /// @dev Updates the allowlist status of a sender for transactions.
    function allowlistSender(address _sender, bool allowed) external onlyOwner {
        allowlistedSenders[_sender] = allowed;
    }

    /// @notice Sends data to receiver on the destination chain.
    /// @notice Pay for fees in LINK.
    /// @dev Assumes your contract has sufficient LINK.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _receiver The address of the recipient on the destination blockchain.
    /// @param _method The method to be actioned on the receiver.
    /// @param _poolAddress The address of the pool that the message pertains to.
    /// @param _data The data to be used in the receiver for executing whatever action necessary.
    /// @return messageId The ID of the CCIP message that was sent.
    function sendMessagePayLINK(
        uint64 _destinationChainSelector,
        address _receiver,
        bytes4 _method,
        address _poolAddress,
        bytes memory _data
    )
        external
        onlyAllowlistedDestinationChain(_destinationChainSelector)
        returns (bytes32)
    {
        require(
            msg.sender == address(registry),
            "Only registry contract may execute CCIP messaging"
        );
        require(_receiver != address(0), "RECEIVER");
        require(_poolAddress != address(0), "POOL");
        require(address(linkToken) != address(0), "FEETOKEN");
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _receiver,
            _method,
            _poolAddress,
            _data,
            address(linkToken)
        );

        // Initialize a router client instance to interact with cross-chain router
        IRouterClient router = IRouterClient(this.getRouter());

        // Get the fee required to send the CCIP message
        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

        require(
            fees <= linkToken.balanceOf(address(this)),
            "Fees exceed Messenger LINK balance"
        );

        // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
        linkToken.approve(address(router), fees);

        // // Send the CCIP message through the router and store the returned CCIP message ID
        bytes32 messageId = router.ccipSend(
            _destinationChainSelector,
            evm2AnyMessage
        );

        // // Emit an event with message details
        emit MessageSent(
            messageId,
            _destinationChainSelector,
            _receiver,
            evm2AnyMessage.data,
            address(linkToken),
            fees
        );

        return messageId;
    }

    function ccipDecodeReceive(
        bytes32 messageId, // MessageId corresponding to ccipSend on source.
        bytes memory data
    ) external view returns (bytes4, address, bytes memory) {
        (bytes4 _method, address _poolAddress, bytes memory _data) = abi.decode(
            data,
            (bytes4, address, bytes)
        );

        return (_method, _poolAddress, _data);
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    )
        internal
        override
        onlyAllowlisted(
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address))
        )
    {
        (bytes4 _method, address _poolAddress, bytes memory _data) = abi.decode(
            any2EvmMessage.data,
            (bytes4, address, bytes)
        );

        if (_method == bytes4(keccak256(abi.encode("AbPivotMovePosition")))) {
            bridgeFunctions.executeExitPivot(_poolAddress, _data);
            emit ExecutionMessage("AbPivotMovePosition success");
        }

        if (_method == bytes4(keccak256(abi.encode("AbWithdrawOrderUser")))) {
            bridgeFunctions.userWithdrawSequence(_poolAddress, _data);
            emit ExecutionMessage("AbWithdrawOrderUser success");
        }

        if (
            _method == bytes4(keccak256(abi.encode("BaMessagePositionBalance")))
        ) {
            IPoolControl(_poolAddress).receivePositionBalance(_data);
            emit ExecutionMessage("BaMessagePositionBalance success");
        }

        if (_method == bytes4(keccak256(abi.encode("BaPositionInitialized")))) {
            IPoolControl(_poolAddress).receivePositionInitialized(_data);
            emit ExecutionMessage("BaPositionInitialized success");
        }

        if (_method == bytes4(keccak256(abi.encode("BaPivotMovePosition")))) {
            (address marketAddress, uint256 positionAmount) = abi.decode(
                _data,
                (address, uint256)
            );

            IPoolControl(_poolAddress).pivotCompleted(
                marketAddress,
                positionAmount
            );
            emit ExecutionMessage("BaPivotMovePosition success");
        }

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
            any2EvmMessage.data
        );
    }

    /// @notice Construct a CCIP message.
    /// @dev This function will create an EVM2AnyMessage struct with all the necessary information for sending a text.
    /// @param _receiver The address of the receiver.
    /// @param _method The method to be actioned on the receiver.
    /// @param _poolAddress The address of the pool that the message pertains to.
    /// @param _data The data to be used in the receiver for executing whatever action necessary.
    /// @param _feeTokenAddress The address of the token used for fees. Set address(0) for native gas.
    /// @return Client.EVM2AnyMessage Returns an EVM2AnyMessage struct which contains information for sending a CCIP message.
    function _buildCCIPMessage(
        address _receiver,
        bytes4 _method,
        address _poolAddress,
        bytes memory _data,
        address _feeTokenAddress
    ) public pure returns (Client.EVM2AnyMessage memory) {
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        bytes memory data = abi.encode(_method, _poolAddress, _data);

        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(_receiver), // ABI-encoded receiver address
                data: data,
                tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array aas no tokens are transferred
                extraArgs: Client._argsToBytes(
                    // Additional arguments, setting gas limit
                    Client.EVMExtraArgsV1({gasLimit: 2_000_000})
                ),
                // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
                feeToken: _feeTokenAddress
            });
    }
}
