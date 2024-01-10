const hre = require("hardhat");
const ethers = require("ethers");

const goerliFirstDeployments = async () => {


  // Deploy manager to user level chain, deploy the test pool
  // const managerDepo1 = await hre.ethers.deployContract("ChaserManager", [hre.network.config.chainId], {
  //   value: 0
  // });
  // const manager1 = await managerDepo1.waitForDeployment();
  // console.log("MANAGER: ", managerDepo1.target); // 0x2B2147eD85859733aE624Ab051d5855adc94305f
  const manager1 = await hre.ethers.getContractAt("ChaserManager", "0x2B2147eD85859733aE624Ab051d5855adc94305f");

  const registryAddress = await manager1.registry();


  const registryContract = await hre.ethers.getContractAt("Registry", registryAddress);
  console.log("REGISTRY: ", registryAddress)

  await (await registryContract.deployBridgedConnector({ gasLimit: 5000000 })).wait()

  const connector = await registryContract.chainIdToBridgedConnector(5)

  console.log("CONNECTOR: ", connector)


  // const poolTx1 = await (await manager1.createNewPool(
  //   "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6",
  //   "",
  //   "PoolName",
  //   {
  //     gasLimit: 5000000
  //   }
  // )).wait();
  // const poolAddress = '0x' + poolTx1.logs[0].topics[1].slice(-40);

  // console.log("Pool Address: ", poolAddress);


  // // console.log("REGISTRY: ", registryAddress)
  // const pool = await hre.ethers.getContractAt("PoolControl", poolAddress);
  // await (await pool.initializeContractConnections(registryAddress, { gasLimit: 300000 })).wait()


  // const connectorAddr = await pool.localBridgedConnector();
  // console.log("Connector Goerli: ", connectorAddr)
}

const mumbaiFirstDeployments = async (goerliConnector) => {

  const registry = await hre.ethers.deployContract("Registry", [80001, 5], {
    value: 0
  });
  const registryContract = await registry.waitForDeployment()
  console.log("Mumbai Registry: ", registryContract.target)

  await (await registryContract.deployBridgedConnector({ gasLimit: 5000000 })).wait()


  const connector = await registryContract.chainIdToBridgedConnector(80001)
  console.log("Mumbai Connector: ", connector)

  await registryContract.addBridgedConnector(5, goerliConnector)

}

const goerliSecondConfig = async (poolAddress, mumbaiConnector) => {
  const pool = await hre.ethers.getContractAt("PoolControl", poolAddress)



  const registryContract = await hre.ethers.getContractAt("Registry", await pool.registry());

  await (await registryContract.addBridgedConnector(80001, mumbaiConnector)).wait()


  console.log(await registryContract.chainIdToBridgedConnector(80001))

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
  const connector = await hre.ethers.getContractAt("BridgedConnector", mumbaiConnector);

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


goerliFirstDeployments().catch((error) => {
  console.error(error);
  console.log(error.logs)
  process.exitCode = 1;
});

// mumbaiFirstDeployments("0xdD7C05F7ACb4a6B22020c7c8BAdE4E9Ad3d6999E").catch((error) => {
//   console.error(error);
//   console.log(error.logs)
//   process.exitCode = 1;
// });

// goerliSecondConfig("0xab79e6c420f89de019097409d94710860aca1103", "0x10d43161026251457F5a733F97BeFb8B73291682").catch((error) => {
//   console.error(error);
//   console.log(error.logs)
//   process.exitCode = 1;
// });

// mumbaiTests("0xab79e6c420f89de019097409d94710860aca1103", "0x10d43161026251457F5a733F97BeFb8B73291682").catch((error) => {
//   console.error(error);
//   console.log(error.logs)
//   process.exitCode = 1;
// });