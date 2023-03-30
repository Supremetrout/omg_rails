import React, { useEffect, useRef, useState } from 'react'
import { useDispatch, useSelector } from "react-redux";
import { Alert, AlertTitle, Box, Button, CircularProgress, Container, Grid, Snackbar, Typography } from "@mui/material";
import { useParams } from "react-router-dom";
import { makeStyles } from "@mui/styles";

import { CompanyGridDropTarget } from "./squads/CompanyGridDropTarget";
import { SquadsGridTabs } from "./squads/SquadsGridTabs";

import { ANTI_ARMOUR, ARMOUR, ASSAULT, CORE, INFANTRY, SUPPORT } from "../../../constants/company";
import { addCost, fetchCompanyById, removeCost, selectCompanyById } from "../companiesSlice";
import {
  resetAvailableUnitState,
  fetchCompanyAvailability,
  selectAllAvailableUnits,
  selectAvailableUnitsStatus
} from "./available_units/availableUnitsSlice"
import { AvailableUnits } from "./available_units/AvailableUnits";
import { AvailableUnitDetails } from "./available_units/AvailableUnitDetails";
import {
  addNonTransportedSquad,
  resetSquadState,
  clearNotifySnackbar,
  showSnackbar,
  removeSquad,
  selectAntiArmourSquads,
  selectArmourSquads,
  selectAssaultSquads,
  selectCoreSquads,
  selectInfantrySquads,
  selectSupportSquads,
  upsertSquads,
  fetchCompanySquads,
  moveSquad,
  addTransportedSquad,
  removeTransportedSquad
} from "./units/squadsSlice";
import { AlertSnackbar } from "../AlertSnackbar";
import { selectIsCompanyUnlocksChanged } from "./unlocks/companyUnlocksSlice";
import { createSquad } from "./units/squad";
import { AvailableOffmaps } from "./available_offmaps/AvailableOffmaps";
import { createCompanyOffmap } from "./company_offmaps/companyOffmap";
import {
  addNewCompanyOffmap, removeExistingCompanyOffmap, removeNewCompanyOffmap,
  selectMergedCompanyOffmaps
} from "./company_offmaps/companyOffmapsSlice";
import { PurchasedOffmaps } from "./company_offmaps/PurchasedOffmaps";

const useStyles = makeStyles(theme => ({
  availableUnitsContainer: {
    minHeight: '280px'
  },
  detailTitle: {
    fontWeight: 'bold'
  },
  saveWrapper: {
    display: 'flex',
    // alignItems: 'center',
    marginTop: "8px"
  },
  saveButton: {
    height: 'fit-content'
  }
}))

const defaultTab = CORE
export const SquadBuilder = ({}) => {
  const dispatch = useDispatch()
  const [currentTab, setCurrentTab] = useState(defaultTab)
  const [selectedUnitId, setSelectedUnitId] = useState(null)
  const [selectedAvailableUnitId, setSelectedAvailableUnitId] = useState(null)
  const [selectedUnitImage, setSelectedUnitImage] = useState(null)
  const [selectedUnitName, setSelectedUnitName] = useState(null)

  const notifySnackbar = useSelector(state => state.squads.notifySnackbar)
  const snackbarMessage = useSelector(state => state.squads.snackbarMessage)
  const [openSnackbar, setOpenSnackbar] = useState(false)
  const allOffmaps = useSelector(selectMergedCompanyOffmaps)

  useEffect(() => {
    setOpenSnackbar(notifySnackbar)
  }, [notifySnackbar])

  const core = useSelector(selectCoreSquads)
  const assault = useSelector(selectAssaultSquads)
  const infantry = useSelector(selectInfantrySquads)
  const armour = useSelector(selectArmourSquads)
  const antiArmour = useSelector(selectAntiArmourSquads)
  const support = useSelector(selectSupportSquads)

  let currentTabPlatoons
  switch (currentTab) {
    case CORE: {
      currentTabPlatoons = core
      break
    }
    case ASSAULT: {
      currentTabPlatoons = assault
      break
    }
    case INFANTRY: {
      currentTabPlatoons = infantry
      break
    }
    case ARMOUR: {
      currentTabPlatoons = armour
      break
    }
    case ANTI_ARMOUR: {
      currentTabPlatoons = antiArmour
      break
    }
    case SUPPORT: {
      currentTabPlatoons = support
      break
    }
    default: {
      console.log(`Unsupported tab ${currentTab}`)
      break
    }
  }

  const classes = useStyles()

  let params = useParams()
  const companyId = params.companyId
  const company = useSelector(state => selectCompanyById(state, companyId))

  const squadsStatus = useSelector(state => state.squads.squadsStatus)
  const isChanged = useSelector(state => state.squads.isChanged)
  const squadsError = useSelector(state => state.squads.squadsError)
  const isSaving = squadsStatus === 'pending'
  const canSave = !isSaving && isChanged
  const errorMessage = isSaving ? "" : squadsError

  const isCompanyUnlocksChange = useSelector(selectIsCompanyUnlocksChanged)

  useEffect(() => {
    console.log("dispatching squad and available_unit fetch from SquadBuilder")
    dispatch(fetchCompanySquads({ companyId }))
    // dispatch(fetchCompanyAvailability({ companyId })) // Rolled up into fetchCompanySquads

    return () => {
      console.log("dispatching resetSquadState resetAvailableUnitState")
      dispatch(resetSquadState())
      dispatch(resetAvailableUnitState())
    }
  }, [companyId, isCompanyUnlocksChange])

  // TODO use this to constrain the drag area
  const constraintsRef = useRef(null)

  const handleCloseSnackbar = () => {
    setOpenSnackbar(false)
    dispatch(clearNotifySnackbar())
  }

  const onTabChange = (newTab) => {
    console.log(`SquadBuilder changed to new tab ${newTab}`)
    setCurrentTab(newTab)
  }

  const onUnitSelect = (unitId, availableUnitId, unitImage, unitName) => {
    /** Called when a unit is selected. Populates the unit stats box with relevant data
     * TODO if a squad is clicked, should take upgrades into account
     */
    setSelectedAvailableUnitId(availableUnitId)
    // setSelectedUnitId(unitId)
    setSelectedUnitImage(unitImage)
    setSelectedUnitName(unitName)
  }

  /** For a new non-transported squad, use the availableUnit and unit to construct a new squad object
   * Update the company's resources with the new squad's base cost and add the squad to state */
  const onNonTransportSquadCreate = (availableUnit, unit, index, tab) => {
    const newSquad = createSquad(availableUnit, unit, index, tab)
    dispatch(addCost({
      id: company.id,
      pop: newSquad.pop,
      man: newSquad.man,
      mun: newSquad.mun,
      fuel: newSquad.fuel
    }))
    dispatch(addNonTransportedSquad(newSquad))
  }

  /** For a new transported squad, use the availableUnit and unit to construct a new squad object.
   * Additionally include the transport's UUID to denote the transport relationship
   * Update the company's resources with the new squad's base cost and add the squad to state */
  const onTransportedSquadCreate = (availableUnit, unit, index, tab, transportUuid) => {
    const newSquad = createSquad(availableUnit, unit, index, tab, transportUuid)
    dispatch(addCost({
      id: company.id,
      pop: newSquad.pop,
      man: newSquad.man,
      mun: newSquad.mun,
      fuel: newSquad.fuel
    }))
    dispatch(addTransportedSquad({ newSquad, transportUuid }))
  }

  const onSquadDestroy = (squad, transportUuid = null) => {
    // TODO remove squad id from company if not null
    dispatch(removeCost({ id: company.id, pop: squad.pop, man: squad.man, mun: squad.mun, fuel: squad.fuel }))
    if (_.isNull(transportUuid)) {
      console.log(`Removing non-transport squad`)
      dispatch(removeSquad(squad))
    } else {
      console.log(`Removing transported squad`)
      dispatch(removeTransportedSquad({ squad, transportUuid }))
    }
  }

  const onSquadMove = (squad, unit, newIndex, newTab, targetTransportUuid = null) => {
    dispatch(moveSquad({ squad, unit, newIndex, newTab, targetTransportUuid }))
  }

  const saveSquads = () => {
    dispatch(upsertSquads({ companyId, offmaps: allOffmaps }))
  }

  const onOffmapSelect = (availableOffmap) => {
    const newCompanyOffmap = createCompanyOffmap(null, availableOffmap)
    dispatch(addCost({ id: company.id, pop: 0, man: 0, mun: newCompanyOffmap.mun, fuel: 0 }))
    dispatch(addNewCompanyOffmap({ newCompanyOffmap }))
  }

  const onOffmapDestroyClick = (companyOffmap) => {
    dispatch(removeCost({ id: company.id, pop: 0, man: 0, mun: companyOffmap.mun, fuel: 0 }))
    if (_.isNull(companyOffmap.id)) {
      dispatch(removeNewCompanyOffmap({ availableOffmapId: companyOffmap.availableOffmapId }))
    } else {
      dispatch(removeExistingCompanyOffmap({
        id: companyOffmap.id,
        availableOffmapId: companyOffmap.availableOffmapId
      }))
    }
  }

  const editEnabled = !company.activeBattleId
  const availableUnitsStatus = useSelector(selectAvailableUnitsStatus)
  const availableUnits = useSelector(selectAllAvailableUnits)
  let availableUnitsContent,
    availableOffmapsContent
  if (availableUnitsStatus === "pending") {
    console.log("Loading available units")
    availableUnitsContent = <CircularProgress />
    availableOffmapsContent = null
  } else {
    console.log("Selected available units")
    console.log(availableUnits)
    availableUnitsContent = <AvailableUnits onUnitSelect={onUnitSelect} enabled={editEnabled} />
    availableOffmapsContent = <AvailableOffmaps onSelect={onOffmapSelect} enabled={editEnabled} />
  }

  let snackbarSeverity = "success"
  let snackbarContent = "Saved successfully"
  let errorAlert
  if (errorMessage?.length > 0) {
    errorAlert = <Alert severity="error">{errorMessage}</Alert>
  }
  if (notifySnackbar) {
    if (errorMessage?.length > 0) {
      snackbarSeverity = "error"
      snackbarContent = "Failed to save company"
    }
  }

  return (
    <>
      <Box sx={{ padding: 1 }}>
        <AlertSnackbar isOpen={openSnackbar}
                       setIsOpen={setOpenSnackbar}
                       handleClose={handleCloseSnackbar}
                       severity={snackbarSeverity}
                       content={snackbarContent} />
        <Grid container spacing={2} ref={constraintsRef}>
          <Grid item container spacing={2} className={classes.availableUnitsContainer}>
            <Grid item container md={6}>
              <Grid item xs={12}>
                {availableUnitsContent}
              </Grid>
              <Grid item>
                {availableOffmapsContent}
              </Grid>
            </Grid>
            <Grid item container md={6} xs={12}>
              <Grid item xs={12}>
                <AvailableUnitDetails unitId={selectedUnitId} availableUnitId={selectedAvailableUnitId}
                                      unitImage={selectedUnitImage} />
                <Box className={classes.saveWrapper}>
                  <Button variant="contained" color="secondary" size="small" onClick={saveSquads}
                          disabled={!canSave} className={classes.saveButton}>Save</Button>
                  {errorAlert}
                </Box>
              </Grid>
            </Grid>
          </Grid>
          <Grid item container spacing={2}>
            <Grid item xs={2} md={1}>
              <Typography variant="subtitle2" color="text.secondary" gutterBottom className={classes.detailTitle}
                          pr={1}>Population</Typography>
              <Typography variant="body2" gutterBottom>{company.pop}</Typography>
            </Grid>
            <Grid item xs={2} md={1}>
              <Typography variant="subtitle2" color="text.secondary" gutterBottom className={classes.detailTitle}
                          pr={1}>Manpower</Typography>
              <Typography variant="body2" gutterBottom>{company.man}</Typography>
            </Grid>
            <Grid item xs={2} md={1}>
              <Typography variant="subtitle2" color="text.secondary" gutterBottom className={classes.detailTitle}
                          pr={1}>Munitions</Typography>
              <Typography variant="body2" gutterBottom>{company.mun}</Typography>
            </Grid>
            <Grid item xs={2} md={1}>
              <Typography variant="subtitle2" color="text.secondary" gutterBottom className={classes.detailTitle}
                          pr={1}>Fuel</Typography>
              <Typography variant="body2" gutterBottom>{company.fuel}</Typography>
            </Grid>
            <Grid item md={2} />
            <Grid item md={6}>
              <Typography variant="subtitle2" color="text.secondary" gutterBottom className={classes.detailTitle}
                          pr={1}>Purchased Offmaps</Typography>
              <PurchasedOffmaps onDeleteClick={onOffmapDestroyClick} enabled={editEnabled} />
            </Grid>
          </Grid>
          <Grid item container spacing={2}>
            <SquadsGridTabs selectedTab={currentTab} changeCallback={onTabChange} />
          </Grid>
          <Grid item container spacing={2}>
            <Grid item xs={3}>
              <CompanyGridDropTarget gridIndex={0} currentTab={currentTab} squads={currentTabPlatoons[0]}
                                     onNonTransportSquadCreate={onNonTransportSquadCreate}
                                     onTransportedSquadCreate={onTransportedSquadCreate}
                                     onUnitClick={onUnitSelect}
                                     onSquadDestroy={onSquadDestroy}
                                     onSquadMove={onSquadMove}
                                     enabled={editEnabled} />
            </Grid>
            <Grid item xs={3}>
              <CompanyGridDropTarget gridIndex={1} currentTab={currentTab} squads={currentTabPlatoons[1]}
                                     onNonTransportSquadCreate={onNonTransportSquadCreate}
                                     onTransportedSquadCreate={onTransportedSquadCreate}
                                     onUnitClick={onUnitSelect}
                                     onSquadDestroy={onSquadDestroy}
                                     onSquadMove={onSquadMove}
                                     enabled={editEnabled} />
            </Grid>
            <Grid item xs={3}>
              <CompanyGridDropTarget gridIndex={2} currentTab={currentTab} squads={currentTabPlatoons[2]}
                                     onNonTransportSquadCreate={onNonTransportSquadCreate}
                                     onTransportedSquadCreate={onTransportedSquadCreate}
                                     onUnitClick={onUnitSelect}
                                     onSquadDestroy={onSquadDestroy}
                                     onSquadMove={onSquadMove}
                                     enabled={editEnabled} />
            </Grid>
            <Grid item xs={3}>
              <CompanyGridDropTarget gridIndex={3} currentTab={currentTab} squads={currentTabPlatoons[3]}
                                     onNonTransportSquadCreate={onNonTransportSquadCreate}
                                     onTransportedSquadCreate={onTransportedSquadCreate}
                                     onUnitClick={onUnitSelect}
                                     onSquadDestroy={onSquadDestroy}
                                     onSquadMove={onSquadMove}
                                     enabled={editEnabled} />
            </Grid>
          </Grid>
          <Grid item container spacing={2}>
            <Grid item xs={3}>
              <CompanyGridDropTarget gridIndex={4} currentTab={currentTab} squads={currentTabPlatoons[4]}
                                     onNonTransportSquadCreate={onNonTransportSquadCreate}
                                     onTransportedSquadCreate={onTransportedSquadCreate}
                                     onUnitClick={onUnitSelect}
                                     onSquadDestroy={onSquadDestroy}
                                     onSquadMove={onSquadMove}
                                     enabled={editEnabled} />
            </Grid>
            <Grid item xs={3}>
              <CompanyGridDropTarget gridIndex={5} currentTab={currentTab} squads={currentTabPlatoons[5]}
                                     onNonTransportSquadCreate={onNonTransportSquadCreate}
                                     onTransportedSquadCreate={onTransportedSquadCreate}
                                     onUnitClick={onUnitSelect}
                                     onSquadDestroy={onSquadDestroy}
                                     onSquadMove={onSquadMove}
                                     enabled={editEnabled} />
            </Grid>
            <Grid item xs={3}>
              <CompanyGridDropTarget gridIndex={6} currentTab={currentTab} squads={currentTabPlatoons[6]}
                                     onNonTransportSquadCreate={onNonTransportSquadCreate}
                                     onTransportedSquadCreate={onTransportedSquadCreate}
                                     onUnitClick={onUnitSelect}
                                     onSquadDestroy={onSquadDestroy}
                                     onSquadMove={onSquadMove}
                                     enabled={editEnabled} />
            </Grid>
            <Grid item xs={3}>
              <CompanyGridDropTarget gridIndex={7} currentTab={currentTab} squads={currentTabPlatoons[7]}
                                     onNonTransportSquadCreate={onNonTransportSquadCreate}
                                     onTransportedSquadCreate={onTransportedSquadCreate}
                                     onUnitClick={onUnitSelect}
                                     onSquadDestroy={onSquadDestroy}
                                     onSquadMove={onSquadMove}
                                     enabled={editEnabled} />
            </Grid>
          </Grid>
        </Grid>
      </Box>
    </>
  )
}
