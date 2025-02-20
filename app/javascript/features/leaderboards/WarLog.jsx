import React, { useEffect } from 'react'
import { useDispatch } from "react-redux";
import { Box } from "@mui/material";
import { makeStyles } from "@mui/styles";
import { fetchBattlesHistory } from "./warLogSlice";
import { BattlesHistory } from "./war_log/BattlesHistory";


const useStyles = makeStyles(() => ({
  wrapper: {
    paddingLeft: '1rem',
    flexGrow: "1"
  },
  cell: {
    border: "none"
  },
  narrowCell: {
    maxWidth: "87px"
  }
}))

export const WarLog = ({}) => {
  const classes = useStyles()
  const dispatch = useDispatch()

  useEffect(() => {
    dispatch(fetchBattlesHistory({ ruleset_id: 1 }))
  }, []);

  return (
    <Box className={classes.wrapper}>
      <BattlesHistory/>
    </Box>
  )
}