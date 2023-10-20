import { Box } from "@mui/material";
import React from "react";
import { formatDate, truncateDecimal } from "../utils";

interface PurchaseObjectProps {
    date: Date;
    amount: string;
    txHash: string;
}

const PurchaseObject = ({ date, amount, txHash }: PurchaseObjectProps) => {
    return (
        <Box
            width="100%"
            bgcolor="black"
            marginBottom={1}
            pt={1}
            pb={1}
            display="flex"
            justifyContent="center"
            alignItems="center"
            style={{ cursor: "pointer" }}
            borderRadius="4px"
            onClick={() => window.open("https://goerli.etherscan.io/tx/" + txHash, "_blank")}
        >
            <div style={{
                color: "white",
                textAlign: "justify",
                maxWidth: "450px",
                width: "100%",
                padding: "8px 12px",
                fontSize: "20px"
            }}>
                <span style={{ width: "100%", textAlign: "justify" }}>
                    {truncateDecimal(amount)} on {formatDate(date)}{"\u200B"}
                </span>
            </div>
        </Box>
    );
};

export default PurchaseObject;