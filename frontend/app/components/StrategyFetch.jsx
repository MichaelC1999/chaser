import React, { useState, useEffect } from 'react';
import { ethers } from 'ethers';
import InvestmentStrategyABI from '../ABI/InvestmentStrategyABI.json'; // Adjust the path as needed
import contractAddresses from '../JSON/contractAddresses.json'

const StrategyFetch = ({ stratNumber, setStrategyNames, provider }) => {

    useEffect(() => {
        const execution = async () => {
            try {
                const investmentStrategyContract = new ethers.Contract(contractAddresses.sepolia["investmentStrategy"], InvestmentStrategyABI, provider);
                const name = (await investmentStrategyContract.strategyName(stratNumber))
                setStrategyNames(prev => ({ ...prev, [stratNumber]: name }))
            } catch (err) {
                setErrorMessage('Error Loading Pool: ' + err.message)
            }
        }
        execution()
    }, []);

    return null;
};

export default StrategyFetch;
