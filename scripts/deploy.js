const hre = require("hardhat");
const ethers = require("ethers");

const goerliFirstDeployments = async () => {


  // Deploy manager to user level chain, deploy the test pool
  const managerDepo1 = await hre.ethers.deployContract("ChaserManager", [hre.network.config.chainId], {
    value: 0
  });
  const manager1 = await managerDepo1.waitForDeployment();
  console.log("MANAGER: ", managerDepo1.target); // 0x6606c32758c54909795F8A045B74a1012A3e76eD
  // const manager1 = await hre.ethers.getContractAt("ChaserManager", "0x615070250c1aCD2Ee0c01968C930a7B5bB470DA7");

  const registryAddress = await manager1.registry();


  const registryContract = await hre.ethers.getContractAt("Registry", registryAddress);
  console.log("REGISTRY: ", registryAddress)

  await (await registryContract.deployBridgeLogic({ gasLimit: 8000000 })).wait()

  const connector = await registryContract.chainIdToBridgeReceiver(5)


  console.log("CONNECTOR: ", connector)


  const poolTx = await (await manager1.createNewPool(
    "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6",
    "",
    "PoolName",
    {
      gasLimit: 7000000
    }
  )).wait();
  const poolAddress = '0x' + poolTx.logs[0].topics[1].slice(-40);

  // const poolAddress = "0x2a7552fe2dd0c6fc7d443127f1670428aed432ab";

  console.log("Pool Address: ", poolAddress);
  const pool = await hre.ethers.getContractAt("PoolControl", poolAddress);


  // // console.log("REGISTRY: ", registryAddress)
  // await (await pool.initializeContractConnections(registryAddress, { gasLimit: 300000 })).wait()

  const rec = await registryContract.chainIdToBridgeReceiver(5)


  console.log("Receiver Goerli: ", rec)
}

const mumbaiFirstDeployments = async (goerliReceiver) => {

  const registry = await hre.ethers.deployContract("Registry", [80001, 5], {
    value: 0
  });
  const registryContract = await registry.waitForDeployment()
  console.log("Mumbai Registry: ", registryContract.target)

  await (await registryContract.deployBridgeLogic({ gasLimit: 8000000 })).wait()




  const receiver = await registryContract.chainIdToBridgeReceiver(80001)
  console.log("Mumbai receiver: ", receiver)

  await registryContract.addBridgeReceiver(5, goerliReceiver)

}

const goerliSecondConfig = async (poolAddress, mumbaiReceiver) => {
  const pool = await hre.ethers.getContractAt("PoolControl", poolAddress)



  const registryContract = await hre.ethers.getContractAt("Registry", await pool.registry());

  await (await registryContract.addBridgeReceiver(80001, mumbaiReceiver)).wait()


  console.log(await registryContract.chainIdToBridgeReceiver(80001))

  // Call userDepositAndSetPosition to initialize on mumbai

  const WETH = await hre.ethers.getContractAt("ERC20", "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6");

  const amount = "1000000000000000"

  await WETH.approve(poolAddress, amount)


  const tx = await pool.userDepositAndSetPosition(
    amount,
    "200000000000000000",
    "0x0242242424242",
    80001,
    "iisjdoij",
    { gasLimit: 1000000 }
  )

  console.log((await tx.wait()).hash)

}

const mumbaiTests = async (poolAddress, mumbaiConnector) => {
  const connector = await hre.ethers.getContractAt("BridgeReceiver", mumbaiConnector);

  console.log('check non zero', await connector.testFlag())
}

//Function for goerli
//--Deploy Manager
//--create pool
//--get the connector addr
//Function for mumbai
//--Deploy registry to mumbai
//--Get the connector addr
//--Add goerli connector to mumbai registry
//Switch to goerli
//--Add mumbai connector to goerli registry
//--pool userDepositAndSetPosition to an address on mumbai
//--Read events from the mumbai positionInitializer


// goerliFirstDeployments().catch((error) => {
//   console.error(error);
//   console.log(error.logs)
//   process.exitCode = 1;
// });

// mumbaiFirstDeployments("0x17E952A00941E0D6Dfe52D0d007A0DeD53D571D4").catch((error) => {
//   console.error(error);
//   console.log(error.logs)
//   process.exitCode = 1;
// });

goerliSecondConfig("0x218621baf387bb346c30d6108a63fdc2dc0459b2", "0xc532035774B1E8664c88Be7A476510EB7EcaE553").catch((error) => {
  console.error(error);
  console.log(error.logs)
  process.exitCode = 1;
});

// mumbaiTests("0x0b9a1fc1bccfbfb68391a1011836052a030770c5", "0x06cF5b9de3096c3eE1f1910d0c220F182Ab0816A").catch((error) => {
//   console.error(error);
//   console.log(error.logs)
//   process.exitCode = 1;
// });