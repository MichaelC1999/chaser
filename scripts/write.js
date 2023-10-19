const fs = require("fs");
const path = require("path");
const {
    SubscriptionManager,
    simulateScript,
    ResponseListener,
    Location,
    ReturnType,
    decodeResult,
    FulfillmentCode,
} = require("@chainlink/functions-toolkit");
const BridgingConduitABI = require("../BridgingConduitABI.json");
const OracleABI = require("../OracleABI.json");

const subConduitAbi = require("../SubConduitABI.json");
const functionsConsumerAbi = require("../functionsClient.json");

const strategyAbi = require("../strategy.json");

const ethers = require("ethers");
require('dotenv').config({ path: path.resolve(__dirname, '../.env') })

const consumerAddress = "0x9F41D138657Dd79a0eae80ecff2aC3d64E3F35d8"; // REPLACE this with your Functions consumer address
const subscriptionId = 843; // REPLACE this with your subscription ID

const makeRequestMumbai = async () => {
    // hardcoded for Polygon Mumbai
    const routerAddress = "0xb83E47C2bC239B3bf370bc41e1459A34b41238D0";
    const linkTokenAddress = "0x779877A7B0D9E8603169DdbD7836e478b4624789";
    const donId = "fun-ethereum-sepolia-1";
    const explorerUrl = "https://sepolia.etherscan.io/";

    // Initialize functions settings
    const rpcUrl = "https://sepolia.infura.io/v3/8b75f801668e4304bbfad6e8b82aaf0c" // fetch mumbai RPC URL

    if (!rpcUrl)
        throw new Error(`rpcUrl not provided  - check your environment variables`);

    const provider = new ethers.InfuraProvider("goerli", "8b75f801668e4304bbfad6e8b82aaf0c", "64d36ff915584767a9b76ff5342247ea");

    const gasLimit = 300000;

    // Initialize ethers signer and provider to interact with the contracts onchain
    const privateKey = process.env.WALLET_PK; // fetch WALLET_PK
    if (!privateKey)
        throw new Error(
            "private key not provided - check your environment variables"
        );


    const wallet = new ethers.Wallet(privateKey);

    wallet.provider = provider
    let signer = wallet.connect(provider); // create ethers signer for signing transactions

    ///////// START SIMULATION ////////////

    signer.provider = provider


    const bridgingConduit = new ethers.Contract(
        "0x8dFb49332ac866350460FA825cE631a0d723e2cE",
        BridgingConduitABI,
        signer
    );
    // const oracle = new ethers.Contract(
    //     "0x9923D42eF695B5dd9911D05Ac944d4cAca3c4EAB",
    //     OracleABI,
    //     signer
    // );
    // console.log("\nMake request...");
    // const tx = await oracle.settleAssertion("0x799c2008f86f09f56f480610ac0645a6946751ab1f4e845402ed6c084700a39b", {
    //     gasLimit: 1000000
    // })
    // console.log(await tx.wait())

    // Actual transaction call
    // const tx1 = await bridgingConduit.approveOracleSpend()
    // await tx1.wait()
    const transaction = await bridgingConduit.queryMovePosition('aave-v3-ethereum', "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
    // const transaction1 = await bridgingConduit.setCurrentPosition("0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951", "0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357", { gasLimit: 1000000 })
    // const transaction = await bridgingConduit.moveToCurrentPosition(
    //     "0x617ba037000000000000000000000000ff34b3d4aee8ddcd6f9afffb6fe49bd371b8a3570000000000000000000000000000000000000000000000056bc75e2d631000000000000000000000000000004d3fa9e212a9cf7108c6d5ff83c1d42a426f62720000000000000000000000000000000000000000000000000000000000000000",
    //     "0x617ba037000000000000000000000000ff34b3d4aee8ddcd6f9afffb6fe49bd371b8a3570000000000000000000000000000000000000000000000056bc75e2d631000000000000000000000000000004d3fa9e212a9cf7108c6d5ff83c1d42a426f62720000000000000000000000000000000000000000000000000000000000000000",
    //     "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951",
    //     "0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357",
    //     {
    //         gasLimit: 1000000
    //     }
    // )
    // bytes calldata depositDataSig,
    // bytes calldata withdrawDataSig,
    // address spenderAddress,
    // address newPositionTokenAddress
    console.log(await transaction.wait(), await bridgingConduit.viewAssertionsAddress(), "TX")

    // const requestId = await bridgingConduit.s_lastRequestId()


};

makeRequestMumbai().catch((e) => {
    console.error(e);
    process.exit(1);
});