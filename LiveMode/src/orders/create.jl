using .Executors: AnyLimitOrder
using .PaperMode: create_sim_limit_order
using .PaperMode.SimMode: construct_order_func
using .Executors.Instruments: AbstractAsset
using .OrderTypes: ordertype, MarketOrderType, GTCOrderType, ForcedOrderType
using .Lang: filterkws

@doc """ Creates a live order.

$(TYPEDSIGNATURES)

This function is designed to create a live order on a given strategy and asset instance.
It verifies the response from the exchange and constructs the order with the provided parameters.
If the order fails to construct and is marked as synced, it attempts to synchronize the strategy and universe cash, and then retries order creation.
Finally, if the order is marked as active, the function sets it as the active order.
"""
function create_live_order(
    s::LiveStrategy,
    resp,
    ai::AssetInstance;
    t,
    price,
    amount,
    synced=true,
    activate=true,
    skipcommit=false,
    kwargs...,
)
    if isnothing(resp)
        @warn "create order: empty response ($(raw(ai)))"
        return nothing
    end

    eid = side = type = loss = profit = date = id = nothing
    try
        eid = exchangeid(ai)
        side = @something _orderside(resp, eid) orderside(t)
        @debug "create order: parsing" _module = LogCreateOrder status = resp_order_status(resp, eid) filled = resp_order_filled(resp, eid) > ZERO id = resp_order_id(resp, eid) side
        let isopen = _ccxtisopen(resp, eid),
            hasfill = resp_order_filled(resp, eid) > ZERO,
            hasid = !isempty(resp_order_id(resp, eid))

            if !isopen && !hasfill && !hasid
                @warn "create order: refusing" isopen hasfill hasid
                return nothing
            end
        end
        this_order_type(ot) = begin
            pos = @something posside(t) posside(ai) Long()
            Order{ot{side},<:AbstractAsset,<:ExchangeID,typeof(pos)}
        end
        type = let ot = ordertype_fromccxt(resp, eid)
            if isnothing(ot)
                if t isa Type{<:Order}
                    t
                else
                    @something ordertype_fromtif(resp, eid) (if _ccxtisstatus(resp, "closed", eid)
                        MarketOrderType
                    else
                        GTCOrderType
                    end |> this_order_type)
                end
            else
                this_order_type(ot)
            end
        end
        amount = resp_order_amount(resp, eid, amount, Val(:amount); ai)
        price = resp_order_price(resp, eid, price, Val(:price); ai)
        loss = resp_order_loss_price(resp, eid)
        profit = resp_order_profit_price(resp, eid)
        date = let this_date = @something pytodate(resp, eid) now()
            # ensure order pricetime doesn't clash
            while haskey(s, ai, (; price, time=this_date), side)
                this_date += Millisecond(1)
            end
            this_date
        end
        id = @something _orderid(resp, eid) begin
            @warn "create order: missing id (default to pricetime hash)" ai = raw(ai) s = nameof(
                s
            )
            string(hash((price, date)))
        end
    catch
        @error "create order: parsing failed" resp
        @debug_backtrace LogCreateOrder
        return nothing
    end
    o = let f = construct_order_func(type)
        function create(; skipcommit)
            @debug "create order: local" _module = LogCreateOrder ai = raw(ai) id amount date type price loss profit
            f(s, type, ai; id, amount, date, type, price, loss, profit, skipcommit, kwargs...)
        end
        o = create(; skipcommit)
        if isnothing(o) && synced
            @warn "create order: can't construct (back-tracking)" id = resp_order_id(resp, eid) ai = raw(ai) cash(ai) s = nameof(s)
            o = findorder(s, ai; resp, side)
            if isnothing(o)
                @debug "create order: retrying (no commits)" _module = LogCreateOrder ai = raw(ai) side = posside(t)
                o = @lock ai create(skipcommit=true)
            end
        end
        o
    end
    if isnothing(o)
        @error "create order: failed to sync" id ai = raw(ai) cash(ai) amount s = nameof(s) type
        @debug "create order: failed sync response" _module = LogCreateOrder resp
        return nothing
    elseif activate
        set_active_order!(s, ai, o; ap=resp_order_average(resp, eid))
        # Perform a trade if the order has been filled instantly
        already_filled = resp_order_filled(resp, eid)
        if already_filled > ZERO && isempty(trades(o))
            # wait for trades watcher
            waitfortrade(s, ai, o, waitfor=s[:func_cache_ttl], force=false)
        end
        if !isequal(ai, already_filled, filled_amount(o), Val(:amount))
            emulate_trade!(s, o, ai; resp)
        end
    end
    @debug "create order: done" _module = LogCreateOrder committed(o) o.amount ordertype(o)
    return o
end

@doc """ Sends and constructs a live order.

$(TYPEDSIGNATURES)

This function sends a live order using the provided parameters and constructs it based on the response received.

"""
function create_live_order(
    s::LiveStrategy,
    ai::AssetInstance,
    args...;
    t,
    amount,
    price=lastprice(s, ai, t),
    exc_kwargs=(),
    skipchecks=false,
    kwargs...,
)
    @debug "create order: " ai = raw(ai) t price amount @caller
    resp = live_send_order(
        s, ai, t, args...; skipchecks, amount, price, withoutkws(:date; kwargs=exc_kwargs)...
    )
    create_live_order(s, resp, ai; amount, price, t, kwargs...)
end
