const hre = require("hardhat");
const ethers = require("ethers");
const fs = require('fs');
const { stringToBytes } = require('viem')


const deployments = require('./contractAddresses.json')

const baseDeployments = async () => {

    const [deployer] = await hre.ethers.getSigners();
    const gasPrice = await deployer.provider.getFeeData();
    console.log(gasPrice)

    // Deploy manager to user level chain, deploy the test pool
    const managerDeployment = await hre.ethers.deployContract("ChaserManager", [11155111], {
        gasLimit: 7500000,
        value: 0
    });
    const manager = await managerDeployment.waitForDeployment();
    deployments.sepolia["managerAddress"] = managerDeployment.target

    const registryContract = await (await hre.ethers.deployContract("Registry", [11155111, 11155111, deployments.sepolia["managerAddress"]], {
        gasLimit: 3000000,
        value: 0
    })).waitForDeployment();

    deployments.sepolia["registryAddress"] = registryContract.target
    writeAddressesToFile(deployments)

    await (await manager.addRegistry(deployments.sepolia["registryAddress"])).wait()
    console.log("REGISTRY: ", deployments.sepolia["registryAddress"])

    const calcContract = await (await hre.ethers.deployContract("PoolCalculations", [], {
        gasLimit: 7000000,
        value: 0
    })).waitForDeployment();

    console.log("POOL CALCULATIONS: ", calcContract.target)
    deployments.sepolia["poolCalculationsAddress"] = calcContract.target
    writeAddressesToFile(deployments)

    await manager.addPoolCalculationsAddress(calcContract.target)

    const bridgeLogicContract = await (await hre.ethers.deployContract("BridgeLogic", [11155111, deployments.sepolia["registryAddress"]], {
        gasLimit: 7000000,
        value: 0
    })).waitForDeployment();

    const bridgeLogicAddress = bridgeLogicContract.target
    console.log("BRIDGE LOGIC", bridgeLogicAddress)
    deployments.sepolia["bridgeLogicAddress"] = bridgeLogicAddress
    writeAddressesToFile(deployments)

    const ccip = (await registryContract.localCcipConfigs())
    console.log(ccip)
    const messengerContract = await (await hre.ethers.deployContract("ChaserMessenger", [ccip[0], ccip[1], deployments.sepolia["registryAddress"], bridgeLogicAddress, ccip[2]], {
        gasLimit: 7000000,
        value: 0
    })).waitForDeployment();

    const messengerAddress = messengerContract.target
    deployments.sepolia["messengerAddress"] = messengerAddress
    writeAddressesToFile(deployments)

    const linkToken = await hre.ethers.getContractAt("ERC20", deployments.sepolia["linkToken"]);

    const amount = "200000000000000000"

    console.log("Token Transfer: ", (await (await linkToken.transfer(deployments.sepolia["messengerAddress"], amount)).wait()).hash)

    const receiverContract = await (await hre.ethers.deployContract("BridgeReceiver", [bridgeLogicAddress], {
        gasLimit: 7000000,
        value: 0
    })).waitForDeployment();

    const receiverAddress = receiverContract.target
    deployments.sepolia["receiverAddress"] = receiverAddress
    writeAddressesToFile(deployments)

    const integratorContract = await (await hre.ethers.deployContract("Integrator", [bridgeLogicAddress, deployments.sepolia["registryAddress"]], {
        gasLimit: 7000000,
        value: 0
    })).waitForDeployment();

    const integratorAddress = integratorContract.target
    deployments.sepolia["integratorAddress"] = integratorAddress
    writeAddressesToFile(deployments)

    await (await bridgeLogicContract.addConnections(messengerAddress, receiverAddress, integratorAddress)).wait()

    await (await registryContract.addBridgeLogic(bridgeLogicAddress, messengerAddress, receiverAddress)).wait()

    console.log('MESSENGER: ', await bridgeLogicContract.messenger(), await registryContract.chainIdToMessageReceiver(11155111))

    console.log('RECEIVER: ', await bridgeLogicContract.bridgeReceiverAddress(), await registryContract.receiverAddress())

    await (await registryContract.enableProtocol(
        "aave-v3"
    )).wait();

    await (await registryContract.enableProtocol(
        "compound-v3"
    )).wait();

    console.log(deployments.sepolia)

}

const sepoliaDeployments = async () => {
    const [deployer] = await hre.ethers.getSigners();
    const gasPrice = await deployer.provider.getFeeData();
    console.log(gasPrice)

    const registryContract = await (await hre.ethers.deployContract("Registry", [11155111, 84532, "0x0000000000000000000000000000000000000000"], {
        gasLimit: 3000000,
        value: 0
    })).waitForDeployment();
    const registryAddress = registryContract.target
    deployments.sepolia["registryAddress"] = registryAddress
    writeAddressesToFile(deployments)
    console.log("Sepolia Registry: ", registryContract.target)

    const bridgeLogicContract = await (await hre.ethers.deployContract("BridgeLogic", [84532, registryAddress], {
        gasLimit: 7000000,
        value: 0
    })).waitForDeployment();

    deployments.sepolia["bridgeLogicAddress"] = bridgeLogicContract.target
    const bridgeLogicAddress = deployments.sepolia["bridgeLogicAddress"]
    writeAddressesToFile(deployments)
    console.log("BRIDGE LOGIC", bridgeLogicAddress)

    const ccip = (await registryContract.localCcipConfigs())
    const messengerContract = await (await hre.ethers.deployContract("ChaserMessenger", [ccip[0], ccip[1], registryAddress, bridgeLogicAddress, ccip[2]], {
        gasLimit: 7000000,
        value: 0
    })).waitForDeployment();

    deployments.sepolia["messengerAddress"] = messengerContract.target
    const messengerAddress = deployments.sepolia["messengerAddress"]
    writeAddressesToFile(deployments)

    const linkToken = await hre.ethers.getContractAt("ERC20", deployments.sepolia["linkToken"]);
    const linkAmount = "500000000000000000"
    console.log("Token Transfer: ", (await (await linkToken.transfer(deployments.sepolia["messengerAddress"], linkAmount)).wait()).hash)

    const receiverContract = await (await hre.ethers.deployContract("BridgeReceiver", [bridgeLogicAddress], {
        gasLimit: 7000000,
        value: 0
    })).waitForDeployment();

    deployments.sepolia["receiverAddress"] = receiverContract.target
    const receiverAddress = deployments.sepolia["receiverAddress"]
    writeAddressesToFile(deployments)

    const integratorContract = await (await hre.ethers.deployContract("Integrator", [bridgeLogicAddress, deployments.sepolia["registryAddress"]], {
        gasLimit: 7000000,
        value: 0
    })).waitForDeployment();

    const integratorAddress = integratorContract.target
    deployments.sepolia["integratorAddress"] = integratorAddress
    writeAddressesToFile(deployments)

    const aaveTestToken = await hre.ethers.getContractAt("ERC20", "0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357");
    const aaveAmount = "100000000000000000"
    console.log("AAVE Token Transfer: ", (await (await aaveTestToken.transfer(deployments.sepolia["integratorAddress"], aaveAmount)).wait()).hash)


    const compTestToken = await hre.ethers.getContractAt("ERC20", "0x2D5ee574e710219a521449679A4A7f2B43f046ad");
    const compAmount = "50000000000000000"
    console.log("COMPOUND Token Transfer: ", (await (await compTestToken.transfer(deployments.sepolia["integratorAddress"], compAmount)).wait()).hash)


    const WETH = await hre.ethers.getContractAt("ERC20", deployments.sepolia["WETH"]);
    const WETHAmount = "50000000000000000"
    console.log("WETH Token Transfer: ", (await (await WETH.transfer(deployments.sepolia["integratorAddress"], WETHAmount)).wait()).hash)


    await (await bridgeLogicContract.addConnections(messengerAddress, receiverAddress, integratorAddress)).wait()
    await (await registryContract.addBridgeLogic(bridgeLogicAddress, messengerAddress, receiverAddress)).wait()

    await sepoliaReceivers()
    console.log('MESSENGER: ', await bridgeLogicContract.messenger(), await registryContract.chainIdToMessageReceiver(84532), 'RECEIVER: ', await bridgeLogicContract.bridgeReceiverAddress())

    console.log(deployments.sepolia)
}

const baseSecondConfig = async () => {
    const registryContract = await hre.ethers.getContractAt("Registry", deployments.base["registryAddress"]);
    await (await registryContract.addBridgeReceiver(11155111, deployments.sepolia["receiverAddress"])).wait()
    await (await registryContract.addMessageReceiver(11155111, deployments.sepolia["messengerAddress"])).wait()

    console.log(await registryContract.chainIdToBridgeReceiver(11155111))

}

const sepoliaReceivers = async () => {
    const registryAddress = deployments.sepolia["registryAddress"]
    const registryContract = await hre.ethers.getContractAt("Registry", registryAddress);

    await (await registryContract.addBridgeReceiver(84532, deployments.base["receiverAddress"])).wait()
    await (await registryContract.addMessageReceiver(84532, deployments.base["messengerAddress"])).wait()

}

const basePoolDeploy = async () => {

    const manager = await hre.ethers.getContractAt("ChaserManager", deployments.sepolia["managerAddress"]);

    const poolTx = await (await manager.createNewPool(
        deployments.sepolia["WETH"],
        "0",
        "PoolName",
        {
            gasLimit: 7000000
        }
    )).wait();
    const poolAddress = '0x' + poolTx.logs[0].topics[1].slice(-40);
    deployments.sepolia["poolAddress"] = poolAddress
    writeAddressesToFile(deployments)

    console.log("Pool Address: ", poolAddress);

}

const basePositionSetDeposit = async () => {
    //This function executes the first deposit on a pool and sets the position (The external protocol/chain/pool that this pool will invest assets in)
    const pool = await hre.ethers.getContractAt("PoolControl", deployments.sepolia["poolAddress"])

    const WETH = await hre.ethers.getContractAt("ERC20", deployments.sepolia["WETH"]);

    const amount = "1200000000000000"

    await WETH.approve(deployments.sepolia["poolAddress"], amount)

    const aaveTestToken = await hre.ethers.getContractAt("ERC20", "0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357");
    const aaveAmount = "100000000000000000"
    console.log("AAVE Token Transfer: ", (await (await aaveTestToken.transfer(deployments.sepolia["integratorAddress"], aaveAmount)).wait()).hash)


    const compTestToken = await hre.ethers.getContractAt("ERC20", "0x2D5ee574e710219a521449679A4A7f2B43f046ad");
    const compAmount = "50000000000000000"
    console.log("COMPOUND Token Transfer: ", (await (await compTestToken.transfer(deployments.sepolia["integratorAddress"], compAmount)).wait()).hash)



    const tx = await pool.userDepositAndSetPosition(
        amount,
        totalFeeCalc(amount),
        "0x0242242424242",
        11155111,
        "aave-v3",
        { gasLimit: 8000000 }
    )

    console.log(`Pool 0x...${deployments.sepolia["poolAddress"].slice(34)} position set and initial deposit tx hash: `, (await tx.wait()).hash)
}

const baseSimulateCCIPReceive = async (messageDataCCIP) => {


    const trimMessageData = messageDataCCIP.split("000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000e0").join("").split("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000100").join("")

    console.log(trimMessageData)
    const pool = await hre.ethers.getContractAt("PoolControl", deployments.base["poolAddress"])
    const registryContract = await hre.ethers.getContractAt("Registry", deployments.base["registryAddress"]);
    const messengerContract = await hre.ethers.getContractAt("ChaserMessenger", deployments.base["messengerAddress"])

    // console.log(await messengerContract.ccipDecodeReceive("0x4d1c4fe3f27639b363f9d52e4dcadc62a2d95f9e9730c8b79fbb437d4e7ab563", trimMessageData))

    console.log("Deposit fulfillment tx hash: ", (await (await messengerContract.ccipReceiveManual("0x4d1c4fe3f27639b363f9d52e4dcadc62a2d95f9e9730c8b79fbb437d4e7ab563", trimMessageData)).wait()).hash)
    const tokenContract = await (hre.ethers.getContractAt("IPoolToken", await pool.poolToken()))
    console.log(await tokenContract.totalSupply())

}

const sepoliaSimulateCCIPReceive = async (messageDataCCIP) => {
    // message should be from event on the base tx (the tx that the user makes with withdraw req) with topics 0,1 as:
    // 0x244e451036514e829e60556484796d2251dc3d952cd079db45d2bfb4c0aff2a1, 0x233263c9f1eb833d29da3a8a1e5149771cfcfa38353e11605e22a1bde618d373
    // From this event take the entirety of the hex bytes and pass as message
    const trimMessageData = messageDataCCIP.split("000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000e0").join("").split("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000100").join("")

    const messengerContract = await (hre.ethers.getContractAt("ChaserMessenger", deployments.sepolia["messengerAddress"]))
    console.log(trimMessageData)
    console.log(await messengerContract.ccipDecodeReceive("0x4d1c4fe3f27639b363f9d52e4dcadc62a2d95f9e9730c8b79fbb437d4e7ab563", trimMessageData))
    const bridgeLogicContract = await (hre.ethers.getContractAt("BridgeLogic", deployments.sepolia["bridgeLogicAddress"]))
    const WETH = await hre.ethers.getContractAt("ERC20", deployments.sepolia["WETH"]);
    const contractWethBal = await WETH.balanceOf(deployments.sepolia["bridgeLogicAddress"])

    console.log(await bridgeLogicContract.readBalanceAtNonce(deployments.base["poolAddress"], 0), await bridgeLogicContract.readBalanceAtNonce(deployments.base["poolAddress"], 1), await bridgeLogicContract.readBalanceAtNonce(deployments.base["poolAddress"], 2), await bridgeLogicContract.readBalanceAtNonce(deployments.base["poolAddress"], 3), await bridgeLogicContract.bridgeNonce(deployments.base["poolAddress"]))
    // console.log(await bridgeLogicContract.getUserMaxWithdraw(contractWethBal, "100000000000000000", deployments.base["poolAddress"], 1))


    console.log("Transaction Hash: ", (await (await messengerContract.ccipReceiveManual("0x4d1c4fe3f27639b363f9d52e4dcadc62a2d95f9e9730c8b79fbb437d4e7ab563", trimMessageData)).wait()).hash)
}

const setPivotConfigs = async () => {
    const pool = await hre.ethers.getContractAt("PoolControl", deployments.sepolia["poolAddress"])
    const registryContract = await hre.ethers.getContractAt("Registry", deployments.sepolia["registryAddress"]);

    // await (await registryContract.enableProtocol(
    //   "aave-v3"
    // )).wait();

    // const arbitrationContract = await (await hre.ethers.deployContract("ArbitrationContract", [deployments.sepolia["registryAddress"], 11155111], {
    //   gasLimit: 7000000,
    //   value: 0
    // })).waitForDeployment();

    // const investmentStrategyContract = await (await hre.ethers.deployContract("InvestmentStrategy", [], {
    //   gasLimit: 7000000,
    //   value: 0
    // })).waitForDeployment();

    // console.log(investmentStrategyContract)

    // (await (await registryContract.addInvestmentStrategyContract(deployments.sepolia["investmentStrategy"])).wait());
    // deployments.sepolia["investmentStrategy"] = investmentStrategyContract.target

    // (await (await registryContract.addArbitrationContract(deployments.sepolia["arbitrationContract"])).wait())

    // deployments.sepolia["arbitrationContract"] = arbitrationContract.target
    // writeAddressesToFile(deployments)


}

const addStrategyCode = async () => {
    let sourceString = ``
    const sourceCode = stringToBytes(sourceString)
    const investmentStrategyContract = await hre.ethers.getContractAt("InvestmentStrategy", deployments.sepolia["investmentStrategy"]);

    console.log(sourceCode)
    const transactionResponse = await investmentStrategyContract.addStrategy(sourceCode, "lowVolHighYield", { gasLimit: 7000000 });
    const receipt = await transactionResponse.wait();

}


const poolStatRead = async () => {
    const pool = await hre.ethers.getContractAt("PoolControl", deployments.sepolia["poolAddress"])
    const tokenContract = await (hre.ethers.getContractAt("IPoolToken", await pool.poolToken()))
    const calcContract = await hre.ethers.getContractAt("PoolCalculations", deployments.sepolia["poolCalculationsAddress"])

    console.log(
        "TARGETS: ",
        await pool.targetPositionMarketId(),
        await pool.targetPositionChain(),
        await pool.targetPositionProtocolHash(),
        "CURRENTS: ",
        await pool.currentPositionAddress(),
        await pool.currentPositionMarketId(),
        await pool.currentPositionChain(),
        await pool.currentPositionProtocolHash(),
        await pool.currentRecordPositionValue(),
        await pool.poolNonce(),
        await pool.localChain(),
        "LASTS: ",
        await pool.lastPositionAddress(),
        await pool.lastPositionChain(),
        await pool.lastPositionProtocolHash())

    console.log("TOKENS: ",
        await tokenContract.totalSupply(),
        await calcContract.getScaledRatio(await pool.poolToken(), "0x1CA2b10c61D0d92f2096209385c6cB33E3691b5E"),
        await tokenContract.balanceOf("0x1CA2b10c61D0d92f2096209385c6cB33E3691b5E"),
        await calcContract.getScaledRatio(await pool.poolToken(), "0xF80cAb395657197967EaEdf94bD7f8a75Ad8F373"),
        await tokenContract.balanceOf("0xF80cAb395657197967EaEdf94bD7f8a75Ad8F373"))

    const bridgeLogicAddress = deployments.sepolia["bridgeLogicAddress"]
    const bridgeLogic = await hre.ethers.getContractAt("BridgeLogic", bridgeLogicAddress);


    const integratorContract = await hre.ethers.getContractAt("Integrator", deployments.sepolia["integratorAddress"]);

    // Get hash of protocol
    const protocolHash = await integratorContract.hasher("aave-v3")
    console.log(await bridgeLogic.poolToAsset(deployments.sepolia["poolAddress"]),
        await bridgeLogic.poolToCurrentPositionMarket(deployments.sepolia["poolAddress"]),
        await bridgeLogic.poolToCurrentProtocolHash(deployments.sepolia["poolAddress"]),)

    const curPos = await bridgeLogic.getPositionBalance(deployments.sepolia["poolAddress"])

    //get pool broker, check what the asset is
    const registryContract = await hre.ethers.getContractAt("Registry", deployments.sepolia["registryAddress"]);

    const poolBrokerAddr = await registryContract.poolAddressToBroker(deployments.sepolia["poolAddress"])
    const poolBroker = await hre.ethers.getContractAt("PoolBroker", poolBrokerAddr);

    console.log(await poolBroker.assetAddress())

    console.log('CURRENT POSITION VALUE + INTEREST: ', curPos)
}

const baseDeposit = async () => {
    const pool = await hre.ethers.getContractAt("PoolControl", deployments.base["poolAddress"])

    const amount = "2000000000000000"

    const WETH = await hre.ethers.getContractAt("ERC20", deployments.base["WETH"]);
    await (await WETH.approve(deployments.base["poolAddress"], amount)).wait()
    const tx = await pool.userDeposit(
        amount,
        totalFeeCalc(amount),
        { gasLimit: 2000000 }
    )

    console.log("Non position set Deposit: ", (await tx.wait()).hash)
}

const baseWithdraw = async () => {
    // Creates CCIP message, manually executed on the base messenger contact, which sends withdraw through across and finalizes on sepolia

    const pool = await hre.ethers.getContractAt("PoolControl", deployments.base["poolAddress"])
    const amount = "1200000000000000"
    const tx = await pool.userWithdrawOrder(amount, { gasLimit: 8000000 })
    console.log((await tx.wait()).hash)
}

const baseCallPivot = async () => {
    const pool = await hre.ethers.getContractAt("PoolControl", deployments.sepolia["poolAddress"])
    const integratorContract = await hre.ethers.getContractAt("Integrator", deployments.sepolia["integratorAddress"]);
    const registryContract = await hre.ethers.getContractAt("Registry", deployments.sepolia["registryAddress"]);



    // Get hash of protocol
    // console.log("PIVOT TRANSACTION: ", (await (await pool.sendPositionChange(
    //   "0x0585585858585",
    //   "aave-v3",
    //   11155111,
    //   { gasLimit: 4000000 }

    // )).wait()).hash)


    // const WETH = await hre.ethers.getContractAt("ERC20", deployments.sepolia["WETH"]);
    // await (await WETH.transfer(deployments.sepolia["integratorAddress"], "100000000000")).wait()

    const USDC = await hre.ethers.getContractAt("ERC20", "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238");
    await (await USDC.approve(deployments.sepolia["arbitrationContract"], 500000)).wait()


    console.log((await (await pool.queryMovePosition("aave-v3", "eihfe", 11155111, 500000, { gasLimit: 7000000 })).wait()).hash)
    //IMPORTANT - TEST IF UMA TESTNET FOLLOWS LIVENESS PERIOD
}

const sepoliaIntegrationsTest = async () => {
    const integratorContract = await hre.ethers.getContractAt("Integrator", deployments.sepolia["integratorAddress"]);
    const registryContract = await hre.ethers.getContractAt("Registry", deployments.sepolia["registryAddress"]);

    // Get hash of protocol
    const protocolHash = await integratorContract.hasher("aave-v3")

    // Get hash operations
    const operation = await integratorContract.hasher("deposit")

    const amount = "50000000000000"

    const WETH = await hre.ethers.getContractAt("ERC20", "0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357");
    // console.log("Token Transfer: ", (await (await WETH.transfer(deployments.sepolia["integratorAddress"], amount)).wait()).hash)
    console.log(protocolHash, operation)
    // Call the routeExternal function
    // console.log((await (await integratorContract.routeExternalProtocolInteraction(protocolHash, operation, amount, deployments.base["poolAddress"], "0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357", "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951", { gasLimit: 1000000 })).wait()).hash)

    const bridgeLogicAddress = deployments.sepolia["bridgeLogicAddress"]
    const bridgeLogic = await hre.ethers.getContractAt("BridgeLogic", bridgeLogicAddress);

    //Check aToken balance of ntegrator
    const curPos = await integratorContract.getCurrentPosition(
        deployments.base["poolAddress"],
        "0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357",
        "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951",
        protocolHash
    );
    console.log(await bridgeLogic.poolToAsset(deployments.base["poolAddress"]), await bridgeLogic.poolToCurrentPositionMarket(deployments.base["poolAddress"]), await bridgeLogic.poolToCurrentMarketId(deployments.base["poolAddress"]), await bridgeLogic.poolToCurrentProtocolHash(deployments.base["poolAddress"]))
    const curPos2 = await bridgeLogic.getPositionBalance(deployments.base["poolAddress"])

    console.log(curPos, curPos2)


    // console.log(await bridgeLogic.readBalanceAtNonce(deployments.base["poolAddress"], 0), await bridgeLogic.readBalanceAtNonce(deployments.base["poolAddress"], 1), await bridgeLogic.readBalanceAtNonce(deployments.base["poolAddress"], 2), await bridgeLogic.readBalanceAtNonce(deployments.base["poolAddress"], 3), await bridgeLogic.bridgeNonce(deployments.base["poolAddress"]))

    console.log("Current Position: ", curPos, "Broker: ", await registryContract.poolAddressToBroker(deployments.base["poolAddress"]))
}

const manualAcrossMessageHandle = async (amount, message) => {
    //This is used when a Bridge message doesnt seem to go through and we need to determine if the issue is reversion
    const receiverContract = await hre.ethers.getContractAt("BridgeReceiver", deployments.base["receiverAddress"]);
    const wethAddr = deployments.base["WETH"]

    //message should be bytes from topic 0xe503f02a28c80b867adfed9777a61077c421693358e2f0f1fc54e13acaa18005
    const trimMessageData = message
        .split("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000160")
        .join("")
        .split("000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c0")
        .join("")

    // Simulate the receiver on base getting bridged WETH, by sending WETH from within base to the receiver
    const WETH = await hre.ethers.getContractAt("ERC20", wethAddr);

    console.log((await (await WETH.transfer(deployments.base["receiverAddress"], amount)).wait()).hash)

    // Paste the message from the V3FundsDeposited event that succeeded on the origin chain
    console.log(await receiverContract.decodeMessageEvent(trimMessageData))


    console.log("Across Handle Hash: ", (await (await receiverContract.handleV3AcrossMessage(wethAddr, amount, wethAddr, trimMessageData, { gasLimit: 8000000 })).wait()).hash)

}

async function mainExecution() {

    try {
        // DEMO STEPS
        // Instructions: Uncomment the below function calls one at a time. Pay attention to the purpose of each section and execute according to what functionality you would like to test
        // Prerequisites:  0.003 WETH and .1 ETH on Base Sepolia, and .1 ETH on Ethereum Sepolia
        // 1. Add private key as "WALLET_PK" env in "../.env"
        // 2. Add your RPC URI/key in "../hardhat.config.js"
        // --------------------------------------------------------------------------------------------
        // IF LOOKING TO DEPLOY YOUR OWN INSTANCE OF ALL CONTRACTS - EXECUTE THE FOLLOWING TWO FUNCTIONS ONE AT A TIME.
        // await baseDeployments() //CHECK THAT THE DEFAULT NETWORK IN "..hardhat.config.js" IS base
        // await sepoliaDeployments() //CHANGE THE DEFAULT NETWORK IN "..hardhat.config.js" TO sepolia
        // await baseSecondConfig() //CHANGE THE DEFAULT NETWORK IN "..hardhat.config.js" TO base
        // --------------------------------------------------------------------------------------------
        // IF YOU EXECUTED THE PRIOR SECTION AND/OR WOULD LIKE TO DEPLOY YOUR POOL FOR TESTING - EXECUTE THE FOLLOWING FUNCTION
        // This function also sends the initial deposit funds through the bridge into the investment as the position is set on sepolia
        // await setPivotConfigs()
        // await basePoolDeploy()
        // await basePositionSetDeposit()

        // --------------------------------------------------------------------------------------------
        // AFTER EXECUTING basePoolDeploy() OR baseDeposit(), WAIT FOR THE ETHEREUM SEPOLIA ACROSS SPOKEPOOL TO RECEIVE THE DEPOSIT
        // GET THE MESSAGE DATA FROM BASESCAN, COPYING THE HEX DATA BYTES FROM EVENT "0x244e451036514e829e60556484796d2251dc3d952cd079db45d2bfb4c0aff2a1"
        // PASTE MESSAGE DATA INTO THE ARGUMENT FOR FOLLOWING FUNCTION
        // await baseSimulateCCIPReceive("0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000e00414e990000000000000000000000000000000000000000000000000000000000000000000000000000000009bdc76b596051e1e86eadb2e2af2a491e32bfa4800000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000886c98ec54a530000000000000000000000000000000000000000000000000005af3107a400003361877a052af4d82301c2eea28d1667f3fdbaff73f9d57880f1b317a552eda2")
        // --------------------------------------------------------------------------------------------
        // EXECUTE THIS FUNCTION TO START A DEPOSIT TO THE POOL
        // await baseDeposit()
        // REMINDER TO REVISIT THE ABOVE SECTION TO SIMULATE THE CCIP TRIGGER MESSAGE FOR EXECUTING THE DEPOSIT ON ETHEREUM SEPOLIA
        // --------------------------------------------------------------------------------------------
        // await poolStatRead()

        // await baseWithdraw()

        // await sepoliaSimulateCCIPReceive("0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001003705af6d000000000000000000000000000000000000000000000000000000000000000000000000000000009bdc76b596051e1e86eadb2e2af2a491e32bfa48000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000803f4c40f2d9e47df3a43c5c97200a65dd80990bf9d69827733cf5f393681c90dc000000000000000000000000000000000000000000000000000886c98b760000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000004a03cea247fc197")
        // --------------------------------------------------------------------------------------------
        // await baseCallPivot()
        await poolStatRead()
        // sepoliaReceivers()
        // await manualAcrossMessageHandle("99600000000000", "0xBD4F4B890000000000000000000000000000000000000000000000000000000000000000000000000000000006B838BF89DFBCFA5FFD085B1FCD5BDD873F2E95000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000802B537FE6CC6E2B9E2AAAC4F5DB3F9477626D66FAB37FE70D2213EDC075C5B71900000000000000000000000000000000000000000000000000005A95EE9EA00000000000000000000000000000000000000000000000000000003F4D0505231E00000000000000000000000000000000000000000000000000001B48EB57E000")

        // await sepoliaIntegrationsTest()



    } catch (error) {
        console.error(error);
        console.log(error.logs)
        process.exitCode = 1;
    }

}


function totalFeeCalc(amount) {
    return (parseInt((Number(amount) / 400).toString())).toString()
}

function writeAddressesToFile(contractAddresses) {
    const fileName = './scripts/contractAddresses.json';

    // Write the merged addresses back to the file
    fs.writeFileSync(fileName, JSON.stringify(contractAddresses, null, 2), 'utf-8');
    // console.log(`Addresses written to ${fileName}`);
}

// writeAddressesToFile({ ...deployments, base: { "ihef": "iefhr" } })


mainExecution()