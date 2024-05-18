'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';

const TxPopup = ({ popupData, clearPopupData }) => {
    const router = useRouter()

    return (
        <div className="popup-container">
            <div className="popup">
                <div className="popup-title" style={{ fontSize: "21px" }} onClick={() => router.push("https://sepolia.etherscan.io/tx/" + popupData?.hash)}>TX: {popupData?.hash}</div>
                <div className="popup-message" style={{ cursor: "pointer" }} onClick={() => router.push(popupData?.URI?.[0] ?? "/")}>
                    {popupData?.message}
                </div>
                <div style={{ display: "block", color: "red", textAlign: "center" }}>
                    {popupData?.URI.map((x, idx) => {
                        let text = x
                        if (x.includes('basescan') && x.includes('tx/')) {
                            text = "View this Transaction on Etherscan"
                        }
                        return <><a key={idx} href={x} target="_blank"><span><u>{text}</u></span></a><br /><br /></>
                    })}
                </div>
                <button onClick={() => {
                    clearPopupData()
                }} className="popup-ok-button">OK</button>
            </div>
        </div>
    );
};

export default TxPopup;
