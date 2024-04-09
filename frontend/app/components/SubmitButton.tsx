import React, { useMemo } from 'react';
import { ethers } from 'ethers';


const SubmitButton = ({ submitMethod }: any) => {
    const windowOverride: any = typeof window !== 'undefined' ? window : null;

    // Instantiate the provider, if the window object remains the same no need to recalculate
    const provider = useMemo(() => {
        return new ethers.BrowserProvider(windowOverride?.ethereum);
    }, [windowOverride]);

    return (
        <button className={'button'} onClick={submitMethod}>
            Submit
        </button>
    );
};


export default SubmitButton;
