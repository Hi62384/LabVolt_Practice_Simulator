extends RefCounted
const START_HEALTH := 100.0
# A fixed low-resistance contact path is a gameplay assumption, not a safety limit.
# NIOSH describes roughly 1,200 ohms for a tight grip; real conditions vary widely.
const CONTACT_OHMS := 1200.0
const AC_INJURY_ONSET_AMPS := .005
const DC_INJURY_ONSET_AMPS := .010
const ARREST_CURRENT := .1
const RESPAWN_SECONDS := 20.0
static func apply_exposure(health: float, volts: float, dt: float, dc := false) -> Dictionary:
 var voltage:=maxf(0.0,volts)
 var current:=voltage/CONTACT_OHMS
 # Smoothly rises from zero at 5 mA. This is a game health curve, not a
 # physiological prediction; exposure time scales the accumulated injury.
 var onset := DC_INJURY_ONSET_AMPS if dc else AC_INJURY_ONSET_AMPS
 var scale := .05 if dc else .03
 var excess:=maxf(0.0,current-onset)
 var damage_rate:=8.0*pow(excess/scale,2.0)
 var arrested:=current>=ARREST_CURRENT
 var damage:=damage_rate*maxf(dt,0.0)
 return {"health":maxf(0.0,health-damage),"arrested":arrested,"current":current}
