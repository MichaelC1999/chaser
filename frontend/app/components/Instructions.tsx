import React, { useEffect, useState } from 'react';


function Instructions({ header, content }: any) {


  return (
    <div className="component-container">
      <span style={{ fontSize: "32px" }}>{header}</span>
      <span style={{ fontSize: "18px" }}>{content}</span>
    </div>
  );
}

export default Instructions;