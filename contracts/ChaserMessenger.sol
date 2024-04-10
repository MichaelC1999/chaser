// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/contracts/token/ERC20/IERC20.sol";
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

    bytes32 private s_lastReceivedMessageId; // Store the last received messageId.
    string private s_lastReceivedText; // Store the last received text.

    bool public testFlag = false; // REMOVE - TESTING

    // Mapping to keep track of allowlisted destination chains.
    mapping(uint64 => bool) public allowlistedDestinationChains;

    // Mapping to keep track of allowlisted source chains.
    mapping(uint64 => bool) public allowlistedSourceChains;

    // Mapping to keep track of allowlisted senders.
    mapping(address => bool) public allowlistedSenders;

    IChaserRegistry public registry;
    IBridgeLogic bridgeFunctions;

    IERC20 private s_linkToken;

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
            s_linkToken = IERC20(_link);
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
        bool allowed
    ) public {
        // bool callerPermitted = false;
        // if (msg.sender == owner()) {
        //     callerPermitted = true;
        // }
        // if (msg.sender == address(this)) {
        //     callerPermitted = true;
        // }
        // require(
        //     callerPermitted == true,
        //     "Function only callable internally or by owner"
        // );
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
    }

    /// @dev Updates the allowlist status of a source chain for transactions.
    function allowlistSourceChain(
        uint64 _sourceChainSelector,
        bool allowed
    ) public {
        bool callerPermitted = false;
        if (msg.sender == owner()) {
            callerPermitted = true;
        }
        if (msg.sender == address(this)) {
            callerPermitted = true;
        }
        require(
            callerPermitted == true,
            "Function only callable internally or by owner"
        );
        allowlistedSourceChains[_sourceChainSelector] = allowed;
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
        onlyOwner
        onlyAllowlistedDestinationChain(_destinationChainSelector) // IMPORTANT - REMOVE THIS AND CHECK REQUIRE CHAIN SELECTOR
        returns (bytes32)
    {
        require(_receiver != address(0), "RECEIVER");
        require(_poolAddress != address(0), "POOL");
        require(address(s_linkToken) != address(0), "FEETOKEN");
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _receiver,
            _method,
            _poolAddress,
            _data,
            address(s_linkToken)
        );

        // Initialize a router client instance to interact with cross-chain router
        IRouterClient router = IRouterClient(this.getRouter());

        // Get the fee required to send the CCIP message
        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

        require(
            fees <= s_linkToken.balanceOf(address(this)),
            "Fees exceed Messenger LINK balance"
        );

        // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
        s_linkToken.approve(address(router), fees);

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
            address(s_linkToken),
            fees
        );

        return messageId;
    }

    function ccipReceiveManual(
        bytes32 messageId, // MessageId corresponding to ccipSend on source.
        bytes memory data
    ) external {
        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: messageId,
            sourceChainSelector: 0,
            sender: abi.encode(msg.sender),
            data: data,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });
        //IMPORTANT - REMOVE TESTING
        _ccipReceive(any2EvmMessage);
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

    // function _ccipReceive(
    //     Client.Any2EVMMessage memory any2EvmMessage
    // )
    //     internal
    //     override
    //     onlyAllowlisted(
    //         any2EvmMessage.sourceChainSelector,
    //         abi.decode(any2EvmMessage.sender, (address))
    //     )
    // { IMPORTANT - USE THE ABOVE COMMENTED OUT FUNCTION DEFINITION

    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override {
        s_lastReceivedMessageId = any2EvmMessage.messageId; // fetch the messageId

        // // decode any2EvmMessage.data
        (bytes4 _method, address _poolAddress, bytes memory _data) = abi.decode(
            any2EvmMessage.data,
            (bytes4, address, bytes)
        );

        // //Get the method, go through if/else conditional to call the function on the external BridgeLogic or PoolControl

        if (_method == bytes4(keccak256(abi.encode("AbPivotMovePosition")))) {
            try bridgeFunctions.executeExitPivot(_poolAddress, _data) {
                emit ExecutionMessage("AbPivotMovePosition success");
            } catch Error(string memory reason) {
                emit ExecutionMessage(reason);
            }
        }

        if (_method == bytes4(keccak256(abi.encode("AbWithdrawOrderUser")))) {
            try bridgeFunctions.userWithdrawSequence(_poolAddress, _data) {
                emit ExecutionMessage("AbWithdrawOrderUser success");
            } catch Error(string memory reason) {
                emit ExecutionMessage(reason);
            }
        }

        if (
            _method == bytes4(keccak256(abi.encode("AbMessagePositionBalance")))
        ) {
            try bridgeFunctions.sendPositionBalance(_poolAddress, bytes32("")) {
                emit ExecutionMessage("AbMessagePositionBalance success");
            } catch Error(string memory reason) {
                emit ExecutionMessage(reason);
            }
        }

        if (_method == bytes4(keccak256(abi.encode("AbMessagePositionData")))) {
            //Reads data to be sent back to pool
            testFlag = true;
            try bridgeFunctions.sendPositionData(_poolAddress) {
                emit ExecutionMessage("AbMessagePositionData success");
            } catch Error(string memory reason) {
                emit ExecutionMessage(reason);
            }
        }

        if (_method == bytes4(keccak256(abi.encode("BaMessagePositionData")))) {
            //Receives data from the position on the current position chain. Sets this to mapping state
            try IPoolControl(_poolAddress).receivePositionData(_data) {
                emit ExecutionMessage("BaMessagePositionData success");
            } catch Error(string memory reason) {
                emit ExecutionMessage(reason);
            }
        }

        if (
            _method == bytes4(keccak256(abi.encode("BaMessagePositionBalance")))
        ) {
            try IPoolControl(_poolAddress).receivePositionBalance(_data) {
                emit ExecutionMessage("BaMessagePositionBalance success");
            } catch Error(string memory reason) {
                emit ExecutionMessage(reason);
            }
        }
        if (_method == bytes4(keccak256(abi.encode("BaPositionInitialized")))) {
            try IPoolControl(_poolAddress).receivePositionInitialized(_data) {
                emit ExecutionMessage("BaPositionInitialized success");
            } catch Error(string memory reason) {
                emit ExecutionMessage(reason);
            }
        }

        if (_method == bytes4(keccak256(abi.encode("sendRegistryAddress")))) {}
        if (_method == bytes4(keccak256(abi.encode("BaPivotMovePosition")))) {
            (address marketAddress, uint256 positionAmount) = abi.decode(
                _data,
                (address, uint256)
            );

            try
                IPoolControl(_poolAddress).pivotCompleted(
                    marketAddress,
                    positionAmount
                )
            {
                emit ExecutionMessage("BaPivotMovePosition success");
            } catch Error(string memory reason) {
                emit ExecutionMessage(reason);
            }
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

    /// @notice Fetches the details of the last received message.
    /// @return messageId The ID of the last received message.
    /// @return text The last received text.
    function getLastReceivedMessageDetails()
        external
        view
        returns (bytes32 messageId, string memory text)
    {
        return (s_lastReceivedMessageId, s_lastReceivedText);
    }

    /// @notice Fallback function to allow the contract to receive Ether.
    /// @dev This function has no function body, making it a default function for receiving Ether.
    /// It is automatically called when Ether is sent to the contract without any data.
    receive() external payable {}

    /// @notice Allows the contract owner to withdraw the entire balance of Ether from the contract.
    /// @dev This function reverts if there are no funds to withdraw or if the transfer fails.
    /// It should only be callable by the owner of the contract.
    /// @param _beneficiary The address to which the Ether should be sent.
    function withdraw(address _beneficiary) public onlyOwner {
        // Retrieve the balance of this contract
        uint256 amount = address(this).balance;

        // Revert if there is nothing to withdraw
        if (amount == 0) revert NothingToWithdraw();

        // Attempt to send the funds, capturing the success status and discarding any return data
        (bool sent, ) = _beneficiary.call{value: amount}("");

        // Revert if the send failed, with information about the attempted transfer
        if (!sent) revert FailedToWithdrawEth(msg.sender, _beneficiary, amount);
    }

    /// @notice Allows the owner of the contract to withdraw all tokens of a specific ERC20 token.
    /// @dev This function reverts with a 'NothingToWithdraw' error if there are no tokens to withdraw.
    /// @param _beneficiary The address to which the tokens will be sent.
    /// @param _token The contract address of the ERC20 token to be withdrawn.
    function withdrawToken(
        address _beneficiary,
        address _token
    ) public onlyOwner {
        // Retrieve the balance of this contract
        uint256 amount = IERC20(_token).balanceOf(address(this));

        // Revert if there is nothing to withdraw
        if (amount == 0) revert NothingToWithdraw();

        IERC20(_token).transfer(_beneficiary, amount);
    }
}
