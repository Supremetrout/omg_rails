import React from 'react'
import { DragDropContainer } from "react-drag-drop-container";
import { makeStyles } from "@mui/styles";
import { Box, Tooltip, Typography, Zoom } from "@mui/material";

import { UnitCard } from "./UnitCard";

const useStyles = makeStyles(() => ({
  dragDropContainer: {
    padding: '2px',
    display: 'inline-block'
  },
  tooltipHeader: {
    fontWeight: 'bold'
  }
}))

/**
 * DragDrop container component to wrap an unit card, populating dragData for the drop target
 *
 * @param label: unit label
 * @param image: unit image
 * @param onDrop: callback fired when the drag drop container is dropped into a drop target
 * @param onClick: callback fired when the unit card is clicked
 */
export const UnitCardDroppable = ({ unitId, unitName, label, availableUnit, image, onDrop, onUnitClick, available, resupply, companyMax }) => {
  const classes = useStyles()

  let cost = ""
  if (availableUnit.man > 0) {
    cost += `${availableUnit.man}MP `
  }
  if (availableUnit.mun > 0) {
    cost += `${availableUnit.mun}MU `
  }
  if (availableUnit.fuel > 0) {
    cost += `${availableUnit.fuel}FU`
  }

  return (
    <Tooltip
      key={unitId}
      title={
        <>
          {/*TODO use unit display name */}
          <Typography variant="subtitle2" className={classes.tooltipHeader}>{label}</Typography>
          <Box><Typography variant="body"><b>Cost:</b> {cost}</Typography></Box>
          <Box><Typography variant="body"><b>Pop:</b> {parseFloat(availableUnit.pop)}</Typography></Box>
          <Box><Typography variant="body"><b>Available:</b> {available}</Typography></Box>
          <Box><Typography variant="body"><b>Resupply:</b> {resupply}</Typography></Box>
        </>
      }
      // TransitionComponent={Zoom}
      followCursor={true}
      placement="bottom-start"
      arrow
    >
      <Box className={classes.dragDropContainer}>
        <DragDropContainer targetKey="unit" onDrop={onDrop} dragData={{ unitId: unitId, unitName: unitName, image: image }}>
          <UnitCard unitId={unitId} label={label} image={image} onUnitClick={onUnitClick} />
        </DragDropContainer>
      </Box>
    </Tooltip>
  )
}