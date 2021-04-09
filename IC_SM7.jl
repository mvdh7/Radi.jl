# Set model run name
modelrun = "IC_SM7"

# Define model timesteps (all times in years)
stoptime = 200.0  # how long to run for
interval = 1/128000  # duration of each model timestep
saveperXsteps = 128000  # save results in intervals of this many timesteps

# Define model depth steps (all depths in metres)
z_res = 1e-2  # height of each depth step
z_max = 40e-2  # total height of the modelled sediment column

# Define diffusive boundary layer thickness / m
dbl = 0.715e-3

# Define sediment porosity parameters
const phiInf = 0.74  # sediment porosity at infinite depth
const phi0 = 0.91  # sediment porosity at the surface
const beta = 33.0  # sediment porosity-depth relationship parameter

# Define characteristic depths
const lambda_b = 0.08  # for bioturbation / m
const lambda_f = 0.03  # for fast-degrading POC / m
const lambda_s = 1.0  # for slow-degrading POC / m
const lambda_i = 0.05  # for irrigation / m

# Define overlying water column properties
const T = 0.84  # temperature / degC
const S = 34.696  # practical salinity
const P = 3932.8  # pressure at seafloor / dbar
rho_sw = gsw_rho(S, T, P) # seawater density / kg/m^3
# Concentrations all in mol/m^3
dO2_w = 215.7e-6rho_sw  # dissolved oxygen
dtCO2_w = 2260e-6rho_sw  # dissolved inorganic carbon
dtNO3_w = 32.2416e-6rho_sw  # nitrate from GLODAP at station location, bottom waters
dtSO4_w = (29264.2e-6S/35)rho_sw  # estimated omputed from salinity (Millero, 2013)
dtPO4_w = 2.2428e-6rho_sw  # total phosphate
dtNH4_w = 1e-6rho_sw  # typical for deep-sea oxic bottom waters (Archer et al., 2002)
dtH2S_w = 0.0  # assumed
dFeII_w = 1e-6rho_sw  # typical for deep-sea oxic bottom waters (Archer et al., 2002)
dMnII_w = 1e-6rho_sw  # typical for deep-sea oxic bottom waters (Archer et al., 2002)
dalk_w = 2365e-6rho_sw  # total alkalinity from GLODAP at station location, bottom waters
dCa_w = 0.02128 / 40.087 * S / 1.80655 * rho_sw  # calcium from salinity (RT67 via PyCO2SYS)
dSi_w = 120e-6rho_sw  # total silicate

# Define organic matter flux to the surface sediment
Fpom = 3.557128618867924  # flux of POM to seafloor / g/m^2/a
Fpom_r = 0.1  # refractory fraction of POM
Fpom_s = 0.25  # slow-degrading fraction of POM
Fpom_f = 0.65  # fast-degrading fraction of POM
FMnO2 = 0.0035  # typical for deep-sea oxic bottom waters (Archer et al., 2002; Boudreau, 1996)
FFeOH3 = 0.0035  # typical for deep-sea oxic bottom waters (Archer et al., 2002; Boudreau, 1996)
Fcalcite = 0.25 * 0.7  # flux of calcite to the seafloor / mol/m^2/a
Faragonite = 0.25 * 0.3  # flux of aragonite to the seafloor / mol/m^2/a
Fclay = 32.0 / 360.31  # flux of clay (montmorillonite) to the seafloor / mol/m^2/a
rho_p = 2.65e6  # average density of all solid matter / g/m^3

# Define initial conditions within the sediment (scalars or arrays)
dO2_i = dO2_w  # dissolved oxygen / mol/m^3
dtCO2_i = dtCO2_w  # dissolved inorganic carbon / mol/m^3
dtNO3_i = dtNO3_w
dtSO4_i = dtSO4_w
dtPO4_i = dtPO4_w
dtNH4_i = dtNH4_w
dtH2S_i = dtH2S_w
dFeII_i = dFeII_w
dMnII_i = dMnII_w
dalk_i = dalk_w
dCa_i = dCa_w
pfoc_i = 0.0  # fast-degrading particulate organic carbon / unit?
psoc_i = 3.0e2  # slow-degrading particulate organic carbon / unit?
proc_i = 6.0e2  # refractory particulate organic carbon / unit?
pFeOH3_i = 0.0
pMnO2_i = 0.0
pcalcite_i = 4.5e3
paragonite_i = 0.0
pclay_i = 0.0