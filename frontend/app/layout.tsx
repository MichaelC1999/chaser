'use client'

import './globals.css'
import React, { useEffect, useState } from 'react';
import { ethers } from "ethers";

import { NetworkSwitcher } from "./components/NetworkSwitcher";
import ErrorPopup from './components/ErrorPopup';
import ConnectButton from './components/ConnectButton';
import Image from 'next/image';
import { useRouter } from 'next/navigation';

const Layout = ({ children }: {
  children: React.ReactNode
}) => {
  const router = useRouter()
  const windowOverride: any = typeof window !== 'undefined' ? window : null;
  const [connected, setConnected] = useState<Boolean | null>(null);
  const [errorMessage, setErrorMessage] = useState<string>("");

  useEffect(() => {
    // Initialize the injected provider event listeners to execute behaviors if account/chain/unlock changes in Metamask 
    windowOverride?.ethereum?.on("chainChanged", () => {
      if (typeof window !== 'undefined') {
        return window.location.reload();
      }
    });
    windowOverride?.ethereum?.on("accountsChanged", () => {

      if (ethers.isAddress(windowOverride?.ethereum?.selectedAddress)) {
        setConnected(true);
      }
      if (typeof window !== 'undefined') {
        return window.location.reload();
      }
    });
    checkUnlock();
  }, [])

  const checkUnlock = async () => {
    const isUnlocked = await windowOverride?.ethereum?._metamask?.isUnlocked();
    setConnected(isUnlocked);
  }

  return (
    <html lang="en">
      <body>
        <div className={"root"}>
          <NetworkSwitcher />
          <ErrorPopup errorMessage={errorMessage} errorMessageCallback={() => setErrorMessage("")} />
          <div className={"header"}>
            <Image style={{ cursor: "pointer" }} onClick={() => router.push('/')} src={"/ChaserLogoNoText.png"} height={48} width={48} />
            <div style={{ marginRight: "12px" }}>
              <ConnectButton connected={connected} setErrorMessage={(msg: string) => setErrorMessage(msg)} />

            </div>
          </div>
          <div className={"contentContainer"}>
            <div className={"childContainer"}>
              {children}
            </div>
          </div>
        </div>
      </body>
    </html>
  );
};


export default Layout;
