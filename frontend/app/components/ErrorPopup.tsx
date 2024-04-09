'use client';

import React, { useEffect, useState } from 'react';

const ErrorPopup = ({ errorMessage, errorMessageCallback }: any) => {
    if (errorMessage === '') return null;
    const [shouldRender, setShouldRender] = useState(false);
    const windowOverride: any = typeof window !== 'undefined' ? window : null;

    useEffect(() => {
        const networkVersion = windowOverride.ethereum?.networkVersion;
        if (networkVersion === "11155111") {
            setShouldRender(true);
        }
    }, []);

    if (!shouldRender) {
        return null;
    }
    return (
        <div className="popup-container">
            <div className="popup">
                <div className="popup-title">Error</div>
                <div className="popup-message">{errorMessage}</div>
                <button onClick={errorMessageCallback} className="popup-ok-button">OK</button>
            </div>
        </div>
    );
};

export default ErrorPopup;
