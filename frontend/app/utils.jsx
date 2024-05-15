import { decodeEventLog, hexToNumber } from "viem";
import MessengerABI from './ABI/MessengerABI.json'; // Adjust the path as needed
import PoolABI from './ABI/PoolABI.json'; // Adjust the path as needed
import ISpokePoolABI from './ABI/ISpokePoolABI.json'; // Adjust the path as needed
import contractAddresses from './JSON/contractAddresses.json'
import networks from './JSON/networks.json'

export function formatDate(date) {

    const day = date.getDate();
    let daySuffix = "th";
    if (day === 1 || day % 10 === 1 && day !== 11) {
        daySuffix = "st";
    } else if (day === 2 || day % 10 === 2 && day !== 12) {
        daySuffix = "nd";
    } else if (day === 3 || day % 10 === 3 && day !== 13) {
        daySuffix = "rd";
    }

    const monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ];

    const month = monthNames[date.getMonth()];

    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');

    return `${day}${daySuffix} ${month} ${hours}:${minutes}`;
}

export function truncateDecimal(decimalString) {
    const str = decimalString.toString();
    const [wholePart, decimalPart] = str.split('.');

    if (decimalPart && decimalPart.length > 6) {
        return `${wholePart}.${decimalPart.slice(0, 3)}...${decimalPart.slice(-1)}`;
    }

    return str;
}

export const decodeAcrossDepositEvent = async (logs) => {
    console.log('LOGS', logs)
    const event = logs?.find(x => x?.topics[0] === "0xa123dc29aebf7d0c3322c8eeb5b999e859f39937950ed31056532713d0de396f");
    if (!event) return null
    const args = decodeEventLog({
        abi: ISpokePoolABI,
        data: event.data,
        topics: event.topics
    }).args
    console.log('TOPICS: ', args)
    return { depositId: args.depositId, spokePool: contractAddresses[networks[args.destinationChainId.toString()]].spokePool }
}

export const decodeCCIPSendMessageEvent = async (logs) => {
    const event = logs?.find(x => x?.topics[0] === "0x3d8a9f055772202d2c3c1fddbad930d3dbe588d8692b75b84cee071946282911");
    if (!event) return null
    const args = decodeEventLog({
        abi: MessengerABI,
        data: event.data,
        topics: event.topics
    }).args
    console.log('TOPICS: ', args)
    return { message: args.data, messageId: args.messageId }
}

export const userLastDeposit = async (poolAddress, userAddress) => {
    const URI = "https://api-sepolia.etherscan.io/api?apikey=" + process.env.NEXT_PUBLIC_ETHERSCAN_API + "&module=logs&action=getLogs&fromBlock=1092029&toBlock=latest&address=" + poolAddress + "&topic0=0xee99ac53f13979350092f60117dc361d473aca8ed92f200a947fefcba78d1221"

    const event = await fetch(URI, {
        method: "get",
        headers: {
            "Content-Type": "application/json",
        }
    })

    const depositEvents = await event.json()
    console.log('results: ', URI, depositEvents.result)
    const log = sortDesc(depositEvents?.result)

    console.log(log)
    const userDeposit = log?.find(x => x.data.includes(userAddress?.slice(26))) || null
    if (!userDeposit) return { depositId: null, success: false, txHash: "" }

    return await findAcrossDepositFromTxHash(userDeposit.transactionHash, process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID)
}

export const userLastWithdraw = async (poolAddress, userAddress) => {
    const URI = "https://api-sepolia.etherscan.io/api?apikey=" + process.env.NEXT_PUBLIC_ETHERSCAN_API + "&module=logs&action=getLogs&fromBlock=1092029&toBlock=latest&address=" + poolAddress + "&topic0=0x4311354ef29bfb2e8c894c9ef5b35830f819dc8371cae086be213257904d3f36"

    const event = await fetch(URI, {
        method: "get",
        headers: {
            "Content-Type": "application/json",
        }
    })

    const withdrawEvents = await event.json()
    console.log('results: ', URI, withdrawEvents.result)
    const log = sortDesc(withdrawEvents?.result)

    const userWithdraw = log?.find(x => x.data.includes(userAddress?.slice(26))) || null
    if (!userWithdraw) return { messageId: null, success: false, txHash: "" }
    return await findCcipMessageFromTxHash(userWithdraw.transactionHash, process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID)
}

export const decodePoolPivot = async (poolAddress) => {
    const URI = "https://api-sepolia.etherscan.io/api?apikey=" + process.env.NEXT_PUBLIC_ETHERSCAN_API + "&module=logs&action=getLogs&fromBlock=1092029&toBlock=latest&address=" + poolAddress + "&topic0=0xad71167b35ad58b7606cb5f5fda8b03a5799113db8f0a73939d152ac29d023a0"

    const event = await fetch(URI, {
        method: "get",
        headers: {
            "Content-Type": "application/json",
        }
    })

    const pivotEvent = await event.json()
    console.log(pivotEvent.result)
    let log = sortDesc(pivotEvent.result)[0]
    const hash = log.transactionHash
    const args = decodeEventLog({
        abi: PoolABI,
        data: log.data,
        topics: log.topics
    }).args

    console.log(args, log)

    let medium = ""
    if (args[0].toString() === process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID) {
        medium = "across"
        const depo = await findAcrossDepositFromTxHash(hash, process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID)
        return { id: depo.depositId, medium, txHash: depo.txHash }

    } else {
        medium = "ccip1"
        const msg = await findCcipMessageFromTxHash(hash, process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID)
        return { id: msg.messageId, medium }
    }
}

export const fetchAcrossRelayFillTx = async (destinationChain, depositId) => {
    try {
        if (!destinationChain) return { success: false, messageId: null }
        let topic = "0x571749edf1d5c9599318cdbc4e28a6475d65e87fd3b2ddbe1e9a8d5e7a0f0ff7"
        let contractAddr = contractAddresses[networks[destinationChain]]["spokePool"]
        let path = "https://api-sepolia.basescan.org/"
        if (destinationChain === process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID) {
            path = "https://api-sepolia.etherscan.io/"
        }
        let logUri = path + "api?apikey=" + process.env.NEXT_PUBLIC_ETHERSCAN_API + "&module=logs&action=getLogs&fromBlock=1092029&toBlock=latest&address=" + contractAddr + "&topic0=" + topic
        const messageEvent = await fetch(logUri, {
            method: "get",
            headers: {
                "Content-Type": "application/json",
            }
        })

        const messageLogEvents = await messageEvent.json()

        const check = messageLogEvents.result.find(x => x.topics[2] === depositId)

        if (!check) return { success: false, messageId: null }


        //ccip
        topic = "0x3d8a9f055772202d2c3c1fddbad930d3dbe588d8692b75b84cee071946282911"
        contractAddr = contractAddresses[networks[destinationChain]]["messengerAddress"]

        logUri = path + "api?apikey=" + process.env.NEXT_PUBLIC_ETHERSCAN_API + "&module=logs&action=getLogs&fromBlock=1092029&toBlock=latest&address=" + contractAddr + "&topic0=" + topic

        const logEvent = await fetch(logUri, {
            method: "get",
            headers: {
                "Content-Type": "application/json",
            }
        })

        const logEvents = await logEvent.json()


        const log = (logEvents?.result?.find(x => x.transactionHash === check.transactionHash)) || null

        if (!log) {
            return { success: true, messageId: null }
        }

        return { messageId: log.topics[1], success: true }
    } catch (err) {
        return { messageId: null, success: false }
    }
}

export const findCcipMessageFromTxHash = async (txHash, chainId) => {
    //ccip
    const topic = "0x3d8a9f055772202d2c3c1fddbad930d3dbe588d8692b75b84cee071946282911"
    let contractAddr = contractAddresses[networks[chainId]]["messengerAddress"]
    let path = "https://api-sepolia.basescan.org/"
    if (chainId === process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID) {
        path = "https://api-sepolia.etherscan.io/"
    }
    let logUri = path + "api?apikey=" + process.env.NEXT_PUBLIC_ETHERSCAN_API + "&module=logs&action=getLogs&fromBlock=1092029&toBlock=latest&address=" + contractAddr + "&topic0=" + topic

    const messageEvent = await fetch(logUri, {
        method: "get",
        headers: {
            "Content-Type": "application/json",
        }
    })

    const messageLogEvents = await messageEvent.json()
    console.log(messageLogEvents)
    if (!messageLogEvents) return { messageId: null, success: false }
    const log = (messageLogEvents?.result?.find(x => x.transactionHash === txHash)) || null
    console.log('fleeg', log, txHash)
    if (!log) return { messageId: null, success: false }


    const decoded = decodeEventLog({
        abi: MessengerABI,
        data: log.data,
        topics: log.topics
    }).args

    return { messageId: decoded.messageId, success: true }
}

export const findAcrossDepositFromTxHash = async (txHash, chainId) => {
    const topic = "0xa123dc29aebf7d0c3322c8eeb5b999e859f39937950ed31056532713d0de396f"
    let contractAddr = contractAddresses[networks[chainId]]["spokePool"]
    let path = "https://api-sepolia.basescan.org/"
    if (chainId === process.env.NEXT_PUBLIC_LOCAL_CHAIN_ID) {
        path = "https://api-sepolia.etherscan.io/"
    }
    let logUri = path + "api?apikey=" + process.env.NEXT_PUBLIC_ETHERSCAN_API + "&module=logs&action=getLogs&fromBlock=1092029&toBlock=latest&address=" + contractAddr + "&topic0=" + topic

    const messageEvent = await fetch(logUri, {
        method: "get",
        headers: {
            "Content-Type": "application/json",
        }
    })

    const messageLogEvents = await messageEvent.json()
    console.log(messageLogEvents)
    if (!messageLogEvents) return { depositId: null, success: false }
    const log = (messageLogEvents?.result?.find(x => x.transactionHash === txHash)) || null
    if (!log) return { depositId: null, success: false }



    const decoded = decodeEventLog({
        abi: ISpokePoolABI,
        data: log.data,
        topics: log.topics
    }).args

    return { depositId: decoded.depositId, success: true, txHash }
}


const sortDesc = (eventsArray) => {
    return eventsArray.map(x => {
        return { ...x, timeStamp: hexToNumber(x.timeStamp) }
    })?.sort((a, b) => b.timeStamp - a.timeStamp)
}
