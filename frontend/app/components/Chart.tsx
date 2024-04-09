import { Box } from '@mui/material';
import { makeStyles } from '@mui/styles';
import React from 'react';
import { Line } from 'react-chartjs-2';

const ChartComponent = ({ data }: any) => {
    const classes = useStyles();
    const chartData = {
        labels: data.reverse().map((x: any) => {
            const dateObj = new Date(x.date);
            const mmddyyyy = `${dateObj.getDate()}/${dateObj.getMonth() + 1}/${dateObj.getFullYear()}`;
            const hhmm = `${dateObj.getHours()}:${dateObj.getMinutes() < 10 ? "0" : ""}${dateObj.getMinutes()}`;
            return `${mmddyyyy} ${hhmm}`;
        }),
        datasets: [
            {
                label: 'LOTUS Price in ETH',
                data: data.map((x: any) => x.price),
                borderColor: '#FF69B4',
                backgroundColor: 'rgba(255, 105, 180, 0.2)',
                fill: true,
            }
        ]
    };

    const options = {
        responsive: true,
        scales: {
            x: {
                grid: {
                    color: 'rgba(255, 255, 255, 0.1)'
                },
            },
            y: {
                grid: {
                    color: 'rgba(255, 255, 255, 0.1)'
                }
            }
        }
    };

    return (
        <Box className={classes.chartContainer}>
            <div>
                <Line height={250} data={chartData} options={options} />
            </div>
        </Box>
    );
};

const useStyles = makeStyles(() => ({
    chartContainer: {
        width: '100%',
        border: '2px solid #FF69B4',
        borderRadius: "4px",
        background: 'white',
        padding: "10px",
    }
}));

export default ChartComponent;
