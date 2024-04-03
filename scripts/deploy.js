const hre = require("hardhat");
const ethers = require("ethers");
const fs = require('fs');

const deployments = require('./contractAddresses.json')

const baseDeployments = async () => {

  const [deployer] = await hre.ethers.getSigners();

  // Fetch the current gas price
  const gasPrice = await deployer.provider.getFeeData();


  console.log(gasPrice)


  // Deploy manager to user level chain, deploy the test pool
  const managerDeployment = await hre.ethers.deployContract("ChaserManager", [84532], {
    gasLimit: 7500000,
    value: 0
  });
  const manager = await managerDeployment.waitForDeployment();
  deployments.base["managerAddress"] = managerDeployment.target

  const registryContract = await (await hre.ethers.deployContract("Registry", [84532, 84532, deployments.base["managerAddress"]], {
    gasLimit: 3000000,
    value: 0
  })).waitForDeployment();

  deployments.base["registryAddress"] = registryContract.target
  writeAddressesToFile(deployments)

  await (await manager.addRegistry(deployments.base["registryAddress"])).wait()
  console.log("REGISTRY: ", deployments.base["registryAddress"])



  const calcContract = await (await hre.ethers.deployContract("PoolCalculations", [], {
    gasLimit: 7000000,
    value: 0
  })).waitForDeployment();

  console.log("POOL CALCULATIONS: ", calcContract.target)
  deployments.base["poolCalculationsAddress"] = calcContract.target
  writeAddressesToFile(deployments)

  await manager.addPoolCalculationsAddress(calcContract.target)

  const bridgeLogicContract = await (await hre.ethers.deployContract("BridgeLogic", [84532, deployments.base["registryAddress"]], {
    gasLimit: 7000000,
    value: 0
  })).waitForDeployment();

  const bridgeLogicAddress = bridgeLogicContract.target
  console.log("BRIDGE LOGIC", bridgeLogicAddress)
  deployments.base["bridgeLogicAddress"] = bridgeLogicAddress
  writeAddressesToFile(deployments)

  const ccip = (await registryContract.localCcipConfigs())
  console.log(ccip)
  const messengerContract = await (await hre.ethers.deployContract("ChaserMessenger", [ccip[0], ccip[1], deployments.base["registryAddress"], bridgeLogicAddress, ccip[2]], {
    gasLimit: 7000000,
    value: 0
  })).waitForDeployment();

  const messengerAddress = messengerContract.target
  deployments.base["messengerAddress"] = messengerAddress
  writeAddressesToFile(deployments)


  const receiverContract = await (await hre.ethers.deployContract("BridgeReceiver", [bridgeLogicAddress], {
    gasLimit: 7000000,
    value: 0
  })).waitForDeployment();

  const receiverAddress = receiverContract.target
  deployments.base["receiverAddress"] = receiverAddress
  writeAddressesToFile(deployments)

  const integratorContract = await (await hre.ethers.deployContract("Integrator", [bridgeLogicAddress, deployments.base["registryAddress"]], {
    gasLimit: 7000000,
    value: 0
  })).waitForDeployment();

  const integratorAddress = integratorContract.target
  deployments.base["integratorAddress"] = integratorAddress
  writeAddressesToFile(deployments)

  await (await bridgeLogicContract.addConnections(messengerAddress, receiverAddress, integratorAddress)).wait()

  await (await registryContract.addBridgeLogic(bridgeLogicAddress, messengerAddress, receiverAddress)).wait()

  console.log('MESSENGER: ', await bridgeLogicContract.messenger(), await registryContract.chainIdToMessageReceiver(84532))

  console.log('RECEIVER: ', await bridgeLogicContract.bridgeReceiverAddress(), await registryContract.receiverAddress())

  console.log(deployments.base)

}

const sepoliaDeployments = async () => {
  const [deployer] = await hre.ethers.getSigners();

  // Fetch the current gas price
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

  const amount = "100000000000000000"

  console.log("Token Transfer: ", (await (await aaveTestToken.transfer(deployments.sepolia["integratorAddress"], amount)).wait()).hash)



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

  const manager = await hre.ethers.getContractAt("ChaserManager", deployments.base["managerAddress"]);

  const poolTx = await (await manager.createNewPool(
    deployments.base["WETH"],
    "",
    "PoolName",
    {
      gasLimit: 7000000
    }
  )).wait();
  const poolAddress = '0x' + poolTx.logs[0].topics[1].slice(-40);
  deployments.base["poolAddress"] = poolAddress
  writeAddressesToFile(deployments)

  console.log("Pool Address: ", poolAddress);

  await basePositionSetDeposit()
}

const basePositionSetDeposit = async () => {
  //This function executes the first deposit on a pool and sets the position (The external protocol/chain/pool that this pool will invest assets in)
  const pool = await hre.ethers.getContractAt("PoolControl", deployments.base["poolAddress"])

  const WETH = await hre.ethers.getContractAt("ERC20", deployments.base["WETH"]);

  const amount = "1000000000000000"

  await WETH.approve(deployments.base["poolAddress"], amount)


  const tx = await pool.userDepositAndSetPosition(
    amount,
    totalFeeCalc(amount),
    "0x0242242424242",
    11155111,
    "aave",
    { gasLimit: 1000000 }
  )

  console.log(`Pool 0x...${deployments.base["poolAddress"].slice(34)} position set and initial deposit tx hash: `, (await tx.wait()).hash)
}

const baseSimulateCCIPReceive = async (messageDataCCIP) => {

  const trimMessageData = messageDataCCIP.split("000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000e0").join("").split("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000100").join("")

  console.log(trimMessageData)
  const pool = await hre.ethers.getContractAt("PoolControl", deployments.base["poolAddress"])
  const registryContract = await hre.ethers.getContractAt("Registry", deployments.base["registryAddress"]);
  const messengerContract = await hre.ethers.getContractAt("ChaserMessenger", deployments.base["messengerAddress"])

  // console.log(await messengerContract.ccipDecodeReceive("0x4d1c4fe3f27639b363f9d52e4dcadc62a2d95f9e9730c8b79fbb437d4e7ab563", trimMessageData))
  // 

  console.log("Deposit fulfillment tx hash: ", (await (await messengerContract.ccipReceiveManual("0x4d1c4fe3f27639b363f9d52e4dcadc62a2d95f9e9730c8b79fbb437d4e7ab563", trimMessageData)).wait()).hash)
  const tokenContract = await (hre.ethers.getContractAt("IPoolToken", await pool.poolToken()))
  console.log(await tokenContract.totalSupply())

  // Dummy pool position amount transmitted from bridgeLogic is less than the actual recorded amount in deposit. Minting calculation subtracts to a negative
  //Amount should really be 2000000000000000

  // console.log(await calcContract.withdrawIdToDepositor("0x2ea3f97b03ea09969bcb183753bd7c232cb7f1afe53cda881fc3e78ac5c4d043"))
  // console.log(await (calcContract.calculatePoolTokensToMint(
  //   "0xe7638e9b52b006d70dcd5223432a14b751ca6c4146e5ee5b995ae62ef1bfbf05",
  //   "2898800767725704",
  //   "262531245619958"
  // )))
}

const sepoliaSimulateCCIPReceive = async (messageDataCCIP) => {

  const trimMessageData = messageDataCCIP.split("000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000e0").join("").split("00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000100").join("")

  const messengerContract = await (hre.ethers.getContractAt("ChaserMessenger", deployments.sepolia["messengerAddress"]))
  console.log(trimMessageData)
  console.log(await messengerContract.ccipDecodeReceive("0x4d1c4fe3f27639b363f9d52e4dcadc62a2d95f9e9730c8b79fbb437d4e7ab563", trimMessageData))
  const bridgeLogicContract = await (hre.ethers.getContractAt("BridgeLogic", deployments.sepolia["bridgeLogicAddress"]))
  const WETH = await hre.ethers.getContractAt("ERC20", deployments.sepolia["WETH"]);
  const contractWethBal = await WETH.balanceOf(deployments.sepolia["bridgeLogicAddress"])

  console.log(await bridgeLogicContract.readBalanceAtNonce(deployments.base["poolAddress"], 0), await bridgeLogicContract.readBalanceAtNonce(deployments.base["poolAddress"], 1), await bridgeLogicContract.readBalanceAtNonce(deployments.base["poolAddress"], 2), await bridgeLogicContract.readBalanceAtNonce(deployments.base["poolAddress"], 3), await bridgeLogicContract.bridgeNonce(deployments.base["poolAddress"]))
  // console.log(await bridgeLogicContract.getUserMaxWithdraw(contractWethBal, "100000000000000000", deployments.base["poolAddress"], 1))
  //Check user max withdraw
  //   getUserMaxWithdraw(
  //     uint256 _currentPositionValue,
  //     uint256 _scaledRatio,
  //     address _poolAddress,
  //     uint256 _poolNonce
  // ) 

  console.log("Transaction Hash: ", (await (await messengerContract.ccipReceiveManual("0x4d1c4fe3f27639b363f9d52e4dcadc62a2d95f9e9730c8b79fbb437d4e7ab563", trimMessageData)).wait()).hash)
}


const poolStatRead = async () => {
  const pool = await hre.ethers.getContractAt("PoolControl", deployments.base["poolAddress"])
  const tokenContract = await (hre.ethers.getContractAt("IPoolToken", await pool.poolToken()))
  const calcContract = await hre.ethers.getContractAt("PoolCalculations", "0x9845860E83c0a310C29A3fd7aC8F0D39615a32A5")

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
    "LASTS: ",
    await pool.lastPositionAddress(),
    await pool.lastPositionChain(),
    await pool.lastPositionProtocolHash())

  console.log("TOKENS: ",
    await tokenContract.totalSupply(),
    // await calcContract.getScaledRatio(await pool.poolToken(), "0x1CA2b10c61D0d92f2096209385c6cB33E3691b5E"),
    await tokenContract.balanceOf("0x1CA2b10c61D0d92f2096209385c6cB33E3691b5E"),
    await calcContract.getScaledRatio(await pool.poolToken(), "0xF80cAb395657197967EaEdf94bD7f8a75Ad8F373"),
    await tokenContract.balanceOf("0xF80cAb395657197967EaEdf94bD7f8a75Ad8F373"))

  // POOL CALCULATIONS:  0x9845860E83c0a310C29A3fd7aC8F0D39615a32A5
  // 333333348757782935n
  // 666666651242217064n
}

const baseDeposit = async () => {
  const pool = await hre.ethers.getContractAt("PoolControl", deployments.base["poolAddress"])

  const amount = "2000000000000000"

  const WETH = await hre.ethers.getContractAt("ERC20", deployments.base["WETH"]);
  await WETH.approve(deployments.base["poolAddress"], amount)
  const tx = await pool.userDeposit(
    amount,
    totalFeeCalc(amount),
    { gasLimit: 1000000 }
  )

  console.log("Non position set Deposit: ", (await tx.wait()).hash)
}

const baseWithdraw = async () => {
  // Creates CCIP message, manually executed on the base messenger contact, which sends withdraw through across and finalizes on sepolia

  const pool = await hre.ethers.getContractAt("PoolControl", deployments.base["poolAddress"])
  const amount = "2400000000000000"
  const tx = await pool.userWithdrawOrder(amount, { gasLimit: 1000000 })
  console.log((await tx.wait()).hash)
}

const sepoliaIntegrationsTest = async () => {
  const integratorContract = await hre.ethers.getContractAt("Integrator", deployments.sepolia["integratorAddress"]);
  const registryContract = await hre.ethers.getContractAt("Registry", deployments.sepolia["registryAddress"]);

  // Get hash of protocol
  const protocolHash = await integratorContract.hasher("aave")

  // Get hash operations
  const operation = await integratorContract.hasher("withdraw")

  const amount = "50000000000000"

  // ??? pass native WETH to the integrator
  // Send aave test WETH to integrator
  const WETH = await hre.ethers.getContractAt("ERC20", "0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357");
  // console.log("Token Transfer: ", (await (await WETH.transfer(deployments.sepolia["integratorAddress"], amount)).wait()).hash)
  console.log(deployments.base["poolAddress"])
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

  console.log(await bridgeLogic.getUserMaxWithdraw(curPos, "333333348757782935", deployments.base["poolAddress"], 2))
  //Check user max withdraw
  //   getUserMaxWithdraw(
  //     uint256 _currentPositionValue,
  //     uint256 _scaledRatio,
  //     address _poolAddress,
  //     uint256 _poolNonce
  // ) 

  // console.log(await bridgeLogic.readBalanceAtNonce(deployments.base["poolAddress"], 0), await bridgeLogic.readBalanceAtNonce(deployments.base["poolAddress"], 1), await bridgeLogic.readBalanceAtNonce(deployments.base["poolAddress"], 2), await bridgeLogic.readBalanceAtNonce(deployments.base["poolAddress"], 3), await bridgeLogic.bridgeNonce(deployments.base["poolAddress"]))


  console.log("Current Position: ", curPos, "Broker: ", await registryContract.poolAddressToBroker(deployments.base["poolAddress"]))
}

const manualAcrossMessageHandle = async (message) => {
  //This is used when a Bridge message doesnt seem to go through and we need to determine if the issue is reversion
  const receiverContract = await hre.ethers.getContractAt("BridgeReceiver", deployments.base["receiverAddress"]);
  const wethAddr = deployments.base["WETH"]

  // Simulate the receiver on base getting bridged WETH, by sending WETH from within base to the receiver
  const WETH = await hre.ethers.getContractAt("ERC20", wethAddr);
  const amount = "640000044422412"
  console.log((await (await WETH.transfer(deployments.base["receiverAddress"], amount)).wait()).hash)

  // Paste the message from the V3FundsDeposited event that succeeded on the origin chain
  console.log(await receiverContract.decodeMessageEvent(message))


  // const registryContract = await hre.ethers.getContractAt("Registry", deployments.base["registryAddress"]);
  // console.log(await registryContract.currentChainId(), await registryContract.managerChainId())

  console.log("Across Handle Hash: ", (await (await receiverContract.handleV3AcrossMessage(wethAddr, amount, wethAddr, message, { gasLimit: 2000000 })).wait()).hash)
  // -Call handleV3AcrossMessage passing in weth as tokenSent, amount, and message

}

//Function for sepolia
//--Deploy Manager
//--create pool
//--get the connector addr
//Function for base
//--Deploy registry to base
//--Get the connector addr
//--Add sepolia connector to base registry
//Switch to sepolia
//--Add base connector to sepolia registry
//--pool userDepositAndSetPosition to an address on base
//--Read events from the base positionInitializer



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
    // await basePoolDeploy()
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

    // await baseWithdraw()

    // await sepoliaSimulateCCIPReceive("0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001003705af6d000000000000000000000000000000000000000000000000000000000000000000000000000000009bdc76b596051e1e86eadb2e2af2a491e32bfa48000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000803f4c40f2d9e47df3a43c5c97200a65dd80990bf9d69827733cf5f393681c90dc000000000000000000000000000000000000000000000000000886c98b760000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000004a03cea247fc197")
    // --------------------------------------------------------------------------------------------
    // 
    // await poolStatRead()
    // basePositionSetDeposit()
    // sepoliaReceivers()
    // await manualAcrossMessageHandle("0xBD4F4B89000000000000000000000000000000000000000000000000000000000000000000000000000000009BDC76B596051E1E86EADB2E2AF2A491E32BFA48000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000803F4C40F2D9E47DF3A43C5C97200A65DD80990BF9D69827733CF5F393681C90DC0000000000000000000000000000000000000000000000000002D79887214A530000000000000000000000000000000000000000000000000005AF3175BAEF2A0000000000000000000000000000000000000000000000000002D79887214A53")

    // await sepoliaIntegrationsTest()



  } catch (error) {
    console.error(error);
    console.log(error.logs)
    process.exitCode = 1;
  }

}


function totalFeeCalc(amount) {
  return (parseInt((Number(amount) * .2).toString())).toString()
}

function writeAddressesToFile(contractAddresses) {
  const fileName = './scripts/contractAddresses.json';

  // Write the merged addresses back to the file
  fs.writeFileSync(fileName, JSON.stringify(contractAddresses, null, 2), 'utf-8');
  // console.log(`Addresses written to ${fileName}`);
}

// writeAddressesToFile({ ...deployments, base: { "ihef": "iefhr" } })


mainExecution()