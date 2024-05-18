'use client'

import './globals.css'
import React, { useEffect, useState } from 'react';
import { ethers } from "ethers";

import { NetworkSwitcher } from "./components/NetworkSwitcher.jsx";
import ErrorPopup from './components/ErrorPopup.jsx';
import ConnectButton from './components/ConnectButton.jsx';
import Image from 'next/image';
import { usePathname, useRouter } from 'next/navigation';

const Layout = ({ children }) => {
  const router = useRouter()
  const path = usePathname()
  const windowOverride = typeof window !== 'undefined' ? window : null;
  const [connected, setConnected] = useState(null);
  const [errorMessage, setErrorMessage] = useState("");
  const [rootStyle, setRootStyle] = useState({
    background: "#1f2c33",
    backgroundColor: "#1f2c33",
    backgroundSize: "cover",
    backgroundRepeat: "no-repeat",
    backgroundPosition: "center center"
  })

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
      } else {
        setConnected(false)
      }

    });
    checkUnlock();
  }, [])

  const checkUnlock = async () => {
    const isUnlocked = await windowOverride?.ethereum?._metamask?.isUnlocked();
    setConnected(isUnlocked);
  }

  useEffect(() => {
    if (path.includes("pool/0x")) {
      setRootStyle({
        background: "#1f2c33",
        backgroundColor: "#1f2c33",
        backgroundSize: "cover",
        backgroundRepeat: "no-repeat",
        backgroundPosition: "center center"
      })
    } else {
      setRootStyle({
        background:
          "url('./../ChaserLogoTransparent.png') no-repeat right 0px bottom 0px / 25% 25%,linear-gradient(90deg, rgba(31, 44, 51, 1) 33%, rgba(55, 77, 89, 1) 93%)",
        backgroundSize: "auto",
        backgroundPosition: "bottom 130px right 0px"
      })
    }

  }, [path])


  return (
    <html lang="en">
      <body>
        <div className={"root"} style={rootStyle}>
          <NetworkSwitcher />
          <ErrorPopup errorMessage={errorMessage} clearErrorMessage={() => setErrorMessage("")} />
          <div className={"header"}>
            <div style={{ display: "flex" }}>
              <Image style={{ cursor: "pointer" }} onClick={() => router.push('/')} src={"/ChaserLogoNoText.png"} height={48} width={48} />
              <span style={{ fontSize: "42px", color: "white" }}><b>CHASER</b></span>
            </div>
            <div style={{ marginRight: "12px" }}>
              <ConnectButton connected={connected} setErrorMessage={(msg) => setErrorMessage(msg)} />

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
