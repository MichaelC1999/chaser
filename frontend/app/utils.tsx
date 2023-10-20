export function formatDate(date: Date) {

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

export function truncateDecimal(decimalString: string) {
    const str = decimalString.toString();
    const [wholePart, decimalPart] = str.split('.');

    if (decimalPart && decimalPart.length > 6) {
        return `${wholePart}.${decimalPart.slice(0, 3)}...${decimalPart.slice(-1)}`;
    }

    return str;
}