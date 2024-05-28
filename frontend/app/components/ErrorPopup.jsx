'use client';

import React, { useEffect, useState } from 'react';

const ErrorPopup = ({ errorMessage, clearErrorMessage }) => {
    if (!errorMessage) return null
    let txEle = null
    if (errorMessage.includes('TX: ')) {
        let x = errorMessage.split('TX: ')[1]
        txEle = <a href={"https://sepolia.arbiscan.io/tx/" + x} target="_blank"><span><u>{"View this Transaction on Arbiscan"}</u></span></a>
    }

    return (
        <div className="popup-container">
            <div className="popup">
                <div className="popup-title">Error</div>
                <div className="popup-message">{errorMessage.split('\n').map((x, idx) => {
                    if (x === '') {
                        return <br key={idx} />
                    }
                    if (x.includes('\b')) {
                        return <span key={idx} style={{ display: "block" }}><b>{x.split('\b').join('')}</b></span>
                    }
                    return <span key={idx} style={{ display: "block" }}>{x}</span>
                })}</div>
                <div style={{ display: "block", color: "red" }}>
                    {txEle}
                </div>
                <button onClick={() => clearErrorMessage()} className="popup-ok-button">OK</button>
            </div>
        </div>
    );
};

export default ErrorPopup;
