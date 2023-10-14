// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import {IBridgingConduit} from "./interfaces/IBridgingConduit.sol";
import {IFunctionsConsumer} from "./interfaces/IFunctionsConsumer.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {IInterestRateDataSource} from "./interfaces/IInterestRateDataSource.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {FunctionsConsumer} from "./FunctionsConsumer.sol";

interface PotLike {
    function dsr() external view returns (uint256);
}

interface RolesLike {
    function canCall(
        bytes32,
        address,
        address,
        bytes4
    ) external view returns (bool);
}

interface RegistryLike {
    function buffers(bytes32 ilk) external view returns (address buffer);
}

contract BridgingConduit is IBridgingConduit, IInterestRateDataSource {
    /**********************************************************************************************/
    /*** Storage                                                                                ***/
    /**********************************************************************************************/

    address public override roles;
    address public override registry;
    uint256 public override subsidySpread;

    /**
     *  @dev   Struct representing a fund request.
     *  @param status          The current status of the fund request.
     *  @param asset           The address of the asset requested in the fund request.
     *  @param ilk             The unique identifier of the ilk.
     *  @param amountRequested The amount of asset requested in the fund request.
     *  @param amountFilled    The amount of asset filled in the fund request.
     *  @param info            Arbitrary string to provide additional info to the Arranger.
     */
    struct FundRequest {
        StatusEnum status;
        address asset;
        bytes32 ilk;
        uint256 amountRequested;
        uint256 amountFilled;
        string info;
    }

    /**
     *  @dev    Enum representing the status of a fund request.
     *  @notice PENDING   - Null state before the fund request has been made.
     *  @notice PENDING   - The fund request has been made, but not yet processed.
     *  @notice CANCELLED - The fund request has been cancelled by the ilk.
     *  @notice COMPLETED - The fund request has been fully processed and completed.
     */
    enum StatusEnum {
        UNINITIALIZED,
        PENDING,
        CANCELLED,
        COMPLETED
    }

    /**
     *  @dev   Event emitted when an Arranger returns funds to the Conduit to fill a fund request.
     *  @param ilk             The unique identifier of the ilk.
     *  @param asset           The address of the asset to be withdrawn.
     *  @param fundRequestId   The ID of the fund request.
     *  @param amountRequested The amount of asset that was requested by the ilk to be withdrawn.
     *  @param returnAmount    The resulting amount that was returned by the Arranger.
     */
    event ReturnFunds(
        bytes32 indexed ilk,
        address indexed asset,
        uint256 fundRequestId,
        uint256 amountRequested,
        uint256 returnAmount
    );

    /**
     *  @dev   Event emitted when funds are drawn from the Conduit by the Arranger.
     *  @param asset       The address of the asset to be withdrawn.
     *  @param destination The address to transfer the funds to.
     *  @param amount      The amount of asset to be withdrawn.
     */
    event DrawFunds(
        address indexed asset,
        address indexed destination,
        uint256 amount
    );
    FundRequest[] internal fundRequests;

    address public arranger;

    address public DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    mapping(address => uint256) public totalDeposits;
    mapping(address => uint256) public totalRequestedFunds;
    mapping(address => uint256) public totalWithdrawableFunds;
    mapping(address => uint256) public totalWithdrawals;

    mapping(address => mapping(address => bool)) public isBroker;

    mapping(address => bool) public assetEnabled;

    mapping(address => mapping(bytes32 => uint256)) public deposits;
    mapping(address => mapping(bytes32 => uint256)) public requestedFunds;
    mapping(address => mapping(bytes32 => uint256)) public withdrawableFunds;
    mapping(address => mapping(bytes32 => uint256)) public withdrawals;

    // records how much has currently been sent over bridge
    mapping(uint256 => uint256) public currentBridged;
    // records how much has been bridged from conduit all time
    mapping(uint256 => uint256) public cumulativeBridged;
    // records how much has been sent back to conduit thru bridge
    mapping(uint256 => uint256) public cumulativeUnbridged;

    mapping(uint256 => address) public chainToSubconduit;

    mapping(bytes32 => uint256) public hashedSlugToChainId;

    mapping(bytes32 => address) public hashedSlugToFunctionsContract;

    uint public currentFundsChain = 1;
    address public currentFundsAddress;

    string public currentDepositPoolId;
    string public currentDepositProtocolSlug;
    address public currentDepositTokenAddress;

    address public strategyContract;

    /**********************************************************************************************/
    /*** Modifiers                                                                              ***/
    /**********************************************************************************************/

    modifier auth() {
        require(msg.sender != address(0), "BridgeConduit/not-authorized");
        _;
    }

    modifier ilkAuth(bytes32 ilk) {
        require(
            RolesLike(roles).canCall(ilk, msg.sender, address(this), msg.sig),
            "BridgeConduit/ilk-not-authorized"
        );
        _;
    }

    modifier isArranger() {
        require(msg.sender == arranger, "ArrangerConduit/not-arranger");
        _;
    }

    /**********************************************************************************************/
    /*** Constructor                                                                            ***/
    /**********************************************************************************************/

    constructor() {
        currentFundsAddress = address(this);
    }

    /**********************************************************************************************/
    /*** Admin Functions                                                                        ***/
    /**********************************************************************************************/

    function setRoles(address _roles) external override auth {
        roles = _roles;

        emit SetRoles(_roles);
    }

    function setRegistry(address _registry) external override auth {
        registry = _registry;

        emit SetRegistry(_registry);
    }

    function setSubsidySpread(uint256 _subsidySpread) external override auth {
        subsidySpread = _subsidySpread;

        emit SetSubsidySpread(_subsidySpread);
    }

    function setAssetEnabled(
        address asset,
        bool enabled_
    ) external override auth {
        assetEnabled[asset] = enabled_;
        // MAYBE APPROVE BRIDGE?
        // IERC20(asset).approve(pool, enabled_ ? type(uint256).max : 0);

        emit SetAssetEnabled(asset, enabled_);
    }

    /**********************************************************************************************/
    /*** Operator Functions                                                                     ***/
    /**********************************************************************************************/

    function deposit(
        bytes32 ilk,
        address asset,
        uint256 amount
    ) external override ilkAuth(ilk) {
        require(assetEnabled[asset], "BridgeConduit/asset-disabled");
        address source = RegistryLike(registry).buffers(ilk);

        // This function does not update currentFundsChain nor currentFundsAddress to conduit
        // It is assumed that deposits will be made to conduit even when funds are held elsewhere.
        if (
            currentFundsChain != 1 &&
            chainToSubconduit[currentFundsChain] != address(0)
        ) {
            // update bridging metrics
            cumulativeBridged[currentFundsChain] += amount;
            currentBridged[currentFundsChain] += amount;
        }

        // Update these metrics regardless if funds will stay in conduit or be bridged
        deposits[asset][ilk] += amount;
        totalDeposits[asset] += amount;

        // Update ledgers and balances to record how much is now in conduit and how much is deposited elsewhere
        // Record amount bridged to chain
        IERC20(asset).transferFrom(source, address(this), amount);

        if (
            currentFundsChain != 1 &&
            chainToSubconduit[currentFundsChain] != address(0)
        ) {
            // BRIDGE FUNDS
            // SHOULD FUNDS BE BRIDGED AT ALL IN THIS FUNCTION?
            // FOR THE SAKE OF NOT BRIDGING FUNDS TO A CHAIN THAT WILL BE MOVED AWAY FROM SOON, BRIDGING SHOULD ONLY BE DONE IN queryMovePosition
            // EASIER TO MANAGE THE BRIDGING BALANCES IF IT IS ONLY ONE FUNCTION
        }

        emit Deposit(ilk, asset, source, amount);
    }

    function queryMovePosition(
        string memory destinationProtocolSlug,
        string memory marketTokenAddress
    ) external {
        // REORIENT THIS FUNCTION TO TAKE MAKE THE REQUEST FROM THE FRONT END, THEN THE ORACLE CALLBACK EXECUTES THE BRIDGE/MOVE IF APPLICABLE
        // IFunctionsConsumer functionsConsumerInstance = IFunctionsConsumer(
        //     graphFunctionAddress
        // );
        // IStrategy strategyContractInstance = IStrategy(strategyContract);
        // string[] memory args = new string[](4);
        // args[0] = currentDepositPoolId;
        // args[1] = currentDepositProtocolSlug;
        // args[2] = destinationProtocolSlug;
        // args[3] = marketTokenAddress;
        // // bytes[] memory bytesArgs = [0x];
        // bytes[] memory emptyArray = new bytes[](0);
        // functionsConsumerInstance.sendRequest(
        //     strategyContractInstance.strategySourceCode(),
        //     FunctionsRequest.Location,
        //     0,
        //     args,
        //     emptyArray,
        //     843,
        //     300000
        // );
        // THe request needs to be processed, then will call separate callback function with the response
        // Response only needs the poolId
        // The slug is already available, value not needed
        // -Conduit state holds the current chain/address of funds
        // This function gets called by a user to call the oracle proposing a new chain/market with a better yield
        // User Passes into oracle new protocolSlug+chain and an input token address (USDC, DAI, etc address), contract passes in both currentDepositProtocolSlug and currentDepositPoolId string
        // Receive result from oracle
        // JSON returned from oracle: [{protocolSlug+chain, subgraphPoolId, value}, {protocolSlug+chain, subgraphPoolId, value}] with the first element being the more efficient/better investment
        // If the new, user passed market is more efficient than  the current market, save  as currentDepositPoolId. Save the new subgraph slug as currentDepositProtocolSlug
        // *********
    }

    function executeMovePosition(
        string memory newPoolId
    ) external // string memory newProtocolSlug,
    // string memory newTokenAddress
    {
        // Instantiate FunctionsConsumer from msg.sender
        // if (
        //     keccak256(abi.encode(currentDepositPoolId)) ==
        //     keccak256(abi.encode(newPoolId))
        // ) {
        //     // If the oracle returns the current Pool Id, no need to update states
        // }

        // uint256 newChainId = hashedSlugToChainId[
        //     keccak256(abi.encode(newProtocolSlug))
        // ];

        // if (
        //     IERC20(DAI).balanceOf(address(this)) > 0 &&
        //     newChainId != currentFundsChain
        // ) {
        //     // How to get the chain of newPoolId?
        //     // -FunctionsConsumer should cache the chainId of the
        //     bridgeToSubconduit();
        // }
        currentDepositPoolId = newPoolId;
        // Read poolId, tokenAddress, protocol-slug
        // If poolId same as currentPoolId, RETURN HERE
        // Check if current deposit is subconduit or if current protocol slug is empty
        // If the deposit is in protocol, execute withdraw sequence
        // ****************************
        // WITHDRAW SEQUENCE
        // read following values currentFundsChain; currentFundsAddress; currentDepositPoolId; currentDepositProtocolSlug; currentDepositTokenAddress;
        // get the externalFunctionConstructor withdraw sequence
        // ****************************
        // RESOLVE BRIDGING DIFFERENCES (SEND FUNDS FROM CONDUIT TO SUBCONDUIT, MOVE FUNDS FROM SUBCONDUIT TO OTHER SUBCONDUIT ON DIFFERENT CHAIN)
        // UPDATE CONDUIT STATES
        // UPDATE SUBCONDUIT STATES (USING CCIP, UPDATE THE STATES TO REFLECT NEW POSITION TO MOVE FUNDS TO)
        // INITIATE SUBCONDUIT DEPOSIT (USING CCIP, ATTEMPT TO DEPOSIT FUNDS INTO THE NEW POSITION IF SOME FUNDS ALREADY IN SUBCONDUIT. )
        // *******************************
        // *******************************
        // *******************************
        // *******************************
        // This is the callback to execute when the oracle has a result
        // The only data in the response is a poolId
        // If its not the same as currentPoolId nor address(0), then execute the move
        // SET THE FOLLOWING STATE TO REFLECT NEW POSITION
        //     uint public currentFundsChain = 1;
        // address public currentFundsAddress;
        // string public currentDepositPoolId;
        // string public currentDepositProtocolSlug;
        // address public currentDepositTokenAddress;
        // *******************************
        // Handle already deposited funds
        // THIS SECTION SHOULD BE ALL PSEUDOCODE, DONT PRIORITIZE THIS CASE
        // Get the subconduit address on currentFundsChain, make IRouterClient.ccipSend() call to bridge funds from current subconduit chain and send to chain resulting from oracle
        // If the deposited funds are already on the target chain, make IRouterClient.ccipSend() call to withdraw position and let funds sit in subconduit
        // *********
        // Get the subconduit address for the chain returned in the oracle call
        // Send Bridge call to send conduit funds to appropriate subconduit
        // *********
        // Set currentFundsChain currentFundsAddress states to result of oracle
        // If Bridge Call is successful, submit CCIP interaction to subconduit to set the destination in subconduit state, also    passing in bytes for the deposit function from externalFunctionConstructor
        // Call router contract initiated with IRouterClient interface
        // IRouterClient.getFee()
        // IRouterClient.ccipSend()
    }

    function withdraw(
        bytes32 ilk,
        address asset,
        uint256 maxAmount
    ) public override ilkAuth(ilk) returns (uint256 amount) {
        // Constrain the amount that can be withdrawn by the max amount
        uint256 withdrawableFunds_ = withdrawableFunds[asset][ilk];

        amount = maxAmount > withdrawableFunds_
            ? withdrawableFunds_
            : maxAmount;

        withdrawableFunds[asset][ilk] -= amount;
        totalWithdrawableFunds[asset] -= amount;

        withdrawals[asset][ilk] += amount;
        totalWithdrawals[asset] += amount;
        address destination = RegistryLike(registry).buffers(ilk);

        // Update deposit records to account for new balances

        // CCIP interaction to destination chain subconduit to wthdraw deposited funds and transfer back to 'destination' through acx bridge

        emit Withdraw(ilk, asset, destination, amount);
    }

    function requestFunds(
        bytes32 ilk,
        address asset,
        uint256 amount,
        string memory info
    ) public ilkAuth(ilk) returns (uint256 fundRequestId) {
        fundRequestId = fundRequests.length; // Current length will be the next index

        fundRequests.push(
            FundRequest({
                status: StatusEnum.PENDING,
                asset: asset,
                ilk: ilk,
                amountRequested: amount,
                amountFilled: 0,
                info: info
            })
        );

        requestedFunds[asset][ilk] += amount;
        totalRequestedFunds[asset] += amount;

        emit RequestFunds(ilk, asset, amount);
    }

    function withdrawAndRequestFunds(
        bytes32 ilk,
        address asset,
        uint256 requestAmount
    )
        external
        override
        ilkAuth(ilk)
        returns (uint256 amountWithdrawn, uint256 requestedFunds)
    {
        uint256 availableLiquidity = totalDeposits[asset];

        // If there is liquidity available, withdraw it before requesting.
        if (availableLiquidity != 0) {
            uint256 amountToWithdraw = _min(availableLiquidity, requestAmount);
            amountWithdrawn = withdraw(ilk, asset, amountToWithdraw);
        }

        // If the withdrawal didn't satisfy the full amount, request the remainder.
        if (requestAmount > amountWithdrawn) {
            unchecked {
                requestedFunds = requestAmount - amountWithdrawn;
            }
            requestFunds(ilk, asset, requestedFunds, "");
        }
    }

    function cancelFundRequest(uint256 fundRequestId) external {
        FundRequest memory fundRequest = fundRequests[fundRequestId];

        require(
            fundRequest.status == StatusEnum.PENDING,
            "ArrangerConduit/invalid-status"
        );

        address asset = fundRequest.asset;
        bytes32 ilk = fundRequest.ilk;

        _checkAuth(ilk);

        uint256 amountRequested = fundRequest.amountRequested;

        fundRequests[fundRequestId].status = StatusEnum.CANCELLED;

        requestedFunds[asset][ilk] -= amountRequested;
        totalRequestedFunds[asset] -= amountRequested;

        emit CancelFundRequest(ilk, asset);
    }

    function addSubconduit(
        uint256 chainId,
        address subconduitAddress
    ) external {
        chainToSubconduit[chainId] = subconduitAddress;
    }

    function bridgeToSubconduit() public {
        // Implementation
    }

    function unbridgeFromSubconduit() public {
        // Implementation
    }

    function updateBridgedLedger() external {
        // Implementation
    }

    /**********************************************************************************************/
    /*** View Functions                                                                         ***/
    /**********************************************************************************************/

    /**********************************************************************************************/
    /*** Fund Manager Functions                                                                 ***/
    /**********************************************************************************************/

    function drawFunds(
        address asset,
        address destination,
        uint256 amount
    ) external isArranger {
        require(
            amount <= availableFunds(asset),
            "ArrangerConduit/insufficient-funds"
        );
        require(isBroker[destination][asset], "ArrangerConduit/invalid-broker");

        IERC20(asset).transfer(destination, amount);

        emit DrawFunds(asset, destination, amount);
    }

    function returnFunds(
        uint256 fundRequestId,
        uint256 returnAmount
    ) external isArranger {
        FundRequest storage fundRequest = fundRequests[fundRequestId];

        address asset = fundRequest.asset;

        require(
            fundRequest.status == StatusEnum.PENDING,
            "ArrangerConduit/invalid-status"
        );
        require(
            returnAmount <= availableFunds(asset),
            "ArrangerConduit/insufficient-funds"
        );

        bytes32 ilk = fundRequest.ilk;

        withdrawableFunds[asset][ilk] += returnAmount;
        totalWithdrawableFunds[asset] += returnAmount;

        uint256 amountRequested = fundRequest.amountRequested;

        requestedFunds[asset][ilk] -= amountRequested;
        totalRequestedFunds[asset] -= amountRequested;

        fundRequest.amountFilled = returnAmount;

        fundRequest.status = StatusEnum.COMPLETED;

        emit ReturnFunds(
            ilk,
            asset,
            fundRequestId,
            amountRequested,
            returnAmount
        );
    }

    function addProtocolSupport(
        string[] memory slugs,
        uint256[] memory chainIds,
        address externalFunctionConstructor
    ) external {
        // Slugs contain protocol+network
        // For now caller manually passes in the
        // This function is to be called by subDAO after voting to add support for a protocol
        // -when prtocol support is added the slug is fully protocol+network. slug => externalfunctionconstructor, slug => chainid, chainId => subconuit
        require(
            slugs.length == chainIds.length,
            "chainIds and slugs lengths must match"
        );
        require(
            slugs.length < 10,
            "A Protocol may have a maximum of 10 deployments"
        );

        for (uint256 i = 0; i < slugs.length; i++) {
            bytes32 slugHash = keccak256(abi.encodePacked(slugs[i]));
            hashedSlugToChainId[slugHash] = chainIds[i];
            hashedSlugToFunctionsContract[
                slugHash
            ] = externalFunctionConstructor;
        }
    }

    /**********************************************************************************************/
    /*** View Functions                                                                         ***/
    /**********************************************************************************************/
    function availableFunds(
        address asset
    ) public view returns (uint256 availableFunds_) {
        availableFunds_ =
            IERC20(asset).balanceOf(address(this)) -
            totalWithdrawableFunds[asset];
    }

    function getFundRequest(
        uint256 fundRequestId
    ) external view returns (FundRequest memory fundRequest) {
        fundRequest = fundRequests[fundRequestId];
    }

    function getFundRequestsLength()
        external
        view
        returns (uint256 fundRequestsLength)
    {
        fundRequestsLength = fundRequests.length;
    }

    function isCancelable(
        uint256 fundRequestId
    ) external view returns (bool isCancelable_) {
        isCancelable_ =
            fundRequests[fundRequestId].status == StatusEnum.PENDING;
    }

    function maxDeposit(
        bytes32,
        address
    ) external pure override returns (uint256 maxDeposit_) {
        maxDeposit_ = type(uint256).max;
    }

    function maxWithdraw(
        bytes32 ilk,
        address asset
    ) external view override returns (uint256 maxWithdraw_) {
        maxWithdraw_ = withdrawableFunds[asset][ilk];
    }

    function cancelFundRequest(bytes32 ilk, address asset) external override {}

    function enabled(address asset) external view override returns (bool) {}

    function getAssetData(
        address asset
    ) external view override returns (bool, uint256, uint256) {}

    function getAvailableLiquidity(
        address asset
    ) external view override returns (uint256) {}

    function getDeposits(address asset) external view returns (uint256) {}

    function getInterestData(
        address asset
    ) external view override returns (InterestData memory data) {}

    function getPosition(
        address asset
    ) external view returns (uint256, uint256) {}

    function getRequestedFunds(address asset) external view returns (uint256) {}

    function getTotalDeposits(
        address asset
    ) external view override returns (uint256) {}

    function getTotalRequestedFunds(
        address asset
    ) external view override returns (uint256) {}

    function pool() external view override returns (address) {}

    function pot() external view override returns (address) {}

    function requestFunds(
        bytes32 ilk,
        address asset,
        uint256 amount
    ) external override {}

    function requestedShares(
        address asset,
        bytes32 ilk
    ) external view returns (uint256) {}

    function shares(
        address asset,
        bytes32 ilk
    ) external view override returns (uint256) {}

    function totalRequestedShares(
        address asset
    ) external view override returns (uint256) {}

    function totalShares(
        address asset
    ) external view override returns (uint256) {}

    function getDeposits(
        address asset,
        bytes32 ilk
    ) external view returns (uint256) {}

    function getPosition(
        address asset,
        bytes32 ilk
    ) external view returns (uint256 deposits, uint256 requestedFunds) {}

    function getRequestedFunds(
        address asset,
        bytes32 ilk
    ) external view returns (uint256) {}

    /**********************************************************************************************/
    /*** Internal Functions                                                                     ***/
    /**********************************************************************************************/

    function _checkAuth(bytes32 ilk) internal view {
        require(
            RolesLike(roles).canCall(ilk, msg.sender, address(this), msg.sig),
            "ArrangerConduit/not-authorized"
        );
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _rayMul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = (x * y) / 1e27;
    }

    function _rayDiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = (x * 1e27) / y;
    }

    function toString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";

        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }

        return string(str);
    }
}
