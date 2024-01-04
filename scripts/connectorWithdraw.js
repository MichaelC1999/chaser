const hre = require("hardhat");
const ethers = require("ethers");

async function main() {
  let managerAddress = "";

  // Deploy testnet dummy asset
  const erc20TokenDepo1 = await hre.ethers.deployContract("TestWETHToken", [], {
    value: 0
  });
  const erc20Token1 = await erc20TokenDepo1.waitForDeployment();
  await erc20Token1.transfer("0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199", "100000000000000000000");
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
  const assetContract = await hre.ethers.getContractAt("ERC20", asset);
  await assetContract.approve(poolAddress, amount1);
  await assetContract.transfer(connectorAddr, amount1);
  const initializePool = await pool.userDepositAndSetPosition(
    amount1,
    relayFeePct,
    "0x944038aEEB5076e8D95604C11c6cCd7392F774E1",
    80001,
    "0x0000000000000000000000000000000000000000000000000000000000000000"
  );
  const eventLogs1 = (await initializePool.wait()).logs;

  // Simulate token mint for depositId
  const depositId1 = eventLogs1[0].args[0];
  const acrossSetAndDepositMessage1 = eventLogs1[eventLogs1.length - 1].args[0];

  const connector = await hre.ethers.getContractAt("BridgedConnector", connectorAddr);
  const positionBalSend1 = await (await connector.handleAcrossMessage(
    asset,
    amount1,
    true,
    "0x944038aEEB5076e8D95604C11c6cCd7392F774E1",
    acrossSetAndDepositMessage1
  )).wait();
  const methodHash1 = positionBalSend1.logs[positionBalSend1.logs.length - 1].args[0];
  const payload1 = positionBalSend1.logs[positionBalSend1.logs.length - 1].args[1];
  await pool.receiveHandler(methodHash1, payload1);
  let poolToken = await pool.poolToken();
  console.log("POOL TOKEN: ", poolToken);
  poolToken = await hre.ethers.getContractAt("PoolToken", poolToken);

  // Simulated second user deposit for minting calculations
  const amount2 = "200000000000000000";
  await assetContract.approve(poolAddress, amount2);
  await assetContract.transfer(connectorAddr, amount2);
  const depositCall2 = await pool.userDeposit(amount2, relayFeePct);
  const eventLogs2 = (await depositCall2.wait()).logs;
  const depositId2 = eventLogs2[0].args[0];
  const acrossDepositMessage2 = eventLogs2[eventLogs2.length - 1].args[0];
  const positionBalSend2 = await (await connector.handleAcrossMessage(
    asset,
    amount2,
    true,
    "0x944038aEEB5076e8D95604C11c6cCd7392F774E1",
    acrossDepositMessage2
  )).wait();
  const methodHash2 = positionBalSend2.logs[positionBalSend2.logs.length - 1].args[0];
  const payload2 = positionBalSend2.logs[positionBalSend2.logs.length - 1].args[1];
  const tx2 = await (await pool.receiveHandler(methodHash2, payload2)).wait();

  // Simulated third user deposit
  const amount3 = "200000000000000000";
  await assetContract.approve(poolAddress, amount3);
  await assetContract.transfer(connectorAddr, amount3);
  const depositCall3 = await pool.userDeposit(amount3, relayFeePct);
  const eventLogs3 = (await depositCall3.wait()).logs;
  const depositId3 = eventLogs3[0].args[0];
  const acrossDepositMessage3 = eventLogs3[eventLogs3.length - 1].args[0];
  const positionBalSend3 = await (await connector.handleAcrossMessage(
    asset,
    amount3,
    true,
    "0x944038aEEB5076e8D95604C11c6cCd7392F774E1",
    acrossDepositMessage3
  )).wait();
  const methodHash3 = positionBalSend3.logs[positionBalSend3.logs.length - 1].args[0];
  const payload3 = positionBalSend3.logs[positionBalSend3.logs.length - 1].args[1];
  const tx3 = await (await pool.receiveHandler(methodHash3, payload3)).wait();

  // Simulated fourth user deposit
  const amount4 = "200000000000000000";
  await assetContract.approve(poolAddress, amount4);
  await assetContract.transfer(connectorAddr, amount4);
  const depositCall4 = await pool.userDeposit(amount4, relayFeePct);
  const eventLogs4 = (await depositCall4.wait()).logs;
  const depositId4 = eventLogs4[0].args[0];
  const acrossDepositMessage4 = eventLogs4[eventLogs4.length - 1].args[0];
  const positionBalSend4 = await (await connector.handleAcrossMessage(
    asset,
    amount4,
    true,
    "0x944038aEEB5076e8D95604C11c6cCd7392F774E1",
    acrossDepositMessage4
  )).wait();

  // User withdraw process
  const withdrawAmount1 = "1700000000000000000";
  const withdrawTx1 = (await (await pool.userWithdrawOrder(withdrawAmount1)).wait());
  const withdrawAcrossMessage1 = withdrawTx1.logs[withdrawTx1.logs.length - 1].args;
  const connectorReceive1 = await (await connector.receiveHandler(withdrawAcrossMessage1[0], withdrawAcrossMessage1[1])).wait();
  const withdrawAcrossReceipt1 = await (await pool.handleAcrossMessage(
    asset,
    withdrawAmount1,
    true,
    "0x944038aEEB5076e8D95604C11c6cCd7392F774E1",
    connectorReceive1.logs[0].args[0]
  )).wait();

  console.log('Position value when calling initializePool: ', await connector.readBalanceAtNonce(poolAddress, 0))
  console.log('Position value when calling deposit2: ', await connector.readBalanceAtNonce(poolAddress, 1))
  console.log('Position value when calling deposit3: ', await connector.readBalanceAtNonce(poolAddress, 2))
  console.log('Position value when calling deposit4: ', await connector.readBalanceAtNonce(poolAddress, 3))
  console.log('Position value when calling withdraw1: ', await connector.readBalanceAtNonce(poolAddress, 4))
  console.log('Position value when calling next transaction: ', await connector.readBalanceAtNonce(poolAddress, 5))

  console.log(await pool.poolNonce())

}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
