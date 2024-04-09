import { ethers } from 'ethers';
import React, { useEffect, useMemo, useState } from 'react';
import RegistryABI from '../ABI/RegistryABI.json'; // Adjust the path as needed
import Loader from './Loader';
import EnabledPools from './EnabledPools';
import Pools from './Pools';

// Inputs.js
function Inputs({ step, setStep }: any) {
  const [poolCount, setPoolCount] = useState(null);
  const [txPopupData, setTxPopupData] = useState({})


  const windowOverride: any = useMemo(() => (
    typeof window !== 'undefined' ? window : null
  ), []);

  const provider = useMemo(() => (
    windowOverride ? new ethers.BrowserProvider(windowOverride.ethereum) : null
  ), [windowOverride]);

  const registry: any = useMemo(() => (
    provider ? new ethers.Contract(process.env.NEXT_PUBLIC_REGISTRY_ADDRESS || "0x0", RegistryABI, provider) : null
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
    inputs = <Pools />
  }
  return (
    <div className="component-container">
      {inputs}
    </div>
  );
}

export default Inputs;
