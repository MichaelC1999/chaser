const hre = require("hardhat");
const ethers = require("ethers");
const fs = require('fs');
const { stringToBytes, bytesToString, hexToString, decodeEventLog } = require('viem')


const deployments = require('./contractAddresses.json')

const sepoliaDeployments = async () => {

  const [deployer] = await hre.ethers.getSigners();
  const gasPrice = await deployer.provider.getFeeData();
  console.log(gasPrice)

  const Manager = await hre.ethers.getContractFactory("ChaserManager");
  const manager = await hre.upgrades.deployProxy(Manager, [11155111]);
  await manager.waitForDeployment();
  console.log("Manager deployed to:", await manager.getAddress());
  const managerAddress = await manager.getAddress()
  deployments.sepolia["managerAddress"] = managerAddress

  console.log('MANAGER OWNER: ', await manager.owner())

  const Registry = await hre.ethers.getContractFactory("Registry");
  const registry = await hre.upgrades.deployProxy(Registry, [11155111, 11155111, deployments.sepolia["managerAddress"]]);
  await registry.waitForDeployment();
  const registryAddress = await registry.getAddress()
  deployments.sepolia["registryAddress"] = registryAddress
  await (await manager.addRegistry(deployments.sepolia["registryAddress"])).wait()
  console.log("REGISTRY: ", deployments.sepolia["registryAddress"])

  const PoolCalculations = await hre.ethers.getContractFactory("PoolCalculations");
  const poolCalculationsContract = await hre.upgrades.deployProxy(PoolCalculations, [deployments.sepolia["registryAddress"]]);
  await poolCalculationsContract.waitForDeployment();
  const poolCalculationsAddress = await poolCalculationsContract.getAddress()
  console.log("POOL CALCULATIONS", poolCalculationsAddress)
  deployments.sepolia["poolCalculationsAddress"] = poolCalculationsAddress
  writeAddressesToFile(deployments)

  await manager.addPoolCalculationsAddress(poolCalculationsAddress)

  const BridgeLogic = await hre.ethers.getContractFactory("BridgeLogic");
  const bridgeLogicContract = await hre.upgrades.deployProxy(BridgeLogic, [11155111, 11155111, deployments.sepolia["registryAddress"]]);
  await bridgeLogicContract.waitForDeployment();
  const bridgeLogicAddress = await bridgeLogicContract.getAddress()
  console.log("BRIDGE LOGIC", bridgeLogicAddress)
  deployments.sepolia["bridgeLogicAddress"] = bridgeLogicAddress
  writeAddressesToFile(deployments)

  const ccip = (await registry.localCcipConfigs())
  console.log(ccip)
  const messengerContract = await (await hre.ethers.deployContract("ChaserMessenger", [ccip[0], ccip[1], deployments.sepolia["registryAddress"], bridgeLogicAddress, ccip[2]], {
    gasLimit: 7000000,
    value: 0
  })).waitForDeployment();

  const messengerAddress = messengerContract.target
  deployments.sepolia["messengerAddress"] = messengerAddress
  writeAddressesToFile(deployments)

  const linkToken = await hre.ethers.getContractAt("ERC20", deployments.sepolia["linkToken"]);

  const amount = "600000000000000000"

  console.log("Token Transfer: ", (await (await linkToken.transfer(deployments.sepolia["messengerAddress"], amount)).wait()).hash)


  const BridgeReceiver = await hre.ethers.getContractFactory("BridgeReceiver");
  const bridgeReceiverContract = await hre.upgrades.deployProxy(BridgeReceiver, [bridgeLogicAddress, deployments.sepolia["spokePool"]]);
  await bridgeReceiverContract.waitForDeployment();
  const bridgeReceiverAddress = await bridgeReceiverContract.getAddress()
  console.log("BRIDGE RECEIVER", bridgeReceiverAddress)
  deployments.sepolia["receiverAddress"] = bridgeReceiverAddress
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
  // const registryAddress = deployments.sepolia["registryAddress"]
  // const registry = await hre.ethers.getContractAt("Registry", registryAddress);


  // const bridgeLogicAddress = deployments.sepolia["bridgeLogicAddress"]
  // const bridgeLogicContract = await hre.ethers.getContractAt("BridgeLogic", bridgeLogicAddress);


  await (await bridgeLogicContract.addConnections(deployments.sepolia["messengerAddress"], deployments.sepolia["receiverAddress"], deployments.sepolia["integratorAddress"])).wait()

  await (await registry.addBridgeLogic(deployments.sepolia["bridgeLogicAddress"], deployments.sepolia["messengerAddress"], deployments.sepolia["receiverAddress"])).wait()

  console.log('MESSENGER: ', await bridgeLogicContract.messenger(), await registry.chainIdToMessageReceiver(11155111))

  console.log('RECEIVER: ', await bridgeLogicContract.bridgeReceiverAddress(), await registry.receiverAddress())

  await (await registry.enableProtocol(
    "aave-v3"
  )).wait();

  await (await registry.enableProtocol(
    "compound-v3"
  )).wait();

  console.log(deployments.sepolia)
  console.log("FINISHED SEPOLIA DEPLOYMENTS 1")
}

const baseDeployments = async () => {
  const [deployer] = await hre.ethers.getSigners();
  const gasPrice = await deployer.provider.getFeeData();
  console.log(gasPrice)

  const Registry = await hre.ethers.getContractFactory("Registry");
  const registry = await hre.upgrades.deployProxy(Registry, [84532, 11155111, "0x0000000000000000000000000000000000000000"]);
  await registry.waitForDeployment();
  const registryAddress = await registry.getAddress()
  deployments.base["registryAddress"] = registryAddress
  console.log("REGISTRY: ", deployments.base["registryAddress"])

  const BridgeLogic = await hre.ethers.getContractFactory("BridgeLogic");
  const bridgeLogicContract = await hre.upgrades.deployProxy(BridgeLogic, [84532, 11155111, registryAddress]);
  await bridgeLogicContract.waitForDeployment();
  const bridgeLogicAddress = await bridgeLogicContract.getAddress()
  console.log("BRIDGE LOGIC", bridgeLogicAddress)
  deployments.base["bridgeLogicAddress"] = bridgeLogicAddress
  writeAddressesToFile(deployments)


  const ccip = (await registry.localCcipConfigs())
  const messengerContract = await (await hre.ethers.deployContract("ChaserMessenger", [ccip[0], ccip[1], registryAddress, bridgeLogicAddress, ccip[2]], {
    gasLimit: 7000000,
    value: 0
  })).waitForDeployment();

  deployments.base["messengerAddress"] = messengerContract.target
  const messengerAddress = deployments.base["messengerAddress"]
  writeAddressesToFile(deployments)

  const linkToken = await hre.ethers.getContractAt("ERC20", deployments.base["linkToken"]);
  const linkAmount = "700000000000000000"
  console.log("Token Transfer: ", (await (await linkToken.transfer(deployments.base["messengerAddress"], linkAmount)).wait()).hash)

  const BridgeReceiver = await hre.ethers.getContractFactory("BridgeReceiver");
  const bridgeReceiverContract = await hre.upgrades.deployProxy(BridgeReceiver, [bridgeLogicAddress, deployments.base["spokePool"]]);
  await bridgeReceiverContract.waitForDeployment();
  const bridgeReceiverAddress = await bridgeReceiverContract.getAddress()
  console.log("BRIDGE RECEIVER", bridgeReceiverAddress)
  deployments.base["receiverAddress"] = bridgeReceiverAddress
  writeAddressesToFile(deployments)


  const Int = await hre.ethers.getContractFactory("Integrator");
  const int = await hre.upgrades.deployProxy(Int, [bridgeLogicAddress, deployments.base["registryAddress"]]);
  await int.waitForDeployment();
  console.log("Integrator deployed to:", await int.getAddress());
  const integratorAddress = await int.getAddress()
  deployments.base["integratorAddress"] = integratorAddress
  writeAddressesToFile(deployments)



  const WETH = await hre.ethers.getContractAt("ERC20", deployments.base["WETH"]);
  const WETHAmount = "10000000000000"
  console.log("WETH Token Transfer: ", (await (await WETH.transfer(deployments.base["integratorAddress"], WETHAmount)).wait()).hash)


  await (await bridgeLogicContract.addConnections(messengerAddress, deployments.base["receiverAddress"], integratorAddress)).wait()
  await (await registry.addBridgeLogic(bridgeLogicAddress, messengerAddress, deployments.base["receiverAddress"])).wait()
  await baseReceivers()
  console.log('MESSENGER: ', await bridgeLogicContract.messenger(), await registry.chainIdToMessageReceiver(84532), 'RECEIVER: ', await bridgeLogicContract.bridgeReceiverAddress())

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
    deployments.sepolia["aaveMarketId"],
    11155111,
    { gasLimit: 8000000 }
  )

  console.log(`Pool 0x...${deployments.sepolia["poolAddress"].slice(34)} position set and initial deposit tx hash: `, (await tx.wait()).hash)
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
  const ArbitrationContract = await hre.ethers.getContractFactory("ArbitrationContract");
  const arbitrationContract = await hre.upgrades.deployProxy(ArbitrationContract, [deployments.sepolia["registryAddress"], 11155111]);
  await arbitrationContract.waitForDeployment();
  const arbitrationAddress = await arbitrationContract.getAddress()
  console.log("Arb", arbitrationAddress)
  deployments.sepolia["arbitrationContract"] = arbitrationAddress

  writeAddressesToFile(deployments)


  //NO NEED TO REDEPLOY INVESTMENTSTRATEGY CONTRACT
  // const investmentStrategyContract = await (await hre.ethers.deployContract("InvestmentStrategy", [], {
  //   gasLimit: 7000000,
  //   value: 0
  // })).waitForDeployment();

  // const investmentStrategyAddress = investmentStrategyContract.target

  // deployments.sepolia["investmentStrategy"] = investmentStrategyAddress
  await (await registryContract.addInvestmentStrategyContract(deployments.sepolia["investmentStrategy"])).wait();
  await (await registryContract.addArbitrationContract(deployments.sepolia["arbitrationContract"])).wait()

  // writeAddressesToFile(deployments)
}

const addStrategyCode = async () => {
  let sourceString = ``

  const sourceCode = stringToBytes(sourceString)

  const investmentStrategyContract = await hre.ethers.getContractAt("InvestmentStrategy", deployments.sepolia["investmentStrategy"]);

  // console.log(sourceCode)
  // const transactionResponse = await investmentStrategyContract.addStrategy(sourceCode, "highYield3Month", { gasLimit: 7000000 });
  // const receipt = await transactionResponse.wait();
  console.log(hexToString(await investmentStrategyContract.strategyCode(1)))
}


const poolStatRead = async () => {
  // "0xec9a7d48230bec7a8b7cc88a8d4edff45d7da01f"
  const poolAddress = deployments.sepolia['poolAddress']
  const pool = await hre.ethers.getContractAt("PoolControl", poolAddress)
  const tokenContract = await (hre.ethers.getContractAt("IPoolToken", await pool.poolToken()))
  const calcContract = await hre.ethers.getContractAt("PoolCalculations", await pool.poolCalculations())

  console.log(
    "TARGETS: ",
    await calcContract.targetPositionMarketId(poolAddress),
    await calcContract.targetPositionChain(poolAddress),
    await calcContract.targetPositionProtocolHash(poolAddress),
    await calcContract.targetPositionProtocol(poolAddress),
    "CURRENTS: ",
    await calcContract.poolDepositNonce(poolAddress),
    await calcContract.poolWithdrawNonce(poolAddress),
    await pool.currentPositionChain(),
    await calcContract.currentPositionAddress(poolAddress),
    await calcContract.currentPositionMarketId(poolAddress),
    await calcContract.currentPositionProtocolHash(poolAddress),
    await calcContract.currentPositionProtocol(poolAddress),
    await calcContract.currentRecordPositionValue(poolAddress),
    await calcContract.currentPositionValueTimestamp(poolAddress))

  console.log("TOKENS: ",
    await pool.poolToken(),
    "totalSupply - ",
    await tokenContract.totalSupply(),
    "balanceOf 1b5E - ",
    await tokenContract.balanceOf("0x1CA2b10c61D0d92f2096209385c6cB33E3691b5E"),
    "scaledRatio - ",
    await calcContract.getScaledRatio(await pool.poolToken(), "0x1CA2b10c61D0d92f2096209385c6cB33E3691b5E"),
  )

  // const bridgeLogicAddress = deployments.base["bridgeLogicAddress"]
  // const bridgeLogic = await hre.ethers.getContractAt("BridgeLogic", bridgeLogicAddress);


  // const integratorContract = await hre.ethers.getContractAt("Integrator", deployments.base["integratorAddress"]);
  // console.log(await integratorContract.getCurrentPosition(
  //   poolAddress,
  //   "0x4200000000000000000000000000000000000006",
  //   "0x07eA79F68B2B3df564D0A34F8e19D9B1e339814b",
  //   "0x465a559e4de536e9b6feec6cb09331bad8f94c75e1f63a0b1a8e46bbc990c476"
  // ));
  // }

  // console.log(await bridgeLogic.getNonPendingPositionBalance(
  //   poolAddress,
  //   2,
  //   0
  // ))
  // // // Get hash of protocol
  // // const protocolHash = await integratorContract.hasher("aave-v3")
  // console.log(await bridgeLogic.poolToAsset(poolAddress),
  //   await bridgeLogic.poolToCurrentPositionMarket(poolAddress),
  //   await bridgeLogic.poolToCurrentProtocolHash(poolAddress),
  //   await bridgeLogic.poolAddressToDepositNonce(poolAddress),
  //   await bridgeLogic.poolAddressToWithdrawNonce(poolAddress))

  // const curPos = await bridgeLogic.getPositionBalance(poolAddress)


  // console.log('CURRENT POSITION VALUE + INTEREST: ', curPos)
}

const sepoliaDeposit = async () => {
  const pool = await hre.ethers.getContractAt("PoolControl", deployments.sepolia["poolAddress"])

  const amount = "672000505322453"
  // const arbContract = await hre.ethers.getContractAt("ArbitrationContract", deployments.sepolia["arbitrationContract"]);

  const WETH = await hre.ethers.getContractAt("ERC20", deployments.sepolia["WETH"]);
  await (await WETH.approve(deployments.sepolia["poolAddress"], amount)).wait()
  const tx = await pool.userDeposit(
    amount,
    totalFeeCalc(amount),
    { gasLimit: 2000000 }
  )

  console.log("Non position set Deposit: ", (await tx.wait()).hash)
}

const sendTokens = async () => {
  const linkToken = await hre.ethers.getContractAt("ERC20", deployments.base["linkToken"]);
  const amount = "2000000000000000000"
  console.log("Token Transfer: ", (await (await linkToken.transfer(deployments.base["messengerAddress"], amount)).wait()).hash)

  // const aaveTestToken = await hre.ethers.getContractAt("ERC20", "0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357");
  // const aaveAmount = "10000000000000000"
  // console.log("AAVE Token Transfer: ", (await (await aaveTestToken.transfer(deployments.sepolia["integratorAddress"], aaveAmount)).wait()).hash)

  // const compTestToken = await hre.ethers.getContractAt("ERC20", "0x2D5ee574e710219a521449679A4A7f2B43f046ad");
  // const compAmount = "100000000000000"
  // console.log("COMPOUND Token Transfer: ", (await (await compTestToken.transfer(deployments.sepolia["integratorAddress"], compAmount)).wait()).hash)

  // const WETH = await hre.ethers.getContractAt("ERC20", deployments["sepolia"]["WETH"]);
  // await (await WETH.transfer(deployments["sepolia"]["integratorAddress"], "1000000000")).wait()

  // const USDC = await hre.ethers.getContractAt("ERC20", "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238");
  // await (await USDC.approve(deployments[chainName]["arbitrationContract"], 500000)).wait()
  // console.log("arbitration: ", await pool.arbitrationContract(), await pool.strategyIndex())

}

const sepoliaWithdraw = async () => {
  // Creates CCIP message, manually executed on the sepolia messenger contact, which sends withdraw through across and finalizes on base
  // "0xec9a7d48230bec7a8b7cc88a8d4edff45d7da01f"
  const pool = await hre.ethers.getContractAt("PoolControl", deployments.sepolia["poolAddress"])
  const amount = "224437505322453"
  const tx = await pool.userWithdrawOrder(amount, { gasLimit: 8000000 })
  console.log((await tx.wait()).hash)
}

const sepoliaCallPivot = async () => {
  const pool = await hre.ethers.getContractAt("PoolControl", deployments.sepolia["poolAddress"])
  const integratorContract = await hre.ethers.getContractAt("Integrator", deployments.sepolia["integratorAddress"]);
  const registryContract = await hre.ethers.getContractAt("Registry", deployments.sepolia["registryAddress"]);
  const protocolName = "compound"
  const chainToName = { 84532: "base", 11155111: "sepolia" }
  const targetChain = 84532
  const chainName = chainToName[targetChain]
  // Get hash of protocol
  // const WETH = await hre.ethers.getContractAt("ERC20", deployments[chainName]["WETH"]);
  // await (await WETH.transfer(deployments[chainName]["integratorAddress"], "100000000000")).wait()

  console.log("PIVOT TRANSACTION: ", (await (await pool.sendPositionChange(
    deployments[chainName][protocolName + "MarketId"],
    protocolName + "-v3",
    targetChain,
    { gasLimit: 4000000 }

  )).wait()).hash)



  // const USDC = await hre.ethers.getContractAt("ERC20", "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238");
  // await (await USDC.approve(deployments[chainName]["arbitrationContract"], 500000)).wait()
  // console.log("arbitration: ", await pool.arbitrationContract(), await pool.strategyIndex())

  // console.log((await (await pool.queryMovePosition(protocolName + "-v3", deployments[chainName][protocolName + "MarketId"], targetChain, { gasLimit: 7000000 })).wait()).hash)
}

const upgradeContract = async () => {

  const BridgeV2 = await hre.ethers.getContractFactory("BridgeLogic");
  const int = await hre.upgrades.upgradeProxy(deployments.base["bridgeLogicAddress"], BridgeV2);
  const newAddr = await int.getAddress()
  console.log("Int upgraded", newAddr);
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

  const PoolCalculations = await hre.ethers.getContractFactory("PoolCalculations");
  const poolCalculationsContract = await hre.upgrades.upgradeProxy(deployments.sepolia["poolCalculationsAddress"], PoolCalculations);
  const poolCalculationsAddress = await poolCalculationsContract.getAddress()
  console.log("POOL CALCULATIONS", poolCalculationsAddress)
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

const testLogFinder = async () => {
  const URI = "https://api-sepolia.etherscan.io/api?apikey=" + process.env.NEXT_PUBLIC_ETHERSCAN_API + "&module=logs&action=getLogs&fromBlock=1092029&toBlock=latest&address=" + "0xdc4514c31907b06f2495661c4a3b34b43d384e4f" + "&topic0=0xad71167b35ad58b7606cb5f5fda8b03a5799113db8f0a73939d152ac29d023a0"

  const event = await fetch(URI, {
    method: "get",
    headers: {
      "Content-Type": "application/json",
    }
  })

  const pivotEvent = await event.json()

  console.log(pivotEvent)

  log = pivotEvent.result[0]
  const hash = log.transactionHash
  const args = decodeEventLog({
    abi: PoolABI,
    data: log.data,
    topics: log.topics
  }).args

  console.log(args)
  let topic = ""
  let contractAddr = ""
  if (args[0].toString() === "11155111") {
    //across
    topic = "0xa123dc29aebf7d0c3322c8eeb5b999e859f39937950ed31056532713d0de396f"
    contractAddr = deployments.sepolia["spokePool"]
  } else {
    //ccip
    topic = "0x3d8a9f055772202d2c3c1fddbad930d3dbe588d8692b75b84cee071946282911"
    contractAddr = deployments.sepolia["messengerAddress"]
  }

  const logUri = "https://api-sepolia.etherscan.io/api?apikey=" + process.env.NEXT_PUBLIC_ETHERSCAN_API + "&module=logs&action=getLogs&fromBlock=1092029&toBlock=latest&address=" + contractAddr + "&topic0=" + topic

  const messageEvent = await fetch(logUri, {
    method: "get",
    headers: {
      "Content-Type": "application/json",
    }
  })

  const messageLogEvents = await messageEvent.json()

  console.log(messageLogEvents.result.find(x => x.transactionHash === hash))

  // const url = "https://corsproxy.io/?https%3A%2F%2Fccip.chain.link%2Fapi%2Fquery%2FMESSAGE_DETAILS_QUERY%3Fvariables%3D%257B%2522messageId%2522%253A%25220x4a39b65996d7b11d31156727e48a3398c63f84e13012dfa7e3394ce4ecb78703%2522%257D";

  // const event = await fetch(url, {
  //     method: "get",
  //     headers: {
  //         "Content-Type": "application/json",
  //     }
  // })

  // const deployments = await event.json()

  // console.log(deployments.data.allCcipMessages.nodes[0])

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
    // await addStrategyCode()

    // await sepoliaCallPivot()
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
    // await upgradeContract()
    // await poolStatRead()
    await sendTokens()



    // await baseSimulateCCIPReceive("0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001003705af6d000000000000000000000000000000000000000000000000000000000000000000000000000000009bdc76b596051e1e86eadb2e2af2a491e32bfa48000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000803f4c40f2d9e47df3a43c5c97200a65dd80990bf9d69827733cf5f393681c90dc000000000000000000000000000000000000000000000000000886c98b760000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000004a03cea247fc197")
    // --------------------------------------------------------------------------------------------
    // baseReceivers()
    // await manualAcrossMessageHandle("3984000000000", "0xBD4F4B8900000000000000000000000000000000000000000000000000000000000000000000000000000000F0A9873B21401C0364AD7BA371D454F10BA6A2B70000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000008031AC05DE107EFE4D62837ECD2F0AEEA4121838CD62A776279A6D671CA564B6C4000000000000000000000000000000000000000000000000000009127C54E6000000000000000000000000000000000000000000000000000000056F29C0A600000000000000000000000000000000000000000000000000000003A352944000")

    // await baseIntegrationsTest()
    // await testLogFinder()

    // const interval = setInterval(async () => await poolStatRead(), 100000); // 300000 ms = 5 minutes

    // return () => clearInterval(interval); // Clean up the interval on component unmount

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