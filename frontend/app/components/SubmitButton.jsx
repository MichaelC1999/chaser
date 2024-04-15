import React, { useMemo } from 'react';

const SubmitButton = ({ submitMethod }) => {
    return (
        <button style={{ width: "100%" }} className={'button'} onClick={submitMethod}>
            Submit
        </button>
    );
};


export default SubmitButton;
