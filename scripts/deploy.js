// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
const ethers = require("ethers")

async function main() {
  // STRATEGY CONTRACT DEPLOYED HERE
  const strat = await hre.ethers.getContractAt("InvestmentStrategyLogic", "0xFa54f50C444d2EB1bC021aCf3d4f0bdE2cc9C037")




  // const currentTimestampInSeconds = Math.round(Date.now() / 1000);
  // const unlockTime = currentTimestampInSeconds + 60;

  // const lockedAmount = hre.ethers.parseEther("0.001");

  // // const lock = await hre.ethers.deployContract("FunctionsConsumer", ["0xb83E47C2bC239B3bf370bc41e1459A34b41238D0", "0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000"], {
  // //   value: 0,
  // // });

  // const lock = await hre.ethers.deployContract("InvestmentStrategyLogic", [], {
  //   value: 0,
  // });

  // await lock.waitForDeployment();

  // console.log(lock)

  // console.log(
  //   `Lock with ${ethers.formatEther(
  //     lockedAmount
  //   )}ETH and unlock timestamp ${unlockTime} deployed to ${lock.target}`
  // );


}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
