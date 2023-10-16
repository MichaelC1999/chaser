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

    const provider = new ethers.InfuraProvider("sepolia", "8b75f801668e4304bbfad6e8b82aaf0c", "64d36ff915584767a9b76ff5342247ea");

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


    console.log(signer, provider)
    const bridgingConduit = new ethers.Contract(
        "0x1Bff74cCF0b418230CE2D6149aF7E01CFd3C544B",
        BridgingConduitABI,
        signer
    );
    console.log("\nMake request...");

    // Actual transaction call
    const transaction = await bridgingConduit.executeMovePosition("fdsf", { gasLimit: 1000000 })

    console.log(await transaction.wait(), "TX")

    // const requestId = await bridgingConduit.s_lastRequestId()


};

makeRequestMumbai().catch((e) => {
    console.error(e);
    process.exit(1);
});