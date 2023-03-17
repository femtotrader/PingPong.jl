module Backtest
using Misc
using Processing.Alignments
using ..Executors: Executors
using ..Executors.Engine.Types
using ..Executors.Engine.Strategies: Strategy, ping!, reset!, WarmupPeriod
using ..Executors.Engine.Simulations: Simulations as sim

@doc """Backtest a strategy `strat` using context `ctx` iterating according to the specified timeframe.

On every iteration, the strategy is queried for the _current_ timestamp.
The strategy should only access data up to this point.
Example:
- Timeframe iteration: `1s`
- Strategy minimum available timeframe `1m`
Iteration gives time `1999-12-31T23:59:59` to the strategy:
The strategy (that can only lookup up to `1m` precision)
looks-up data until the timestamp `1999-12-31T23:58:00` which represents the
time until `23:59:00`.
Therefore we have to shift by one period down, the timestamp returned by `apply`:
```julia
julia> t = TimeTicks.apply(tf"1m", dt"1999-12-31T23:59:59")
1999-12-31T23:59:00 # we should not access this timestamp
julia> t - tf"1m".period
1999-12-31T23:58:00 # this is the correct candle timestamp that we can access
```
To avoid this mistake, use the function `available(::TimeFrame, ::DateTime)`, instead of apply.
"""
function backtest!(s::Strategy, ctx::Context; trim_universe=false, doreset=true)
    # ensure that universe data start at the same time
    if trim_universe
        let data = flatten(s.universe)
            !check_alignment(data) && trim!(data)
        end
    end
    if doreset
        reset(ctx.range, ctx.range.start + ping!(s, WarmupPeriod()))
        reset!(s)
    end
    ordersdefault!(s)
    for date in ctx.range
        ping!(s, date, ctx)
    end
    s
end

@doc "Backtest with context of all data loaded in the strategy universe."
backtest!(strat; kwargs...) = backtest!(strat, Context(strat); kwargs...)

export backtest!

end
