module Ccxt
using Python
using Python: pynew
using Python.PythonCall: pyisnull
using Misc: DATA_PATH

const ccxt = pynew()
const ccxt_ws = pynew()
const ccxt_errors = Set{String}()

function __init__()
    clearpypath!()
    if pyisnull(ccxt)
        @pymodule ccxt ccxt.async_support
        @pymodule ccxt_ws ccxt.pro
        (errors -> union(ccxt_errors, errors))(
            Set(string.(pydir(pyimport("ccxt.base.errors"))))
        )
        mkpath(joinpath(DATA_PATH, "markets"))
    end
end

@doc "Instantiate a ccxt exchange class matching name."
function ccxt_exchange(name::Symbol, params=nothing)
    @debug "Instantiating Exchange $name..."
    exc_cls = getproperty(ccxt, name)
    isnothing(params) ? exc_cls() : exc_cls(params)
end

export ccxt, ccxt_ws, ccxt_errors, ccxt_exchange
end # module Ccxt
