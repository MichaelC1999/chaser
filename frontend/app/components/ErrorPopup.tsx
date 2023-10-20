import { Box, Button, Dialog, DialogContent, DialogTitle, Typography } from '@mui/material';
import React from 'react';

interface ErrorPopupProps {
    errorMessageCallback: () => void;
    errorMessage: string;
}

function ErrorPopup({ errorMessage, errorMessageCallback }: ErrorPopupProps) {
    const open = errorMessage !== "";
    return (
        <Dialog open={open} aria-labelledby="error-popup-title">
            <DialogTitle id="error-popup-title">
                <Typography variant="h5" align="center">
                    Error
                </Typography>
            </DialogTitle>
            <DialogContent>
                <Box display="flex" flexDirection="column" alignItems="center" >
                    <Typography variant="body1">
                        {errorMessage}
                    </Typography>
                    <Box mt={2}>
                        <Button
                            variant="contained"
                            color="primary"
                            onClick={errorMessageCallback}
                        >
                            OK
                        </Button>
                    </Box>
                </Box>
            </DialogContent>
        </Dialog>
    );
}

export default ErrorPopup;