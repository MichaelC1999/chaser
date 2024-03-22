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
    gasLimit: 2000000,
    value: 0
  })).waitForDeployment();

  deployments.base["registryAddress"] = registryContract.target
  writeAddressesToFile(deployments)

  await (await manager.addRegistry(registryContract.target)).wait()
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

  await (await bridgeLogicContract.addConnections(messengerAddress, receiverAddress)).wait()

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
    gasLimit: 2000000,
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

  const bridgeLogicAddress = bridgeLogicContract.target
  deployments.sepolia["bridgeLogicAddress"] = bridgeLogicAddress
  writeAddressesToFile(deployments)
  console.log("BRIDGE LOGIC", bridgeLogicAddress)

  const ccip = (await registryContract.localCcipConfigs())
  const messengerContract = await (await hre.ethers.deployContract("ChaserMessenger", [ccip[0], ccip[1], registryAddress, bridgeLogicAddress, ccip[2]], {
    gasLimit: 7000000,
    value: 0
  })).waitForDeployment();

  const messengerAddress = messengerContract.target
  deployments.sepolia["messengerAddress"] = messengerAddress
  writeAddressesToFile(deployments)

  const receiverContract = await (await hre.ethers.deployContract("BridgeReceiver", [bridgeLogicAddress], {
    gasLimit: 7000000,
    value: 0
  })).waitForDeployment();

  const receiverAddress = receiverContract.target
  deployments.sepolia["receiverAddress"] = receiverAddress
  writeAddressesToFile(deployments)

  await (await bridgeLogicContract.addConnections(messengerAddress, receiverAddress)).wait()
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
    "iisjdoij",
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


  console.log("Deposit fulfillment tx hash: ", (await (await messengerContract.ccipReceiveManual("0x4d1c4fe3f27639b363f9d52e4dcadc62a2d95f9e9730c8b79fbb437d4e7ab563", trimMessageData)).wait()).hash)
  // const tokenContract = await (hre.ethers.getContractAt("IPoolToken", await pool.poolToken()))
  // console.log(await tokenContract.totalSupply())

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

  console.log(await messengerContract.ccipDecodeReceive("0x4d1c4fe3f27639b363f9d52e4dcadc62a2d95f9e9730c8b79fbb437d4e7ab563", trimMessageData))
  const bridgeLogicContract = await (hre.ethers.getContractAt("BridgeLogic", deployments.sepolia["bridgeLogicAddress"]))
  const WETH = await hre.ethers.getContractAt("ERC20", deployments.sepolia["WETH"]);
  const contractWethBal = await WETH.balanceOf(deployments.sepolia["bridgeLogicAddress"])

  console.log(contractWethBal, await bridgeLogicContract.readBalanceAtNonce(deployments.base["poolAddress"], 0), await bridgeLogicContract.readBalanceAtNonce(deployments.base["poolAddress"], 1), await bridgeLogicContract.readBalanceAtNonce(deployments.base["poolAddress"], 2), await bridgeLogicContract.bridgeNonce(deployments.base["poolAddress"]))
  // console.log(await bridgeLogicContract.getUserMaxWithdraw(contractWethBal, "100000000000000000", deployments.base["poolAddress"], 1))
  //Check user max withdraw
  //   getUserMaxWithdraw(
  //     uint256 _currentPositionValue,
  //     uint256 _scaledRatio,
  //     address _poolAddress,
  //     uint256 _poolNonce
  // ) 

  // console.log((await (await messengerContract.ccipReceiveManual("0x4d1c4fe3f27639b363f9d52e4dcadc62a2d95f9e9730c8b79fbb437d4e7ab563", trimMessageData)).wait()).hash)
}


const poolStatRead = async () => {
  const pool = await hre.ethers.getContractAt("PoolControl", deployments.base["poolAddress"])
  const tokenContract = await (hre.ethers.getContractAt("IPoolToken", await pool.poolToken()))
  //CHECK POSITIONAL DATA
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
  console.log(await tokenContract.totalSupply())
}

const baseDeposit = async () => {
  const pool = await hre.ethers.getContractAt("PoolControl", deployments.base["poolAddress"])

  const amount = "1000000000000000"


  const WETH = await hre.ethers.getContractAt("ERC20", deployments.base["WETH"]);
  await WETH.approve(deployments.base["poolAddress"], amount)
  const tx = await pool.userDeposit(
    amount,
    totalFeeCalc(amount),
    { gasLimit: 1000000 }
  )

  console.log((await tx.wait()).hash)
}

const baseWithdraw = async () => {
  // Creates CCIP message, manually executed on the base messenger contact, which sends withdraw through across and finalizes on sepolia

  const pool = await hre.ethers.getContractAt("PoolControl", deployments.base["poolAddress"])
  const amount = "2000000000000000"
  const tx = await pool.userWithdrawOrder(amount, { gasLimit: 1000000 })
  console.log((await tx.wait()).hash)
}

const manualAcrossMessageHandle = async () => {
  //This is used when a Bridge message doesnt seem to go through and we need to determine if the issue is reversion
  const receiverContract = await hre.ethers.getContractAt("BridgeReceiver", deployments.sepolia["receiverAddress"]);
  const wethAddr = deployments.sepolia["WETH"]

  // Simulate the receiver on base getting bridged WETH, by sending WETH from within base to the receiver
  const WETH = await hre.ethers.getContractAt("ERC20", wethAddr);
  const amount = "800000000000000"
  console.log((await (await WETH.transfer(deployments.sepolia["receiverAddress"], amount)).wait()).hash)

  // Paste the message from the V3FundsDeposited event that succeeded on the origin chain
  const message = "0x5F240EEE00000000000000000000000000000000000000000000000000000000000000000000000000000000CCE6526A2AE1A7DA4B8E4B2DC8151E04BB0EC10B000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000408FFA3A2BFFB84610CBEAE450D0F2E11FA247772DAF40BF56A610B34E446952B20000000000000000000000001CA2B10C61D0D92F2096209385C6CB33E3691B5E"
  console.log(await receiverContract.decodeMessageEvent(message))


  const registryContract = await hre.ethers.getContractAt("Registry", deployments.sepolia["registryAddress"]);
  console.log(await registryContract.currentChainId(), await registryContract.managerChainId())

  console.log((await (await receiverContract.handleV3AcrossMessage(wethAddr, amount, wethAddr, message)).wait()).hash)
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
    // baseDeployments() //CHECK THAT THE DEFAULT NETWORK IN "..hardhat.config.js" IS base
    // sepoliaDeployments() //CHANGE THE DEFAULT NETWORK IN "..hardhat.config.js" TO sepolia
    // await baseSecondConfig() //CHANGE THE DEFAULT NETWORK IN "..hardhat.config.js" TO base
    // --------------------------------------------------------------------------------------------
    // IF YOU EXECUTED THE PRIOR SECTION AND/OR WOULD LIKE TO DEPLOY YOUR POOL FOR TESTING - EXECUTE THE FOLLOWING FUNCTION
    // This function also sends the initial deposit funds through the bridge into the investment as the position is set on sepolia
    // await basePoolDeploy()
    // --------------------------------------------------------------------------------------------
    // AFTER EXECUTING basePoolDeploy() OR baseDeposit(), WAIT FOR THE ETHEREUM SEPOLIA ACROSS SPOKEPOOL TO RECEIVE THE DEPOSIT
    // GET THE MESSAGE DATA FROM BASESCAN, COPYING THE HEX DATA BYTES FROM EVENT "0x244e451036514e829e60556484796d2251dc3d952cd079db45d2bfb4c0aff2a1"
    // PASTE MESSAGE DATA INTO THE ARGUMENT FOR FOLLOWING FUNCTION
    // sepoliaSimulateCCIPReceive("0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000100fd8be16600000000000000000000000000000000000000000000000000000000000000000000000000000000cce6526a2ae1a7da4b8e4b2dc8151e04bb0ec10b000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000002d79883d200000000000000000000000000000000000000000000000000000002d79883d2000000000000000000000000000020bd5ead8d7397b0ba346fd81b66e58793b746a875d469e49828e31c8e506a32983f6cb898508374df0ce744e94949cf846599e9")
    // --------------------------------------------------------------------------------------------
    // EXECUTE THIS FUNCTION TO START A DEPOSIT TO THE POOL
    // baseDeposit()
    // REMINDER TO REVISIT THE ABOVE SECTION TO SIMULATE THE CCIP TRIGGER MESSAGE FOR EXECUTING THE DEPOSIT ON ETHEREUM SEPOLIA
    // --------------------------------------------------------------------------------------------

    // baseWithdraw()
    // baseSimulateCCIPReceive("0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001003705af6d00000000000000000000000000000000000000000000000000000000000000000000000000000000b946566da84d8e80a0ef2d6119367ea6eab8cbcb000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000808c234950f5604c768a98aa1105c018b53cb7ac88f7c85954c6c09d64bbb9bd2200000000000000000000000000000000000000000000000000071afd498d000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000de0b6b3a7640000")

    // --------------------------------------------------------------------------------------------

    // poolStatRead()
    // basePositionSetDeposit()
    // sepoliaReceivers()
    // manualAcrossMessageHandle()




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