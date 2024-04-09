'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';

const TxPopup = ({ popupData, clearPopupData }: any) => {
    const router = useRouter()

    return (
        <div className="popup-container">
            <div className="popup">
                <div className="popup-title" onClick={() => router.push("https://dashboard.tenderly.co/tx/base-sepolia/" + popupData?.hash)}>TX: {popupData?.hash}</div>
                <div className="popup-message" style={{ cursor: "pointer" }} onClick={() => router.push(popupData?.URI ?? "/")}>
                    {popupData?.message}
                </div>
                <button onClick={() => {
                    clearPopupData()
                    router.push(popupData?.URI ?? "/")
                }} className="popup-ok-button">OK</button>
            </div>
        </div>
    );
};

export default TxPopup;
