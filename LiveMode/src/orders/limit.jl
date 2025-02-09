@doc """ Places a limit order and waits for its completion.

$(TYPEDSIGNATURES)

This function creates a live limit order and then waits for it to either be filled or cancelled, depending on the waiting time provided.
It handles immediate orders differently, in such cases it waits for the order to be closed.
If an order fails or is cancelled, the function returns the relevant status.

"""
function _live_limit_order(s::LiveStrategy, ai, t; skipchecks=false, amount, price, waitfor, synced, kwargs)
    # NOTE: necessary locks to prevent race conditions between balance/positions updates
    # and order creation
    @lock ai @lock s begin
        o = create_live_order(s, ai; skipchecks, t, amount, price, exc_kwargs=kwargs)
        isnothing(o) && return nothing
        order_trades = attr(o, :trades)
        @debug "pong limit order: waiting" _module = LogCreateOrder waitfor
        @timeout_start
        # if immediate should wait for the order to be closed
        if isimmediate(o)
            if waitfororder(s, ai, o; waitfor=@timeout_now) && !isempty(order_trades)
                last(order_trades)
            else
                synced && _force_fetchtrades(s, ai, o)
                if isempty(order_trades)
                    if haskey(s, ai, pricetime(o))
                        missing
                    else
                        @debug "pong limit order: immediate order failed" _module = LogCreateOrder o.id
                    end
                else
                    last(order_trades)
                end
            end
        elseif !isempty(order_trades)
            last(order_trades)
            # otherwise wait a little in case the there is already a fill for the gtc order
        elseif waitfortrade(s, ai, o; waitfor=@timeout_now)
            last(order_trades)
        elseif haskey(s, ai, o)
            synced && _force_fetchtrades(s, ai, o)
            if isempty(order_trades)
                @debug "pong limit order: no trades yet" _module = LogCreateOrder synced
                missing
            else
                last(order_trades)
            end
        else
            @debug "pong limit order: cancelled or failed" _module = LogCreateOrder
        end
    end
end
