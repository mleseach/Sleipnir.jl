"""
    create_results(simulation::SIM, glacier_idx::I, solution, loss=nothing; light=false, batch_id::Union{Nothing, I}=nothing) where {SIM <: Simulation, I <: Integer}

Create a `Results` object from a given simulation and solution.

# Arguments
- `simulation::SIM`: The simulation object of type `Simulation`.
- `glacier_idx::I`: The index of the glacier within the simulation.
- `solution`: The solution object containing all the steps including intermediate ones.
- `loss=nothing`: The loss value, default is `nothing`.
- `light=false`: A boolean flag to indicate if only the first and last steps of the solution should be used.
- `batch_id::Union{Nothing, I}=nothing`: The batch ID, default is `nothing`.

# Returns
- `results`: A `Results` object containing the processed simulation data.

# Details
The function processes the solution to select the last value for each time step. It then constructs a `Results` object containing various attributes from the simulation and the iceflow model.
"""
function create_results(simulation::SIM, glacier_idx::I, solution, loss=nothing; light=false, batch_id::Union{Nothing, I}=nothing) where {SIM <: Simulation, I <: Integer}
    # The solution contains all the steps including the intermediate ones
    # This results in solution having multiple values for a given time step, we select the last one of each time step
    t₀ = simulation.parameters.simulation.tspan[1]
    t₁ = simulation.parameters.simulation.tspan[2]
    Δt = simulation.parameters.simulation.step

    nSteps = (t₁-t₀) / Δt
    timeSteps = t₀ .+ collect(0:nSteps) .* Δt
    ϵ = 1e-6 # Need this because of numerical rounding
    compfct(t,val) = (t<=val+ϵ) & (t>=val-ϵ)
    solStepIndices = [findlast(t->compfct(t,val), solution.t) for val in timeSteps]

    t = light ? nothing : solution.t[solStepIndices]
    H = light ? [solution.u[begin],solution.u[end]] : solution.u[solStepIndices]

    # Simulations using Reverse Diff require an iceflow model per glacier
    if isnothing(batch_id)
        iceflow_model = simulation.model.iceflow
    else
        iceflow_model = simulation.model.iceflow[batch_id]
    end
    if !isnothing(simulation.model.machine_learning)
        θ = simulation.model.machine_learning.θ
    else
        θ = nothing
    end

    results = Results(simulation.glaciers[glacier_idx], iceflow_model;
                      H = H,
                      S = iceflow_model.S,
                      B = simulation.glaciers[glacier_idx].B,
                      V = iceflow_model.V,
                      Vx = iceflow_model.Vx,
                      Vy = iceflow_model.Vy,
                      Δx = simulation.glaciers[glacier_idx].Δx,
                      Δy = simulation.glaciers[glacier_idx].Δy,
                      lon = simulation.glaciers[glacier_idx].cenlon,
                      lat = simulation.glaciers[glacier_idx].cenlat,
                      nx = simulation.glaciers[glacier_idx].nx,
                      ny = simulation.glaciers[glacier_idx].ny,
                      t = t,
                      tspan = simulation.parameters.simulation.tspan,
                      θ = θ,
                      loss = loss
                    )

    return results
end


"""
    save_results_file!(results_list::Vector{Results{F, I}}, simulation::SIM; path::Union{String,Nothing}=nothing) where {F <: AbstractFloat, I <: Int, SIM <: Simulation}

Save the results of a simulation to a file.

# Arguments
- `results_list::Vector{Results{F, I}}`: A vector containing the results of the simulation.
- `simulation::SIM`: The simulation object containing the parameters and results.
- `path::Union{String,Nothing}`: Optional. The path where the results file will be saved. If not provided, a default path will be used.

# Description
This function saves the results of a simulation to a file in JLD2 format. If the `path` argument is not provided, the function will create a default path based on the current project directory. The results are saved in a file named `prediction_<nglaciers>glaciers_<tspan>.jld2`, where `<nglaciers>` is the number of glaciers in the simulation and `<tspan>` is the simulation time span.
"""
function save_results_file!(results_list::Vector{Results{F, I}}, simulation::SIM; path::Union{String,Nothing}=nothing) where {F <: AbstractFloat, I <: Int, SIM <: Simulation}
    # Create path for simulation results
    if isnothing(path)
        predictions_path = joinpath(dirname(Base.current_project()), "data/results/predictions")
    else
        predictions_path = path
    end
    if !ispath(predictions_path)
        mkpath(predictions_path)
    end

    simulation.results = results_list

    tspan = simulation.parameters.simulation.tspan
    nglaciers = length(simulation.glaciers)
    jldsave(joinpath(predictions_path, "prediction_$(nglaciers)glaciers_$tspan.jld2"); simulation.results)
end

"""
    get_result_id_from_rgi(glacier_id::I, simulation::SIM) where {I <: Integer, SIM <: Simulation}

Extract results of specific simulation from the `Simulation` object.

# Arguments
- `glacier_id::I`: Numerical ID of glacier used to generate simulation.
- `simulation::SIM``: The simulation object containing the parameters and results.
"""
function get_result_id_from_rgi(glacier_id::I, simulation::SIM) where {I <: Integer, SIM <: Simulation}

    rgi_id = simulation.glaciers[glacier_id].rgi_id

    for id in 1:length(simulation.glaciers)
        if simulation.results[id].rgi_id == rgi_id
            return id
        end
    end
    @warn "No glacier ID found for current simulation."
end