import React, { useState, useEffect } from 'react';
import PurchaseObject from './PurchaseObject';
import { formatEther } from 'ethers';
import { makeStyles } from '@mui/styles';
import { createGrpcTransport } from "@connectrpc/connect-node";
import {
    createAuthInterceptor,
    createRegistry,
    createRequest,
    fetchSubstream,
    isEmptyMessage,
    streamBlocks,
    unpackMapOutput,
} from "@substreams/core";

interface HistoryProps {
    setErrorMessage: (message: string) => void;
}

const History = ({ setErrorMessage }: HistoryProps) => {
    const [outputArray, setOutputArray] = useState([]);
    const [contracts, setContracts] = useState({});

    const SUBSTREAM = "https://spkg.io/streamingfast/erc20-balance-changes-v0.0.5.spkg";
    const MODULE = "map_valid_balance_changes";

    const createChannels = async () => {
        const substream = await fetchSubstream(SUBSTREAM);
        const registry = createRegistry(substream);
        const transport = createGrpcTransport({
            baseUrl: "https://mainnet.eth.streamingfast.io",
            httpVersion: "2",
            interceptors: [createAuthInterceptor("eyJhbGciOiJLTVNFUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjIwMTUzNTE0OTMsImp0aSI6IjQxMDlkMjE0LWMyYTYtNGNmNi05YWYzLTNlYWNlMTFkZmI2YyIsImlhdCI6MTY5OTk5MTQ5MywiaXNzIjoiZGZ1c2UuaW8iLCJzdWIiOiIwY3lraTNlNGNlYWU2N2MzMDI3YjQiLCJ2IjoxLCJha2kiOiI1MGQyYjhhMTQxNmExMDhjMmM4NmVhZmZiZDU5OGE4NWI2YWI1MjE4NWFlYWY3MTY3MjNlM2UwMDMyYmUwYWVkIiwidWlkIjoiMGN5a2kzZTRjZWFlNjdjMzAyN2I0In0.sgJPeVaKWJxiXrObA67dC7X9u-G0Uy0xqegKjbTLWEhkAGBc-yh2jHf6Ic-S10vxqdQT_BMmpdFMvohviyjRyA")],
            jsonOptions: {
                typeRegistry: registry,
            },
        });

        const request = createRequest({
            substreamPackage: substream,
            outputModule: MODULE,
            productionMode: true,
            startBlockNum: 18584817,
            stopBlockNum: "+1000",
        });
        for await (const response of streamBlocks(transport, request)) {

            console.log(response?.message?.value);
        }
    }

    const classes = useStyles();


    useEffect(() => {
        // Rather than calling getTxHistory() upon mount, set the loadContent state to true to display certain components while waiting for response from etherscan
        createChannels()
    }, [])

    useEffect(() => {
        getTxHistory();
    }, [])


    const getTxHistory = async () => {
        try {

        } catch (err: any) {
        }
    }

    return (
        <div className={classes.history}>
            <div className={classes.headerContainer}>
            </div>
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