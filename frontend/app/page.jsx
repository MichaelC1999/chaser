"use client"

import React, { useEffect, useState } from "react";
import { NetworkSwitcher } from "./components/NetworkSwitcher";
import { ethers } from "ethers";
import ConnectButton from "./components/ConnectButton";
import ErrorPopup from "./components/ErrorPopup.jsx";
import Inputs from "./components/Inputs.jsx";
import Image from "next/image";

const MainPage = () => {
  //This page is for handling pool selection/deployment
  const windowOverride = typeof window !== 'undefined' ? window : null;
  const [errorMessage, setErrorMessage] = useState("");


  return (<>
    <ErrorPopup errorMessage={errorMessage} clearErrorMessage={() => {
      setErrorMessage("")
    }} />
    <div className="MainPage">
      <div style={{ marginLeft: "64px", color: "white" }}>
        <span style={{ paddingTop: "220px", display: "block", fontSize: "138px" }}>Chaser Finance</span>
        <span style={{ paddingLeft: "16px", paddingTop: "2px", display: "block", fontSize: "32px" }}>Chase Better Yields, Unlock Data Based Investing for Your DAO</span>
        <div style={{ display: "flex", paddingLeft: "16px", paddingTop: "16px" }}>
          <button style={{ width: "225px", padding: "8px" }} className={'button'}>Earn Yield</button>
          <button style={{ marginLeft: "6px", width: "225px", padding: "8px" }} className={'button'}>Create A Strategy</button>
        </div>
      </div>
    </div>
  </>
  );
};


export default MainPage;
