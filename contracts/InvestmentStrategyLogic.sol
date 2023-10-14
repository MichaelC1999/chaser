// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {IStrategy} from "./interfaces/IStrategy.sol";

contract InvestmentStrategyLogic is IStrategy {
    // Initiate Strategy as lowVolHighYield
    // '	marketDailySnapshots(first: 30, orderBy: timestamp, orderDirection: desc, where: {market:"${curPoolId}"}) {'
    // '	marketDailySnapshots(first: 30, orderBy: timestamp, orderDirection: desc, where: {market_:{inputToken:"${marketTokenAddress}"}}) {'

    string public strategySourceCode =
        "const curPoolId = args[0];"
        "try {"
        "const marketTokenAddress = args[3];"
        "const base = `https://api.thegraph.com/subgraphs/name/messari/`;"
        "const curSubgraphURL = base + args[1];"
        "const desSubgraphURL = base + args[2];"
        ""
        "const curPositionData = await Functions.makeHttpRequest({"
        "url: curSubgraphURL,"
        'method: "POST",'
        "headers: {"
        '"Content-Type": "application/json",'
        "},"
        "data: {"
        "query: `{"
        "\x09\x6D\x61\x72\x6B\x65\x74\x44\x61\x69\x6C\x79\x53\x6E\x61\x70\x73\x68\x6F\x74\x73\x28\x66\x69\x72\x73\x74\x3A\x20\x33\x30\x2C\x20\x6F\x72\x64\x65\x72\x42\x79\x3A\x20\x74\x69\x6D\x65\x73\x74\x61\x6D\x70\x2C\x20\x6F\x72\x64\x65\x72\x44\x69\x72\x65\x63\x74\x69\x6F\x6E\x3A\x20\x64\x65\x73\x63\x2C\x20\x77\x68\x65\x72\x65\x3A\x20\x7B\x6D\x61\x72\x6B\x65\x74\x3A\x22\x24\x7B\x63\x75\x72\x50\x6F\x6F\x6C\x49\x64\x7D\x22\x7D\x29\x20\x7B\x0A"
        "totalDepositBalanceUSD"
        "dailySupplySideRevenueUSD"
        "}"
        "}`"
        "}"
        "});"
        ""
        "const positionDesData = await Functions.makeHttpRequest({"
        "url: desSubgraphURL,"
        'method: "POST",'
        "headers: {"
        '"Content-Type": "application/json",'
        "},"
        "data: {"
        "query: `{"
        'markets (where: {inputToken:"${marketTokenAddress}"}) {'
        "id"
        "} "
        "\x09\x6D\x61\x72\x6B\x65\x74\x44\x61\x69\x6C\x79\x53\x6E\x61\x70\x73\x68\x6F\x74\x73\x28\x66\x69\x72\x73\x74\x3A\x20\x33\x30\x2C\x20\x6F\x72\x64\x65\x72\x42\x79\x3A\x20\x74\x69\x6D\x65\x73\x74\x61\x6D\x70\x2C\x20\x6F\x72\x64\x65\x72\x44\x69\x72\x65\x63\x74\x69\x6F\x6E\x3A\x20\x64\x65\x73\x63\x2C\x20\x77\x68\x65\x72\x65\x3A\x20\x7B\x6D\x61\x72\x6B\x65\x74\x5F\x3A\x7B\x69\x6E\x70\x75\x74\x54\x6F\x6B\x65\x6E\x3A\x22\x24\x7B\x6D\x61\x72\x6B\x65\x74\x54\x6F\x6B\x65\x6E\x41\x64\x64\x72\x65\x73\x73\x7D\x22\x7D\x7D\x29\x20\x7B\x0A"
        "totalDepositBalanceUSD"
        "dailySupplySideRevenueUSD"
        "}"
        "}`"
        "}"
        "});"
        "let curROR = [];"
        "if (curPositionData?.data?.data) curROR = curPositionData.data.data.marketDailySnapshots.map(ins => (Number(ins.dailySupplySideRevenueUSD) * 365) / Number(ins.totalDepositBalanceUSD) || 0);"
        "const curMeanROR = curROR.reduce((acc, curr) => acc + curr, 0) / curROR.length;"
        ""
        "const curVariance = curROR.reduce((acc, curr) => acc + Math.pow(curr - curMeanROR, 2), 0) / curROR.length;"
        "const curStandardDeviation = Math.sqrt(curVariance);"
        ""
        "const curSharpeRatio = (curMeanROR / curStandardDeviation) || -1;"
        ""
        "const desPoolId = positionDesData?.data?.data?.markets?.[0]?.id;"
        "if (!desPoolId) return Functions.encodeString(curPoolId);"
        ""
        "let desROR = [];"
        "if (positionDesData?.data?.data) desROR = positionDesData.data.data.marketDailySnapshots.map(ins => (ins.dailySupplySideRevenueUSD * 365) / ins.totalDepositBalanceUSD);"
        "const desMeanROR = desROR.reduce((acc, curr) => acc + curr, 0) / desROR.length;"
        ""
        "const desVariance = desROR.reduce((acc, curr) => acc + Math.pow(curr - desMeanROR, 2), 0) / desROR.length;"
        "const desStandardDeviation = Math.sqrt(desVariance);"
        ""
        "const desSharpeRatio = desMeanROR / desStandardDeviation;"
        ""
        "if (desSharpeRatio > curSharpeRatio) return Functions.encodeString(desPoolId);"
        "} catch (err) {"
        'console.log("Error caught - ", err.message);'
        "}"
        ""
        "return Functions.encodeString(curPoolId);";

    string public strategyName = "lowVolHighYield";

    constructor() {}

    function updateStrategy(
        string memory sourceCode,
        string memory name
    ) public {
        strategySourceCode = sourceCode;
        name = strategyName;
    }
}
