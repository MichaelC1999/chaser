// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./PoolToken.sol";
import {ISpokePool} from "./interfaces/ISpokePool.sol";
import {IChaserRegistry} from "./interfaces/IChaserRegistry.sol";
import {IBridgedConnector} from "./interfaces/IBridgedConnector.sol";
import {IChaserRouter} from "./interfaces/IChaserRouter.sol";
import {IChaserManager} from "./ChaserManager.sol";
import {ArbitrationContract} from "./ArbitrationContract.sol";

contract PoolControl {
    uint256 localChain;
    bytes32 poolId;
    address deployingUser;
    uint256 public poolNonce = 0;
    string public poolName;
    string public strategySource; // STRATEGY SOURCE CAN BE A REPO URL WITH CODE TO EXECUTE, OR THIS STRING COULD POINT TO AN ADDRESS/CHAIN/METHOD THAT RETURNS THE INSTRUCTIONS

    IChaserRouter public router;
    IBridgedConnector public localBridgedConnector;
    IChaserManager public manager;
    IChaserRegistry public registry;
    PoolToken public poolToken;
    ERC20 public asset;

    event PivotOrder(address, uint256, bytes32);
    event DepositRecorded(bytes32, uint256);
    event WithdrawRecorded(bytes32, uint256);
    event AcrossMessageSent(bytes);
    event LzMessageSent(bytes4, bytes);
    event Numbers(uint256, uint256);

    mapping(bytes32 => address) depositIdToDepositor;
    mapping(bytes32 => uint256) depositIdToDepositAmount;
    mapping(bytes32 => bool) depositIdToTokensMinted;

    mapping(bytes32 => address) withdrawIdToDepositor;
    mapping(bytes32 => uint256) withdrawIdToDepositAmount;
    mapping(address => bool) userHasPendingWithdraw;

    mapping(bytes32 => string) public assertionToRequestedPoolId;
    mapping(bytes32 => string) public assertionToRequestedProtocol;

    // POSITION STATE
    //State contains position target, current position location and last position location (for failed bridge handling)
    // target state is for holding the position to pivot to. This facilitates the new position to enter

    address targetPositionAddress; //THE MARKET ADDRESS THAT WILL BE PASSED TO BRIDGECONNECTION, NOT THE FINAL ADDRESS THAT FUNDS ARE ACTUALLY HELD IN
    uint256 targetPositionChain;
    bytes32 targetPositionProtocolHash;

    // current state holds the position that funds are currently deposited into. This facilitates withdraws. Current state gets set as chaser + address(this) when the bridge request to withdraw has been sent
    address currentPositionAddress;
    uint256 currentPositionChain = 80001; //IMPORTANT - CURRENT HARDCODED BEFORE PIVOT FUNCTIONALITY
    bytes32 currentPositionProtocolHash;
    uint256 currentRecordPositionValue; //This holds the most recently recorded value of the entire position sent from the current position chain.

    // last state holds the previous position data. In the case of error while bridging, this is to rescue funds
    address lastPositionAddress;
    uint256 lastPositionChain;
    bytes32 lastPositionProtocolHash;

    bytes32 currentPositionAssertion;
    bool pivotPending = false;

    struct Origin {
        uint32 srcEid; // The source chain's Endpoint ID.
        bytes32 sender; // The sending OApp address.
        uint64 nonce; // The message nonce for the pathway.
    }

    /**
     * @notice Initial pool configurations and address caching
     * @param _deployingUser The address that called the pool deployment from the manager contract
     * @param _asset The asset that is being invested in this pool
     * @param _strategySource The source of the strategy for determining investment
     * @param _poolName The name of the pool
     * @param _localChain The integer Chain ID of this pool
     */
    constructor(
        address _deployingUser,
        address _asset,
        string memory _strategySource,
        string memory _poolName,
        uint256 _localChain
    ) {
        localChain = _localChain;
        poolId = keccak256(abi.encode(address(this), _poolName));
        poolName = _poolName;
        deployingUser = _deployingUser;
        asset = ERC20(_asset);
        strategySource = _strategySource;
        manager = IChaserManager(address(msg.sender));
        registry = IChaserRegistry(manager.viewRegistryAddress());
        localBridgedConnector = IBridgedConnector(
            registry.chainIdToBridgedConnector(localChain)
        );
        router = IChaserRouter(localBridgedConnector.chaserRouter());
    }

    /**
     * @notice Handles methods called from another chain through LZ. Router contract receives the message and calls pool methods through this function
     * @param _method The name of the method that was called from the other chain
     * @param _data The data to be calculated upon in the method
     */
    function receiveHandler(bytes4 _method, bytes memory _data) external {
        //IMPORTANT - Should only be callable by pool router
        // require(msg.sender != address(router), "");

        if (
            _method ==
            bytes4(keccak256(abi.encode("readPositionBalanceResult")))
        ) {
            // Decode the payload data
            (uint256 positionAmount, bytes32 depositId) = abi.decode(
                _data,
                (uint256, bytes32)
            );
            //Receives the current value of the entire position. Sets this to a contract wide state (or mapping with timestamp => uint balance, and save timestamp to contract wide state)

            currentRecordPositionValue = positionAmount;
            if (depositId != bytes32("")) {
                mintUserPoolTokens(depositId, positionAmount);
            }

            //If depositId included in the payload data, mint position tokens for user
            //Check mapping if depositId has minted position tokens yet
        }
        if (
            _method == bytes4(keccak256(abi.encode("readPositionDataResult")))
        ) {
            //Receives data from the position on the current position chain. Sets this to mapping state
        }
        if (
            _method ==
            bytes4(keccak256(abi.encode("readRegistryAddressResult")))
        ) {
            //Receives the current address of an upgradeable contract on another chain. Sets this to a mapping state
        }
    }

    /**
     * @notice Standard Across Message reception
     * @dev This function separates messages by method and executes the different logic for each based off of the first 4 bytes of the message
     */
    function handleAcrossMessage(
        address tokenSent,
        uint256 amount,
        bool fillCompleted,
        address relayer,
        bytes memory message
    ) external {
        // IMPORTANT: HOW CAN I ACCESS CONTROL THIS FUNCTION TO ONLY BE CALLABLE BY SPOKE POOL? require msg.sender == spoke pool address
        // IMPORTANT: THESE INTERNAL FUNCTIONS SHOULD BE MOVED TO A SEPARATE CONTRACT - IF THEY FAIL, THE TX WONT REVERT. THESE if{} SECTIONS SHOULD CACHE THE AMOUNT AND MESSAGE DATA FOR RETRY

        // Separate method from message data
        (bytes4 method, bytes memory data) = abi.decode(
            message,
            (bytes4, bytes)
        );

        if (method == bytes4(keccak256(abi.encode("poolReturn")))) {
            // Receive the entire pool's funds if there are no currently viable markets or if the pool is disabled
        }
        if (method == bytes4(keccak256(abi.encode("userWithdrawOrder")))) {
            //Take amount in asset sent through bridge and totalAvailableForUser, take this proportion
            //Burn the users pool tokens based off this proportion
            //Send user their tokens
            (bytes32 withdrawId, uint256 totalAvailableForUser) = abi.decode(
                data,
                (bytes32, uint256)
            );

            address depositor = withdrawIdToDepositor[withdrawId];

            uint256 userPoolTokenBalance = poolToken.balanceOf(depositor);
            // asset/totalAvailableForUser=x/userPoolTokenBalance

            // IMPORTANT - IF totalAvailableForUser IS VERY CLOSE TO amount, MAKE amount = totalAvailableForUser
            if (totalAvailableForUser < amount) {
                amount = totalAvailableForUser; // IMPORTANT - IF THE CALCULATED TOTAL AVAILABLE FOR USER IS LESS THAN THE AMOUNT BRIDGED BACK, ONLY TRANSFER THE CALCULATED AMOUNT TO USER
            }
            //COULD IT BE AMOUNT SENT IN THE BRIDGE FROM CONNECTOR?

            uint256 poolTokensToBurn = userPoolTokenBalance;
            if (totalAvailableForUser > 0) {
                uint256 ratio = (amount * (10 ** 18)) / (totalAvailableForUser);
                poolTokensToBurn = (ratio * userPoolTokenBalance) / (10 ** 18);
            }

            poolNonce += 1;

            userHasPendingWithdraw[depositor] = false;
            poolToken.burn(depositor, poolTokensToBurn);
            asset.transfer(depositor, amount);
        }
    }

    /**
     * @notice The user-facing function for beginning the withdraw sequence
     * @dev This function is the "A" of the "A=>B=>A" sequence of withdraws
     * @dev On this chain we don't have access to the current position value after gains. If the amount specified is over the proportion available with user's pool tokens, withdraw the maximum proportion
     * @param _amount The amount to withdraw, denominated in the pool asset
     */
    function userWithdrawOrder(uint256 _amount) external {
        //IMPORTANT - Since we dont know the actual amount of pool tokens to be burnt from the withdraw, we should lock withdraws from the user until all pending withdraws are completed
        require(
            userHasPendingWithdraw[msg.sender] == false,
            "User may only open new withdraw order if they do not have a pending withdraw order"
        );
        bytes32 withdrawId = keccak256(
            abi.encode(msg.sender, _amount, block.timestamp)
        );

        withdrawIdToDepositor[withdrawId] = msg.sender;
        withdrawIdToDepositAmount[withdrawId] = _amount;
        userHasPendingWithdraw[msg.sender] = true;

        emit WithdrawRecorded(withdrawId, _amount);

        uint256 userPoolTokenBalance = poolToken.balanceOf(msg.sender);
        require(userPoolTokenBalance > 0, "User has no deposits in pool");
        uint256 poolTokenSupply = poolToken.totalSupply();

        uint256 scaledRatio = (10 ** 18); // scaledRatio defaults to 1, if the user has all pool tokens
        if (userPoolTokenBalance != poolTokenSupply) {
            scaledRatio =
                (userPoolTokenBalance * (10 ** 18)) /
                (poolTokenSupply);
        }

        bytes memory data = abi.encode(
            withdrawId,
            address(this),
            _amount,
            poolNonce,
            scaledRatio
        );

        bytes memory options;
        bytes4 method = bytes4(keccak256(abi.encode("userWithdrawOrder")));

        emit LzMessageSent(method, data);

        router.send(
            registry.chainIdToEndpointId(currentPositionChain),
            method,
            false,
            address(this),
            data,
            options
        );
    }

    /**
     * @notice After pivot was successfully asserted, send the execution request for the pivot
     */
    function pivotPosition() external {
        // Send message to BridgedConnector on new target position chain, with instructions to move funds to new position
        // Uses lzSend to send message with instructions on how to handle pivot

        bytes memory data;
        bytes memory options;

        router.send(
            registry.chainIdToEndpointId(currentPositionChain),
            bytes4(keccak256(abi.encode("pivotPosition"))),
            false,
            address(this),
            data,
            options
        );
    }

    /**
     * @notice Send a request to the position chain for the up to date value of the position (including any gains)
     */
    function readPositionBalance() external {
        // Get the value of the entire position for the pool with gains
        // Uses lzSend to send message to request this data be sent back
        bytes4 method = bytes4(keccak256("readPositionBalance"));
        bytes memory data;
        bytes memory options;

        router.send(
            registry.chainIdToEndpointId(currentPositionChain),
            method,
            false,
            address(this),
            data,
            options
        );
    }

    /**
     * @notice Send a request to the position chain for arbitrary data about the position
     */
    function getPositionData() external {
        // Uses lzSend to request position data be sent back

        bytes memory data;
        bytes memory options;

        router.send(
            registry.chainIdToEndpointId(currentPositionChain),
            bytes4(keccak256(abi.encode("getPositionData"))),
            false,
            address(this),
            data,
            options
        );
    }

    /**
     * @notice Send a request to the position chain to get an address from its' registry
     */
    function getRegistryAddress() external {
        // Uses lzSend to request an address from the registry on another chain
        bytes memory data;
        bytes memory options;

        router.send(
            registry.chainIdToEndpointId(currentPositionChain),
            bytes4(keccak256(abi.encode("getRegistryAddress"))),
            false,
            address(this),
            data,
            options
        );
    }

    /**
     * @notice Make the first deposit on the pool and set up the first position. This is a function meant to be called from a user/investing entity.
     * @notice This function simultaneously sets the first position and deposits the first funds
     * @notice After executing, other functions are called withdata generated in this function, in order to direction the position entrance
     * @param _amount The amount of the initial deposit
     * @param _relayFeePct The Across Bridge relay fee %
     * @param _currentPositionAddress The address to be passed to the integration function for investment entrance
     * @param _currentPositionChain The destination chain on which the first position exists
     * @param _currentPositionProtocolHash The protocol that the position is made on
     */
    function userDepositAndSetPosition(
        uint256 _amount,
        int64 _relayFeePct,
        address _currentPositionAddress,
        uint256 _currentPositionChain,
        bytes32 _currentPositionProtocolHash
    ) public {
        // This is for the initial deposit and position set up after pool creation
        require(
            msg.sender == deployingUser,
            "Only deploying user can set position and deposit"
        );
        require(
            poolNonce == 0,
            "The position may only be set before the first deposit has settled"
        );

        // Set the current position values
        currentPositionAddress = _currentPositionAddress;
        currentPositionChain = _currentPositionChain;
        currentPositionProtocolHash = _currentPositionProtocolHash;

        // Generate a deposit ID
        bytes32 depositId = keccak256(
            abi.encode(msg.sender, _amount, block.timestamp)
        );

        // Map deposit ID to depositor and deposit amount
        depositIdToDepositor[depositId] = msg.sender;
        depositIdToDepositAmount[depositId] = _amount;
        depositIdToTokensMinted[depositId] = false;

        emit DepositRecorded(depositId, _amount);

        // Encode the data including position details
        bytes memory data = abi.encode(
            depositId,
            msg.sender,
            currentPositionAddress,
            currentPositionProtocolHash
        );

        emit PivotOrder(
            currentPositionAddress,
            currentPositionChain,
            currentPositionProtocolHash
        );

        enterFundsCrossChain(depositId, _relayFeePct, true, data);
    }

    /**
     * @notice Make a deposit on the pool
     * @dev This function creates the deposit data and routes the function call depending on whether or not the position is local or cross chain
     * @param _amount The amount of the deposit
     * @param _relayFeePct The Across Bridge relay fee % (irrelevant if local deposit)
     */
    function userDeposit(uint256 _amount, int64 _relayFeePct) public {
        bytes32 depositId = keccak256(
            abi.encode(msg.sender, _amount, block.timestamp)
        );

        depositIdToDepositor[depositId] = msg.sender;
        depositIdToDepositAmount[depositId] = _amount;
        depositIdToTokensMinted[depositId] = false;

        emit DepositRecorded(depositId, _amount);

        if (currentPositionChain == localChain) {
            enterFundsLocalChain(depositId);
        } else {
            enterFundsCrossChain(depositId, _relayFeePct, false, "");
        }
    }

    function dummyUserDeposit(uint256 amount, int64 _relayFeePct) public {
        bytes32 depositId = keccak256(
            abi.encode(
                address(0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199),
                amount,
                block.timestamp
            )
        );

        depositIdToDepositor[depositId] = address(
            0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199
        );
        depositIdToDepositAmount[depositId] = amount;
        depositIdToTokensMinted[depositId] = false;

        emit DepositRecorded(depositId, amount);

        if (currentPositionChain == localChain) {
            enterFundsLocalChain(depositId);
        } else {
            enterFundsCrossChain(depositId, _relayFeePct, false, "");
        }
    }

    /**
     * @notice Complete the process of sending funds to a local BridgedConnector fr entering the position
     * @dev This function does not use the Bridge or cross chain communication for execution
     * @param _depositId The id of the deposit, used for data lookup
     */
    function enterFundsLocalChain(bytes32 _depositId) internal {
        address sender = depositIdToDepositor[_depositId];
        uint256 amount = depositIdToDepositAmount[_depositId];

        uint256 poolPositionAmount = 0;
        address currentConnectionAddress = registry.chainIdToBridgedConnector(
            currentPositionChain
        );
        if (currentPositionAddress == address(this)) {
            // -funds are currently in this pool
            // --TransferFrom sender to address(this)
            asset.transferFrom(sender, address(this), amount);
            // --Measure ERC20(asset).balanceOf(address(this)), get proportion of amount to the full balance of this pool
            poolPositionAmount = asset.balanceOf(address(this));
        } else {
            // -funds are in a connection/external on same chain
            uint256 positionValueBeforeDeposit = 0;

            // --read full position amount, get proportion of deposit to full position
            poolPositionAmount = positionValueBeforeDeposit + amount;

            // --deposit funds into position
            asset.transferFrom(sender, currentConnectionAddress, amount);
            // --Call function on connection to deposit funds into external protocol
        }
        // -Perform checks that the funds were transfered (wouldnt the tx fail if user didnt actually transfer?)
        // -mint tokens according to proportion
        mintUserPoolTokens(_depositId, poolPositionAmount);
    }

    /**
     * @notice Complete the process of sending funds to the BridgedConnector on another chain for entering the position
     * @dev This function is the first "A" step of the "A=>B=>A" deposit sequence
     * @param _depositId The id of the deposit, used for data lookup
     * @param _relayFeePct The Across Bridge relay fee %
     * @param _isInitializer Boolean that determines whether or not the call is setting the first position
     * @param _data Bytes that are passed in the Across "message" parameter, particularly to help set the position
     */
    function enterFundsCrossChain(
        bytes32 _depositId,
        int64 _relayFeePct,
        bool _isInitializer,
        bytes memory _data
    ) internal {
        require(
            pivotPending == false,
            "If a pivot proposal has been approved, no cross-chain position entrances are allowed"
        );

        address sender = depositIdToDepositor[_depositId];
        uint256 amount = depositIdToDepositAmount[_depositId];

        // fund entrance can automatically bridge into position.
        address acrossSpokePool = registry.chainIdToSpokePoolAddress(
            currentPositionChain
        );

        // Take the sucessfully proposed position, input into a registry function to get Bridge Connection address for its chain
        address bridgedConnector = registry.chainIdToBridgedConnector(
            currentPositionChain
        );

        bytes4 method = bytes4(keccak256(abi.encode("userDeposit")));

        if (_isInitializer == true) {
            method = bytes4(keccak256(abi.encode("positionInitializer")));
        } else {
            _data = abi.encode(_depositId, sender);
        }

        bytes memory message = abi.encode(method, address(this), _data);

        // Approval made from sender to this contract
        // spokePoolPreparation makes approval for spokePool
        spokePoolPreparation(sender, amount);

        emit AcrossMessageSent(message);

        //When assertion is settled, pivotPending state is true and no deposits are allowed until new position is successfully engaged
        // ISpokePool(acrossSpokePool).deposit(
        //     bridgedConnector,
        //     assetAddress,
        //     amount,
        //     currentPositionChain,
        //     _relayFeePct,
        //     uint32(block.timestamp),
        //     message,
        //     (2 ** 256 - 1)
        // );
    }

    /**
     * @notice IMPORTANT - TESTING FUNCTION, CAN DELETE. THIS IS FOR MAKING A DUMMY ACROSS WITHDRAW MESSAGE
     * @param _method The method to call in message
     * @param _withdrawId The id of the withdraw, for data lookup
     * @param _totalAvailableWithdraw The total amount of assets that are available for user to withdraw
     */
    function generateAcrossMessage(
        string memory _method,
        bytes32 _withdrawId,
        uint256 _totalAvailableWithdraw
    ) external view returns (bytes memory) {
        bytes4 method = bytes4(keccak256(abi.encode(_method)));
        bytes memory data = abi.encode(_withdrawId, _totalAvailableWithdraw);
        return (abi.encode(method, data));
    }

    function chaserPosition(bytes32 assertionId) external {
        //IMPORTANT - CHANGE TO LZ SEND

        // This function makes the call to the BridgedConnector that is holding pool deposits, passing in the new chain/pool to move deposits to
        //Can only be called by Arbitration contract
        currentPositionAssertion = assertionId;
        address arbitrationContract = registry.arbitrationContract();
        require(
            msg.sender == arbitrationContract,
            "chaserPosition() may only be called by the arbitration contract"
        );

        string memory requestPoolId = assertionToRequestedPoolId[assertionId];
        string memory requestProtocolSlug = assertionToRequestedProtocol[
            assertionId
        ];

        uint256 destinationChainId = registry.slugToChainId(
            requestProtocolSlug
        );

        bytes32 protocolHash = registry.slugToProtocolHash(requestProtocolSlug);

        //Construct across message with instructions for BridgedConnector to process the pivot
        //What does this message need?
        // -Pool id/addr
        // -New position protocol name, market id/addr, chain
        // -User deposit info???
        // -New position method bytes???

        //CALL ACROSS DEPOSIT FOR EXECUTING THE PIVOT

        //marketAddress is user address for user methods, pivot this is the destination market address
        address marketAddress = address(bytes20(bytes(requestPoolId)));

        // IMPORTANT - The market id in the subgraph could be different than the address of market contract. The subgraph market id is needed for assertion, the market address is needed to move funds into position
        //IMPORTANT - NEED TO VERIFY makretAddress is not prone to manipulation (neither here nor on bridgedConnector)
        // IMPORTANT - NEED TO VERIFY marketAddress ACTUALLY PERTAINS TO THE PROTOCOL RATHER THAN A DUMMY CLONE OF THE PROTOCOL. MAYBE CAN BE VERIFIED IN ASSERTION?

        bytes memory bridgingMessage = createPivotBridgingMessage(
            protocolHash,
            marketAddress,
            destinationChainId
        );

        // TEST-CEI REORDER IN PRODUCTION***********************
        // uint256 wethBalance = IERC20(wethAddress).balanceOf(address(this));
        // require(
        //     wethBalance >= transferAmount,
        //     "Deployer has insufficient asset balance"
        // );

        //How do we handle amounts/transfer in a pivot?
        //No value needs to be transfered, but relayers still need to be paid
        //Could this be sourced by the user signing off the assertionSettled callback?
        //Doesnt need to be a high amount. However need funds on this network in order to pay these fees

        //*************************************** */
        // IERC20(wethAddress).approve(acrossSpokePool, transferAmount);

        address acrossSpokePool = registry.chainIdToSpokePoolAddress(
            currentPositionChain
        );

        address destinationBridgedConnector = registry
            .chainIdToBridgedConnector(destinationChainId);

        uint256 transferAmount = 0;

        // The amount bridged is protocol fee
    }

    //THIS FUNCTION queryMovePosition() IS THE FIRST STEP IN THE PROCESS TO PIVOT MARKETS. ANY USER CALLS THIS FUNCTION, WHICH OPENS AN ASSERTION
    //IN ORDER TO CALL THIS FUNCTION, USER MUST APPROVE TOKEN TO THIS ADDRESS FOR BOND
    function queryMovePosition(
        string memory requestProtocolSlug,
        string memory requestPoolId,
        uint256 bond
    ) public {
        require(bond >= 1000000000, "Bond provided must be above 1000 USDC");

        bool slugEnabled = registry.slugEnabled(requestProtocolSlug);
        require(
            slugEnabled == true,
            "Protocol-Chain slug must be enabled to make proposal"
        );

        ArbitrationContract arbitrationContract = ArbitrationContract(
            registry.arbitrationContract()
        );

        uint256 userAllowance = asset.allowance(
            msg.sender,
            address(arbitrationContract)
        );

        require(
            bond <= userAllowance,
            "User must approve bond amount for PoolControl to spend"
        );
        //IMPORTANT - ASSERTION MUST ALSO INCLUDE THE CORRECT ASSET THAT CORRESPONDS TO THIS POOL. ie THE PROPOSED MARKET MUST BE FOR THE ASSET USED ON THIS POOL

        // Assertion should use protocol-chain slugs and subgraph id for dispute UX
        string memory currentDepositProtocolSlug = assertionToRequestedProtocol[
            currentPositionAssertion
        ];
        string memory currentDepositPoolId = assertionToRequestedPoolId[
            currentPositionAssertion
        ];

        bytes memory data = abi.encode(
            "The market on ",
            requestProtocolSlug,
            " for pool with an id of ",
            requestPoolId,
            " yields a better investment than the current market on ",
            currentDepositProtocolSlug,
            " with an id of ",
            currentDepositPoolId,
            ". This is according to the current strategy whose Javascript logic that can be read from ",
            strategySource,
            " as of block ",
            block.number
        ); // This message must be rewritten to be very exacting/measurable. Check for uint/address byte conversion breaking the value
        //Switch this message to use different strategy mechanism, not contract string based strategy

        // Submit UMA assertion proposing the move
        bytes32 assertionId = arbitrationContract.assertDataFor(
            data,
            msg.sender,
            bond
        );

        //DOES THIS VIOLATE CEI?
        assertionToRequestedPoolId[assertionId] = requestPoolId;
        assertionToRequestedProtocol[assertionId] = requestProtocolSlug;
    }

    /**
     * @notice Called after receiving communication of successful position entrance on the connector, minting tokens for the users proportional stake in the pool
     * @param _depositId The id of the deposit, for data lookup
     * @param _poolPositionAmount The amount of assets in the position, read recently from the connector in the "B" step of the "A=>B=>A" deposit sequence
     */
    function mintUserPoolTokens(
        bytes32 _depositId,
        uint256 _poolPositionAmount
    ) internal {
        require(
            depositIdToTokensMinted[_depositId] == false,
            "Deposit has already minted tokens"
        );

        address depositor = depositIdToDepositor[_depositId];
        uint256 userAssetDepositAmount = depositIdToDepositAmount[_depositId];
        poolNonce += 1;

        if (address(poolToken) == address(0)) {
            poolToken = new PoolToken(
                depositor,
                userAssetDepositAmount,
                poolName
            );
        } else {
            emit Numbers(userAssetDepositAmount, _poolPositionAmount);
            uint256 ratio = (userAssetDepositAmount * (10 ** 18)) /
                (_poolPositionAmount - userAssetDepositAmount);

            // // Calculate the correct amount of pool tokens to mint
            uint256 poolTokenSupply = poolToken.totalSupply();
            uint256 poolTokensToMint = (ratio * poolTokenSupply) / (10 ** 18);

            depositIdToTokensMinted[_depositId] = true;

            poolToken.mint(depositor, poolTokensToMint);
        }
    }

    /**
     * @notice Transfer deposit funds from user to pool, make approval for funds to the spokepool for moving the funds to the destination chain
     * @param _sender The address of the user who is making the deposit
     * @param _amount The amount of assets to deposit
     */
    function spokePoolPreparation(address _sender, uint256 _amount) internal {
        address acrossSpokePool = registry.chainIdToSpokePoolAddress(
            localChain
        );
        require(acrossSpokePool != address(0), "SPOKE ADDR");
        uint256 senderAssetBalance = asset.balanceOf(_sender);
        require(
            senderAssetBalance >= _amount,
            "Sender has insufficient asset balance"
        );
        asset.transferFrom(_sender, address(this), _amount);
        asset.approve(acrossSpokePool, _amount);
    }

    function createPivotBridgingMessage(
        bytes32 protocolHash,
        address marketAddress,
        uint256 destinationChainId
    ) internal view returns (bytes memory) {
        bytes4 method = bytes4(keccak256(abi.encode("exitPivot")));
        bytes memory message = abi.encode(
            method,
            address(this),
            protocolHash,
            marketAddress,
            destinationChainId,
            0
        );

        return message;
    }
}
