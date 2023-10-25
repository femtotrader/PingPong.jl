using Engine
using Engine.Exchanges
using .Exchanges.ExchangeTypes.Python
using Engine.Data
using Engine.Misc
using .Misc: Lang
using Pkg: Pkg as Pkg

include("logmacros.jl")
include("repl.jl")
include("strat.jl")

function _doinit()
    @debug "Initializing python async..."
    if "JULIA_BACKTEST_REPL" ∈ keys(ENV)
        exc = Symbol(get!(ENV, "JULIA_BACKTEST_EXC", :kucoin))
        Config(exc)
        wait(t)
        setexchange!(exc)
    end
    # default to using lmdb store for data
    @debug "Initializing LMDB zarr instance..."
    Data.zi[] = Data.zilmdb()
    if isinteractive()
        @info "Loading interactive utilities"
        @eval Main begin
            $(@__MODULE__).@environment!
            (isdefined(Main, :Revise) ? Revise.includet : include)(
                $(joinpath(@__DIR__, "dev.jl"))
            )
        end
    end
end

macro environment!()
    quote
        using PingPong
        using PingPong: PingPong as pp
        using PingPong.Exchanges
        using PingPong.Exchanges: Exchanges as exs
        using PingPong.Engine:
            OrderTypes as ot,
            Instances as inst,
            Collections as co,
            Simulations as sim,
            Strategies as st,
            Executors as ect,
            SimMode as sm,
            PaperMode as pm,
            LiveMode as lm,
            Engine as egn

        using Lang: @m_str
        using TimeTicks
        using TimeTicks: TimeTicks as tt
        using Misc
        using Misc: Misc as mi
        using Instruments
        using Instruments: Instruments as im
        using Instruments.Derivatives
        using Instruments.Derivatives: Derivatives as der
        using Data: Data as da, DFUtils as du
        using Data.Cache: save_cache, load_cache
        using Processing: Processing as pro
        using Remote: Remote as rmt
        using Watchers
        using Watchers: WatchersImpls as wi

        using Random
        using Stubs
        using .inst
        using .ot
    end
end

macro strategyenv!()
    quote
        using PingPong: PingPong as pp
        using .pp.Engine
        using .pp.Engine.Strategies
        using .pp.Engine: Strategies as st
        using .pp.Engine.Instances: Instances as inst
        using .pp.Engine.LiveMode.Watchers: Watchers
        using .pp.Engine.Executors
        using .pp.Engine.OrderTypes

        using .pp.Engine.OrderTypes.ExchangeTypes
        using .pp.Engine.Data
        using .pp.Engine.Data.DFUtils
        using .pp.Engine.Data.DataFrames
        using .pp.Engine.Instruments
        using .pp.Engine.Misc
        using .pp.Engine.TimeTicks
        using .pp.Engine.Lang

        using .st: freecash, setattr!, attr
        using .pp.Engine.Exchanges: getexchange!, marketsid
        using .pp.Engine.Processing: resample, islast, iscomplete, isincomplete
        using .Data: propagate_ohlcv!
        using .Misc: after, before, rangeafter, rangebefore
        using .inst: ohlcv, raw, lastprice, posside, collateral
        using .pp.Engine.LiveMode: updated_at!

        const $(esc(:ect)) = PingPong.Engine.Executors
        const $(esc(:pro)) = PingPong.Engine.Processing
        const $(esc(:wim)) = PingPong.Engine.LiveMode.Watchers.WatchersImpls

        using .pp.Engine.Executors: OptSetup, OptRun, OptScore
        using .pp.Engine.Executors: NewTrade
        using .pp.Engine.Executors: WatchOHLCV, UpdateData, InitData
        using .pp.Engine.Executors: UpdateOrders, CancelOrders

        $(@__MODULE__).Engine.Strategies.@interface
    end
end

macro contractsenv!()
    quote
        using Engine.Instances: PositionOpen, PositionUpdate, PositionClose
        using Engine.Instances: position, leverage, PositionSide
        using Engine.Executors: UpdateLeverage, UpdateMargin, UpdatePositions
    end
end

macro optenv!()
    quote
        using Engine.SimMode: SimMode as sm
        using Stats: Stats as stats
    end
end

export @environment!, @strategyenv!, @contractsenv!, @optenv!
