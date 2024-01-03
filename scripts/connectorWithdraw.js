// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");
const ethers = require("ethers")

async function main() {
  let managerAddress = ""

  //***********************************************************************************************************************************************
  // Deploy testnet dummy asset
  let erc20TokenDepo = await hre.ethers.deployContract("TestWETHToken", [], {
    value: 0
  });

  const erc20Token = await erc20TokenDepo.waitForDeployment()

  await erc20Token.transfer("0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199", "100000000000000000000")

  console.log(erc20TokenDepo.target, hre.network.config.chainId)

  //***********************************************************************************************************************************************
  // Deploy manager to user level chain, deploy the test pool
  const managerDepo = await hre.ethers.deployContract("ChaserManager", [hre.network.config.chainId], {
    value: 0
  });
  const manager = await managerDepo.waitForDeployment();

  console.log(managerDepo.target) //0x944038aEEB5076e8D95604C11c6cCd7392F774E1

  const poolTx = await (await manager.createNewPool(
    erc20TokenDepo.target, // erc20TokenDepo.target, //"0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6"
    "",
    "PoolName"
  )).wait()

  const address = '0x' + poolTx.logs[0].topics[1].slice(-40);
  console.log(poolTx.hash, address) //0x3cfC27702B2D45c2ADec073325e8547536824970
  //***********************************************************************************************************************************************
  //Enter new position sequence

  const pool = await hre.ethers.getContractAt("PoolControl", address)
  const connectorAddr = await pool.localBridgedConnector()
  const amount = "200000000000000000"
  const relayFeePct = "100000000000000000"
  //Approve token spend by pool
  const asset = await pool.assetAddress()
  const erc20 = await hre.ethers.getContractAt("ERC20", asset)
  const appTx = await erc20.approve(address, amount)
  await erc20.transfer(connectorAddr, amount)
  // const depositCall = await pool.userDeposit(amount, "100000000000000000")
  const initCall = await pool.userDepositAndSetPosition(
    amount,
    relayFeePct,
    "0x944038aEEB5076e8D95604C11c6cCd7392F774E1",
    80001,
    "0x0000000000000000000000000000000000000000000000000000000000000000"
  )

  const eventLogs = (await initCall.wait()).logs


  //***********************************************************************************************************************************************
  //Simulate token mint for depositId 0x38999d5ed49f585c77bb6c3021b511ac9202913e1f278f2f67911a20a9a91860
  const depositId = eventLogs[0].args[0]
  const acrossSetAndDepositMessage = eventLogs[eventLogs.length - 1].args[0]
  console.log(acrossSetAndDepositMessage)

  const connector = await hre.ethers.getContractAt("BridgedConnector", connectorAddr)

  //BEGIN CONNECTOR DEPOSIT CONNECTION

  //Call handleAcrossMessage() with message data from the pool tx events

  const positionBalSend = await (await connector.handleAcrossMessage(
    asset,
    amount,
    true,
    "0x944038aEEB5076e8D95604C11c6cCd7392F774E1",
    acrossSetAndDepositMessage
  )).wait()

  const methodHash = positionBalSend.logs[positionBalSend.logs.length - 1].args[0]
  const payload = positionBalSend.logs[positionBalSend.logs.length - 1].args[1]


  // //END CONNECTOR DEPOSIT CONNECTION
  console.log(methodHash, payload)

  await pool.receiveHandler(methodHash, payload)
  let poolToken = await pool.poolToken()
  console.log("POOL TOKEN: ", poolToken)
  poolToken = await hre.ethers.getContractAt("PoolToken", poolToken)

  console.log(await poolToken.totalSupply())


  // //*********************************************************************** */
  // //**SIMULATED USER DEPO FOR MINTING CALCULATIONS */

  const amount2 = "200000000000000000"
  await erc20.approve(address, amount2)
  await erc20.transfer(connectorAddr, amount2)
  const depositCall = await pool.userDeposit(amount2, "100000000000000000")

  const eventLogs2 = (await depositCall.wait()).logs

  const depositId2 = eventLogs2[0].args[0]

  const acrossDepositMessage = eventLogs2[eventLogs2.length - 1].args[0]


  //BEGIN CONNECTOR DEPOSIT CONNECTION

  //Call handleAcrossMessage() with message data from the pool tx events

  const positionBalSend2 = await (await connector.handleAcrossMessage(
    asset,
    amount2,
    true,
    "0x944038aEEB5076e8D95604C11c6cCd7392F774E1",
    acrossDepositMessage
  )).wait()

  const methodHash2 = positionBalSend2.logs[positionBalSend2.logs.length - 1].args[0]
  const payload2 = positionBalSend2.logs[positionBalSend2.logs.length - 1].args[1]
  const tx = await (await pool.receiveHandler(methodHash2, payload2)).wait()

  // DUMMY USER DEPOSIT ********************************************************************************
  console.log("BEFORE: 2xxxx -", await poolToken.totalSupply(), await poolToken.balanceOf("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"))

  const amount3 = "200000000000000000"
  await erc20.approve(address, amount3)
  await erc20.transfer(connectorAddr, amount3)
  const depositCall3 = await pool.userDeposit(amount3, "100000000000000000")

  const eventLogs3 = (await depositCall3.wait()).logs

  const depositId3 = eventLogs3[0].args[0]

  const acrossDepositMessage3 = eventLogs3[eventLogs3.length - 1].args[0]


  //BEGIN CONNECTOR DEPOSIT CONNECTION

  //Call handleAcrossMessage() with message data from the pool tx events

  const positionBalSend3 = await (await connector.handleAcrossMessage(
    asset,
    amount3,
    true,
    "0x944038aEEB5076e8D95604C11c6cCd7392F774E1",
    acrossDepositMessage3
  )).wait()

  const methodHash3 = positionBalSend3.logs[positionBalSend3.logs.length - 1].args[0]
  const payload3 = positionBalSend3.logs[positionBalSend3.logs.length - 1].args[1]



  const amount4 = "200000000000000000"
  await erc20.approve(address, amount4)
  await erc20.transfer(connectorAddr, amount4)
  const depositCall4 = await pool.userDeposit(amount4, "100000000000000000")

  const eventLogs4 = (await depositCall4.wait()).logs


  const acrossDepositMessage4 = eventLogs4[eventLogs4.length - 1].args[0]


  //BEGIN CONNECTOR DEPOSIT CONNECTION

  //Call handleAcrossMessage() with message data from the pool tx events

  const positionBalSend4 = await (await connector.handleAcrossMessage(
    asset,
    amount4,
    true,
    "0x944038aEEB5076e8D95604C11c6cCd7392F774E1",
    acrossDepositMessage4
  )).wait()

  // await erc20.transfer(connectorAddr, amount3)


  // call the userWithdrawOrder(uint256 amount) on pool
  const withdrawAmount = "1700000000000000000"
  const withdrawTx = (await (await pool.userWithdrawOrder(withdrawAmount)).wait())


  //get the withdrawId

  const withdrawAcrossMessage = withdrawTx.logs[withdrawTx.logs.length - 1].args

  const connectorReceive = await (await connector.receiveHandler(withdrawAcrossMessage[0], withdrawAcrossMessage[1])).wait()

  const withdrawAcrossReceipt = await (await pool.handleAcrossMessage(
    asset,
    withdrawAmount,
    true,
    "0x944038aEEB5076e8D95604C11c6cCd7392F774E1",
    connectorReceive.logs[0].args[0]
  )).wait()

  // END USER WITHDRAW

  console.log('WITHDRAW NUMBERS: ', withdrawAcrossReceipt.logs)





  const tx3 = await (await pool.receiveHandler(methodHash3, payload3)).wait()
  console.log("AFTER: 25xxx - ", await poolToken.totalSupply(), await poolToken.balanceOf("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"))

  // ***************************************************************************************************


  // //END CONNECTOR DEPOSIT CONNECTION

  // BEGIN USER WITHDRAW


  console.log(await connector.readBalanceAtNonce(address, 0))
  console.log(await connector.readBalanceAtNonce(address, 1))
  console.log(await connector.readBalanceAtNonce(address, 2))
  console.log(await connector.readBalanceAtNonce(address, 3))
  console.log(await connector.readBalanceAtNonce(address, 4))
  console.log(await connector.readBalanceAtNonce(address, 5))

  console.log(await pool.poolNonce())




  // //Check user asset balance

  // // /Take this Message, create a dummy handleAcrossMessage for processing withdraw
  // const handleWithdraw = await (await pool.handleAcrossMessage(
  //   "0x944038aEEB5076e8D95604C11c6cCd7392F774E1",
  //   "200000000000000000",
  //   true,
  //   "0x944038aEEB5076e8D95604C11c6cCd7392F774E1",
  //   acrossMessage
  // )).wait()

  // console.log(handleWithdraw.logs[0].args)

  // // Check the total supply and user asset balance 
  // console.log(await poolToken.totalSupply())


}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
