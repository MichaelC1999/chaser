const hre = require("hardhat");
const ethers = require("ethers");

async function main() {
  let managerAddress = "";

  // Deploy testnet dummy asset

  const erc20Token1 = await erc20TokenDepo1.waitForDeployment();
  console.log(erc20TokenDepo1.target, hre.network.config.chainId);

  // Deploy manager to user level chain, deploy the test pool
  const managerDepo1 = await hre.ethers.deployContract("ChaserManager", [hre.network.config.chainId], {
    value: 0
  });
  const manager1 = await managerDepo1.waitForDeployment();
  console.log(managerDepo1.target);

  const poolTx1 = await (await manager1.createNewPool(
    erc20TokenDepo1.target,
    "",
    "PoolName"
  )).wait();
  const poolAddress = '0x' + poolTx1.logs[0].topics[1].slice(-40);
  console.log(poolTx1.hash, poolAddress);

  // Enter new position sequence
  const pool = await hre.ethers.getContractAt("PoolControl", poolAddress);
  const connectorAddr = await pool.localBridgedConnector();
  const amount1 = "200000000000000000";
  const relayFeePct = "100000000000000000";
  const asset = await pool.asset();

}

//Function for goerli
//--Deploy Manager
//--convert some eth to WETH
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


main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
