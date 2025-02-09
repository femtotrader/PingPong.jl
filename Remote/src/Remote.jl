@doc "Control the bot remotely."
module Remote

if get(ENV, "JULIA_NOPRECOMP", "") == "all"
    __init__() = begin
        include(joinpath(@__DIR__, "remote.jl"))
    end
else
    occursin(string(@__MODULE__), get(ENV, "JULIA_NOPRECOMP", "")) && __precompile__(false)
    include("module.jl")
    if occursin("Remote", get(ENV, "JULIA_PRECOMP", ""))
        include("precompile.jl")
    end
end

end
