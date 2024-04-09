import React from 'react';
import PoolRow from './PoolRow'; // Import PoolRow component

const EnabledPools = ({ poolCount, provider, registry }: any) => {
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
                    {Array.from({ length: poolCount }, (_, index) => (
                        <PoolRow key={index} poolNumber={index} provider={provider} registry={registry} />
                    ))}
                </tbody>
            </table>
        </div>
    );
};

export default EnabledPools;