"use client"

import React, { useEffect, useState } from "react";
import Mint from "./components/Deposit";
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
      <div className="component-container">
        <span style={{ fontSize: "32px" }}>POOL SELECTION</span>
        <span style={{ fontSize: "18px" }}>To demo Chaser, you need to select a pool. You can either choose a pool from the list, or deploy a new pool</span>
      </div>
      <Inputs step={0} setStep={() => null} setErrorMessage={(x) => setErrorMessage(x)} />
    </div>
  </>
  );
};


export default MainPage;
