'use client';

import React from 'react';
import Loader from './Loader.jsx';

const LoadingPopup = ({ loadingMessage }) => {
    return (
        <div className="popup-container">
            <div className="popup">
                <Loader />
                <div className="popup-message">{loadingMessage}</div>

            </div>
        </div>
    );
};

export default LoadingPopup;
