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

    const cons2 = await hre.ethers.getContractAt("FunctionsConsumer", "0x9F41D138657Dd79a0eae80ecff2aC3d64E3F35d8")

    const conduit = await hre.ethers.getContractAt("BridgingConduit", "0x5641e9fD6CE3E8E8e4f23c6d939777fE616e5369")
    console.log(await conduit.executeMovePosition("fdsf"))
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
