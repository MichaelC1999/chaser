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

const functionsConsumerAbi = require("../functionsClient.json");
const strategyAbi = require("../strategy.json");

const ethers = require("ethers");
require('dotenv').config({ path: path.resolve(__dirname, '../.env') })

const consumerAddress = "0x7a475B488bDbA9EAe56812F7aeCf84b8949B9379"; // REPLACE this with your Functions consumer address
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
    const strategyContract = new ethers.Contract("0x9e6CED8aE154fFCaAB3Bb9dC6E9d78374E69C2a6", strategyAbi, provider);

    console.log('TEXT', provider, rpcUrl, process.env.WALLET_PK)
    const source = await strategyContract.strategySourceCode();
    console.log(source, 'src')

    const args = [];
    args.push("0x00907f9921424583e7ffbfedf84f92b7b2be4977");
    args.push("aave-v3-ethereum");
    args.push("compound-v3-ethereum");
    args.push("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48");
    // Cannot be higher than 300000
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

    console.log("Start simulation...", signer, JSON.stringify(provider));

    const response = await simulateScript({
        source: source,
        args: args,
        bytesArgs: [], // bytesArgs - arguments can be encoded off-chain to bytes.
        secrets: {}, // no secrets in this example
    });

    console.log("Simulation result", response);
    const errorString = response.errorString;
    if (errorString) {
        console.log(`❌ Error during simulation: `, errorString);
    } else {
        const returnType = ReturnType.string;
        const responseBytesHexstring = response.responseBytesHexstring;
        // if (ethers.utils.arrayify(responseBytesHexstring).length > 0) {
        const decodedResponse = decodeResult(
            response.responseBytesHexstring,
            returnType
        );
        console.log(`✅ Decoded response to ${returnType}: `, decodedResponse);
        // }
    }

    //////// ESTIMATE REQUEST COSTS ////////
    // console.log("\nEstimate request costs...");
    // // Initialize and return SubscriptionManager
    // const subscriptionManager = new SubscriptionManager({
    //     signer: signer,
    //     linkTokenAddress: linkTokenAddress,
    //     functionsRouterAddress: routerAddress,
    // });
    // await subscriptionManager.initialize();

    // // estimate costs in Juels

    // const gasPriceWei = await signer.getGasPrice(); // get gasPrice in wei

    // const estimatedCostInJuels =
    //     await subscriptionManager.estimateFunctionsRequestCost({
    //         donId: donId, // ID of the DON to which the Functions request will be sent
    //         subscriptionId: subscriptionId, // Subscription ID
    //         callbackGasLimit: gasLimit, // Total gas used by the consumer contract's callback
    //         gasPriceWei: BigInt(gasPriceWei), // Gas price in gWei
    //     });

    // console.log(
    //     `Fulfillment cost estimated to ${ethers.utils.formatEther(
    //         estimatedCostInJuels
    //     )} LINK`
    // );

    //////// MAKE REQUEST ////////


    const functionsConsumer = new ethers.Contract(
        consumerAddress,
        functionsConsumerAbi,
        signer
    );
    console.log("\nMake request...");

    // Actual transaction call
    const transaction = await functionsConsumer.sendRequest(
        source, // source
        Location.Remote, // user hosted secrets - encryptedSecretsUrls - empty in this example
        "0x", // don hosted secrets - slot ID - empty in this example
        args,
        [], // bytesArgs - arguments can be encoded off-chain to bytes.
        subscriptionId,
        gasLimit,
        {
            gasLimit: 1000000
        }
    );

    console.log(await transaction.wait(), "TX")

    const requestId = await functionsConsumer.s_lastRequestId()

    // Log transaction details
    console.log(
        `\n✅ Functions request sent! Transaction hash ${transaction.hash} -  Request id is ${requestId}. Waiting for a response...`
    );

    console.log(
        `See your request in the explorer ${explorerUrl}/tx/${transaction.hash}`
    );

    const responseListener = new ResponseListener({
        provider: provider,
        functionsRouterAddress: routerAddress,
    }); // Instantiate a ResponseListener object to wait for fulfillment.
    (async () => {
        try {
            const response = await new Promise((resolve, reject) => {
                responseListener
                    .listenForResponse(requestId)
                    .then((response) => {
                        console.log(response, 'SUCCESSFULLY LISTENED')
                        resolve(response); // Resolves once the request has been fulfilled.
                    })
                    .catch((error) => {
                        console.log(error, "LISTEN FAIL")
                        reject(error); // Indicate that an error occurred while waiting for fulfillment.
                    });
            });

            const fulfillmentCode = response.fulfillmentCode;

            if (fulfillmentCode === FulfillmentCode.FULFILLED) {
                console.log(
                    `\n✅ Request ${requestId} successfully fulfilled. Cost is ${ethers.utils.formatEther(
                        response.totalCostInJuels
                    )} LINK.Complete reponse: `,
                    response
                );
            } else if (fulfillmentCode === FulfillmentCode.USER_CALLBACK_ERROR) {
                console.log(
                    `\n⚠️ Request ${requestId} fulfilled. However, the consumer contract callback failed. Cost is ${ethers.utils.formatEther(
                        response.totalCostInJuels
                    )} LINK.Complete reponse: `,
                    response
                );
            } else {
                console.log(
                    `\n❌ Request ${requestId} not fulfilled. Code: ${fulfillmentCode}. Cost is ${ethers.utils.formatEther(
                        response.totalCostInJuels
                    )} LINK.Complete reponse: `,
                    response
                );
            }

            const errorString = response.errorString;
            if (errorString) {
                console.log(`\n❌ Error during the execution: `, errorString);
            } else {
                const responseBytesHexstring = response.responseBytesHexstring;
                if (ethers.utils.arrayify(responseBytesHexstring).length > 0) {
                    const decodedResponse = decodeResult(
                        response.responseBytesHexstring,
                        ReturnType.string
                    );
                    console.log(
                        `\n✅ Decoded response to ${ReturnType.string}: `,
                        decodedResponse
                    );
                }
            }
        } catch (error) {
            console.error("Error listening for response:", error);
        }
    })();
};

makeRequestMumbai().catch((e) => {
    console.error(e);
    process.exit(1);
});