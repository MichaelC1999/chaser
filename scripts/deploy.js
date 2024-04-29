const hre = require("hardhat");
const ethers = require("ethers");
const fs = require('fs');
const { stringToBytes } = require('viem')


const deployments = require('./contractAddresses.json')

const sepoliaDeployments = async () => {

  const [deployer] = await hre.ethers.getSigners();
  const gasPrice = await deployer.provider.getFeeData();
  console.log(gasPrice)

  // Deploy manager to user level chain, deploy the test pool

  const Manager = await hre.ethers.getContractFactory("ChaserManager");
  const manager = await hre.upgrades.deployProxy(Manager, [11155111]);
  await manager.waitForDeployment();
  console.log("Manager deployed to:", await manager.getAddress());
  const managerAddress = await manager.getAddress()
  deployments.sepolia["managerAddress"] = managerAddress

  console.log('MANAGER OWNER: ', await manager.owner())

  const registryContract = await (await hre.ethers.deployContract("Registry", [11155111, 11155111, deployments.sepolia["managerAddress"]], {
    gasLimit: 3000000,
    value: 0
  })).waitForDeployment();

  deployments.sepolia["registryAddress"] = registryContract.target
  writeAddressesToFile(deployments)

  await (await manager.addRegistry(deployments.sepolia["registryAddress"])).wait()
  console.log("REGISTRY: ", deployments.sepolia["registryAddress"])

  const calcContract = await (await hre.ethers.deployContract("PoolCalculations", [deployments.sepolia["registryAddress"]], {
    gasLimit: 7000000,
    value: 0
  })).waitForDeployment();

  console.log("POOL CALCULATIONS: ", calcContract.target)
  deployments.sepolia["poolCalculationsAddress"] = calcContract.target
  writeAddressesToFile(deployments)

  await manager.addPoolCalculationsAddress(calcContract.target)

  const BridgeLogic = await hre.ethers.getContractFactory("BridgeLogic");
  const bridgeLogicContract = await hre.upgrades.deployProxy(BridgeLogic, [11155111, 11155111, deployments.sepolia["registryAddress"]]);
  await bridgeLogicContract.waitForDeployment();
  const bridgeLogicAddress = await bridgeLogicContract.getAddress()
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

  const receiverContract = await (await hre.ethers.deployContract("BridgeReceiver", [bridgeLogicAddress, deployments.sepolia["spokePool"]], {
    gasLimit: 7000000,
    value: 0
  })).waitForDeployment();

  const receiverAddress = receiverContract.target
  deployments.sepolia["receiverAddress"] = receiverAddress
  writeAddressesToFile(deployments)

  const Int = await hre.ethers.getContractFactory("Integrator");
  const int = await hre.upgrades.deployProxy(Int, [bridgeLogicAddress, deployments.sepolia["registryAddress"]]);
  await int.waitForDeployment();
  console.log("Integrator deployed to:", await int.getAddress());
  const integratorAddress = await int.getAddress()
  deployments.sepolia["integratorAddress"] = integratorAddress
  writeAddressesToFile(deployments)

  const aaveTestToken = await hre.ethers.getContractAt("ERC20", "0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357");
  const aaveAmount = "10000000000000000"
  console.log("AAVE Token Transfer: ", (await (await aaveTestToken.transfer(deployments.sepolia["integratorAddress"], aaveAmount)).wait()).hash)

  const compTestToken = await hre.ethers.getContractAt("ERC20", "0x2D5ee574e710219a521449679A4A7f2B43f046ad");
  const compAmount = "10000000000000000"

  console.log("COMPOUND Token Transfer: ", (await (await compTestToken.transfer(deployments.sepolia["integratorAddress"], compAmount)).wait()).hash)


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
  console.log("FINISHED SEPOLIA DEPLOYMENTS 1")
}

const baseDeployments = async () => {
  const [deployer] = await hre.ethers.getSigners();
  const gasPrice = await deployer.provider.getFeeData();
  console.log(gasPrice)

  const registryContract = await (await hre.ethers.deployContract("Registry", [84532, 11155111, "0x0000000000000000000000000000000000000000"], {
    gasLimit: 3000000,
    value: 0
  })).waitForDeployment();
  const registryAddress = registryContract.target
  deployments.base["registryAddress"] = registryAddress
  writeAddressesToFile(deployments)
  console.log("Sepolia Registry: ", registryContract.target)

  const BridgeLogic = await hre.ethers.getContractFactory("BridgeLogic");
  const bridgeLogicContract = await hre.upgrades.deployProxy(BridgeLogic, [84532, 11155111, registryAddress]);
  await bridgeLogicContract.waitForDeployment();
  const bridgeLogicAddress = await bridgeLogicContract.getAddress()
  console.log("BRIDGE LOGIC", bridgeLogicAddress)
  deployments.base["bridgeLogicAddress"] = bridgeLogicAddress
  writeAddressesToFile(deployments)


  const ccip = (await registryContract.localCcipConfigs())
  const messengerContract = await (await hre.ethers.deployContract("ChaserMessenger", [ccip[0], ccip[1], registryAddress, bridgeLogicAddress, ccip[2]], {
    gasLimit: 7000000,
    value: 0
  })).waitForDeployment();

  deployments.base["messengerAddress"] = messengerContract.target
  const messengerAddress = deployments.base["messengerAddress"]
  writeAddressesToFile(deployments)

  const linkToken = await hre.ethers.getContractAt("ERC20", deployments.base["linkToken"]);
  const linkAmount = "500000000000000000"
  console.log("Token Transfer: ", (await (await linkToken.transfer(deployments.base["messengerAddress"], linkAmount)).wait()).hash)

  const receiverContract = await (await hre.ethers.deployContract("BridgeReceiver", [bridgeLogicAddress, deployments.base["spokePool"]], {
    gasLimit: 7000000,
    value: 0
  })).waitForDeployment();

  deployments.base["receiverAddress"] = receiverContract.target
  const receiverAddress = deployments.base["receiverAddress"]
  writeAddressesToFile(deployments)

  const Int = await hre.ethers.getContractFactory("Integrator");
  const int = await hre.upgrades.deployProxy(Int, [bridgeLogicAddress, deployments.base["registryAddress"]]);
  await int.waitForDeployment();
  console.log("Integrator deployed to:", await int.getAddress());
  const integratorAddress = await int.getAddress()
  deployments.base["integratorAddress"] = integratorAddress
  writeAddressesToFile(deployments)



  const WETH = await hre.ethers.getContractAt("ERC20", deployments.base["WETH"]);
  const WETHAmount = "10000000000000000"
  console.log("WETH Token Transfer: ", (await (await WETH.transfer(deployments.base["integratorAddress"], WETHAmount)).wait()).hash)


  await (await bridgeLogicContract.addConnections(messengerAddress, receiverAddress, integratorAddress)).wait()
  await (await registryContract.addBridgeLogic(bridgeLogicAddress, messengerAddress, receiverAddress)).wait()
  await baseReceivers()
  console.log('MESSENGER: ', await bridgeLogicContract.messenger(), await registryContract.chainIdToMessageReceiver(84532), 'RECEIVER: ', await bridgeLogicContract.bridgeReceiverAddress())

  console.log(deployments.base)
  console.log("FINISHED BASE DEPLOYMENTS 1")
}

const sepoliaSecondConfig = async () => {
  const registryContract = await hre.ethers.getContractAt("Registry", deployments.sepolia["registryAddress"]);
  await (await registryContract.addBridgeReceiver(84532, deployments.base["receiverAddress"])).wait()
  await (await registryContract.addMessageReceiver(84532, deployments.base["messengerAddress"])).wait()
  console.log("FINISHED SEPOLIA DEPLOYMENTS 2")

}

const baseReceivers = async () => {
  const registryAddress = deployments.base["registryAddress"]
  const registryContract = await hre.ethers.getContractAt("Registry", registryAddress);

  await (await registryContract.addBridgeReceiver(11155111, deployments.sepolia["receiverAddress"])).wait()
  await (await registryContract.addMessageReceiver(11155111, deployments.sepolia["messengerAddress"])).wait()

}

const sepoliaPoolDeploy = async () => {

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

const sepoliaPositionSetDeposit = async () => {
  //This function executes the first deposit on a pool and sets the position (The external protocol/chain/pool that this pool will invest assets in)
  const pool = await hre.ethers.getContractAt("PoolControl", deployments.sepolia["poolAddress"])

  const WETH = await hre.ethers.getContractAt("ERC20", deployments.sepolia["WETH"]);

  const amount = "1500000000000000"

  await WETH.approve(deployments.sepolia["poolAddress"], amount)


  const tx = await pool.userDepositAndSetPosition(
    amount,
    totalFeeCalc(amount),
    "aave-v3",
    "0x0242242424242",
    84532,
    { gasLimit: 8000000 }
  )

  console.log(`Pool 0x...${deployments.base["poolAddress"].slice(34)} position set and initial deposit tx hash: `, (await tx.wait()).hash)
}

const sepoliaSimulateCCIPReceive = async (messageDataCCIP) => {


  const trimMessageData = messageDataCCIP.split("000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000e0").join("").split("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000100").join("")

  console.log(trimMessageData)
  const pool = await hre.ethers.getContractAt("PoolControl", deployments.sepolia["poolAddress"])
  const registryContract = await hre.ethers.getContractAt("Registry", deployments.sepolia["registryAddress"]);
  const messengerContract = await hre.ethers.getContractAt("ChaserMessenger", deployments.sepolia["messengerAddress"])

  // console.log(await messengerContract.ccipDecodeReceive("0x4d1c4fe3f27639b363f9d52e4dcadc62a2d95f9e9730c8b79fbb437d4e7ab563", trimMessageData))

  console.log("Deposit fulfillment tx hash: ", (await (await messengerContract.ccipReceiveManual("0x4d1c4fe3f27639b363f9d52e4dcadc62a2d95f9e9730c8b79fbb437d4e7ab563", trimMessageData)).wait()).hash)
  const tokenContract = await (hre.ethers.getContractAt("IPoolToken", await pool.poolToken()))
  console.log(await tokenContract.totalSupply())

}

const baseSimulateCCIPReceive = async (messageDataCCIP) => {
  // message should be from event on the sepolia tx (the tx that the user makes with withdraw req) with topics 0,1 as:
  // From this event take the entirety of the hex bytes and pass as message
  const trimMessageData = messageDataCCIP.split("000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000e0").join("").split("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000100").join("")

  const messengerContract = await (hre.ethers.getContractAt("ChaserMessenger", deployments.base["messengerAddress"]))
  console.log(trimMessageData)
  console.log(await messengerContract.ccipDecodeReceive("0x4d1c4fe3f27639b363f9d52e4dcadc62a2d95f9e9730c8b79fbb437d4e7ab563", trimMessageData))
  const bridgeLogicContract = await (hre.ethers.getContractAt("BridgeLogic", deployments.base["bridgeLogicAddress"]))
  const WETH = await hre.ethers.getContractAt("ERC20", deployments.base["WETH"]);
  const contractWethBal = await WETH.balanceOf(deployments.base["bridgeLogicAddress"])

  // console.log(await bridgeLogicContract.getUserMaxWithdraw(contractWethBal, "100000000000000000", deployments.sepolia["poolAddress"], 1))


  console.log("Transaction Hash: ", (await (await messengerContract.ccipReceiveManual("0x4d1c4fe3f27639b363f9d52e4dcadc62a2d95f9e9730c8b79fbb437d4e7ab563", trimMessageData)).wait()).hash)
}

const setPivotConfigs = async () => {
  const registryContract = await hre.ethers.getContractAt("Registry", deployments.sepolia["registryAddress"]);
  const arbitrationContract = await (await hre.ethers.deployContract("ArbitrationContract", [deployments.sepolia["registryAddress"], 11155111], {
    gasLimit: 7000000,
    value: 0
  })).waitForDeployment();

  //NO NEED TO REDEPLOY INVESTMENTSTRATEGY CONTRACT
  // const investmentStrategyContract = await (await hre.ethers.deployContract("InvestmentStrategy", [], {
  //   gasLimit: 7000000,
  //   value: 0
  // })).waitForDeployment();

  // const investmentStrategyAddress = investmentStrategyContract.target

  // deployments.sepolia["investmentStrategy"] = investmentStrategyAddress
  await (await registryContract.addInvestmentStrategyContract(deployments.sepolia["investmentStrategy"])).wait();

  deployments.sepolia["arbitrationContract"] = arbitrationContract.target
  await (await registryContract.addArbitrationContract(deployments.sepolia["arbitrationContract"])).wait()

  writeAddressesToFile(deployments)
}

const addStrategyCode = async () => {
  let sourceString = ``
  const sourceCode = stringToBytes(sourceString)
  const investmentStrategyContract = await hre.ethers.getContractAt("InvestmentStrategy", deployments.base["investmentStrategy"]);

  console.log(sourceCode)
  const transactionResponse = await investmentStrategyContract.addStrategy(sourceCode, "lowVolHighYield", { gasLimit: 7000000 });
  const receipt = await transactionResponse.wait();

}


const poolStatRead = async () => {
  // "0xec9a7d48230bec7a8b7cc88a8d4edff45d7da01f"

  const pool = await hre.ethers.getContractAt("PoolControl", deployments.sepolia["poolAddress"])
  const tokenContract = await (hre.ethers.getContractAt("IPoolToken", await pool.poolToken()))
  const calcContract = await hre.ethers.getContractAt("PoolCalculations", await pool.poolCalculations())

  console.log(
    "TARGETS: ",
    await calcContract.targetPositionMarketId(deployments.sepolia["poolAddress"]),
    await calcContract.targetPositionChain(deployments.sepolia["poolAddress"]),
    await calcContract.targetPositionProtocolHash(deployments.sepolia["poolAddress"]),
    await calcContract.targetPositionProtocol(deployments.sepolia["poolAddress"]),
    "CURRENTS: ",
    await calcContract.poolNonce(deployments.sepolia["poolAddress"]),
    await pool.currentPositionChain(),
    await calcContract.currentPositionAddress(deployments.sepolia["poolAddress"]),
    await calcContract.currentPositionMarketId(deployments.sepolia["poolAddress"]),
    await calcContract.currentPositionProtocolHash(deployments.sepolia["poolAddress"]),
    await calcContract.currentPositionProtocol(deployments.sepolia["poolAddress"]),
    await calcContract.currentRecordPositionValue(deployments.sepolia["poolAddress"]),
    await calcContract.currentPositionValueTimestamp(deployments.sepolia["poolAddress"]))

  console.log("TOKENS: ",
    await pool.poolToken(),
    "totalSupply - ",
    await tokenContract.totalSupply(),
    "balanceOf 1b5E - ",
    await tokenContract.balanceOf("0x1CA2b10c61D0d92f2096209385c6cB33E3691b5E"),
    "scaledRatio - ",
    await calcContract.getScaledRatio(await pool.poolToken(), "0x1CA2b10c61D0d92f2096209385c6cB33E3691b5E"),
  )

  const bridgeLogicAddress = deployments.sepolia["bridgeLogicAddress"]
  const bridgeLogic = await hre.ethers.getContractAt("BridgeLogic", bridgeLogicAddress);


  const integratorContract = await hre.ethers.getContractAt("Integrator", deployments.sepolia["integratorAddress"]);

  // Get hash of protocol
  const protocolHash = await integratorContract.hasher("aave-v3")
  // console.log(await bridgeLogic.poolToAsset(deployments.sepolia["poolAddress"]),
  //   await bridgeLogic.poolToCurrentPositionMarket(deployments.sepolia["poolAddress"]),
  //   await bridgeLogic.poolToCurrentProtocolHash(deployments.sepolia["poolAddress"]),)

  const curPos = await bridgeLogic.getPositionBalance(deployments.sepolia["poolAddress"])

  console.log('CURRENT POSITION VALUE + INTEREST: ', curPos)
}

const sepoliaDeposit = async () => {
  const pool = await hre.ethers.getContractAt("PoolControl", deployments.sepolia["poolAddress"])

  const amount = "750000000000000"

  const WETH = await hre.ethers.getContractAt("ERC20", deployments.sepolia["WETH"]);
  await (await WETH.approve(deployments.sepolia["poolAddress"], amount)).wait()
  const tx = await pool.userDeposit(
    amount,
    totalFeeCalc(amount),
    { gasLimit: 2000000 }
  )

  console.log("Non position set Deposit: ", (await tx.wait()).hash)
}

const sepoliaWithdraw = async () => {
  // Creates CCIP message, manually executed on the sepolia messenger contact, which sends withdraw through across and finalizes on base
  // "0xec9a7d48230bec7a8b7cc88a8d4edff45d7da01f"
  const pool = await hre.ethers.getContractAt("PoolControl", deployments.sepolia["poolAddress"])
  const amount = "900000000000000"
  const tx = await pool.userWithdrawOrder(amount, { gasLimit: 8000000 })
  console.log((await tx.wait()).hash)
}

const sepoliaCallPivot = async () => {
  const pool = await hre.ethers.getContractAt("PoolControl", deployments.sepolia["poolAddress"])
  const integratorContract = await hre.ethers.getContractAt("Integrator", deployments.sepolia["integratorAddress"]);
  const registryContract = await hre.ethers.getContractAt("Registry", deployments.sepolia["registryAddress"]);

  // Get hash of protocol
  console.log("PIVOT TRANSACTION: ", (await (await pool.sendPositionChange(
    "0x0585585858585",
    "compound-v3",
    84532,
    { gasLimit: 4000000 }

  )).wait()).hash)


  // const WETH = await hre.ethers.getContractAt("ERC20", deployments.base["WETH"]);
  // await (await WETH.transfer(deployments.base["integratorAddress"], "100000000000")).wait()

  // const USDC = await hre.ethers.getContractAt("ERC20", "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238");
  // await (await USDC.approve(deployments.sepolia["arbitrationContract"], 500000)).wait()
  // console.log("arbitration: ", await pool.arbitrationContract(), await pool.strategyIndex())

  // console.log((await (await pool.queryMovePosition("compound-v3", "0x0ef3f4gp", 11155111, 500000, { gasLimit: 7000000 })).wait()).hash)
  //IMPORTANT - TEST IF UMA TESTNET FOLLOWS LIVENESS PERIOD
}

const upgradeContract = async () => {
  const integratorContract = await hre.ethers.getContractAt("Integrator", deployments.sepolia["integratorAddress"]);
  const WETH = await hre.ethers.getContractAt("ERC20", deployments.sepolia["WETH"]);

  console.log(await integratorContract.registryAddress(), await WETH.balanceOf(deployments.sepolia["integratorAddress"]))
  const IntV2 = await hre.ethers.getContractFactory("Integrator");
  const int = await hre.upgrades.upgradeProxy(deployments.sepolia["integratorAddress"], IntV2);
  const newAddr = await int.getAddress()
  console.log("Int upgraded", newAddr);
  console.log(await int.registryAddress())
}

const baseIntegrationsTest = async () => {
  const integratorContract = await hre.ethers.getContractAt("Integrator", deployments.base["integratorAddress"]);
  const registryContract = await hre.ethers.getContractAt("Registry", deployments.base["registryAddress"]);

  // Get hash of protocol
  const protocolHash = await integratorContract.hasher("aave-v3")

  // Get hash operations
  const operation = await integratorContract.hasher("deposit")

  const amount = "50000000000000"

  const WETH = await hre.ethers.getContractAt("ERC20", "0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357");
  // console.log("Token Transfer: ", (await (await WETH.transfer(deployments.base["integratorAddress"], amount)).wait()).hash)
  console.log(protocolHash, operation)
  // Call the routeExternal function
  // console.log((await (await integratorContract.routeExternalProtocolInteraction(protocolHash, operation, amount, deployments.sepolia["poolAddress"], "0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357", "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951", { gasLimit: 1000000 })).wait()).hash)

  const bridgeLogicAddress = deployments.base["bridgeLogicAddress"]
  const bridgeLogic = await hre.ethers.getContractAt("BridgeLogic", bridgeLogicAddress);

  //Check aToken balance of ntegrator
  const curPos = await integratorContract.getCurrentPosition(
    deployments.sepolia["poolAddress"],
    "0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357",
    "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951",
    protocolHash
  );
  console.log(await bridgeLogic.poolToAsset(deployments.sepolia["poolAddress"]), await bridgeLogic.poolToCurrentPositionMarket(deployments.sepolia["poolAddress"]), await bridgeLogic.poolToCurrentMarketId(deployments.sepolia["poolAddress"]), await bridgeLogic.poolToCurrentProtocolHash(deployments.sepolia["poolAddress"]))
  const curPos2 = await bridgeLogic.getPositionBalance(deployments.sepolia["poolAddress"])

  console.log(curPos, curPos2)



  console.log("Current Position: ", curPos, "Broker: ", await registryContract.poolAddressToBroker(deployments.sepolia["poolAddress"]))
}

const upgradeCalc = async () => {

  const ManagerV2 = await hre.ethers.getContractFactory("ChaserManager");
  const manager = await hre.upgrades.upgradeProxy(deployments.sepolia["managerAddress"], ManagerV2);
  const newAddr = await manager.getAddress()
  console.log("Manager upgraded", newAddr);


  const calcContract = await (await hre.ethers.deployContract("PoolCalculations", [deployments.sepolia["registryAddress"]], {
    gasLimit: 7000000,
    value: 0
  })).waitForDeployment();

  console.log("POOL CALCULATIONS: ", calcContract.target)
  deployments.sepolia["poolCalculationsAddress"] = calcContract.target
  deployments.sepolia["managerAddress"] = newAddr
  writeAddressesToFile(deployments)

  await manager.addPoolCalculationsAddress(calcContract.target)
}

const manualAcrossMessageHandle = async (amount, message) => {
  //This is used when a Bridge message doesnt seem to go through and we need to determine if the issue is reversion
  const receiverContract = await hre.ethers.getContractAt("BridgeReceiver", deployments.sepolia["receiverAddress"]);
  const wethAddr = deployments.sepolia["WETH"]

  //message should be bytes from topic 0xe503f02a28c80b867adfed9777a61077c421693358e2f0f1fc54e13acaa18005
  const trimMessageData = message
    .split("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000160")
    .join("")
    .split("000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c0")
    .join("")

  // Simulate the receiver on sepolia getting bridged WETH, by sending WETH from within sepolia to the receiver
  const WETH = await hre.ethers.getContractAt("ERC20", wethAddr);

  console.log((await (await WETH.transfer(deployments.sepolia["receiverAddress"], amount)).wait()).hash)

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
    // await sepoliaDeployments() //CHECK THAT THE DEFAULT NETWORK IN "..hardhat.config.js" IS sepolia
    // await baseDeployments() //CHANGE THE DEFAULT NETWORK IN "..hardhat.config.js" TO base
    // await sepoliaSecondConfig() //CHANGE THE DEFAULT NETWORK IN "..hardhat.config.js" TO sepolia
    // --------------------------------------------------------------------------------------------
    // IF YOU EXECUTED THE PRIOR SECTION AND/OR WOULD LIKE TO DEPLOY YOUR POOL FOR TESTING - EXECUTE THE FOLLOWING FUNCTION
    // This function also sends the initial deposit funds through the bridge into the investment as the position is set on base
    // await setPivotConfigs()
    // await upgradeCalc()
    // await sepoliaPoolDeploy()
    // await sepoliaPositionSetDeposit()

    // await sepoliaDeposit()
    // --------------------------------------------------------------------------------------------
    // AFTER EXECUTING sepoliaPoolDeploy() OR sepoliaDeposit(), WAIT FOR THE ETHEREUM BASE ACROSS SPOKEPOOL TO RECEIVE THE DEPOSIT
    // GET THE MESSAGE DATA FROM SEPOLIASCAN, COPYING THE HEX DATA BYTES FROM EVENT "0x244e451036514e829e60556484796d2251dc3d952cd079db45d2bfb4c0aff2a1"
    // PASTE MESSAGE DATA INTO THE ARGUMENT FOR FOLLOWING FUNCTION
    // await sepoliaSimulateCCIPReceive("0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000e00414e990000000000000000000000000000000000000000000000000000000000000000000000000000000009bdc76b596051e1e86eadb2e2af2a491e32bfa4800000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000886c98ec54a530000000000000000000000000000000000000000000000000005af3107a400003361877a052af4d82301c2eea28d1667f3fdbaff73f9d57880f1b317a552eda2")
    // --------------------------------------------------------------------------------------------
    // EXECUTE THIS FUNCTION TO START A DEPOSIT TO THE POOL
    // REMINDER TO REVISIT THE ABOVE SECTION TO SIMULATE THE CCIP TRIGGER MESSAGE FOR EXECUTING THE DEPOSIT ON ETHEREUM BASE
    // --------------------------------------------------------------------------------------------
    // await poolStatRead()
    // await sepoliaWithdraw()
    // await sepoliaCallPivot()
    // await upgradeContract()
    await poolStatRead()

    // await baseSimulateCCIPReceive("0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001003705af6d000000000000000000000000000000000000000000000000000000000000000000000000000000009bdc76b596051e1e86eadb2e2af2a491e32bfa48000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000803f4c40f2d9e47df3a43c5c97200a65dd80990bf9d69827733cf5f393681c90dc000000000000000000000000000000000000000000000000000886c98b760000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000004a03cea247fc197")
    // --------------------------------------------------------------------------------------------
    // baseReceivers()
    // await manualAcrossMessageHandle("2235397550132765", "0xBD4F4B890000000000000000000000000000000000000000000000000000000000000000000000000000000009257CB399B8BB79AFD2DEE5E45812B5E49DA4DA00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000080B79A1BFB6744AF89DE765763E93F90B26F46D6A3C184E242F36F89F5687DBC1F0000000000000000000000000000000000000000000000000007F93F499E2F9500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007F93F499E2F95")

    // await baseIntegrationsTest()



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

// writeAddressesToFile({ ...deployments, sepolia: { "ihef": "iefhr" } })


mainExecution()