import React, { useEffect, useMemo, useState } from 'react';
import { Button, CircularProgress, IconButton, InputAdornment, TextField, Tooltip } from '@mui/material';
import { makeStyles } from '@mui/styles';
import { ethers, parseEther } from 'ethers';
import BridgingConduitABI from '../BridgingConduitABI.json'
import IERC20ABI from '../IERC20ABI.json'
import BigNumber from 'bignumber.js';

interface DepositProps {
    setErrorMessage: (message: string) => void;
}

const Deposit = ({ setErrorMessage }: DepositProps) => {
    const windowOverride: any = typeof window !== 'undefined' ? window : null;
    const bridgingConduitAddress: string = process.env.NEXT_PUBLIC_CONDUIT_ADDRESS || "";
    const wethAddress: string = "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6"

    const [tokenAmount, setTokenAmount] = useState<string>('');
    const [depoInputError, setDepoInputError] = useState<Boolean>(false);
    const [depoInitialized, setDepoInitialized] = useState<Boolean>(false);
    // isEthereumAvailable helps prevent 'window' object errors while browser loads injected provider 
    const [isEthereumAvailable, setIsEthereumAvailable] = useState(false);
    const classes = useStyles();

    useEffect(() => {
        if (typeof window !== 'undefined' && 'ethereum' in window) {
            setIsEthereumAvailable(true);
        }
    }, [])

    useEffect(() => {
        // Depo flow starts with clearing input errors detected on last depo attempt
        if (depoInitialized) {
            setDepoInputError(false);
            handleDepo();
        }
    }, [depoInitialized])

    const provider: ethers.BrowserProvider = useMemo(() => {
        return new ethers.BrowserProvider(windowOverride?.ethereum);
    }, [windowOverride]);

    const handleDepo = async () => {
        // The main Depo logic. Prepare the data to be passed in the depo() method and execute the call.
        if (tokenAmount === "0" || !tokenAmount) {
            setDepoInputError(true);
            setDepoInitialized(false);
            return;
        }
        try {

            await provider.send("eth_requestAccounts", []);
            const signer = await provider.getSigner();
            const wethContract = new ethers.Contract(wethAddress, IERC20ABI, signer);
            if (!wethContract) {
                throw new Error("Could not Instantiate Contract at address " + wethAddress);
            }
            const writeBridgingConduitContract = new ethers.Contract(bridgingConduitAddress, BridgingConduitABI, signer);
            if (!writeBridgingConduitContract) {
                throw new Error("Could not Instantiate Contract at address " + bridgingConduitAddress);
            }

            console.log(signer, window, parseEther(tokenAmount))
            const approvetx = await wethContract.approve(bridgingConduitAddress, parseEther(tokenAmount));
            const approvetxReceipt = await approvetx.wait();

            const tx = await writeBridgingConduitContract.userDeposit(wethAddress, parseEther(tokenAmount));
            const txReceipt = await tx.wait();
            // Clear the amount state
            setTokenAmount('');
        } catch (err: any) {
            setErrorMessage("Transaction Error: " + err?.info?.error?.message ?? err?.message);
        }
        setDepoInitialized(false);
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
                setDepoInputError(false)
                setTokenAmount(e.target.value)
            }}
            InputProps={{
                classes: { input: classes.inputText }
            }}
        />);

    if ((!tokenAmount || tokenAmount === "0") && depoInputError === true) {
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

    let button: React.JSX.Element = <Button className={classes.depoButton} onClick={() => setDepoInitialized(true)}>Deposit</Button>;
    if (depoInitialized) {
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
        <div className={classes.depo}>
            <span className="sectionHeader">Amount of WETH to Deposit</span>
            {tokenInput}
            {button}
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
        width: '100%',
        '& .MuiOutlinedInput-adornment': {
            position: 'absolute',
            right: '0',
        },
    },
    inputText: {
        color: 'white',
    },
    depoButton: {
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

export default Deposit;