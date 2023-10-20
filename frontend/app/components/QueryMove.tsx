import React, { useEffect, useMemo, useState } from 'react';
import { Button, CircularProgress, IconButton, InputLabel, MenuItem, Select, TextField, Tooltip, Typography } from '@mui/material';
import { makeStyles } from '@mui/styles';
import InfoIcon from '@mui/icons-material/Info';

import { ethers } from 'ethers';
import BridgingConduitABI from '../BridgingConduitABI.json'

interface QueryMoveProps {
    setErrorMessage: (message: string) => void;
}

const QueryMove = ({ setErrorMessage }: QueryMoveProps) => {
    const windowOverride: any = typeof window !== 'undefined' ? window : null;
    const bridgingConduitAddress: string = process.env.NEXT_PUBLIC_CONDUIT_ADDRESS || "";
    const wethAddress: string = "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6"

    const [proposeInputError, setProposeInputError] = useState<Boolean>(false);
    const [proposeInitialized, setProposeInitialized] = useState<Boolean>(false);
    const [proposedProtocolSlug, setProposedProtocolSlug] = useState<string>('');
    const [proposedPoolId, setProposedPoolId] = useState<string>('');
    const [txReceipt, setTxReceipt] = useState<string>('');
    const [assertionId, setAssertionId] = useState<string>('');

    // isEthereumAvailable helps prevent 'window' object errors while browser loads injected provider 
    const [isEthereumAvailable, setIsEthereumAvailable] = useState(false);
    const classes = useStyles();

    useEffect(() => {
        if (typeof window !== 'undefined' && 'ethereum' in window) {
            setIsEthereumAvailable(true);
        }
    }, [])

    useEffect(() => {
        // Propose flow starts with clearing input errors detected on last propose attempt
        if (proposeInitialized) {
            setProposeInputError(false);
            handlePropose();
        }
    }, [proposeInitialized])

    const provider: ethers.BrowserProvider = useMemo(() => {
        return new ethers.BrowserProvider(windowOverride?.ethereum);
    }, [windowOverride]);

    const handlePropose = async () => {
        // The main Propose logic. Prepare the data to be passed in the propose() method and execute the call.

        try {

            await provider.send("eth_requestAccounts", []);
            const signer = await provider.getSigner();

            const writeBridgingConduitContract = new ethers.Contract(bridgingConduitAddress, BridgingConduitABI, signer);
            if (!writeBridgingConduitContract) {
                throw new Error("Could not Instantiate Contract at address " + bridgingConduitAddress);
            }

            const tx = await writeBridgingConduitContract.queryMovePosition(proposedProtocolSlug, proposedPoolId);
            const txReceipt = await tx.wait();
            console.log(txReceipt, writeBridgingConduitContract.interface, txReceipt.logs[4].topics[1])
            setTxReceipt(txReceipt.hash)
            setAssertionId(txReceipt.logs[4].topics[1])
            // Clear the amount state
        } catch (err: any) {
            setErrorMessage("Transaction Error: " + err?.info?.error?.message ?? err?.message);
        }
        setProposeInitialized(false);
    };


    let button: React.JSX.Element = <Button className={classes.proposeButton} onClick={() => setProposeInitialized(true)}>Propose</Button>;
    if (proposeInitialized) {
        button = (
            <Button className={classes.loadingButton} disabled>
                <CircularProgress size={24} className={classes.spinner} />
            </Button>
        );
    }

    if (!isEthereumAvailable) {
        return <></>;
    }

    const protocolOptions = ['aave-v3-ethereum', 'aave-v3-arbitrum', 'aave-v3-polygon', 'aave-v3-optimism', 'compound-v3-ethereum', 'compound-v3-polygon', 'compound-v3-arbitrum'];

    return (
        <div className={classes.depo}>
            <div className={classes.costSpan}>
                <span className="sectionHeader">Propose New Investment To Chase</span>
                <Tooltip classes={{ tooltip: classes.customTooltip }} title="Protocol slug is the end route on a Messari standardized subgraph URI (ie. 'aave-v3-ethereum'). Pool Id is the 'id' property of the pool/market entity on the subgraph that the investment should be deposited to." arrow>
                    <IconButton size="small" className={classes.infoIcon}>
                        <InfoIcon />
                    </IconButton>
                </Tooltip>
            </div>

            <InputLabel id="protocol-label" className={classes.labelStyle}>Protocol Slug</InputLabel>
            <Select
                labelId="protocol-label"
                label="Protocol Slug"
                variant="outlined"
                color='secondary'
                placeholder='Select Deployment'
                className={classes.input}
                value={proposedProtocolSlug}
                onChange={(e) => setProposedProtocolSlug(e.target.value as string)}
                inputProps={{
                    classes: { input: classes.inputText }
                }}
            >
                {protocolOptions.map((option) => (
                    <MenuItem key={option} value={option}>
                        {option}
                    </MenuItem>
                ))}
            </Select>
            <InputLabel id="pool-label" className={classes.labelStyle}>Pool ID</InputLabel>
            <TextField
                variant="outlined"
                type="text"
                color='secondary'
                // placeholder="Pool ID"
                className={classes.input}
                value={proposedPoolId}
                onChange={(e) => setProposedPoolId(e.target.value)}
                InputProps={{
                    classes: { input: classes.inputText }
                }}
            />
            {button}
            {assertionId ? <Typography>UMA Assertion: {assertionId}</Typography> : null}
            {txReceipt ? <Typography>TX: {txReceipt}</Typography> : null}
        </div>
    );
};

const useStyles = makeStyles(() => ({
    depo: {
        width: "100%",
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'flex-start',
    },
    input: {
        borderRadius: '4px',
        border: 'white 1px solid',
        marginBottom: '16px',
        color: "white",
        width: '100%',
        '& .MuiOutlinedInput-adornment': {
            position: 'absolute',
            right: '0',
        },
    },
    inputText: {
        color: 'white',
    },
    proposeButton: {
        border: '#FF69B4 2px solid',
        padding: "4px 20px",
        fontSize: "16px",
        borderRadius: '4px',
        backgroundColor: '#FFC1CC',
        color: 'black',
        marginBottom: '16px',
        alignSelf: 'stretch',
        "&:disabled": {
            cursor: "none"
        },
        "&:hover": {
            color: '#FF69B4'
        }
    },
    costSpan: {
        display: 'flex',
        alignItems: 'center',
        width: '100%',
    },
    infoIcon: {
        marginLeft: "8px",
        color: 'white',
    },
    customTooltip: {
        fontSize: "1.2rem",
        backgroundColor: "black",
        padding: "10px 15px",
    },
    loadingButton: {
        padding: "8px 20px",
        fontSize: "16px",
        borderRadius: '4px',
        backgroundColor: 'black',
        color: 'white',
        marginBottom: '16px',
        alignSelf: 'stretch',
        "&:disabled": {
            cursor: "not-allowed",
        },
        display: 'flex',
        justifyContent: 'center',
        alignItems: 'center',
    },
    spinner: {
        color: '#fff',
    },
    labelStyle: {
        color: 'white',
        '&.Mui-focused': {
            color: 'white',
        }
    },
}));

export default QueryMove;