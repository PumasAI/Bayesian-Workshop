using Pumas
using DataFrames
using CSV
using PumasPlots

poppk2cpt = @model begin
    @param begin
        tvcl ~ LogNormal(log(10), 0.25)
        tvq ~ LogNormal(log(15), 0.5)
        tvvc ~ LogNormal(log(35), 0.25)
        tvvp ~ LogNormal(log(105), 0.5)
        tvka ~ LogNormal(log(2.5), 1)
        σ ~ truncated(Cauchy(0, 5), 0, Inf)
        C ~ LKJCholesky(5, 1.0)
        ω ~ Constrained(
            MvNormal(zeros(5), Diagonal(0.4^2 * ones(5))),
            lower=zeros(5),
            upper=fill(Inf, 5),
            init=ones(5),
        )
    end

    @random begin
        ηstd ~ MvNormal(I(5))
    end

    @pre begin
        # compute the η from the ηstd
        # using lower Cholesky triangular matrix
        η = ω .* (getchol(C).L * ηstd)

        # PK parameters
        CL = tvcl * exp(η[1])
        Q = tvq * exp(η[2])
        Vc = tvvc * exp(η[3])
        Vp = tvvp * exp(η[4])
        Ka = tvka * exp(η[5])
    end

    @dynamics begin
        Depot' = -Ka * Depot
        Central' = Ka * Depot - (CL + Q) / Vc * Central + Q / Vp * Peripheral
        Peripheral' = Q / Vc * Central - Q / Vp * Peripheral
    end

    @derived begin
        cp := @. Central / Vc
        dv ~ @. LogNormal(log(cp), σ)
    end
end

df = CSV.read("data/poppk2cpt.csv", DataFrame)
pop = read_pumas(df)[1:5]

# Prior predictive check
prior_sims = simobs(poppk2cpt, pop[2]; samples = 200, simulate_error = true)
postprocess(prior_sims, stat = mean) do sim, data
    mean(sim.dv .> data.dv)
end

iparams = (;
    tvcl=9.5,
    tvq=19,
    tvvc=67,
    tvvp=102,
    tvka=1.2,
    σ=0.83,
    C=float.(Matrix(I(5))),
    ω=[0.8, 0.1, 1.8, 2.0, 0.5]
)

poppk2cpt_fit = fit(
    poppk2cpt,
    pop,
    iparams,
    Pumas.BayesMCMC(
        nsamples=1000,
        nadapts=500,
        target_accept = 0.6,
    )
)

poppk2cpt_tfit = Pumas.truncate(poppk2cpt_fit; burnin=500)

gdiag = gewekediag(poppk2cpt_tfit)
hdiag = heideldiag(poppk2cpt_tfit)

# Visualizations
trace_plot(poppk2cpt_fit; parameters = [:tvcl, :tvvc])
trace_plot(poppk2cpt_fit; subjects = 1:2)
density_plot(poppk2cpt_tfit; parameters = [:tvcl])
density_plot(poppk2cpt_tfit; subjects = 1:2)
corner_plot(poppk2cpt_tfit, subject = 1)
autocor_plot(poppk2cpt_fit, parameters = [:tvcl, :tvvc])
autocor_plot(poppk2cpt_fit, subjects = 1)
