import React, { useEffect, useMemo, useState } from 'react';
import { Button, CircularProgress, IconButton, InputAdornment, TextField, Tooltip } from '@mui/material';
import { makeStyles } from '@mui/styles';
import { ethers } from 'ethers';
import abi from '../BridgingConduitABI.json'

interface WithdrawProps {
    setErrorMessage: (message: string) => void;
}

const Withdraw = ({ setErrorMessage }: WithdrawProps) => {
    const windowOverride: any = typeof window !== 'undefined' ? window : null;
    const bridgingConduitAddress: string = process.env.NEXT_PUBLIC_CONDUIT_ADDRESS || "";

    const [tokenAmount, setTokenAmount] = useState<string>('');
    const [withdrawInputError, setWithdrawInputError] = useState<Boolean>(false);
    const [withdrawInitialized, setWithdrawInitialized] = useState<Boolean>(false);
    // isEthereumAvailable helps prevent 'window' object errors while browser loads injected provider 
    const [isEthereumAvailable, setIsEthereumAvailable] = useState(false);
    const classes = useStyles();

    useEffect(() => {
        if (typeof window !== 'undefined' && 'ethereum' in window) {
            setIsEthereumAvailable(true);
        }
    }, [])

    useEffect(() => {
        // Withdraw flow starts with clearing input errors detected on last withdraw attempt
        if (withdrawInitialized) {
            setWithdrawInputError(false);
            handleWithdraw();
        }
    }, [withdrawInitialized])

    const provider: ethers.BrowserProvider = useMemo(() => {
        return new ethers.BrowserProvider(windowOverride?.ethereum);
    }, [windowOverride]);


    const readBridgingConduitContract: ethers.Contract = new ethers.Contract(bridgingConduitAddress, abi, provider);

    const handleWithdraw = async () => {

    };

    let tokenInput: React.JSX.Element = (
        <TextField
            variant="outlined"
            type="number"
            color='secondary'
            placeholder="0.0"
            className={classes.input}
            value={tokenAmount}
            onChange={(e) => {
                setWithdrawInputError(false)
                setTokenAmount(e.target.value)
            }}
            InputProps={{
                classes: { input: classes.inputText }
            }}
        />);

    if ((!tokenAmount || tokenAmount === "0") && withdrawInputError === true) {
        // Add the 'Invalid' tooltip message when user attempts an invalid amount to purchase 
        tokenInput = (
            <Tooltip
                title="Invalid Amount!"
                open={true}
                classes={{ tooltip: classes.customTooltip }}
                placement="top-end"
            >
                {tokenInput}
            </Tooltip>
        );
    }

    let button: React.JSX.Element = <Button className={classes.withdrawButton} onClick={() => setWithdrawInitialized(true)}>Withdraw</Button>;
    if (withdrawInitialized) {
        button = (
            <Button className={classes.loadingButton} disabled>
                <CircularProgress size={24} className={classes.spinner} />
            </Button>
        );
    }

    if (!isEthereumAvailable) {
        return <></>;
    }

    return (
        <div className={classes.withdraw}>
            <span className="sectionHeader">Amount of WETH to Withdraw</span>
            {tokenInput}
            {button}
        </div>
    );
};

const useStyles = makeStyles(() => ({
    withdraw: {
        width: "100%",
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'flex-start',
    },
    input: {
        borderRadius: '4px',
        border: 'white 1px solid',
        marginBottom: '16px',
        width: '100%',
        '& .MuiOutlinedInput-adornment': {
            position: 'absolute',
            right: '0',
        },
    },
    inputText: {
        color: 'white',
    },
    withdrawButton: {
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
        "&:hover": {
            color: '#FF69B4'
        },
        display: 'flex',
        justifyContent: 'center',
        alignItems: 'center',
    },
    spinner: {
        color: '#fff',
    },
}));

export default Withdraw;