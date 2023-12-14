"use client"

import React, { useEffect, useMemo, useState } from "react";
import { Button, Container, Typography } from "@mui/material";
import { makeStyles } from "@mui/styles";
import Interaction from "./components/Interaction";
import { NetworkSwitcher } from "./components/NetworkSwitcher";
import { ethers } from "ethers";
import ConnectButton from "./components/ConnectButton";
import ErrorPopup from "./components/ErrorPopup";
import { Fade } from '@mui/material';
import abi from './BridgingConduitABI.json'
import FundsState from "./components/FundsState";
import QueryMove from "./components/QueryMove";
import History from "./components/History";


const HomePage = () => {
  const windowOverride: any = typeof window !== 'undefined' ? window : null;
  const bridgingConduitAddress: string = process.env.NEXT_PUBLIC_CONDUIT_ADDRESS || "";
  const [connected, setConnected] = useState<Boolean | null>(null);
  const [errorMessage, setErrorMessage] = useState<string>("");
  const [currentProtocolSlug, setCurrentProtocolSlug] = useState("");
  const [currentPoolId, setCurrentPoolId] = useState("");
  const [currentStrategy, setCurrentStrategy] = useState("");
  const [showMovePropose, setShowMovePropose] = useState(false);

  const classes = useStyles({ connected });


  return (
    <Fade in appear timeout={1500}>
      <div className={classes.root}>
        <History setErrorMessage={setErrorMessage} />
      </div>
    </Fade>
  );
};

const useStyles = makeStyles(theme => ({
  root: {
    width: "100%",
    height: "100vh",
    backgroundColor: "black",
    backgroundSize: "cover",
    backgroundRepeat: "no-repeat",
    backgroundPosition: "center center",
  },
  buttonDiv: {
    width: "100%",
    display: "flex",
    justifyContent: "flex-end",
    marginBottom: "16px"
  },
  toggleButton: {
    border: '#FF69B4 2px solid',
    padding: "4px 20px",
    fontSize: "16px",
    borderRadius: '4px',
    backgroundColor: '#FFC1CC',
    color: 'black',
    marginBottom: '16px',
    alignSelf: 'stretch',
    "&:disabled": {
      cursor: "none"
    },
    "&:hover": {
      color: '#FF69B4'
    }
  },
  contentContainer: {
    marginLeft: "84px",
    width: "100%",
    marginTop: "32px"
  },
  header: {
    fontFamily: '"Roboto", "Helvetica", "Arial", sans-serif',
    fontSize: "68px",
    marginBottom: "136px"
  },
  childContainer: {
    display: "flex",
    width: "100%",
    marginTop: "120px",
    justifyContent: "space-between",
    alignItems: "flex-start",
  },
}));

export default HomePage;
