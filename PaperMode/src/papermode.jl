using SimMode
using Executors
using Base: SimpleLogger, with_logger
using Executors: orders, orderscount
using Executors.OrderTypes
using Executors.TimeTicks
using Executors.Instances
using Executors.Misc
using Executors.Instruments: compactnum as cnum
using .Misc.ConcurrentCollections: ConcurrentDict
using .Misc.TimeToLive: safettl
using .Misc.Lang: @lget!, @deassert, Option, @logerror
using Executors.Strategies: MarginStrategy, Strategy, Strategies as st, ping!
using Executors.Strategies
using .Instances: MarginInstance
using .Instances.Exchanges: CcxtTrade
using .Instances.Data.DataStructures: CircularBuffer
using SimMode: AnyMarketOrder, AnyLimitOrder
import Executors: pong!
using Fetch: pytofloat

const TradesCache = Dict{AssetInstance,CircularBuffer{CcxtTrade}}()

function paper!(s::Strategy{Paper}; throttle=Second(5), doreset=false, foreground=true)
    if doreset
        st.reset!(s)
    elseif :paper_running ∉ keys(s.attrs) # only set defaults on first run
        ordersdefault!(s)
    end
    startinfo = "Starting strategy $(nameof(s)) in paper mode!

    throttle: $throttle
    timeframes: $(string(s.timeframe)) (main), $(string(get(s.attrs, :timeframe, nothing))) (optional), $(join(string.(s.config.timeframes), " ")...) (extras)
    cash: $(s.cash) [$(cnum(st.current_total(s, lastprice)))]
    assets: $(let str = join(getproperty.(st.assets(s), :raw), ", "); str[begin:min(length(str), displaysize()[2] - 1)] end)
    margin: $(marginmode(s))
    "
    infofunc =
        () -> begin
            long, short, liq = st.trades_count(s, Val(:positions))
            cv = cnum(s.cash.value)
            comm = cnum(s.cash_committed.value)
            inc = orderscount(s, Val(:increase))
            red = orderscount(s, Val(:reduce))
            tot = st.current_total(s, lastprice) |> cnum
            @info "$(now())($(nameof(s))@$(s.exchange)) $comm/$cv[$tot]($(nameof(s.cash))), orders: $inc/$red(+/-) trades: $long/$short/$liq(L/S/Q)"
        end
    doping(loghandle) = begin
        @info startinfo
        name = nameof(s)
        last_flush = DateTime(0)
        paper_running = attr(s, :paper_running)
        @assert isassigned(paper_running)
        try
            while paper_running[]
                infofunc()
                now() - last_flush > Second(1) && flush(loghandle)
                last_flush = now()
                try
                    ping!(s, now(), nothing)
                catch e
                    @logerror loghandle
                end
                sleep(throttle)
            end
        finally
            paper_running[] = false
        end
    end
    s[:paper_running] = Ref(true)
    if foreground
        s[:paper_task] = nothing
        doping(stdout)
    else
        logfile = paperlog(s)
        loghandle = open(logfile, "w")
        logger = SimpleLogger(open(logfile, "w"))
        try
            s[:paper_task] = @async with_logger(logger) do
                doping(loghandle)
            end
        finally
            flush(loghandle)
            close(loghandle)
        end
    end
end

function paperstop!(s::PaperStrategy)
    running = attr(s, :paper_running, nothing)
    task = attr(s, :paper_task, nothing)
    if isnothing(running)
        @assert isnothing(task) || istaskdone(task)
    else
        @assert running[] || istaskdone(task)
    end
    v[1][] = false
    wait(v[2])
end

function paperlog(s)
    get!(s.attrs, :logfile, st.logpath(s; name="paper"))
end

export paper!, paperstop!

include("utils.jl")
include("orders/utils.jl")
include("orders/state.jl")
include("orders/limit.jl")
include("orders/pong.jl")
include("positions/pong.jl")
