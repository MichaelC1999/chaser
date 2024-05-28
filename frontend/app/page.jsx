"use client"

import React, { useEffect, useState } from "react";
import ErrorPopup from "./components/ErrorPopup.jsx";
import { usePathname, useRouter } from 'next/navigation';

const MainPage = () => {
  //This page is for handling pool selection/deployment
  const windowOverride = typeof window !== 'undefined' ? window : null;
  const [errorMessage, setErrorMessage] = useState("");

  const router = useRouter()


  return (<>
    <ErrorPopup errorMessage={errorMessage} clearErrorMessage={() => {
      setErrorMessage("")
    }} />
    <div className="MainPage">
      <div style={{ marginLeft: "64px", color: "white" }}>
        <h1 id="LandingPageTitle" style={{ fontWeight: "lighter", paddingTop: "220px", display: "block", fontSize: "138px" }}>Chaser Finance</h1>
        <span id="LandingPageDesc" style={{ paddingLeft: "16px", paddingTop: "2px", display: "block", fontSize: "32px" }}>Chase Better Yields, Unlock Data Based Investing for Your DAO</span>
        <div id="LandingPageButtons" style={{ display: "flex", paddingLeft: "16px", paddingTop: "16px" }}>
          <button style={{ width: "225px", padding: "8px" }} onClick={() => router.push('/pool')} className={'button'}>Earn Yield</button>
          <button style={{ marginLeft: "6px", width: "225px", padding: "8px" }} onClick={() => router.push("https://github.com/MichaelC1999/chaser#chaser")} className={'button'}>Read The Docs</button>
        </div>
      </div>
    </div>
  </>
  );
};


export default MainPage;
