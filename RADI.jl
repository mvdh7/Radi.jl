module RADI

include("gsw_rho.jl")

"""
    timeprep(t_start, t_end, t_interval, saveperXsteps)

Prepare vectors of model timesteps and savepoints. All time units are in days.
"""
function timeprep(stoptime, interval, saveperXsteps)
    timesteps = 0.0:interval:stoptime
    ntps = length(timesteps)
    savepoints = collect(1:saveperXsteps:ntps)
    # Save final timepoint if it's not already in the list
    if !(ntps in savepoints)
        append!(savepoints, ntps)
    end
    nsps = length(savepoints)
    return timesteps, savepoints, ntps, nsps
end # function timeprep

# const interval = 1/128000

"""
    model()

Run the RADI model.
"""
function model(stoptime, interval, saveperXsteps)

    timesteps, savepoints, ntps, nsps = timeprep(stoptime, interval, saveperXsteps)
    sp = 1

    # Set water column conditions
    T = 1.4 # temperature / degC
    S = 34.69 # practical salinity
    rho_sw = gsw_rho(S, T, 1) # seawater density [kg/m^3]
    oxy_w = 159.7e-6*rho_sw # dissolved oxygen [mol/m3]
    po4_w = 2.39e-6*rho_sw # phosphate from GLODAP at station location, bottom
    # waters [mol/m3]

    # "Redfield" ratios
    RC = @. 1/(6.9e-3po4_w/(1e-6rho_sw) + 6e-3)
    # ^P:C computed as a function of SRP from Galbraith and Martiny PNAS 2015
    RN = 11 # value at 60 degS from Martiny et al. Nat G 2013
    RP = 1 # Redfield ratio for P in the deep sea
    M_OM = @. 30.03 + (RN/RC)*17.03 + (RP/RC)*97.994
    # ^ Organic Matter molar mass [g of OM per mol of OC]

    # Create arrays for modelled variables
    z_res = 0.001
    z_res2 = z_res^2
    z_max = 0.2
    depths = collect(-z_res:z_res:(z_max+z_res)) # in m
    depths[1] = NaN
    depths[end] = NaN
    ndepths = length(depths)
    oxy0 = fill(oxy_w*0.5, ndepths)
    oxy = copy(oxy0)*0
    poc0 = fill(10.0, ndepths)
    poc = copy(poc0)*0

    # Depth-dependent porosity
    phi0 = 0.85
    phiInf = 0.74
    beta = 33.0
    phi = @. (phi0 - phiInf)*exp(-beta*depths) + phiInf
    # ^ porosity profile (porewater bulk fraction) fitted from station7 mooring3
    # of cruise NBP98-2 by Sayles et al. DSR 2001
    phiS = 1.0 .- phi # solid volume fraction
    phiS_phi = phiS./phi
    tort2 = @. 1.0 - 2.0log(phi) # tortuosity squared from Boudreau (1996, GCA)
    tort = sqrt.(tort2) # tortuosity

    # Solid fluxes and solid initial conditions
    Foc = 1.0 # flux of total organic carbon to the bottom [mol/m2/a]
    Ftot = Foc.*M_OM # total sediment flux [g/m2/a]
    rho_pom = 2.65e6 # solid density [g/m3]
    v0 = Ftot/(rho_pom*phiS[2]) # [m/a] bulk burial velocity at sediment-water interface
    vinf = v0*phiS[2]/phiS[end-1] # [m/a] bulk burial velocity at the infinite depth
    u = vinf*phi[end-1]./phi # [m/a] porewater burial velocity
    w = vinf*phiS[end-1]./phiS # [m/a] solid burial velocity

    # Diffusive boundary layer
    dbl = 1e-3 # thickness at location taken from Sulpis et al. 2018 PNAS [m]

    # Temperature-dependent "free solution" diffusion coefficients
    D_oxy = @. 0.034862 + 0.001409T # [m2/a] oxygen diffusion coefficient from Li and Gregiry
    D_oxy_tort2 = D_oxy./tort2

    # Bioturbation (for solids)
    D_bio_0 = @. 0.0232e-4*(1e2Foc)^0.85 # [m2/a] surf bioturb coeff, Archer et al (2002)
    lambda_b = 0.08 # [m] characteristic depth of Archer et al. (2002), value
                    # here following Martin & Sayles (1990)
    D_bio = @. D_bio_0*exp(-(depths/lambda_b)^2)*oxy_w/(oxy_w + 0.02)
    # ^[m2/a] bioturb coeff, Archer et al (2002)

    # Irrigation (for solutes)
    alpha_0 = @. 11.0*(atan((1e2Foc*5.0 - 400.0)/400.0)/pi + 0.5) - 0.9 +
        20.0*(oxy_w/(oxy_w + 0.01))*exp(-oxy_w/0.01)*1e2Foc/(1e2Foc + 30.0)
    # ^[/a] from Archer et al (2002)
    lambda_i = 0.05 # [m] mysterious characteristic depth
    alpha = @. alpha_0*exp(-(depths/lambda_i)^2)
    # ^[/a] Archer et al (2002) the depth of 5 cm was changed

    # Depth-dependent porosity and diffusion coefficient loss
    delta_phi = append!([0.0], diff(phi)) # depth-dependent porosity loss
    delta_phiS = append!([0.0], diff(phiS)) # depth-dependent solid fraction gain
    delta_tort2 = append!([0.0], diff(tort.^2)) # depth-dependent tortuosity gain
    delta_D_bio = append!([0.0], diff(D_bio)) # [m/a]

    # Biodiffusion depth-attenuation: see Boudreau (1996); Fiadeiro and Veronis (1977)
    Peh = @. w*z_res/2D_bio # one half the cell Peclet number (Eq. 97 in Boudreau 1996)
    # when Peh<<1, biodiffusion dominates, when Peh>>1, advection dominates
    sigma = @. 1/tanh(Peh) - 1/(Peh) # Eq. 96 in Boudreau 1996

    # Organic matter degradation parameters
    krefractory = @. 80.25D_bio_0*exp(-depths) # [/a] from Archer et al (2002)

    # Short-cut transport variables
    APPW = @. w - delta_D_bio - delta_phiS*D_bio/phiS
    DFF = @. (tort2*delta_phi/phi - delta_tort2)/tort2^2
    # DBF = @. D_bio*(phiS - delta_phi) # not used?
    # TR = @. 2z_res*tort2/dbl

    # Create arrays for saved variables
    oxy_save = fill(NaN, (ndepths-2, nsps))
    poc_save = fill(NaN, (ndepths-2, nsps))

    "Reactions throughout the sediment."
    function react!(z::Int, var::Array{Float64,1}, rate::Float64)
        var[z] += interval*rate
    end # function react!

    "Burial of solutes at the sediment-water interface."
    function bury!(var0::Array{Float64,1}, var::Array{Float64,1},
            var_w::Float64)
        var[1] += interval*u[1]*TR[1]*(var_w - var0[1])/2.0z_res
    end # function bury!

    "Burial of solutes throughout the sediment."
    function bury!(z::Int, var0::Array{Float64,1}, var::Array{Float64,1},
            D_var::Float64)
        var[z] -= interval*(u[z] - D_var*DFF[z])*
            (var0[z+1] - var0[z-1])/2.0z_res
    end # function bury!

    "Accumulation of solids at the sediment-water interface."
    function accumulate!(var0::Array{Float64,1}, var::Array{Float64,1},
            var_w::Float64)
        var[z] += interval*(2.0*(Foc - phiS[1]*w[1]*var0[1])/
            (D_bio[1]*phiS[1]*z_res) + w[1]*Foc)
    end # function accumulate!

    "Accumulation of solids within the sediment."
    function accumulate!(z::Int, var0::Array{Float64,1}, var::Array{Float64,1})
        var[z] -= interval*APPW[z]*
            ((1.0 - sigma[z])*var0[z] - (1.0 + sigma[z])*var0[z-1])/2.0z_res
    end # function accumulate!

    "Accumulation of solids at the bottom of the modelled sediment."
    function accumulate!(var0::Array{Float64,1}, var::Array{Float64,1})
        var[ndepths] -= interval*APPW[ndepths]*sigma[ndepths]*
            (var0[ndepths] - var0[ndepths-1])/z_res
    end #function accumulate!

    "Substitute in above-surface value for solutes."
    function surface!(var0::Array{Float64,1}, var_w::Float64)
        # # Equation following Boudreau (1996, method-of-lines):
        # n = 2 # ambiguous value from Eq. (104)
        # var0[1] = var0[3] + (var_w - var0[2])*2z_res/(dbl*phi[2]^(n+1))
        # Or, equation following RADI-Matlab and CANDI-Fortran:
        var0[1] = var0[3] + (var_w - var0[2])*2z_res*tort2[2]/dbl
    end # function surface!

    "Substitute in above-surface value for solids."
    function surface!(var0::Array{Float64,1}, Fvar::Float64, D_var_0::Float64)
        var0[1] = var0[3] + (Fvar/phiS[2] - w[2]*var0[2])*2z_res/D_var_0
    end # function surface!

    "Substitute in below-bottom value."
    function bottom!(var0::Array{Float64,1})
        var0[end] = var0[end-2]
    end # function bottom!

    "Substitute in above-surface and below-bottom values for solutes."
    function substitute!(var0::Array{Float64,1}, var_w::Float64)
        surface!(var0, var_w)
        bottom!(var0)
    end # function substitute!

    "Substitute in above-surface and below-bottom values for solids."
    function substitute!(var0::Array{Float64,1}, Fvar::Float64,
            D_var_0::Float64)
        surface!(var0, Fvar, D_var_0)
        bottom!(var0)
    end # function substitute!

    "Diffusion throughout the sediment."
    function diffuse!(z::Int, var0::Array{Float64,1}, var::Array{Float64,1},
            D_var::Float64)
        var[z] += interval*(var0[z-1] - 2.0var0[z] + var0[z+1])*D_var/z_res2
    end # function diffuse!

    "Irrigation of solutes throughout the sediment."
    function irrigate!(z::Int, var0::Array{Float64,1}, var::Array{Float64,1},
            var_w::Float64)
        var[z] += interval*alpha[z]*(var_w - var0[z])
    end # function irrigate!

    # ===== Run RADI run: main model loop ======================================
    for t in 1:ntps
        tsave = t in savepoints # i.e. do we save this time?

        # Substitutions above and below the modelled sediment column
        substitute!(oxy0, oxy_w)
        substitute!(poc0, Foc, D_bio_0)

        for z in 2:(ndepths-1)
        # ~~~ BEGIN SEDIMENT PROCESSING ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            diffuse!(z, oxy0, oxy, D_oxy_tort2[z])
            irrigate!(z, oxy0, oxy, oxy_w)

            diffuse!(z, poc0, poc, D_bio[z])


        # # --- Everywhere within the sediment (incl. top and bottom): -----------
        #     # irrigate!(z, oxy0, oxy, oxy_w)
        #     # Rg_z = poc[z]*krefractory[z]
        #     # react!(z, oxy, -Rg_z*phiS_phi[z])
        #     # react!(z, poc, -Rg_z)
        # ~~~ END SEDIMENT PROCESSING ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

            # Save output if we are at a savepoint
            if tsave
                if t == 1
                    oxy_save[z-1, sp] = oxy0[z]
                    poc_save[z-1, sp] = poc0[z]
                else
                    oxy_save[z-1, sp] = oxy[z]
                    poc_save[z-1, sp] = poc[z]
                end
                if z == ndepths-1
                    println("RADI: reached savepoint $sp (step $t of $ntps)...")
                    sp += 1
                end # if
            end # if
        end # for z in 2:(ndepths-1)

        # Copy results into "previous step" arrays
        for z in 2:(ndepths-1)
            oxy0[z] = oxy[z]
            poc0[z] = poc[z]
        end # for z in 2:(ndepths-1)
    end # for t
    # ===== End of main model loop =============================================

    return depths[2:end-1], oxy_save, poc_save

end # function model

say_RADI() = println("RADI done!")

end # module RADI
