const hre = require("hardhat");
const ethers = require("ethers");

const goerliFirstDeployments = async () => {

    const [deployer] = await hre.ethers.getSigners();

    // Fetch the current gas price
    const gasPrice = await deployer.provider.getFeeData();


    console.log(gasPrice)


    // Deploy manager to user level chain, deploy the test pool
    // const managerDepo1 = await hre.ethers.deployContract("ChaserManager", [5], {
    //     gasLimit: 7500000,
    //     value: 0
    // });
    // const manager1 = await managerDepo1.waitForDeployment();
    // console.log("MANAGER: ", managerDepo1.target); // 0x441baB02f35e0317e09FD7Bc97B97a8825a895F3
    const managerAddr = "0x9d0aED1f105876620d4d1ae4235E613059274428"
    const manager1 = await hre.ethers.getContractAt("ChaserManager", managerAddr);
    const registryContract = await (await hre.ethers.deployContract("Registry", [5, 5, managerAddr], {
        gasLimit: 2000000,
        value: 0
    })).waitForDeployment();


    await (await manager1.addRegistry(registryContract.target)).wait()

    // console.log("Registry: ", registryContract.target)




    const registryAddress = await manager1.registry();
    console.log("REGISTRY: ", registryAddress)


    // const registryContract = await hre.ethers.getContractAt("Registry", registryAddress);

    // const calcContract = await (await hre.ethers.deployContract("PoolCalculations", [], {
    //     gasLimit: 7000000,
    //     value: 0
    // })).waitForDeployment();

    // console.log("POOL CALCULATIONS: ", calcContract.target)

    // await manager1.addPoolCalculationsAddress(calcContract.target)

    // console.log('ADDED')

    const bridgeLogicContract = await (await hre.ethers.deployContract("BridgeLogic", [5, registryAddress], {
        gasLimit: 7000000,
        value: 0
    })).waitForDeployment();

    const bridgeLogicAddress = bridgeLogicContract.target
    console.log("BRIDGE LOGIC", bridgeLogicAddress)

    // const bridgeLogicAddress = "0xFe03e24821E478A7194110Bb797b275a14490cd1"
    // const bridgeLogicContract = await hre.ethers.getContractAt("BridgeLogic", bridgeLogicAddress);

    await (await registryContract.addBridgeLogic(bridgeLogicAddress)).wait()

    console.log("CCIP:", await registryContract.localCcipConfigs())



    console.log('MESSENGER: ', await bridgeLogicContract.messenger(), await registryContract.chainIdToMessageReceiver(5))

    console.log('RECEIVER: ', await bridgeLogicContract.bridgeReceiverAddress(), await registryContract.receiverAddress())


    const poolTx = await (await manager1.createNewPool(
        "0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa",
        "",
        "PoolName",
        {
            gasLimit: 7000000
        }
    )).wait();
    const poolAddress = '0x' + poolTx.logs[0].topics[1].slice(-40);

    // // // const poolAddress = "0x9bba47ec903a97cc7639265d26b774443653e2a2";

    console.log("Pool Address: ", poolAddress);
    // const pool = await hre.ethers.getContractAt("PoolControl", poolAddress);

    // await (await pool.externalSetup({
    //     gasLimit: 7000000
    // })).wait()

    // console.log("Success")

    // const rec = await registryContract.chainIdToBridgeReceiver(5)
    // const mes = await registryContract.chainIdToMessageReceiver(5)

    // console.log("Receiver: ", rec)

    // console.log("Messenger: ", mes)

}

const mumbaiFirstDeployments = async (goerliReceiver, goerliMessenger) => {
    // const registryAddress = "0x3dADf0363D63f5289Cb1B57316660372874b3c04"
    // const registryContract = await hre.ethers.getContractAt("Registry", registryAddress);
    const registryContract = await (await hre.ethers.deployContract("Registry", [80001, 5, "0x0000000000000000000000000000000000000000"], {
        gasLimit: 2000000,
        value: 0
    })).waitForDeployment();
    const registryAddress = registryContract.target
    console.log("Mumbai Registry: ", registryContract.target)

    const bridgeLogicContract = await (await hre.ethers.deployContract("BridgeLogic", [5, registryAddress], {
        gasLimit: 7000000,
        value: 0
    })).waitForDeployment();

    const bridgeLogicAddress = bridgeLogicContract.target
    console.log("BRIDGE LOGIC", bridgeLogicAddress)

    // const bridgeLogicContract = await hre.ethers.getContractAt("BridgeLogic", "0x4468987D27c8aeFa9D815340409309aC2528b728");
    await (await registryContract.addBridgeLogic(bridgeLogicAddress)).wait()

    console.log("CCIP:", await registryContract.localCcipConfigs())


    console.log('MESSENGER: ', await bridgeLogicContract.messenger(), 'RECEIVER: ', await bridgeLogicContract.bridgeReceiverAddress())
    const messengerContract = await hre.ethers.getContractAt("ChaserMessenger", await bridgeLogicContract.messenger())

    // await messengerContract.allowlistedSenders("0x7e7C8D21dEEa277d118461Ae3dc40e88808ECF3D")
    await (await registryContract.addBridgeReceiver(5, goerliReceiver)).wait()
    await (await registryContract.addMessageReceiver(5, goerliMessenger)).wait()
    // await (await registryContract.deployBridgedReceiver({ gasLimit: 5000000 })).wait()
    console.log(await messengerContract.allowlistedSourceChains("16015286601757825753"), await messengerContract.allowlistedDestinationChains("12532609583862916517"), await messengerContract.allowlistedSenders(goerliMessenger), await registryContract.chainIdToMessageReceiver(5), await registryContract.chainIdToMessageReceiver(80001))


    // console.log(await (await connectorContract.setPeer(5, goerliRouter)).wait())


    // console.log("Mumbai Router: ", await connectorContract.chaserRouter())


}

const goerliSecondConfig = async (poolAddress, mumbaiReceiver, mumbaiMessenger) => {

    const registryContract = await hre.ethers.getContractAt("Registry", "0x79bbFcee1F2c62dEcF95C6712650C6813DC2EB8B");
    // console.log('HERE?')




    // const registryContract = await (await hre.ethers.deployContract("Registry", [5, 5], {
    //     gasLimit: 5000000,
    //     value: 0
    // })).waitForDeployment();

    // console.log("Registry: ", registryContract.target)
    // await (await registryContract.deployBridgedReceiver({ gasLimit: 5000000 })).wait()



    await (await registryContract.addBridgeReceiver(80001, mumbaiReceiver)).wait()
    await (await registryContract.addMessageReceiver(80001, mumbaiMessenger)).wait()

    const sel2 = (await registryContract.chainIdToMessageReceiver(5))
    const messengerContract = await hre.ethers.getContractAt("ChaserMessenger", sel2)
    const sel3 = (await registryContract.chainIdToMessageReceiver(80001))
    const sel7 = await messengerContract.allowlistedSenders(mumbaiMessenger)
    const sel8 = await messengerContract.allowlistedSenders(sel3)

    const pool = await hre.ethers.getContractAt("PoolControl", poolAddress);


    console.log('HERE', sel2, sel3, sel7, sel8)

    const tx = await (await pool.getPositionData()).wait()

    console.log(tx)





    // console.log(await messengerContract._buildCCIPMessage("0x61DB30790588c6623d4fD6d70c424eCf37D1F421", "0x40c41741", "0x1be5ff66f92b7d2c23689eece9b589d0df6b06c3", "0x61DB30790588c6623d4fD6d70c424eCf37D1F421000000000000000000000000", "0x779877A7B0D9E8603169DdbD7836e478b4624789"))
    // console.log("CONNECTOR:", connectorContract.target)
    // const routerAddr = await connectorContract.chaserRouter()
    // const router = await hre.ethers.getContractAt("ChaserRouter", routerAddr);

    // await (await connectorContract.setPeer(80001, mumbaiMessenger)).wait()
    // console.log(await router.peers(40109), await router.owner(), await router.endpoint())
    // console.log("OPS: ", await router.getOptions())
    // console.log("Number 1: ", await router.quote(40109, "test", "0x00030100110100000000000000000000000000030d40", false))
    // // Call userDepositAndSetPosition to initialize on mumbai

    // const options = "0x00030100110100000000000000000000000000030d40"

    // console.log('NUMBER 2: ', await (await pool.getPositionData({ value: "10000000000000000", gasLimit: 10000000 })).wait())

}

const mumbaiTesting = async (mumbaiMessenger) => {
    const registryAddress = "0x4EA981f72B547f98F2e5D732e7eFAEef31791E4E"
    const registryContract = await hre.ethers.getContractAt("Registry", registryAddress);

    // await (await registryContract.addMessageReceiver(5, "0x7e7C8D21dEEa277d118461Ae3dc40e88808ECF3D")).wait()

    const messengerContract = await hre.ethers.getContractAt("ChaserMessenger", mumbaiMessenger)
    console.log(await messengerContract.testFlag())
    // await (await messengerContract.allowlistSender("0x7e7C8D21dEEa277d118461Ae3dc40e88808ECF3D", true)).wait()

    console.log(await messengerContract.allowlistedSenders("0x73710d04dd9D96Ed15596fa2d199E90D66Af8e58"), await registryContract.chainIdToMessageReceiver(5), await registryContract.chainIdToMessageReceiver(80001))

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
//     console.error(error);
//     console.log(error.logs)
//     process.exitCode = 1;
// });

// mumbaiFirstDeployments("0x42a7450e8e55D04b27a0930e819BfE5843577188", "0x941ade328B53323Ee470A27DfA1c102670793A83").catch((error) => {
//     console.error(error);
//     console.log(error.logs)
//     process.exitCode = 1;
// });

goerliSecondConfig("0x79e63e943f5baca1971ba468565bc33007e46a48", "0x3a8882b80cA1498370709203DaF0CcAf79B071f3", "0xcb6E45211E54DC1a8DC5E606C43d85368023F226").catch((error) => {
    console.error(error);
    console.log(error.logs)
    process.exitCode = 1;
});


// mumbaiTesting("0x8c8ad32a0cfd5fb1b895bb790d1a8d2b599c69e7").catch((error) => {
//     console.error(error);
//     console.log(error.logs)
//     process.exitCode = 1;
// });


