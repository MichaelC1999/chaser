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
  // const strat = await hre.ethers.getContractAt("InvestmentStrategyLogic", "0x571061a5190E096A76f76b843b511e9b962f3183")

  // console.log(await strat.strategySourceCode())


  // 0x9e6CED8aE154fFCaAB3Bb9dC6E9d78374E69C2a6


  // const cons = await hre.ethers.getContractAt("FunctionsConsumer", "0x9823b0F589229527ec4E14E47cA6852E963D770e")

  // console.log(await cons.donId())

  // const cons2 = await hre.ethers.getContractAt("FunctionsConsumer", "0xBfb4aA2f8B275105b87c60F820C5b47Eb8b761da")

  // console.log(await cons2.donId())

  //Deploy the new bridgingConduit
  // Manually deploy the FunctionConsumer with donid bytes 0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000, manually provide the conduit address
  // 
  const lock2 = await hre.ethers.deployContract("BridgingConduit", [], {
    value: 0
  });
  console.log(lock2)
  await lock2.waitForDeployment(); //0x571061a5190E096A76f76b843b511e9b962f3183 ;

  console.log(lock2.target)



  // const lock1 = await hre.ethers.deployContract("FunctionsConsumer", ["0xb83E47C2bC239B3bf370bc41e1459A34b41238D0", "0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000"], {
  //   value: 0,
  // });


  // await lock1.waitForDeployment(); //0x84a824C2CDb6d6381E70767305d327B636cBCB23

  // console.log(lock1.target)
  // const conduit = await hre.ethers.getContractAt("BridgingConduit", await cons2.bridgingConduit())
  // console.log(await conduit.currentDepositPoolId())
  // console.log(await conduit.graphFunctionAddress()) //0x86ACa2eDbD5B713d76648bbFe87a25eab22F4401
  // BRIDGECONDUIT 0x19c43eB4AAeB16dBE87a4D4A3ACAe4FbA253B215

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
