import React, { useState, useEffect } from 'react';
import PurchaseObject from './PurchaseObject';
import { formatEther } from 'ethers';
import { makeStyles } from '@mui/styles';
import Deposit from './Deposit';
import Withdraw from './Withdraw';

interface InteractionProps {
    setErrorMessage: (message: string) => void;
}

const Interaction = ({ setErrorMessage }: InteractionProps) => {
    const classes = useStyles();

    const [interactionType, setInteractionType] = useState<'Deposit' | 'Withdraw'>('Deposit');

    const handleToggle = () => {
        // Handle switching between price history and purchase history views 
        const typeToChange = interactionType === 'Deposit' ? 'Withdraw' : 'Deposit';
        setInteractionType(typeToChange);
    }
    let render: React.JSX.Element | null = null;
    if (interactionType === 'Deposit') {
        render = <Deposit setErrorMessage={setErrorMessage} />
    } else if (interactionType === 'Withdraw') {
        render = <Withdraw setErrorMessage={setErrorMessage} />
    }
    return (
        <div className={classes.interaction}>
            <div className={classes.headerContainer}>
                <span className="sectionHeader">{interactionType} Interaction</span>
                <button className={classes.switchButton} onClick={handleToggle}>
                    {(interactionType === 'Deposit' ? 'Withdraw' : 'Deposit').toUpperCase()}
                </button>
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
    interaction: {
        width: "100%",
        padding: "0px 30px 0px 0px",
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

export default Interaction;