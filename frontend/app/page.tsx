"use client"

import React, { useEffect, useState } from "react";
import Mint from "./components/Deposit";
import { NetworkSwitcher } from "./components/NetworkSwitcher";
import { ethers } from "ethers";
import ConnectButton from "./components/ConnectButton";
import ErrorPopup from "./components/ErrorPopup";
import Instructions from "./components/Instructions";
import Inputs from "./components/Inputs";
import Image from "next/image";

const MainPage = () => {
  //This page is for handling pool selection/deployment
  const windowOverride: any = typeof window !== 'undefined' ? window : null;


  useEffect(() => {

  }, [])
  const poolSelectionHeader =
    "POOL SELECTION"

  const poolSelectContent =
    "To demo Chaser, you need to select a pool. You can either choose a pool from the list, or deploy a new pool."

  return (<>
    <div className="MainPage">
      <Instructions header={poolSelectionHeader} content={poolSelectContent} />
      <Inputs step={0} setStep={() => null} />

    </div>
  </>
  );
};


export default MainPage;
