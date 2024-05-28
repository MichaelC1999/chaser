import React from 'react';
import PoolRow from './PoolRow.jsx'; // Import PoolRow component

const EnabledPools = ({ poolCount, provider, registry, setErrorMessage }) => {
    return (
        <div className="enabled-pools">
            <table>
                <thead>
                    <tr>
                        <th>Pool</th>
                        <th>TVL (ETH)</th>
                        <th>Current Investment</th>
                    </tr>
                </thead>
                <tbody>
                    {
                        !poolCount ? (<tr>
                            <th>
                                No Chaser Pools Are Available!
                            </th>
                        </tr>) : null
                    }
                    {Array.from({ length: poolCount }, (_, index) => {
                        if (index <= 1) return null
                        return <PoolRow key={index} poolNumber={index} provider={provider} registry={registry} setErrorMessage={(x) => setErrorMessage(x)} />
                    })}
                </tbody>
            </table>
        </div>
    );
};

export default EnabledPools;