import { decodeEventLog } from "viem";
import MessengerABI from './ABI/MessengerABI.json'; // Adjust the path as needed
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