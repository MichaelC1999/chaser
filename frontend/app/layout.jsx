'use client'

import './globals.css'
import React, { useEffect, useState } from 'react';
import { ethers } from "ethers";
import { NetworkSwitcher } from "./components/NetworkSwitcher.jsx";
import ErrorPopup from './components/ErrorPopup.jsx';
import ConnectButton from './components/ConnectButton.jsx';
import Image from 'next/image';
import { usePathname, useRouter } from 'next/navigation';
import { Web3Modal } from '../context/web3modal'
import { useWeb3ModalAccount, useWeb3ModalEvents } from '@web3modal/ethers/react';


const Layout = ({ children }) => {
  const router = useRouter()
  const path = usePathname()
  const windowOverride = typeof window !== 'undefined' ? window : null;
  const [connected, setConnected] = useState(null);
  const [connectedAdddress, setConnectedAddress] = useState("")
  const [errorMessage, setErrorMessage] = useState("");
  const [rootStyle, setRootStyle] = useState({
    background: "#1f2c33",
    backgroundColor: "#1f2c33",
    backgroundSize: "cover",
    backgroundRepeat: "no-repeat",
    backgroundPosition: "center center"
  })

  const { address, chainId, isConnected } = useWeb3ModalAccount()

  useEffect(() => {

    if (ethers.isAddress(address)) {
      setConnectedAddress(address)
      setConnected(true);
    } else {
      setConnected(false)
    }

  }, [address, chainId, isConnected])

  useEffect(() => {
    // Initialize the injected provider event listeners to execute behaviors if account/chain/unlock changes in Metamask 
    windowOverride?.ethereum?.on("chainChanged", () => {
      if (typeof window !== 'undefined') {
        return window.location.reload();
      }
    });
  }, [])


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
      <head>
        <title>Chaser Finance</title>
        <meta name='description' content='Chaser Finance is a DeFi platform for metric based investing strategies' />
        <meta
          name="keywords"
          content="defi aave compound ethereum arbitrum finance bridge across"
        />

      </head>
      <body>
        <Web3Modal>
          <div className={"root"} style={rootStyle}>
            <NetworkSwitcher />
            <ErrorPopup errorMessage={errorMessage} clearErrorMessage={() => setErrorMessage("")} />
            <div className={"header"}>
              <div style={{ display: "flex", cursor: "pointer" }} onClick={() => router.push('/')}>
                <Image src={"/ChaserLogoNoText.png"} alt="ChaserFinance" height={48} width={48} />
                <span style={{ fontSize: "42px", color: "white", fontFamily: "Arquette" }}>chaser</span>
              </div>
              <div style={{ display: "flex", justifyContent: "space-between" }}>
                <div style={{ marginRight: "40px", display: "flex", fontFamily: "Aquette" }}>
                  <a href="/pool"><span style={{ fontFamily: "Arquette", display: "inline-block", lineHeight: "36px", color: "white", margin: "10px" }} >POOLS</span></a>
                  <a target="_blank" href="https://github.com/MichaelC1999/chaser#chaser"><span style={{ fontFamily: "Arquette", display: "inline-block", lineHeight: "36px", color: "white", margin: "10px" }} >DOCUMENTATION</span></a>
                  <a target="_blank" href="https://github.com/MichaelC1999/chaser"><span style={{ fontFamily: "Arquette", display: "inline-block", lineHeight: "36px", color: "white", margin: "10px" }} >GITHUB</span></a>
                  <a target="_blank" href="https://github.com/MichaelC1999/chaser/tree/master/contracts"><span style={{ fontFamily: "Arquette", display: "inline-block", lineHeight: "36px", color: "white", margin: "10px" }} >CONTRACTS</span></a>

                </div>
                <div style={{ margin: "10px 14px 16px 0", padding: "2px 5px", borderRadius: "5px", backgroundColor: "white", display: "flex" }}>
                  <Image style={{ backgroundColor: "white", padding: "1px", borderRadius: "10px" }} src={"/arbitrum-logo.svg"} height={28} width={28} />
                  <span style={{ fontFamily: "Arquette", display: "inline-block", margin: "4px", color: "black" }} >SEPOLIA</span>
                </div>
                <div style={{ marginRight: "14px" }}>
                  <ConnectButton connected={connected} address={connectedAdddress} setErrorMessage={(msg) => setErrorMessage(msg)} />
                </div>
              </div>
            </div>
            <div className={"contentContainer"}>
              <div className={"childContainer"}>
                {children}
              </div>
            </div>
          </div>
        </Web3Modal>
      </body>
    </html>
  );
};


export default Layout;
