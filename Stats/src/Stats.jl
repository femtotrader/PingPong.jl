module Stats

if get(ENV, "JULIA_NOPRECOMP", "") == "all"
    __init__() = begin
        include(joinpath(@__DIR__, "stats.jl"))
    end
else
    occursin(string(@__MODULE__), get(ENV, "JULIA_NOPRECOMP", "")) && __precompile__(false)
    include("module.jl")
    include("precompile.jl")
end

end # module Stats
