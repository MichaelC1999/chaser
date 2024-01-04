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
    const registry1 = await hre.ethers.getContractAt("Registry", await manager1.registry());

    const connector1 = await registry1.chainIdToBridgedConnector(hre.network.config.chainId)



    const registry2 = await hre.ethers.deployContract("Registry", [80001, hre.network.config.chainId], {
        value: 0
    });

    const connector2 = await registry2.chainIdToBridgedConnector(80001)

    await registry1.addBridgedConnector(80001, connector2)


    await registry2.addBridgedConnector(hre.network.config.chainId, connector1)



    const poolTx1 = await (await manager1.createNewPool(
        erc20TokenDepo1.target,
        "",
        "PoolName"
    )).wait();
    const poolAddress = '0x' + poolTx1.logs[0].topics[1].slice(-40);
    console.log(poolTx1.hash, poolAddress);

    // Enter new position sequence
    const pool = await hre.ethers.getContractAt("PoolControl", poolAddress);
    const amount1 = "200000000000000000";
    const relayFeePct = "100000000000000000";
    const asset = await pool.asset();
    const assetContract = await hre.ethers.getContractAt("ERC20", asset);
    await assetContract.approve(poolAddress, amount1);
    await assetContract.transfer(connector1, amount1);
    const initializePool = await pool.userDepositAndSetPosition(
        amount1,
        relayFeePct,
        "0x944038aEEB5076e8D95604C11c6cCd7392F774E1",
        1337,
        "0x776566717765667771394c4c3a3032736b64646b6b646b646b646b646b646b70"
    );
    const eventLogs1 = (await initializePool.wait()).logs;

    // Simulate token mint for depositId
    const depositId1 = eventLogs1[0].args[0];
    const acrossSetAndDepositMessage1 = eventLogs1[eventLogs1.length - 1].args[0];

    const connectorCont1 = await hre.ethers.getContractAt("BridgedConnector", connector1);

    const positionBalSend1 = await (await connectorCont1.handleAcrossMessage(
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

    const pivotTx = (await (await pool.sendPositionChange("0x0000000000000000000000000000000000000000000000000000000000000000")).wait())
    console.log("A=>B lzSend data", pivotTx.logs[0].args)


    const bridgePositionTx = await (await connectorCont1.receiveHandler(pivotTx.logs[0].args[0], pivotTx.logs[0].args[1])).wait();

    // Get the log data from this tx

    console.log("handleAcrossMessage B=>A", bridgePositionTx.logs)

    // Call handleAcrossMessage from the second connector

    const connectorCont2 = await hre.ethers.getContractAt("BridgedConnector", connector2);


    const enterPositionTx = await (await connectorCont2.handleAcrossMessage(
        asset,
        amount1,
        true,
        "0x944038aEEB5076e8D95604C11c6cCd7392F774E1",
        bridgePositionTx.logs[0].args[0]
    )).wait()

    const pivotCallback = await (await pool.receiveHandler(enterPositionTx.logs[0].args[0], enterPositionTx.logs[0].args[1])).wait();


    // read from pool state about where the current position address/id/chain
    console.log("FIRST PIVOT POSITION STATUS: ", await pool.currentPositionAddress(), await pool.currentPositionChain(), await pool.currentPositionProtocolHash(), await pool.currentRecordPositionValue())


    // make a pivot back to the 'original' position



    const pivotTx2 = (await (await pool.sendPositionChange("0x776566717765667771394c4c3a3032736b64646b6b6472656b646b646b646b70")).wait())
    // console.log("A=>B lzSend data", pivotTx2.logs)


    const bridgePositionTx2 = await (await connectorCont2.receiveHandler(pivotTx2.logs[0].args[0], pivotTx2.logs[0].args[1])).wait();

    // Get the log data from this tx

    console.log("handleAcrossMessage B=>A", bridgePositionTx2.logs[0].args[0])

    // Call handleAcrossMessage from the second connector


    const enterPositionTx2 = await (await connectorCont1.handleAcrossMessage(
        asset,
        amount1,
        true,
        "0x944038aEEB5076e8D95604C11c6cCd7392F774E1",
        bridgePositionTx2.logs[0].args[0]
    )).wait()

    console.log(enterPositionTx2.logs[0].args)

    const pivotCallback2 = await (await pool.receiveHandler(enterPositionTx2.logs[0].args[0], enterPositionTx2.logs[0].args[1])).wait();

    console.log("SECOND PIVOT POSITION STATUS: ", await pool.currentPositionAddress(), await pool.currentPositionChain(), await pool.currentPositionProtocolHash(), await pool.currentRecordPositionValue())

}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});


