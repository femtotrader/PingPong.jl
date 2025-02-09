using Test
using .PingPong.Engine.Simulations.Random
using PingPongDev.Stubs
using PingPongDev.PingPong.Engine.Lang: @m_str

function emptyuni!(s)
    copysubs! = @eval da.DFUtils.copysubs!
    for ai in s.universe
        for df in values(ai.data)
            copysubs!(df, similar)
        end
    end
end

function doreset!(s)
    st.reset!(s)
    emptyuni!(s)
end

function test_paper_margin(s)
    s.config.initial_cash = 1e8
    doreset!(s)
    @test s.cash == 1e8
    @test s isa st.IsolatedStrategy
    @test execmode(s) == Paper()
    ai = s[m"eth"]
    date = now()
    this_p = lastprice(ai)
    prevcash = s.cash.value
    @info "paper: market order buy" prevcash this_p
    t = ect.pong!(
        s, ai, ot.MarketOrder{ot.Buy}; amount=0.02, price=this_p + this_p / 50.0, date
    )
    @test t isa ot.LongTrade
    @test t isa ot.BuyTrade
    @test t.amount == 0.02
    @test isapprox(prevcash - s.cash, abs(t.size), atol=s.cash.precision)
    pos = position(ai, Long())
    @test t.entryprice < inst.price(pos) ||
          isapprox(t.entryprice, inst.price(pos); atol=1e01)
    @test inst.isopen(pos)
    @test !inst.isopen(position(ai, Short()))
    @test cash(pos) ≈ 0.02
    @test t.value ≈ inst.notional(pos) atol = 1e-1
    @test trunc(t.size + t.fees) == Base.negate(trunc(inst.notional(pos)))
    @test pos.timestamp[] == date == t.date
    @test pos.asset == ai.asset
    @test inst.additional(pos) == 0.0
    @test inst.leverage(pos) == s[:def_lev] == t.leverage
    @test cash(pos) >= pos.min_size
    @test pos.hedged == false
    date += Minute(1)
    prevcash = s.cash.value
    @info "TEST: paper market sell" prevcash cash(ai)
    t = ect.pong!(s, ai, ot.MarketOrder{ot.Sell}; amount=0.011, date)
    @test t isa ot.LongTrade
    @test t isa ot.SellTrade
    @test cash(pos) == 0.009
    @test pos.timestamp[] == date
    @test isapprox(s.cash.value - prevcash, t.value - t.fees, atol=1e-1)
    prev_cash = s.cash.value
    lpr = lastprice(ai)
    ai_pnl = inst.pnl(ai, Long(), lpr)
    ai_margin = inst.margin(ai, Long()) + inst.additional(ai, Long())
    ect.pong!(s, ai, Long(), now(), ect.PositionClose())
    @test ai_margin <= 1e8
    @test iszero(ai)
    @test !isopen(pos)
    @test iszero(s.cash_committed)
    @test s.cash - prev_cash ≈ ai_margin + ai_pnl atol = 1e-1
    trade = last(ai.history)
    @test trade.value >= s.cash - prev_cash || trade.price < lpr
    @test ect.pong!(s, ai, 1.2, ect.UpdateLeverage(); pos=Long())
    @test inst.leverage(pos) == 1.2
    this_p = lastprice(ai)
    t = ect.pong!(
        s, ai, ot.GTCOrder{ot.Buy}; amount=0.02, price=this_p - this_p / 2.0, date
    )
    @test ect.orderscount(s, ai) == length(s[:paper_order_tasks])
    @test !(t isa ot.Trade)
    _, taken_vol, total_vol = st.attr(s, :paper_liquidity)[ai]
    date += Millisecond(1)
    prev_taken = taken_vol[]
    t = ect.pong!(
        s,
        ai,
        ot.GTCOrder{ot.Buy};
        amount=total_vol[] / 100.0,
        price=this_p + this_p / 2.0,
        date,
    )
    @test t isa ot.Trade
    @test !ect.isfilled(ai, t.order) || cash(ai) == t.order.amount
    @test taken_vol[] > prev_taken
    prev_cash = cash(ai)
    pos_price = inst.price(ai, this_p, Long)
    @test this_p != pos_price || this_p == t.price
    prev_count = ect.orderscount(s, ai)
    ect.cash!(s.cash, this_p * total_vol[])
    t = ect.pong!(
        s,
        ai,
        ot.GTCOrder{ot.Buy};
        amount=total_vol[] / 10.0,
        price=this_p + this_p / 100.0,
        date,
    )
    @test cash(ai) == prev_cash || t isa ot.Trade
    @test if t isa ot.Trade
        length(ot.trades(t.order)) > 0
    else
        @test ismissing(t)
        o = first(ect.orders(s, ai, Buy))
        !ect.isfilled(ai, o)
    end
    @test ect.orderscount(s, ai) - 1 == prev_count
    @test ect.orderscount(s, ai) == length(s[:paper_order_tasks])
    @test !ect.pong!(s, ai, 1.0, ect.UpdateLeverage(); pos=Long())
    ect.pong!(s, ai, ect.CancelOrders())
    @test ect.orderscount(s, ai) == 0 == length(s[:paper_order_tasks])
    @test !ect.pong!(s, ai, 1.1, ect.UpdateLeverage(); pos=Long())
    @test ect.pong!(s, ai, 1.1, ect.UpdateLeverage(); pos=Short())
    @test inst.leverage(ai, Short()) == 1.1
    date += Millisecond(1)
    t = ect.pong!(s, ai, ot.FOKOrder{ot.Buy}; amount=total_vol[] / 10.0, date)
    @test isnothing(t)
    t = ect.pong!(
        s,
        ai,
        ot.IOCOrder{ot.Buy};
        amount=total_vol[] / 10.0,
        price=this_p + this_p / 2.0,
        date,
    )
    @test t isa ot.Trade
    @test !ect.isfilled(ai, t.order)
end

function test_paper_nomargin_market(s)
    doreset!(s)
    @test execmode(s) == Paper()
    ai = s[m"eth"]
    date = now()
    prev_cash = s.cash.value
    t = ect.pong!(s, ai, ot.MarketOrder{ot.Buy}; amount=0.02, date)
    @test t isa ot.Trade
    @test t.amount ≈ 0.02 atol = 1e-1
    @test s.cash + abs(t.size) ≈ prev_cash atol = 1e-1
    @test iszero(s.cash_committed)
    @test cash(ai) ≈ 0.02
    t = ect.pong!(s, ai, ot.MarketOrder{ot.Sell}; amount=0.021, date)
    @test isnothing(t)
    t = ect.pong!(s, ai, ot.MarketOrder{ot.Sell}; amount=0.01, date)
    @test t isa ot.Trade
    @test t.amount ≈ 0.01 atol = 1e-1
    @test ai.cash ≈ 0.01
    t = ect.pong!(s, ai, ot.MarketOrder{ot.Sell}; amount=0.03, date)
    @test isnothing(t)
    @test ai.cash ≈ 0.01
    date = now()
    t = ect.pong!(s, ai, ot.MarketOrder{ot.Sell}; amount=ai.cash.value, date)
    @test t isa ot.Trade
    @test t.date == date
    @test iszero(ai.cash)
end

function test_paper_nomargin_gtc(s)
    s.config.initial_cash = 1e8
    doreset!(s)
    @test execmode(s) == Paper()
    @test s isa st.NoMarginStrategy
    ai = s[m"eth"]
    date = now()
    # prev_cash = s.cash.value
    # @info "TEST: paper pong buy (last price)"
    # ect.pong!(s, ai, ot.GTCOrder{ot.Buy}; amount=0.02, date)
    # @test length(collect(ect.orders(s, ai))) == 1 || length(ai.history) > 0
    # o = if length(ai.history) > 0
    #     last(ai.history).order
    # else
    #     first(values(ect.orders(s, ai, ot.Buy)))
    # end
    # if haskey(s[:paper_order_tasks], o)
    #     task, alive = s[:paper_order_tasks][o]
    #     @test istaskdone(task) || alive[]
    #     wait(task)
    # end
    # @test ect.isfilled(ai, last(ai.history).order)
    # @test s.cash <= prev_cash
    # @test !ect.iszero(cash(ai, Long()))
    # date = now()
    # prev_cash = s.cash.value
    this_p = lastprice(ai)
    # @info "TEST: paper pong sell"
    # t = ect.pong!(
    #     s, ai, ot.GTCOrder{ot.Sell}; amount=0.01, price=this_p - this_p / 100.0, date
    # )
    # if haskey(st.attr(s, :paper_order_tasks), o)
    #     task, alive = st.attr(s, :paper_order_tasks)[o]
    #     @test istaskdone(task) || !alive[]
    #     wait(task)
    # end
    # @test ect.isfilled(ai, last(ai.history).order)
    # @test s.cash >= prev_cash
    # @test !ect.iszero(cash(ai, Long())) && cash(ai, Long()) < 0.02

    _, taken_vol, total_vol = pm._paper_liquidity(s, ai)
    @info "TEST: paper pong buy 2 (price below)"
    t = ect.pong!(
        s,
        ai,
        ot.GTCOrder{ot.Buy};
        amount=total_vol[] / 100.0,
        price=this_p + this_p / 100000.0,
        date,
    )
    @test !isnothing(t)
    o = ismissing(t) ? last(ect.orders(s, ai, Buy)).second : t.order
    if !ect.isfilled(ai, o)
        o = first(ect.orders(s, ai, ot.Buy))[2]
        prev_len = length(o.attrs.trades)
        start_mon = now()
        was_filled = false
        if !ect.isfilled(ai, o)
            while now() - start_mon < Second(10)
                sleep(1)
                if length(o.attrs.trades) > prev_len
                    was_filled = true
                    break
                end
            end
        end
        @test ect.isfilled(ai, o) ||
              length(o.attrs.trades) > prev_len ||
              lastprice(ai) >= o.price * 0.999
    end
    amount = total_vol[] / 100.0
    price = this_p * 2.0
    date += Millisecond(1)
    this_vol = 0.0
    @info "TEST: paper pong buy loop"
    while taken_vol[] + amount < total_vol[] * 0.9
        t = ect.pong!(s, ai, ot.GTCOrder{ot.Buy}; amount, price, date)
        if t isa ot.Trade
            # @info "TEST: paper pong " taken_vol[] total_vol[]
            this_vol += t.amount
        else
            price *= 1.1
            price = min(ai.limits.cost.max, price)
        end
        date += Millisecond(1)
        yield()
    end
    n_orders = ect.orderscount(s, ai)
    @info "TEST: paper pong buy 3"
    t = ect.pong!(
        s, ai, ot.GTCOrder{ot.Buy}; amount=total_vol[] / 100.0, price=this_p, date
    )
    if !isnothing(t)
        @test n_orders < ect.orderscount(s, ai)
    else
        @test n_orders == ect.orderscount(s, ai)
    end
    @test s.cash < s.initial_cash - this_vol * this_p
end

function test_paper_nomargin_ioc(s)
    s.config.initial_cash = 1e8
    doreset!(s)
    @test execmode(s) == Paper()
    @test s isa st.NoMarginStrategy
    ai = s[m"eth"]
    date = now()
    prev_cash = s.cash.value
    this_p = lastprice(ai)
    t = ect.pong!(
        s, ai, ot.IOCOrder{ot.Buy}; amount=0.01, price=this_p + this_p / 100.0, date
    )
    _, _, total_vol = st.attr(s, :paper_liquidity)[ai]
    @test t isa ot.Trade
    @test ot.isimmediate(t.order)
    @test t.amount ≈ 0.01
    @test ect.isfilled(ai, t.order)
    @test ect.orderscount(s, ai) == 0
    ai_unlimited = similar(
        ai;
        limits=(;
            ai.limits.leverage, ai.limits.amount, ai.limits.price, cost=(min=1.0, max=Inf)
        ),
    )
    t = ect.pong!(
        s,
        ai_unlimited,
        ot.IOCOrder{ot.Buy};
        amount=total_vol[] / 2.0,
        price=this_p + this_p / 100.0,
        date,
    )
    @test t isa ot.Trade
    @test ot.isimmediate(t.order)
    o = t.order
    @test ect.orderscount(s, ai_unlimited) == 0
    @test length(o.attrs.trades) == 0 || ect.unfilled(o) < o.amount
    @test o.amount - ect.unfilled(o) < total_vol[]
    @test s.cash < prev_cash
end

function test_paper_nomargin_fok(s)
    s.config.initial_cash = 1e8
    doreset!(s)
    @test s isa st.NoMarginStrategy
    @test execmode(s) == Paper()
    ai = s[m"eth"]
    date = now()
    prev_cash = s.cash.value
    this_p = lastprice(ai)
    t = ect.pong!(
        s, ai, ot.FOKOrder{ot.Buy}; amount=0.01, price=this_p + this_p / 50.0, date
    )
    @test ot.isimmediate(t.order)
    @test t isa ot.BuyTrade
    @test ect.isfilled(ai, t.order)
    @test s.cash < prev_cash
    prev_cash = s.cash.value
    sell_price = this_p - this_p / 50.0
    t = ect.pong!(
        s, ai, ot.FOKOrder{ot.Sell}; amount=cash(ai).value, price=sell_price, date
    )
    @test ot.isimmediate(t.order)
    @test t isa ot.SellTrade
    @test t.price >= sell_price
    @test ect.isfilled(ai, t.order)
    @test s.cash > prev_cash
    @test iszero(ai)
    _, _, total_vol = st.attr(s, :paper_liquidity)[ai]
    ai_unlimited = similar(
        ai;
        limits=(;
            ai.limits.leverage, ai.limits.amount, ai.limits.price, cost=(min=1.0, max=Inf)
        ),
    )
    n_trades = length(ai_unlimited.history)
    t = ect.pong!(
        s,
        ai_unlimited,
        ot.FOKOrder{ot.Buy};
        amount=total_vol[],
        price=this_p + this_p / 100.0,
        date,
    )
    @test ect.orderscount(s, ai_unlimited) == 0
    @test isnothing(t)
    @test iszero(ai_unlimited)
    @test n_trades == length(ai_unlimited.history)
end

function test_paper()
    @eval begin
        using PingPongDev
        using .PingPong
        PingPong.@environment!
    end
    s = @eval backtest_strat(:Example; exchange=EXCHANGE, config_attrs=(; skip_watcher=true), mode=Paper())
    try
        @testset failfast = FAILFAST "paper" begin
            # try
            #     @info "TEST: paper nomargin market"
            #     @testset test_paper_nomargin_market(s)
            #     @info "TEST: paper nomargin gtc"
            #     @testset test_paper_nomargin_gtc(s)
            #     @info "TEST: paper nomargin ioc"
            #     @testset test_paper_nomargin_ioc(s)
            #     @info "TEST: paper nomargin fok"
            #     @testset test_paper_nomargin_fok(s)
            # finally
            #     stop!(s)
            #     reset!(s)
            # end

            s = @eval backtest_strat(
                :ExampleMargin; exchange=EXCHANGE_MM, config_attrs=(; skip_watcher=true), mode=Paper()
            )
            try
                @testset test_paper_margin(s)
            finally
                stop!(s)
                reset!(s)
            end
        end
    finally
        stop!(s)
    end
end
