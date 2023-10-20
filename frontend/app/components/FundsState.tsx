"use client"

import React, { useEffect, useMemo, useState } from "react";
import { Container, Typography } from "@mui/material";
import { makeStyles } from "@mui/styles";

const FundsState = ({ currentProtocolSlug, currentPoolId, currentStrategy }: any) => {
    const classes = useStyles();

    return (

        <div className="currentStateSection">
            <Typography className={classes.currentStateSubHeader}>
                Chaser Deposits are located in {currentProtocolSlug ? (
                    <a
                        href={`https://api.thegraph.com/subgraphs/name/messari/${currentProtocolSlug}`}
                        target="_blank"
                        style={{ color: "#FF69B4", fontWeight: "bolder", textDecoration: "none" }}
                    >
                        {currentProtocolSlug}
                    </a>
                ) : (
                    <span>...</span>
                )}
            </Typography>
            <Typography className={classes.currentStateSubHeader}>
                Deposited into market {currentPoolId ? (
                    <a
                        href={`https://api.thegraph.com/subgraphs/name/messari/${currentProtocolSlug}/graphql?query=query+MyQuery+%7B%0A++market%28id%3A+"${currentPoolId}%22%29+%7B%0A++++name%0A++++id%0A++++isActive%0A++++inputTokenPriceUSD%0A++++inputTokenBalance%0A++++outputTokenSupply%0A++++outputTokenPriceUSD%0A++++openPositionCount%0A++++totalBorrowBalanceUSD%0A++++totalDepositBalanceUSD%0A++++stakedOutputTokenAmount%0A++++stableBorrowedTokenBalance%0A++++cumulativeBorrowUSD%0A++++cumulativeDepositUSD%0A++++cumulativeFlashloanUSD%0A++++cumulativeLiquidateUSD%0A++++cumulativeProtocolSideRevenueUSD%0A++++cumulativeSupplySideRevenueUSD%0A++++cumulativeTotalRevenueUSD%0A++++cumulativeTransferUSD%0A++++cumulativeUniqueUsers%0A++++totalValueLockedUSD%0A++++transactionCount%0A++++transferCount%0A++++withdrawCount%0A++%7D%0A%7D`}
                        target="_blank"
                        style={{ color: "#FF69B4", fontWeight: "bolder", textDecoration: "none" }}
                    >
                        {currentPoolId}
                    </a>
                ) : (
                    <span>...</span>
                )}
            </Typography>
            <Typography className={classes.currentStateSubHeader}>
                Using Strategy {currentStrategy ? (
                    <span style={{ color: "#FF69B4", fontWeight: "bolder", textDecoration: "none" }}>{currentStrategy}</span>
                ) : (
                    <span>...</span>
                )}
            </Typography>
        </div>

    );
};

const useStyles = makeStyles(theme => ({
    currentStateSection: {
        marginTop: "140px"
    },
    currentStateSubHeader: {
        fontSize: "30px"
    }
}));

export default FundsState;
