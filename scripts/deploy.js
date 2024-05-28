const hre = require("hardhat");
const ethers = require("ethers");
const fs = require('fs');
const { stringToBytes, bytesToString, hexToString, decodeEventLog, zeroAddress } = require('viem')


const deployments = require('./contractAddresses.json')
const mainChain = "arbitrum"
const secondaryChains = ["sepolia", "optimism"]
const networks = { "base": 84532, "sepolia": 11155111, "arbitrum": 421614, "optimism": 11155420 }

const mainDeployments = async () => {

  const [deployer] = await hre.ethers.getSigners();
  const gasPrice = await deployer.provider.getFeeData();
  console.log(gasPrice)

  const Manager = await hre.ethers.getContractFactory("ChaserManager");
  const manager = await hre.upgrades.deployProxy(Manager, [networks[mainChain]]);
  await manager.waitForDeployment();
  console.log("Manager deployed to:", await manager.getAddress());
  const managerAddress = await manager.getAddress()
  deployments[mainChain]["managerAddress"] = managerAddress

  console.log('MANAGER OWNER: ', await manager.owner())

  const Registry = await hre.ethers.getContractFactory("Registry");
  const registry = await hre.upgrades.deployProxy(Registry, [networks[mainChain], networks[mainChain], deployments[mainChain]["managerAddress"]]);
  await registry.waitForDeployment();
  const registryAddress = await registry.getAddress()
  deployments[mainChain]["registryAddress"] = registryAddress
  await (await manager.addRegistry(deployments[mainChain]["registryAddress"])).wait()
  console.log("REGISTRY: ", deployments[mainChain]["registryAddress"])

  const PoolCalculations = await hre.ethers.getContractFactory("PoolCalculations");
  const poolCalculationsContract = await hre.upgrades.deployProxy(PoolCalculations, [deployments[mainChain]["registryAddress"]]);
  await poolCalculationsContract.waitForDeployment();
  const poolCalculationsAddress = await poolCalculationsContract.getAddress()
  console.log("POOL CALCULATIONS", poolCalculationsAddress)
  deployments[mainChain]["poolCalculationsAddress"] = poolCalculationsAddress
  writeAddressesToFile(deployments)

  await manager.addPoolCalculationsAddress(poolCalculationsAddress)

  const BridgeLogic = await hre.ethers.getContractFactory("BridgeLogic");
  const bridgeLogicContract = await hre.upgrades.deployProxy(BridgeLogic, [networks[mainChain], networks[mainChain], deployments[mainChain]["registryAddress"]]);
  await bridgeLogicContract.waitForDeployment();
  const bridgeLogicAddress = await bridgeLogicContract.getAddress()
  console.log("BRIDGE LOGIC", bridgeLogicAddress)
  deployments[mainChain]["bridgeLogicAddress"] = bridgeLogicAddress
  writeAddressesToFile(deployments)

  const ccip = (await registry.localCcipConfigs())
  console.log(ccip)
  const messengerContract = await (await hre.ethers.deployContract("ChaserMessenger", [ccip[0], ccip[1], deployments[mainChain]["registryAddress"], bridgeLogicAddress, ccip[2]], {
    gasLimit: 7000000,
    value: 0
  })).waitForDeployment();

  const messengerAddress = messengerContract.target
  deployments[mainChain]["messengerAddress"] = messengerAddress
  writeAddressesToFile(deployments)

  const linkToken = await hre.ethers.getContractAt("ERC20", deployments[mainChain]["linkToken"]);

  const amount = "1500000000000000000"

  console.log("Token Transfer: ", (await (await linkToken.transfer(deployments[mainChain]["messengerAddress"], amount)).wait()).hash)


  const BridgeReceiver = await hre.ethers.getContractFactory("BridgeReceiver");
  const bridgeReceiverContract = await hre.upgrades.deployProxy(BridgeReceiver, [bridgeLogicAddress, deployments[mainChain]["spokePool"]]);
  await bridgeReceiverContract.waitForDeployment();
  const bridgeReceiverAddress = await bridgeReceiverContract.getAddress()
  console.log("BRIDGE RECEIVER", bridgeReceiverAddress)
  deployments[mainChain]["receiverAddress"] = bridgeReceiverAddress
  writeAddressesToFile(deployments)

  const Int = await hre.ethers.getContractFactory("Integrator");
  const int = await hre.upgrades.deployProxy(Int, [bridgeLogicAddress, deployments[mainChain]["registryAddress"]]);
  await int.waitForDeployment();
  console.log("Integrator deployed to:", await int.getAddress());
  const integratorAddress = await int.getAddress()
  deployments[mainChain]["integratorAddress"] = integratorAddress
  writeAddressesToFile(deployments)

  const WETH = await hre.ethers.getContractAt("ERC20", deployments[mainChain]["WETH"]);
  const WETHAmount = "10000000000000" // This is the extra amount that accounts for different in interest gains of Aave/Compound
  console.log("WETH Token Transfer: ", (await (await WETH.transfer(deployments[mainChain]["integratorAddress"], WETHAmount)).wait()).hash)

  const aaveTestToken = await hre.ethers.getContractAt("ERC20", deployments[mainChain]["aaveTestWETH"]);
  const aaveAmount = "200000000000000" // This amount is for forwarding a dummy balance (needs to be enough for the entire position, not just interest diff)
  console.log("AAVE Token Transfer: ", (await (await aaveTestToken.transfer(deployments[mainChain]["integratorAddress"], aaveAmount)).wait()).hash)

  if (Object.keys(deployments[mainChain]).includes("compoundTestWETH")) {
    const compTestToken = await hre.ethers.getContractAt("ERC20", deployments[mainChain]["compoundTestWETH"]);
    const compAmount = "200000000000000"

    console.log("COMPOUND Token Transfer: ", (await (await compTestToken.transfer(deployments[mainChain]["integratorAddress"], compAmount)).wait()).hash)

  }
  // const registryAddress = deployments[mainChain]["registryAddress"]
  // const registry = await hre.ethers.getContractAt("Registry", registryAddress);


  // const bridgeLogicAddress = deployments[mainChain]["bridgeLogicAddress"]
  // const bridgeLogicContract = await hre.ethers.getContractAt("BridgeLogic", bridgeLogicAddress);


  await (await bridgeLogicContract.addConnections(deployments[mainChain]["messengerAddress"], deployments[mainChain]["receiverAddress"], deployments[mainChain]["integratorAddress"])).wait()

  await (await registry.addBridgeLogic(deployments[mainChain]["bridgeLogicAddress"], deployments[mainChain]["messengerAddress"], deployments[mainChain]["receiverAddress"])).wait()

  console.log('MESSENGER: ', await bridgeLogicContract.messenger(), await registry.chainIdToMessageReceiver(networks[mainChain]))

  console.log('RECEIVER: ', await bridgeLogicContract.bridgeReceiverAddress(), await registry.receiverAddress())

  await (await registry.enableProtocol(
    "aave-v3"
  )).wait();

  await (await registry.enableProtocol(
    "compound-v3"
  )).wait();

  console.log(deployments[mainChain])
  console.log("FINISHED MAIN - " + mainChain.toUpperCase() + " DEPLOYMENTS 1")
}

const secondaryDeployments = async (chain) => {
  const [deployer] = await hre.ethers.getSigners();
  const gasPrice = await deployer.provider.getFeeData();
  console.log(gasPrice)

  const Registry = await hre.ethers.getContractFactory("Registry");
  const registry = await hre.upgrades.deployProxy(Registry, [networks[chain], networks[mainChain], "0x0000000000000000000000000000000000000000"]);
  await registry.waitForDeployment();
  const registryAddress = await registry.getAddress()
  deployments[chain]["registryAddress"] = registryAddress
  console.log("REGISTRY: ", deployments[chain]["registryAddress"])

  const BridgeLogic = await hre.ethers.getContractFactory("BridgeLogic");
  const bridgeLogicContract = await hre.upgrades.deployProxy(BridgeLogic, [networks[chain], networks[mainChain], registryAddress]);
  await bridgeLogicContract.waitForDeployment();
  const bridgeLogicAddress = await bridgeLogicContract.getAddress()
  console.log("BRIDGE LOGIC", bridgeLogicAddress)
  deployments[chain]["bridgeLogicAddress"] = bridgeLogicAddress
  writeAddressesToFile(deployments)


  const ccip = (await registry.localCcipConfigs())
  const messengerContract = await (await hre.ethers.deployContract("ChaserMessenger", [ccip[0], ccip[1], registryAddress, bridgeLogicAddress, ccip[2]], {
    gasLimit: 7000000,
    value: 0
  })).waitForDeployment();

  deployments[chain]["messengerAddress"] = messengerContract.target
  const messengerAddress = deployments[chain]["messengerAddress"]
  writeAddressesToFile(deployments)

  const linkToken = await hre.ethers.getContractAt("ERC20", deployments[chain]["linkToken"]);
  const linkAmount = "1500000000000000000"
  console.log("Token Transfer: ", (await (await linkToken.transfer(deployments[chain]["messengerAddress"], linkAmount)).wait()).hash)

  const BridgeReceiver = await hre.ethers.getContractFactory("BridgeReceiver");
  const bridgeReceiverContract = await hre.upgrades.deployProxy(BridgeReceiver, [bridgeLogicAddress, deployments[chain]["spokePool"]]);
  await bridgeReceiverContract.waitForDeployment();
  const bridgeReceiverAddress = await bridgeReceiverContract.getAddress()
  console.log("BRIDGE RECEIVER", bridgeReceiverAddress)
  deployments[chain]["receiverAddress"] = bridgeReceiverAddress
  writeAddressesToFile(deployments)


  const Int = await hre.ethers.getContractFactory("Integrator");
  const int = await hre.upgrades.deployProxy(Int, [bridgeLogicAddress, deployments[chain]["registryAddress"]]);
  await int.waitForDeployment();
  console.log("Integrator deployed to:", await int.getAddress());
  const integratorAddress = await int.getAddress()
  deployments[chain]["integratorAddress"] = integratorAddress
  writeAddressesToFile(deployments)



  const WETH = await hre.ethers.getContractAt("ERC20", deployments[chain]["WETH"]);
  const WETHAmount = "10000000000000"
  console.log("WETH Token Transfer: ", (await (await WETH.transfer(deployments[chain]["integratorAddress"], WETHAmount)).wait()).hash)

  if (Object.keys(deployments[chain]).includes("aaveTestWETH")) {

    const aaveTestToken = await hre.ethers.getContractAt("ERC20", deployments[chain]["aaveTestWETH"]);
    const aaveAmount = "200000000000000"
    console.log("AAVE Token Transfer: ", (await (await aaveTestToken.transfer(deployments[chain]["integratorAddress"], aaveAmount)).wait()).hash)

  }
  if (Object.keys(deployments[chain]).includes("compoundTestWETH")) {
    const compTestToken = await hre.ethers.getContractAt("ERC20", deployments[chain]["compoundTestWETH"]);
    const compAmount = "200000000000000"

    console.log("COMPOUND Token Transfer: ", (await (await compTestToken.transfer(deployments[chain]["integratorAddress"], compAmount)).wait()).hash)

  }


  await (await bridgeLogicContract.addConnections(messengerAddress, deployments[chain]["receiverAddress"], integratorAddress)).wait()
  await (await registry.addBridgeLogic(bridgeLogicAddress, messengerAddress, deployments[chain]["receiverAddress"])).wait()
  console.log('MESSENGER: ', await bridgeLogicContract.messenger(), await registry.chainIdToMessageReceiver(84532), 'RECEIVER: ', await bridgeLogicContract.bridgeReceiverAddress())

  console.log(deployments[chain])
  console.log("FINISHED " + chain.toUpperCase() + " DEPLOYMENTS")
}

const setReceivers = async (currentChain) => {
  const registryAddress = deployments[currentChain]["registryAddress"]
  const registryContract = await hre.ethers.getContractAt("Registry", registryAddress);

  if (currentChain !== "arbitrum") {
    await (await registryContract.addBridgeReceiver(networks["arbitrum"], deployments["arbitrum"]["receiverAddress"])).wait()
    await (await registryContract.addMessageReceiver(networks["arbitrum"], deployments["arbitrum"]["messengerAddress"])).wait()
  }

  if (currentChain !== "sepolia") {
    await (await registryContract.addBridgeReceiver(networks["sepolia"], deployments["sepolia"]["receiverAddress"])).wait()
    await (await registryContract.addMessageReceiver(networks["sepolia"], deployments["sepolia"]["messengerAddress"])).wait()
  }

  if (currentChain !== "optimism") {
    await registryContract.addBridgeReceiver(networks["optimism"], deployments["optimism"]["receiverAddress"])
    await registryContract.addMessageReceiver(networks["optimism"], deployments["optimism"]["messengerAddress"])

  }

  const messengerContract = await hre.ethers.getContractAt("ChaserMessenger", deployments[currentChain]["messengerAddress"]);
}

const poolDeploy = async () => {

  const manager = await hre.ethers.getContractAt("ChaserManager", deployments[mainChain]["managerAddress"]);

  const poolTx = await (await manager.createNewPool(
    deployments[mainChain]["WETH"],
    "0",
    "PoolName",
    {
      gasLimit: 7000000
    }
  )).wait();
  const poolAddress = '0x' + poolTx.logs[0].topics[1].slice(-40);
  deployments[mainChain]["poolAddress"] = poolAddress
  writeAddressesToFile(deployments)

  console.log("Pool Address: ", poolAddress);

}

const positionSetDeposit = async () => {
  //This function executes the first deposit on a pool and sets the position (The external protocol/chain/pool that this pool will invest assets in)
  const pool = await hre.ethers.getContractAt("PoolControl", deployments[mainChain]["poolAddress"])

  const WETH = await hre.ethers.getContractAt("ERC20", deployments[mainChain]["WETH"]);
  const amount = "150000000000000"
  await WETH.approve(deployments[mainChain]["poolAddress"], amount)

  const tx = await pool.userDepositAndSetPosition(
    amount,
    totalFeeCalc(amount),
    "aave-v3",
    deployments["sepolia"]["aaveMarketId"],
    11155111,
    { gasLimit: 8000000 }
  )

  console.log(`Pool 0x...${deployments[mainChain]["poolAddress"].slice(34)} position set and initial deposit tx hash: `, (await tx.wait()).hash)
}

const setPivotConfigs = async () => {
  const registryContract = await hre.ethers.getContractAt("Registry", deployments[mainChain]["registryAddress"]);
  // const ArbitrationContract = await hre.ethers.getContractFactory("ArbitrationContract");
  // const arbitrationContract = await hre.upgrades.deployProxy(ArbitrationContract, [deployments[mainChain]["registryAddress"], networks[mainChain]]);
  // await arbitrationContract.waitForDeployment();
  // const arbitrationAddress = await arbitrationContract.getAddress()
  // console.log("Arb", arbitrationAddress)
  // deployments[mainChain]["arbitrationContract"] = arbitrationAddress

  // writeAddressesToFile(deployments)


  //NO NEED TO REDEPLOY INVESTMENTSTRATEGY CONTRACT
  const investmentStrategyContract = await (await hre.ethers.deployContract("InvestmentStrategy", [], {
    gasLimit: 7000000,
    value: 0
  })).waitForDeployment();

  const investmentStrategyAddress = investmentStrategyContract.target

  deployments[mainChain]["investmentStrategy"] = investmentStrategyAddress
  await (await registryContract.addInvestmentStrategyContract(deployments[mainChain]["investmentStrategy"])).wait();
  // await (await registryContract.addArbitrationContract(deployments[mainChain]["arbitrationContract"])).wait()

  writeAddressesToFile(deployments)
}

const addStrategyCode = async () => {
  let sourceString = `export const strategyCalculation = async () => {
    // This object converts Sepolia/Base testnet markets to their mainnet addresses for the subgraph query
    const TESTNET_ANALOG_MARKETS = {
        '0x61490650abaa31393464c3f34e8b29cd1c44118ee4ab69c077896252fafbd49efd26b5d171a32410': "0x46e6b214b524310239732d51387075e0e70970bf4200000000000000000000000000000000000006",
        '0x2943ac1216979ad8db76d9147f64e61adc126e96e4ab69c077896252fafbd49efd26b5d171a32410': "0xa17581a9e3356d9a858b789d68b4d866e593ae94c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
        '0x96e32de4b1d1617b8c2ae13a88b9cc287239b13f': "0xd4a0e0b9149bcee3c920d2e00b5de09138fd8bb7",
        '0x29598b72eb5cebd806c5dcd549490fda35b13cd8': "0x4d5f47fa6a74757f35c14fd3a6ef8e3c9bc514e8",
        "0xf5f17EbE81E516Dc7cB38D61908EC252F150CE60": "0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8",
        "0x23e4E76D01B2002BE436CE8d6044b0aA2f68B68a": "0xe50fa9b3c56ffb159cb0fca61f5c9d750e8128c8"
    }

        return false;
  }
strategyCalculation().then(x => console.log(x));
`

  const sourceCode = stringToBytes(sourceString)

  const investmentStrategyContract = await hre.ethers.getContractAt("InvestmentStrategy", deployments[mainChain]["investmentStrategy"]);

  console.log(sourceCode.length)
  const transactionResponse = await investmentStrategyContract.addStrategy(sourceCode, "WETH High Yield 90 days", { gasLimit: 30000000 });
  const receipt = await transactionResponse.wait();
  console.log(receipt.hash)
  // console.log(hexToString(await investmentStrategyContract.strategyCode(1)))
}


const poolStatRead = async () => {
  const poolAddress = deployments[mainChain]['poolAddress']
  const pool = await hre.ethers.getContractAt("PoolControl", poolAddress)
  const assertionId = await pool.openAssertion()
  const tokenContract = await (hre.ethers.getContractAt("IPoolToken", await pool.poolToken()))
  const calcContract = await hre.ethers.getContractAt("PoolCalculations", await pool.poolCalculations())
  const registryContract = await hre.ethers.getContractAt("Registry", deployments[mainChain]["registryAddress"]);
  const Manager = await hre.ethers.getContractAt("ChaserManager", deployments.arbitrum.managerAddress);

  console.log(await pool.registry(), await registryContract.poolEnabled("0xE512fec32aD1645Ae650Bb8AD0fd26D1CFC6C4cc"), await Manager.registry())
  console.log(
    "ASSERTION: ",
    assertionId,
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

  const arbContract = await hre.ethers.getContractAt("ArbitrationContract", deployments[mainChain]["arbitrationContract"]);

  const RequestedMarketId = await arbContract.assertionToRequestedMarketId(assertionId)
  const RequestedProtocol = await arbContract.assertionToRequestedProtocol(assertionId)
  const RequestedChainId = await arbContract.assertionToRequestedChainId(assertionId)
  const assertionBlock = await arbContract.inAssertionBlockWindow(assertionId)
  const assertionToBlockTime = await arbContract.assertionToBlockTime(assertionId)
  const assertionToSettleTime = await arbContract.assertionToSettleTime(assertionId)

  console.log(RequestedMarketId,
    RequestedProtocol,
    RequestedChainId,
    assertionBlock,
    assertionToBlockTime,
    assertionToSettleTime, Date.now() / 1000)


  // const bridgeLogicAddress = deployments.base["bridgeLogicAddress"]
  // const bridgeLogic = await hre.ethers.getContractAt("BridgeLogic", bridgeLogicAddress);


  // const integratorContract = await hre.ethers.getContractAt("Integrator", deployments.base["integratorAddress"]);

  // const curPos = await bridgeLogic.getPositionBalance(poolAddress)


  // console.log('CURRENT POSITION VALUE + INTEREST: ', curPos)
}

const poolDeposit = async () => {
  const pool = await hre.ethers.getContractAt("PoolControl", deployments[mainChain]["poolAddress"])

  const amount = "49026502049296"
  // const arbContract = await hre.ethers.getContractAt("ArbitrationContract", deployments[mainChain]["arbitrationContract"]);

  const WETH = await hre.ethers.getContractAt("ERC20", deployments[mainChain]["WETH"]);
  await (await WETH.approve(deployments[mainChain]["poolAddress"], amount)).wait()
  const tx = await pool.userDeposit(
    amount,
    totalFeeCalc(amount),
    { gasLimit: 2000000 }
  )

  console.log("Non position set Deposit: ", (await tx.wait()).hash)
}

const sendTokens = async () => {
  const linkToken = await hre.ethers.getContractAt("ERC20", deployments.sepolia["linkToken"]);
  const amount = "9000000000000000000"
  console.log("Token Transfer: ", (await (await linkToken.transfer(deployments.sepolia["messengerAddress"], amount)).wait()).hash)

  const aaveTestToken = await hre.ethers.getContractAt("ERC20", deployments.sepolia["aaveTestWETH"]);
  const aaveAmount = "1000000000000000000"
  console.log("AAVE Token Transfer: ", (await (await aaveTestToken.transfer(deployments.sepolia["integratorAddress"], aaveAmount)).wait()).hash)

  // const compTestToken = await hre.ethers.getContractAt("ERC20", deployments.sepolia["compoundTestWETH"]);
  // const compAmount = "1000000000000000000"
  // console.log("COMPOUND Token Transfer: ", (await (await compTestToken.transfer(deployments.sepolia["integratorAddress"], compAmount)).wait()).hash)

  const WETH = await hre.ethers.getContractAt("ERC20", deployments["sepolia"]["WETH"]);
  await (await WETH.transfer(deployments["sepolia"]["integratorAddress"], "100000000000", { gasLimit: "8000000" })).wait()

  // const USDC = await hre.ethers.getContractAt("ERC20", "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238");
  // await (await USDC.approve(deployments[chainName]["arbitrationContract"], 500000)).wait()
  // console.log("arbitration: ", await pool.arbitrationContract(), await pool.strategyIndex())

}

const poolWithdraw = async () => {
  // Creates CCIP message, manually executed on the sepolia messenger contact, which sends withdraw through across and finalizes on base
  // "0xec9a7d48230bec7a8b7cc88a8d4edff45d7da01f"
  const pool = await hre.ethers.getContractAt("PoolControl", deployments[mainChain]["poolAddress"])
  const amount = "100000000000000"
  const tx = await pool.userWithdrawOrder(amount, { gasLimit: 8000000 })
  console.log((await tx.wait()).hash)
}

const callPivot = async () => {
  const pool = await hre.ethers.getContractAt("PoolControl", deployments[mainChain]["poolAddress"])
  const integratorContract = await hre.ethers.getContractAt("Integrator", deployments[mainChain]["integratorAddress"]);
  const registryContract = await hre.ethers.getContractAt("Registry", deployments[mainChain]["registryAddress"]);
  const protocolName = "aave"
  const chainToName = { 84532: "base", 11155111: "sepolia", 11155420: "optimism", 421614: "arbitrum" }
  const targetChain = 11155420
  const chainName = chainToName[targetChain]
  // // Get hash of protocol
  // const WETH = await hre.ethers.getContractAt("ERC20", deployments[mainChain]["WETH"]);
  // await (await WETH.transfer(deployments[mainChain]["integratorAddress"], "10000000000000")).wait()

  console.log("PIVOT TRANSACTION: ", (await (await pool.sendPositionChange(
    deployments[chainName][protocolName + "MarketId"],
    protocolName + "-v3",
    targetChain,
    { gasLimit: 4000000 }

  )).wait()).hash)


  const assertionId = await pool.openAssertion()
  const arbContract = await hre.ethers.getContractAt("ArbitrationContract", deployments[mainChain]["arbitrationContract"]);

  // const USDC = await hre.ethers.getContractAt("ERC20", "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238");
  // await (await USDC.approve(deployments[chainName]["arbitrationContract"], 500000)).wait()
  // console.log("arbitration: ", await pool.arbitrationContract(), await pool.strategyIndex())

  // console.log((await (await pool.queryMovePosition(protocolName + "-v3", deployments[chainName][protocolName + "MarketId"], targetChain, { gasLimit: 7000000 })).wait()).hash)
  // console.log((await (await arbContract.assertionResolvedCallback(
  //   assertionId,
  //   true,
  //   { gasLimit: 7000000 }
  // )).wait()).hash)
}

const upgradeContract = async (chain) => {

  const registryContract = await hre.ethers.getContractFactory("Registry");
  const registry = await hre.upgrades.upgradeProxy(deployments[chain]["registryAddress"], registryContract);
  const newAddr = await registry.getAddress()
  console.log("Reg upgraded", newAddr);
  deployments[chain]["registryAddress"] = newAddr
  writeAddressesToFile(deployments)
}

const baseIntegrationsTest = async () => {
  const integratorContract = await hre.ethers.getContractAt("Integrator", deployments.optimism["integratorAddress"]);
  const registryContract = await hre.ethers.getContractAt("Registry", deployments.optimism["registryAddress"]);

  // Get hash of protocol
  const protocolHash = await integratorContract.hasher("aave-v3")

  // Get hash operations
  // const operation = await integratorContract.hasher("deposit")

  // const amount = "50000000000000"

  // const WETH = await hre.ethers.getContractAt("ERC20", deployments.sepolia["aaveTestWETH"]);
  // console.log("Token Transfer: ", (await (await WETH.transfer(deployments.optimism["integratorAddress"], amount)).wait()).hash)
  // console.log(protocolHash, operation)
  // Call the routeExternal function
  // console.log((await (await integratorContract.routeExternalProtocolInteraction(protocolHash, operation, amount, deployments.sepolia["poolAddress"], deployments.sepolia["aaveTestWETH"], "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951", { gasLimit: 1000000 })).wait()).hash)

  const bridgeLogicAddress = deployments.optimism["bridgeLogicAddress"]
  const bridgeLogic = await hre.ethers.getContractAt("BridgeLogic", bridgeLogicAddress);

  //Check aToken balance of ntegrator
  // const curPos = await integratorContract.getCurrentPosition(
  //   deployments.sepolia["poolAddress"],
  //   deployments.sepolia["aaveTestWETH"],
  //   "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951",
  //   protocolHash
  // );
  console.log(await bridgeLogic.poolToAsset(deployments.arbitrum["poolAddress"]), await bridgeLogic.poolToCurrentPositionMarket(deployments.arbitrum["poolAddress"]), await bridgeLogic.poolToCurrentProtocolHash(deployments.arbitrum["poolAddress"]))
  const curPos2 = await bridgeLogic.getPositionBalance(deployments.arbitrum["poolAddress"])

  console.log(curPos2)



  console.log("Current Position: ", "Broker: ", await registryContract.poolAddressToBroker(deployments.arbitrum["poolAddress"]))
}

const upgradeCalc = async () => {

  const ManagerV2 = await hre.ethers.getContractFactory("ChaserManager");
  const manager = await hre.upgrades.upgradeProxy(deployments[mainChain]["managerAddress"], ManagerV2);
  const newAddr = await manager.getAddress()
  console.log("Manager upgraded", newAddr);

  const PoolCalculations = await hre.ethers.getContractFactory("PoolCalculations");
  const poolCalculationsContract = await hre.upgrades.upgradeProxy(deployments[mainChain]["poolCalculationsAddress"], PoolCalculations);
  const poolCalculationsAddress = await poolCalculationsContract.getAddress()
  console.log("POOL CALCULATIONS", poolCalculationsAddress)
}

const bridgeTokens = async (currentChain, destinationChain) => {

  const amount = "1000000000000"
  const wethAddr = deployments[currentChain]["WETH"]
  // const WETH = await hre.ethers.getContractAt("ERC20", wethAddr);
  // await WETH.approve(deployments[currentChain]["spokePool"], amount)

  const spokePool = await hre.ethers.getContractAt("ISpokePool", "0xec6e1527948a1d6bb3fdcd528d75844020b20a1d");
  const bridgeTx = await (await spokePool.depositV3Now(
    "0x1CA2b10c61D0d92f2096209385c6cB33E3691b5E",
    "0x1CA2b10c61D0d92f2096209385c6cB33E3691b5E",
    deployments[currentChain]["WETH"],
    zeroAddress,
    amount,
    totalFeeCalc(amount),
    networks[destinationChain],
    zeroAddress,
    0,
    0,
    "0x",
    { gasLimit: "8000000" }
  )).wait();

  console.log(bridgeTx)


}

const manualAcrossMessageHandle = async (amount, chain, message) => {
  //This is used when a Bridge message doesnt seem to go through and we need to determine if the issue is reversion
  const receiverContract = await hre.ethers.getContractAt("BridgeReceiver", deployments[chain]["receiverAddress"]);

  const wethAddr = deployments[chain]["WETH"]

  //message should be bytes from topic 0xe503f02a28c80b867adfed9777a61077c421693358e2f0f1fc54e13acaa18005
  const trimMessageData = message
    .split("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000160")
    .join("")
    .split("000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000c0")
    .join("")

  // Simulate the receiver on[chain] getting bridged WETH, by sending WETH from within[chain] to the receiver
  const WETH = await hre.ethers.getContractAt("ERC20", wethAddr);

  console.log((await (await WETH.transfer(deployments[chain]["receiverAddress"], amount)).wait()).hash)

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
    // await mainDeployments() //CHECK THAT THE DEFAULT NETWORK IN "..hardhat.config.js" IS sepolia
    // await secondaryDeployments("optimism") //CHANGE THE DEFAULT NETWORK IN "..hardhat.config.js" TO base
    // await setReceivers("arbitrum")
    // await setPivotConfigs()
    // --------------------------------------------------------------------------------------------
    // IF YOU EXECUTED THE PRIOR SECTION AND/OR WOULD LIKE TO DEPLOY YOUR POOL FOR TESTING - EXECUTE THE FOLLOWING FUNCTION
    // This function also sends the initial deposit funds through the bridge into the investment as the position is set on base
    // await upgradeCalc()
    // await poolDeploy()
    // await positionSetDeposit()

    // await callPivot()
    // await poolDeposit()
    // await sendTokens()
    // await addStrategyCode()
    // --------------------------------------------------------------------------------------------
    // --------------------------------------------------------------------------------------------
    // EXECUTE THIS FUNCTION TO START A DEPOSIT TO THE POOL
    // REMINDER TO REVISIT THE ABOVE SECTION TO SIMULATE THE CCIP TRIGGER MESSAGE FOR EXECUTING THE DEPOSIT ON ETHEREUM BASE
    // --------------------------------------------------------------------------------------------
    // await upgradeContract("optimism")
    // await poolStatRead()
    // await poolWithdraw()
    // await poolStatRead()
    // 
    // 
    // await bridgeTokens("sepolia", "optimism")

    // --------------------------------------------------------------------------------------------
    // await manualAcrossMessageHandle("48903935794173", "optimism", "0x5F240EEE00000000000000000000000000000000000000000000000000000000000000000000000000000000E512FEC32AD1645AE650BB8AD0FD26D1CFC6C4CC0000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000004094F0D1C80A7B855DC8BD48D38EA0ADB40266A859A3B4B9C2A0E1B0AE6F60BC7E0000000000000000000000000000000000000000000000000000000000000001")

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




//These addresses pertain to a Chaser version deployed to sepolia to demonstrate Uma capabilities. On other chains, this is a dummy UMA process 
const sepoliaUMAdemo = {
  "registryAddress": "0x5af00752888CA07391fA001cA2E06901f3b8Eeb6",
  "poolCalculationsAddress": "0x7f69D502Bc7580BBD5d74a2D6E5D0E98e89Cb4d1",
  "bridgeLogicAddress": "0x6dF1E4611b95F6D0fF2Bade43C6506940fC6d2F5",
  "messengerAddress": "0xE60A6CCb85A7a4248F7FCb87188C5148e97884Cb",
  "receiverAddress": "0xB6930f81CAae1F74b0B77c91d2851564Cf92232d",
  "spokePool": "0x5ef6C01E11889d86803e0B23e3cB3F9E9d97B662",
  "WETH": "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14",
  "aaveMarketId": "0x29598b72eb5CeBd806C5dCD549490FdA35B13cD8",
  "compoundMarketId": "0x2943ac1216979aD8dB76D9147F64E61adc126e96E4aB69C077896252FAFBD49EFD26B5D171A32410",
  "integratorAddress": "0x5c5eBDd1837E109F85Db6Ba19FFcd7ff17d2f443",
  "linkToken": "0x779877A7B0D9E8603169DdbD7836e478b4624789",
  "managerAddress": "0x4899fc38660240d82f986243D472b5D4334455ba",
  "poolAddress": "0x5804b12c656c115029f05586ce42bdf293c0a00e",
  "investmentStrategy": "0x3Af008eBd82C8Bf3e5E62668F10f130b453f3Fda",
  "arbitrationContract": "0xcEA44a22562d145fCEfEb836DB8D9cc6246AF80b",
  "aaveTestWETH": "0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c",
  "compoundTestWETH": "0x2D5ee574e710219a521449679A4A7f2B43f046ad"
}



