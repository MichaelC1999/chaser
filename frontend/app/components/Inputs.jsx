import { ethers } from 'ethers';
import React, { useEffect, useMemo, useState } from 'react';
import RegistryABI from '../ABI/RegistryABI.json'; // Adjust the path as needed
import Pools from './Pools.jsx';
import contractAddresses from '../JSON/contractAddresses.json'


// Inputs.js
function Inputs({ step, setStep, setErrorMessage }) {
  const [poolCount, setPoolCount] = useState(null);

  const windowOverride = useMemo(() => (
    typeof window !== 'undefined' ? window : null
  ), []);

  const provider = useMemo(() => (
    windowOverride ? new ethers.BrowserProvider(windowOverride.ethereum) : null
  ), [windowOverride]);

  const registry = useMemo(() => (
    provider ? new ethers.Contract(contractAddresses["base"].registryAddress || "0x0", RegistryABI, provider) : null
  ), [provider]);


  useEffect(() => {
    const fetchPoolCount = async () => {
      if (!registry) {
        return;
      }
      const count = await registry.poolCount();
      setPoolCount(count);
    };

    fetchPoolCount();
  }, []);


  let inputs = null;

  if (step === 0) {
    inputs = <Pools setErrorMessage={(x) => setErrorMessage(x)} />
  }
  return (
    <div className="component-container">
      {inputs}
    </div>
  );
}

export default Inputs;
