## Strategy interface
@doc "Called on each timestep iteration, possible multiple times.
Receives:
- `current_time`: the current timestamp to evaluate (the current candle would be `current_time - timeframe`).
- `ctx`: The context of the executor.
"
ping!(::Strategy, current_time, ctx, args...; kwargs...) = error("Not implemented")
const evaluate! = ping!
struct LoadStrategy <: ExecAction end
@doc "Called to construct the strategy, should return the strategy instance."
ping!(::Type{<:Strategy}, ::LoadStrategy, ctx) = nothing
struct WarmupPeriod <: ExecAction end
@doc "How much lookback data the strategy needs."
ping!(s::Strategy, ::WarmupPeriod) = s.timeframe.period

macro interface()
    quote
        import Engine.Strategies: ping!, evaluate!
        using Engine.Strategies: assets, exchange
        using Engine: pong!, execute!
    end
end
