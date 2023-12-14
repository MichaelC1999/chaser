// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "hardhat/console.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";

interface IBridgeConnection {
    function readPositionValue() external view returns (uint256);
}

contract BridgeConnection {
    //IMPORTANT - BridgeConnection CONTRACTS GET DEPLOYED FROM CENTRAL CONTROL CONTRACT TO MULTIPLE CHAINS USING CrossDeploy

    // Across handleAcrossMessage
    // These contracts are upgraeable
    // Import AAVE pool, Compound market, etc interface
    // Receives bridged funds and handles their positioning on external protocolsneed to properly allocate funds when more than one pool deposits into the same market
    // Needs PoolControl address as an argument when depositing,
    // function to send funds back to the PivotPoolManager on mainnet
    // function to send funds to new position on other L2
    //How will bridgeConnection handle pushing funds into position? Should the funds be escrowed to this contract and then transfered to external protocol?
    // Two cases
    // -funds bridged
    // --Asset funds arrive in connection contract from bridge. Funds need to approve the spender of external protocol
    // -funds from same chain
    // --Pool transfers to the connection contract, then calls appropriate entrance flow which includes approving external protocol spend
    // External protocol deposits usually will require approval, token transfer called in their contract

    //IMPORTANT - HOW TO HANDLE TWO POOLS DEPOSITING INTO THE SAME MARKET? BY DEFAULT THESE POSITIONS WOULD BE COMBINED TO ONE
    // - RECORD POOL PROPORTIONS. TWO POOLS ARE A SINGLE POSITION IN A MARKET, WITH THIS PROPORTION WE CAN MAKE SURE CORRECT DEPOSIT AMOUNTS PERTAIN TO EACH POOL
    // - DEPLOY POOLCONTROL ON EACH CHAIN, THE DEPOSITS PASS THROUGH THIS POOL CONTRACT AND EACH POSITION ON EXTERNAL PROTOCOL ONLY PERTAINS TO ONE POOL

    function handleAcrossMessage(
        address tokenSent,
        uint256 amount,
        bool fillCompleted,
        address relayer,
        bytes memory message
    ) public {
        // IMPORTANT - require msg.sender to be the Across Spoke Pool
        // Parses message for method and bytecode
        (
            bytes4 method,
            address poolAddress,
            bytes32 protocolHash,
            address actionAddress,
            uint256 num1,
            uint256 userProportionRatio
        ) = extractMessageComponents(message);

        if (method == bytes4(keccak256("enterPivot"))) {
            // - enterPivot: bytes32 destinationProtocol, bytes20 destinationMarket
        }
        if (method == bytes4(keccak256("exitPivot"))) {
            uint256 destinationChainId = num1;
            // - exitPivot: bytes32 destinationProtocol, bytes20 destinationMarket, uint256 destinationChainId
        }
        if (method == bytes4(keccak256("userDeposit"))) {
            // - userDeposit: bytes32 protocol, bytes 20 userAddress
            // IMPORTANT - MUST RECEIVE + VERIFY USER SIGNED MESSAGE FROM POOLCONTROL
        }
        if (method == bytes4(keccak256("userWithdraw"))) {
            uint256 amountToWithdraw = num1;
            // - userWithdraw: bytes32 protocol, bytes 20 userAddress, uint256 amountToWithdraw, uint256 userProportionRatio
            // IMPORTANT - MUST RECEIVE + VERIFY USER SIGNED MESSAGE FROM POOLCONTROL
        }

        //What data not accessible in this contract do we need to execute user deposits/withdraws?
        // -Pool id that the user is depositing to/withdrawing from
        // -User address
        // -User pool token proportion (if withdraw)

        //What data do we need to execute pool pivots?
        // -Pool id that will be pivoting position
        // -Destination protocol, chain, pool
        // -If any funds/data needs to be sent back to pool control

        //methods
        // - userDeposit
        // - userWithdraw
        // - enterPivot - This is called when a position has been undone and bridged to the correct chain. Called from poolControl or other BridgeConnection
        // - exitPivot - This is called to undo a position and set up for entering new position. Always called from poolControl

        // with all of these inputs, how could we structure the message data bytes?
        // bytes 4 method, bytes32 poolId, are always included in the message
        //After these, the remaining bytes depend on the method

        // METHOD BYTES STRUCTURE

        //handleAcrossMessage processes bytes4,bytes32,bytes32,bytes20,bytes32(uint),bytes32(uint)
        //NOTE enterPivot/exitPivot market addresses still need to go through process to get the address of contracts to deposit/withdraw
    }

    // IMPORTANT - The market id in the subgraph could be different than the address of market contract. The subgraph market id is needed for assertion,
    // how can we get the market address from market id?

    //Operation is deposit/withdraw

    function aaveConnection(bytes32 operation) internal {
        // From subgraph market id, how can we get the address of the contract to call functions on?
        //-Instantiate market with address of pool id
        //- on this contract call POOL() to get address of the pool to supply/withdraw
    }

    function compoundConnection(bytes32 operation) internal {
        // From subgraph market id, how can we get the address of the contract to call functions on?
        //- CompoundV3 subgraph market id is 40 bytes long, joining the market address bytes to the asset address bytes
        //-Take the first 20 bytes to get address to make spply/withdraw method calls
    }

    function sparkConnection(bytes32 operation) internal {
        // From subgraph market id, how can we get the address of the contract to call functions on?
    }

    function acrossConnection(bytes32 operation) internal {
        // From subgraph market id, how can we get the address of the contract to call functions on?
    }

    function routeExternalProtocolInteraction(
        bytes32 protocolHash,
        bytes32 operation
    ) internal {
        if (protocolHash == keccak256(abi.encode("aave"))) {
            aaveConnection(operation);
        } else if (protocolHash == keccak256(abi.encode("compound"))) {
            compoundConnection(operation);
        } else if (protocolHash == keccak256(abi.encode("spark"))) {
            sparkConnection(operation);
        } else if ((protocolHash == keccak256(abi.encode("across")))) {
            acrossConnection(operation);
        }
    }

    function passDepositProportion() internal {
        //This function gets called after a user position is bridged and enters position
        //Makes a deposit() call back to the PoolControl with the proportion of pool of the deposit
        //No value actually transfered, just passing data back to PoolControl
    }

    function extractMessageComponents(
        bytes memory message
    )
        internal
        view
        returns (
            bytes4 method,
            address poolAddress,
            bytes32 protocolHash,
            address actionAddress,
            uint256 num1,
            uint256 userProportionRatio
        )
    {
        // This function separates the method to execute on the destination contract from the data
        (
            bytes4 method,
            address poolAddress,
            bytes32 protocolHash,
            address actionAddress,
            uint256 num1,
            uint256 userProportionRatio
        ) = abi.decode(
                message,
                (bytes4, address, bytes32, address, uint256, uint256)
            );
    }
}
