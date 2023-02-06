import Base.getproperty

using Reexport
using TimeTicks
using DataFrames: DataFrame
using Ccxt
@reexport using ExchangeTypes
using ExchangeTypes: OptionsDict, exc
using JSON
using Misc: DATA_PATH, dt, futures_exchange, exchange_keys
using Instruments
using Python
using Python.PythonCall: pycopy!, pyisnone
using Serialization: deserialize, serialize
using TimeToLive: TTL

const exclock = ReentrantLock()
const tickers_cache = TTL{String,T where T<:AbstractDict}(Minute(100))

@doc "Define an exchange variable set to its matching exchange instance."
macro exchange!(name)
    exc_var = esc(name)
    exc_str = lowercase(string(name))
    exc_istr = string(name)
    quote
        exc_sym = Symbol($exc_istr)
        $exc_var = if (exc.isset && lowercase(exc.name) === $exc_str)
            exc
        else
            (
                if hasproperty($(__module__), exc_sym)
                    getproperty($(__module__), exc_sym)
                else
                    Exchange(exc_sym)
                end
            )
        end
    end
end

function isfileyounger(f::AbstractString, p::Period)
    isfile(f) && dt(stat(f).mtime) < now() - p
end

function py_except_name(e::PyException)
    string(pygetattr(pytype(e), "__name__"))
end

@doc "Load exchange markets:
- `cache`: rely on storage cache
- `agemax`: max cache valid period [1 day]."
function loadmarkets!(exc; cache=true, agemax=Day(1))
    sbox = issandbox(exc) ? "_sandbox" : ""
    mkt = joinpath(DATA_PATH, exc.name, "markets$(sbox).jlz")
    empty!(exc.markets)
    function force_load()
        @debug "Loading markets from exchange and caching at $mkt."
        pyfetch(exc.loadMarkets, true)
        pd = pyconvert(OptionsDict, exc.py.markets)
        mkpath(dirname(mkt))
        serialize(mkt, PyDict(pd))
        merge!(exc.markets, pd)
    end
    if isfileyounger(mkt, agemax) && cache
        try
            cached_dict = deserialize(mkt) # this should be a PyDict
            merge!(exc.markets, pyconvert(OptionsDict, cached_dict))
            exc.py.markets = pydict(cached_dict)
            exc.py.markets_by_id = exc.py.index_by(exc.markets, "id")
        catch error
            @warn error
            force_load()
        end
    else
        force_load()
    end
    nothing
end

getexchange() = exc

@doc """getexchage!: ccxt exchange by symbol either from cache or anew. """
function getexchange!(x::Symbol, args...; kwargs...)
    get!(
        exchanges,
        x,
        begin
            py = ccxt_exchange(x, args...; kwargs...)
            e = Exchange(py)
            setexchange!(e)
        end,
    )
end

@doc "Instantiate an exchange struct. it sets:
- The matching ccxt class.
- Pre-emptively loads the markets.
- Sets the exchange timeframes.
- Sets exchange api keys.
"
function setexchange!(exc::Exchange, args...; markets=true, kwargs...)
    empty!(exc.timeframes)
    tfkeys = if pyisnone(exc.py.timeframes)
        Set{String}()
    else
        pyconvert(Set{String}, exc.py.timeframes.keys())
    end
    isempty(tfkeys) || push!(exc.timeframes, tfkeys...)
    @debug "Loading Markets..."
    markets && loadmarkets!(exc)
    @debug "Loaded $(length(exc.markets))."
    precision = getfield(exc, :precision)
    precision[1] = (x -> ExcPrecisionMode(pyconvert(Int, x)))(exc.py.precisionMode)
    exckeys!(exc)
    exc
end

function setexchange!(x::Symbol, args...; kwargs...)
    exc = getexchange!(x, args...; kwargs...)
    setexchange!(exc, args...; kwargs...)
    globalexchange!(exc)
end

@doc "Check if exchange has tickers list."
@inline function hastickers(exc::Exchange)
    Bool(exc.has["fetchTickers"])
end

@doc "Fetch and cache tickers data."
macro tickers(force=false)
    exc = esc(:exc)
    tickers = esc(:tickers)
    quote
        begin
            local $tickers
            let nm = $(exc).name
                if $force || nm ∉ keys(tickers_cache)
                    @assert hastickers($exc) "Exchange doesn't provide tickers list."
                    tickers_cache[nm] =
                        $tickers = pyconvert(
                            Dict{String,Dict{String,Any}}, pyfetch($(exc).fetchTickers)
                        )
                else
                    $tickers = tickers_cache[nm]
                end
            end
        end
    end
end

@doc "Get the the markets of the `ccxt` instance, according to `min_volume` and `quot`e currency.
"
function get_markets(exc; min_volume=10e4, quot="USDT", sep='/')
    @assert exc.has["fetchTickers"] "Exchange doesn't provide tickers list."
    markets = exc.markets
    @tickers
    f_markets = Dict()
    for (p, info) in markets
        _, pquot = split(p, sep)
        # NOTE: split returns a substring
        if pquot == quot && tickers[p]["quoteVolume"] > min_volume
            f_markets[p] = info
        end
    end
    f_markets
end

@doc "Get price from ticker."
function aprice(t)
    something(t["average"], t["last"], t["bid"])
end

@doc "Get price ranges using tickers data from exchange."
function price_ranges(pair::AbstractString, args...; kwargs...)
    tkrs = @tickers true
    price_ranges(tkrs[pair]["last"], args...; kwargs...)
end

@doc "Get quote volume of market."
function qvol(t::AbstractDict)
    v1 = t["quoteVolume"]
    isnothing(v1) || return v1
    v2 = t["baseVolume"]
    isnothing(v2) || return v2 * aprice(t)
    0
end

@doc "Trims the settlement currency in futures."
@inline function as_spot_ticker(k, v)
    if "quote" ∈ keys(v)
        "$(v["base"])/$(v["quote"])"
    else
        split(k, ":")[1]
    end
end

function is_timeframe_supported(timeframe, exc)
    timeframe ∈ exc.timeframes
end

@doc "Set exchange api keys."
function exckeys!(exc, key, secret, pass)
    name = uppercase(exc.name)
    # FIXME: ccxt key/secret naming is swapped for kucoin apparently
    if nameof(exc.id) ∈ (:kucoin, :kucoinfutures)
        (key, secret) = secret, key
    end
    exc.py.apiKey = key
    exc.py.secret = secret
    exc.py.password = pass
    nothing
end

function exckeys!(exc)
    exc_keys = exchange_keys(exc.id)
    # Check the exchange->futures mapping to re-use keys
    if isempty(exc_keys) && nameof(exc.id) ∈ values(futures_exchange)
        sym = Symbol(exc.id)
        id = argmax(x -> x[2] == sym, futures_exchange)
        merge!(exc_keys, exchange_keys(id.first))
    end
    if !isempty(exc_keys)
        @debug "Setting exchange keys..."
        exckeys!(exc, values(exc_keys)...)
    end
end

@doc "Enable sandbox mode for exchange"
function sandbox!(exc::Exchange=exc, flag=true)
    exc.py.setSandboxMode(flag)
    loadmarkets!(exc)
end
@doc "Check if sandbox mode is enabled for exchange."
issandbox(exc::Exchange=exc) = pyconvert(Bool, exc.py.urls["test"] == exc.py.urls["api"])

@doc "Enable or disable rate limit."
ratelimit!(exc::Exchange=exc, flag=true) = exc.py.enableRateLimit = flag

timestamp(exc::Exchange) = pyconvert(Int64, pyfetch(exc.py.fetchTime))
Base.time(exc::Exchange) = dt(pyconvert(Float64, pyfetch(exc.py.fetchTime)))

include("pairlist.jl")
include("data.jl")

export exc, @exchange!, setexchange!, getexchange!, exckeys!
export loadmarkets!, get_pairlist, get_pairs
export sandbox!, issandbox, ratelimit!
export timestamp
