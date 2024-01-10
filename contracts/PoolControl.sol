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
    IERC20 public asset;

    event DepositRecorded(bytes32, uint256);
    event WithdrawRecorded(bytes32, uint256);
    event AcrossMessageSent(bytes);
    event LzMessageSent(bytes4, bytes);
    event Numbers(uint256, uint256);
    event PivotCompleted(string, address, bytes32, uint256);

    mapping(bytes32 => address) depositIdToDepositor;
    mapping(bytes32 => uint256) depositIdToDepositAmount;
    mapping(bytes32 => bool) depositIdToTokensMinted;

    mapping(bytes32 => address) withdrawIdToDepositor;
    mapping(bytes32 => uint256) withdrawIdToDepositAmount;
    mapping(address => bool) userHasPendingWithdraw;

    mapping(bytes32 => string) public assertionToRequestedMarketId;
    mapping(bytes32 => string) public assertionToRequestedProtocol;

    // POSITION STATE
    //State contains position target, current position location and last position location (for failed bridge handling)
    // target state is for holding the position to pivot to. This facilitates the new position to enter

    string public targetPositionMarketId; //THE MARKET ADDRESS THAT WILL BE PASSED TO BRIDGECONNECTION, NOT THE FINAL ADDRESS THAT FUNDS ARE ACTUALLY HELD IN
    uint256 public targetPositionChain;
    bytes32 public targetPositionProtocolHash;

    // current state holds the position that funds are currently deposited into. This facilitates withdraws. Current state gets set as chaser + address(this) when the bridge request to withdraw has been sent
    address public currentPositionAddress;
    string public currentPositionMarketId;
    uint256 public currentPositionChain; //IMPORTANT - CURRENT HARDCODED BEFORE PIVOT FUNCTIONALITY
    bytes32 public currentPositionProtocolHash;
    uint256 public currentRecordPositionValue; //This holds the most recently recorded value of the entire position sent from the current position chain.

    // last state holds the previous position data. In the case of error while bridging, this is to rescue funds
    address public lastPositionAddress;
    uint256 public lastPositionChain;
    bytes32 public lastPositionProtocolHash;

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
        currentPositionChain = localChain;
        poolId = keccak256(abi.encode(address(this), _poolName));
        poolName = _poolName;
        deployingUser = _deployingUser;
        asset = IERC20(_asset);
        strategySource = _strategySource;
    }

    function initializeContractConnections(address _registry) external {
        // manager = IChaserManager(address(msg.sender));
        registry = IChaserRegistry(_registry);
        localBridgedConnector = IBridgedConnector(
            registry.chainIdToBridgedConnector(localChain)
        );
        router = IChaserRouter(localBridgedConnector.router());
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
            (
                uint256 positionAmount,
                address marketAddress,
                bytes32 depositId
            ) = abi.decode(_data, (uint256, address, bytes32));
            //Receives the current value of the entire position. Sets this to a contract wide state (or mapping with timestamp => uint balance, and save timestamp to contract wide state)

            currentRecordPositionValue = positionAmount;
            if (depositId != bytes32("")) {
                if (poolNonce == 0) {
                    pivotCompleted(marketAddress, positionAmount);
                }
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
        if (_method == bytes4(keccak256(abi.encode("pivotCompleted")))) {
            (address marketAddress, uint256 positionAmount) = abi.decode(
                _data,
                (address, uint256)
            );

            pivotCompleted(marketAddress, positionAmount);
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
    function userWithdrawOrder(uint256 _amount) external payable {
        //IMPORTANT - Since we dont know the actual amount of pool tokens to be burnt from the withdraw, we should lock withdraws from the user until all pending withdraws are completed
        require(
            userHasPendingWithdraw[msg.sender] == false,
            "User may only open new withdraw order if they do not have a pending withdraw order"
        );
        require(
            pivotPending == false,
            "Withdraws are blocked until the Pivot is completed"
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

        router.send{value: msg.value}(
            currentPositionChain,
            method,
            false,
            address(this),
            data,
            200000
        );
    }

    /**
     * @notice After pivot was successfully asserted, send the execution request for the pivot
     */
    function pivotPosition() external payable {
        // Send message to BridgedConnector on new target position chain, with instructions to move funds to new position
        // Uses lzSend to send message with instructions on how to handle pivot

        bytes memory data;
        bytes memory options;

        router.send{value: msg.value}(
            currentPositionChain,
            bytes4(keccak256(abi.encode("pivotPosition"))),
            false,
            address(this),
            data,
            200000
        );
    }

    /**
     * @notice Send a request to the position chain for the up to date value of the position (including any gains)
     */
    function readPositionBalance() external payable {
        // Get the value of the entire position for the pool with gains
        // Uses lzSend to send message to request this data be sent back
        bytes4 method = bytes4(keccak256("readPositionBalance"));
        bytes memory data;
        bytes memory options;

        router.send{value: msg.value}(
            currentPositionChain,
            method,
            false,
            address(this),
            data,
            200000
        );
    }

    /**
     * @notice Send a request to the position chain for arbitrary data about the position
     */
    function getPositionData() external payable {
        // Uses lzSend to request position data be sent back

        bytes memory data;
        bytes memory options;

        router.send{value: msg.value}(
            currentPositionChain,
            bytes4(keccak256(abi.encode("getPositionData"))),
            false,
            address(this),
            data,
            200000
        );
    }

    /**
     * @notice Send a request to the position chain to get an address from its' registry
     */
    function getRegistryAddress() external payable {
        // Uses lzSend to request an address from the registry on another chain
        bytes memory data;
        bytes memory options;

        router.send{value: msg.value}(
            currentPositionChain,
            bytes4(keccak256(abi.encode("getRegistryAddress"))),
            false,
            address(this),
            data,
            200000
        );
    }

    /**
     * @notice Make the first deposit on the pool and set up the first position. This is a function meant to be called from a user/investing entity.
     * @notice This function simultaneously sets the first position and deposits the first funds
     * @notice After executing, other functions are called withdata generated in this function, in order to direction the position entrance
     * @param _amount The amount of the initial deposit
     * @param _relayFeePct The Across Bridge relay fee %
     * @param _targetPositionMarketId The market Id to be processed by Connector/Integrator to derive the market address
     * @param _targetPositionChain The destination chain on which the first position exists
     * @param _targetPositionProtocol The protocol that the position is made on
     */
    function userDepositAndSetPosition(
        uint256 _amount,
        int64 _relayFeePct,
        string memory _targetPositionMarketId,
        uint256 _targetPositionChain,
        string memory _targetPositionProtocol
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

        // IMPORTANT - Check protocol enabled
        bytes32 _targetPositionProtocolHash = keccak256(
            abi.encode(_targetPositionProtocol)
        );

        targetPositionMarketId = _targetPositionMarketId;
        targetPositionChain = _targetPositionChain;
        targetPositionProtocolHash = _targetPositionProtocolHash;

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
            targetPositionMarketId,
            currentPositionProtocolHash
        );

        // emit PivotOrder(
        //     targetPositionMarketId,
        //     targetPositionChain,
        //     targetPositionProtocolHash
        // );

        if (targetPositionChain == localChain) {
            localBridgedConnector.initializePoolPosition(
                address(this),
                address(asset),
                currentPositionProtocolHash,
                _targetPositionMarketId,
                poolNonce,
                _amount
            );
            enterFundsLocalChain(depositId);
            address marketAddress = localBridgedConnector
                .poolToCurrentPositionMarket(address(this));

            uint256 positionAmount = localBridgedConnector.getPositionBalance(
                address(this)
            );
            pivotCompleted(marketAddress, positionAmount);
        } else {
            bytes4 method = bytes4(
                keccak256(abi.encode("positionInitializer"))
            );
            bytes memory message = abi.encode(method, address(this), data);
            enterFundsCrossChain(depositId, _relayFeePct, message);
        }
    }

    /**
     * @notice Make a deposit on the pool
     * @dev This function creates the deposit data and routes the function call depending on whether or not the position is local or cross chain
     * @param _amount The amount of the deposit
     * @param _relayFeePct The Across Bridge relay fee % (irrelevant if local deposit)
     */
    function userDeposit(uint256 _amount, int64 _relayFeePct) external {
        bytes32 depositId = keccak256(
            abi.encode(msg.sender, _amount, block.timestamp)
        );

        // IMPORTANT - While assertion is open, user deposits sit in the pool rather than being sent.

        depositIdToDepositor[depositId] = msg.sender;
        depositIdToDepositAmount[depositId] = _amount;
        depositIdToTokensMinted[depositId] = false;

        emit DepositRecorded(depositId, _amount);

        if (currentPositionChain == localChain) {
            enterFundsLocalChain(depositId);
        } else {
            bytes4 method = bytes4(keccak256(abi.encode("userDeposit")));

            bytes memory message = abi.encode(
                method,
                address(this),
                abi.encode(depositId, msg.sender)
            );
            enterFundsCrossChain(depositId, _relayFeePct, message);
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

        asset.transferFrom(sender, address(localBridgedConnector), amount);

        localBridgedConnector.receiveDepositFromPool(
            amount,
            _depositId,
            address(this),
            sender
        );

        currentRecordPositionValue = localBridgedConnector.getPositionBalance(
            address(this)
        );
        mintUserPoolTokens(_depositId, currentRecordPositionValue);
    }

    /**
     * @notice Complete the process of sending funds to the BridgedConnector on another chain for entering the position
     * @dev This function is the first "A" step of the "A=>B=>A" deposit sequence
     * @param _depositId The id of the deposit, used for data lookup
     * @param _relayFeePct The Across Bridge relay fee %
     * @param _message Bytes that are passed in the Across "message" parameter, particularly to help set the position
     */
    function enterFundsCrossChain(
        bytes32 _depositId,
        int64 _relayFeePct,
        bytes memory _message
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
            targetPositionChain
        );

        // Approval made from sender to this contract
        // spokePoolPreparation makes approval for spokePool
        spokePoolPreparation(sender, amount);

        emit AcrossMessageSent(_message);

        currentPositionChain = targetPositionChain; // REMOVE - TESTING. This simulates finalizing the new position, which normally occurs after LZ callback

        //When assertion is settled, pivotPending state is true and no deposits are allowed until new position is successfully engaged
        ISpokePool(acrossSpokePool).deposit(
            bridgedConnector,
            address(asset),
            amount,
            targetPositionChain,
            _relayFeePct,
            uint32(block.timestamp),
            _message,
            (2 ** 256 - 1)
        );
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

    function sendPositionChange(bytes32 assertionId) external payable {
        //IMPORTANT - CHANGE TO LZ SEND
        // This gets executed open callback of the position pivot assertion resolving
        // This send lz message to the connector to make the transition

        //Can only be called by Arbitration contract
        currentPositionAssertion = assertionId;
        address arbitrationContract = registry.arbitrationContract();
        // require(
        //     msg.sender == arbitrationContract,
        //     "sendPositionChange() may only be called by the arbitration contract"
        // ); IMPORTANT - UNCOMMENT

        //SInce withdraws use  LZ ordered messaging, can be made uninterrupted up until the exitPivot is executed
        //Block withdraws once exitPivot is executed, until the new target position is entered and sends message to pool

        string memory requestMarketId = assertionToRequestedMarketId[
            assertionId
        ];
        string memory requestProtocolSlug = assertionToRequestedProtocol[
            assertionId
        ];

        requestMarketId = string(
            abi.encodePacked(assertionId, abi.encode("0xTEST"))
        ); // REMOVE - TESTING
        requestProtocolSlug = string(
            abi.encodePacked(assertionId, abi.encode("SLUG"))
        ); //REMOVE - TESTING

        uint256 destinationChainId = registry.slugToChainId(
            requestProtocolSlug
        );

        if (currentPositionChain == 1337) {
            destinationChainId = 80001; // REMOVE - TESTING
        } else {
            destinationChainId = 1337;
        }

        bytes32 protocolHash = registry.slugToProtocolHash(requestProtocolSlug);

        bytes memory pivotMessage = createPivotExitMessage(
            protocolHash,
            requestMarketId,
            destinationChainId
        );

        bytes memory options;

        bytes4 method = bytes4(keccak256(abi.encode("exitPivot")));

        targetPositionMarketId = requestMarketId;
        targetPositionChain = destinationChainId;
        targetPositionProtocolHash = protocolHash;

        pivotPending = true;

        emit LzMessageSent(method, pivotMessage);
        emit Numbers(currentPositionChain, destinationChainId);

        // IF POSITION NEEDS TO PIVOT *FROM* THIS CHAIN (LOCAL/BRIDGE LOGIC HELD ON CONNECTOR)
        // THIS IF STATEMENT DETERMINES WHETHER TO ACTION THE EXITPIVOT LOCALLY OR THROUGH CROSS CHAIN
        if (currentPositionChain == localChain) {
            address destinationBridgedConnector = registry
                .chainIdToBridgedConnector(destinationChainId);

            localBridgedConnector.executeExitPivot(
                address(this),
                poolNonce,
                protocolHash,
                targetPositionMarketId,
                targetPositionChain,
                destinationBridgedConnector
            );
        } else {
            router.send{value: msg.value}(
                currentPositionChain,
                method,
                false,
                address(this),
                pivotMessage,
                200000
            );
        }
    }

    //THIS FUNCTION queryMovePosition() IS THE FIRST STEP IN THE PROCESS TO PIVOT MARKETS. ANY USER CALLS THIS FUNCTION, WHICH OPENS AN ASSERTION
    //IN ORDER TO CALL THIS FUNCTION, USER MUST APPROVE TOKEN TO THIS ADDRESS FOR BOND
    function queryMovePosition(
        string memory requestProtocolSlug,
        string memory requestMarketId,
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
        string memory currentDepositMarketId = assertionToRequestedMarketId[
            currentPositionAssertion
        ];

        bytes memory data = abi.encode(
            "The market on ",
            requestProtocolSlug,
            " for pool with an id of ",
            requestMarketId,
            " yields a better investment than the current market on ",
            currentDepositProtocolSlug,
            " with an id of ",
            currentDepositMarketId,
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
        assertionToRequestedMarketId[assertionId] = requestMarketId;
        assertionToRequestedProtocol[assertionId] = requestProtocolSlug;
    }

    function pivotCompleted(
        address marketAddress,
        uint256 positionAmount
    ) public {
        lastPositionAddress = currentPositionAddress;
        lastPositionChain = currentPositionChain;
        lastPositionProtocolHash = currentPositionProtocolHash;

        currentPositionAddress = marketAddress;
        currentPositionMarketId = targetPositionMarketId;
        currentPositionChain = targetPositionChain;
        currentPositionProtocolHash = targetPositionProtocolHash;
        currentRecordPositionValue = positionAmount;

        targetPositionMarketId = "";
        targetPositionChain = 0;
        targetPositionProtocolHash = bytes32("");

        pivotPending = false;

        emit PivotCompleted(
            currentPositionMarketId,
            marketAddress,
            currentPositionProtocolHash,
            positionAmount
        );
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

    function createPivotExitMessage(
        bytes32 protocolHash,
        string memory requestMarketId,
        uint256 destinationChainId
    ) internal view returns (bytes memory) {
        address destinationBridgedConnector = registry
            .chainIdToBridgedConnector(destinationChainId);

        bytes memory data = abi.encode(
            address(this),
            poolNonce,
            protocolHash,
            requestMarketId,
            destinationChainId,
            destinationBridgedConnector
        );

        return data;
    }
}
