import React, { useState, useEffect } from 'react';
import PurchaseObject from './PurchaseObject';
import { formatEther } from 'ethers';
import { makeStyles } from '@mui/styles';
import { CircularProgress } from '@mui/material';
import { Interface } from 'ethers';
import BigNumber from 'bignumber.js';
import FlipMove from 'react-flip-move';

interface HistoryProps {
    setErrorMessage: (message: string) => void;
}

const History = ({ setErrorMessage }: HistoryProps) => {
    const bridgingConduitAddress: string = process.env.NEXT_PUBLIC_CONDUIT_ADDRESS || "";
    const etherscanURI = "https://api-goerli.etherscan.io/api?module=account&action=txlist&address=" + bridgingConduitAddress + "&startblock=0&endblock=99999999&page=1&offset=100&sort=desc&apikey=" + process.env.NEXT_PUBLIC_ETHERSCAN_API;

    const [historyObjects, setHistoryObjects] = useState<{ [x: string]: any }[]>([]);
    const [loadContent, setLoadContent] = useState<Boolean>(false);
    const [showCount, setShowCount] = useState<number>(5);

    const classes = useStyles();


    useEffect(() => {
        // Rather than calling getTxHistory() upon mount, set the loadContent state to true to display certain components while waiting for response from etherscan
        setLoadContent(true);
    }, [])

    useEffect(() => {
        getTxHistory();
    }, [loadContent])


    const getTxHistory = async () => {
        try {
            const res = await fetch(etherscanURI);
            const resultTransactions = (await res.json()).result;
            const transactions = resultTransactions.filter((x: any) => x.functionName.includes('buy(') && x.isError === "0");
            const transactionsToRender = transactions.map((x: any) => {
                const contractInterface = new Interface(abi);
                const decoded = contractInterface.decodeFunctionData('buy', x.input);
                const price: BigNumber = new BigNumber(x.value).dividedBy(new BigNumber(decoded.toString()));
                const date: Date = new Date(parseInt(x.timeStamp) * 1000);
                const amount: string = formatEther(decoded.toString());
                // Construct the object that will be set in state
                return { block: x.blockNumber, txHash: x.hash, priceInEth: price.toString(), amount, date };
            })
            setHistoryObjects(transactionsToRender);
        } catch (err: any) {
            // setErrorMessage("Error Fetching Transaction History: " + err?.info?.error?.message ?? err?.message);
        }
        setLoadContent(false);
    }

    const handleLoadMorePurchases = () => {
        setShowCount(prevCount => prevCount + 5);
    }

    let render: React.JSX.Element | null = null;
    if (loadContent) {
        // If the etherscan request is still loading, display a loading spinner
        render = (
            <div className={classes.centeredContainer}>
                <CircularProgress className={classes.spinner} />
            </div>
        );
    } else {
        // Display a list of buy transaction history on the contract 
        const purchaseObjects: React.JSX.Element[] = historyObjects.slice(0, showCount).map((obj: any) => (
            <div key={obj.txHash}>
                <PurchaseObject date={obj.date} amount={obj.amount} txHash={obj.txHash} />
            </div>
        ));

        render = (
            <div className="fullWidth">
                <FlipMove
                    typeName={null}
                    enterAnimation="fade"
                    leaveAnimation="fade"
                    duration={500}
                >
                    {purchaseObjects}
                </FlipMove>
                <button className={classes.loadMoreButton} onClick={handleLoadMorePurchases}>
                    Load More
                </button>
            </div>
        );
    }

    return (
        <div className={classes.history}>
            <div className={classes.headerContainer}>
                <span className="sectionHeader">Deposit History</span>
            </div>
            {render}
        </div>
    );
};

const useStyles = makeStyles(theme => ({
    centeredContainer: {
        width: '100%',
        display: 'flex',
        justifyContent: 'center',
        alignItems: 'center',
        height: '100px' // This ensures vertical centering by occupying the full viewport height.
    },
    spinner: {
        color: 'black',
    },
    history: {
        width: "100%",
        padding: "0px 30px",
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'flex-start',
    },
    loadMoreButton: {
        width: '100%',
        textAlign: 'right',
        background: 'white',
        color: 'blue',
        border: 'none',
        cursor: 'pointer',
        marginBottom: "50px"
    },
    headerContainer: {
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        width: '100%'
    },
    switchButton: {
        padding: "8px 20px",
        fontSize: "16px",
        marginBottom: "10px",
        borderRadius: "4px",
        color: 'black',
        background: '#FFC1CC',
        border: '#FF69B4 solid 2px',
        cursor: 'pointer',
        '&:hover': {
            background: 'white'
        }
    },
}))

export default History;