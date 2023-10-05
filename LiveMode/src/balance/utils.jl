using .Executors.Instruments: AbstractCash

function _handle_bal_resp(resp)
    if resp isa PyException
        @debug "force fetch bal: error" resp
        return nothing
    elseif isdict(resp)
        return resp
    else
        @debug "force fetch bal: unhandled response" resp
        return nothing
    end
end

function _force_fetchbal(s; fallback_kwargs)
    w = balance_watcher(s)
    @debug "force fetch bal: locking w" islocked(w) f = @caller
    waslocked = islocked(w)
    @lock w begin
        waslocked && return nothing
        time = now()
        params, rest = split_params(fallback_kwargs)
        params["type"] = _ccxtbalance_type(s)
        resp = fetch_balance(s; params, rest...)
        bal = _handle_bal_resp(resp)
        isnothing(bal) && return nothing
        pushnew!(w, bal, time)
        process!(w)
    end
end

function waitforbal(
    s::LiveStrategy,
    ai,
    args...;
    force=false,
    since=nothing,
    waitfor=Second(5),
    fallback_kwargs=(),
)
    timeout = Millisecond(waitfor).value
    slept = 0
    minsleep = Millisecond(max(Second(1), waitfor))
    bal = get_balance(s)
    if isnothing(bal) && force
        while true
            bal = get_balance(s, ai)
            isnothing(bal) || break
            slept < timeout || begin
                @debug "wait bal: timedout (balance not found)" ai = raw(ai) f = @caller
                return false
            end
            sleep(minsleep)
            slept += minsleep.value
            _force_fetchbal(s; fallback_kwargs)
        end
    end

    prev_timestamp = @something bal.date[] DateTime(0)
    prev_since = @something since typemin(DateTime)
    @debug "wait bal" prev_timestamp since
    if prev_timestamp >= prev_since
        return true
    end

    this_timestamp = prev_timestamp - Millisecond(1)
    w = balance_watcher(s)
    cond = w.beacon.process
    buf = buffer(w)
    @debug "wait bal: waiting" timeout = timeout
    while true
        slept += waitforcond(cond, timeout - slept)
        if length(buf) > 0
            this_timestamp = last(buf).time
        end
        if this_timestamp >= prev_timestamp >= prev_since
            @debug "wait bal: up to date " prev_timestamp this_timestamp
            return true
        else
            @debug "wait bal:" time_left = Millisecond(timeout - slept) prev_timestamp ai = raw(
                ai
            )
        end
        slept < timeout || begin
            @debug "wait bal: timedout (balance not changed)" ai = raw(ai) f = @caller
            return false
        end
    end
end

function live_balance(
    s::LiveStrategy,
    ai=nothing;
    fallback_kwargs=(),
    since=nothing,
    force=false,
    waitfor=Second(5),
    type=nothing,
)
    bal = get_balance(s, ai, type)
    if force &&
        !islocked(balance_watcher(s)) &&
        (isnothing(bal) || (!isnothing(since)) && bal.date < since)
        _force_fetchbal(s; fallback_kwargs)
        bal = get_balance(s, ai, type)
    end
    isnothing(since) ||
        isnothing(bal) ||
        begin
            if waitforbal(s, ai; since, force, waitfor, fallback_kwargs)
            elseif force
                @debug "live bal: last force fetch"
                _force_fetchbal(s; fallback_kwargs)
            end
            bal = get_balance(s, ai, type)
            if isnothing(bal) || bal.date < since
                @error "live bal: unexpected" date = isnothing(bal) ? nothing : bal.date since f = @caller
            end
        end
    bal
end

function _live_kind(args...; kind, kwargs...)
    bal = live_balance(args...; kwargs...)
    if isnothing(bal)
        bal = zerobal()
        bal.date[] = @something since now()
    end
    getproperty(bal.balance, kind)
end

live_total(args...; kwargs...) = _live_kind(args...; kind=:total, kwargs...)
live_used(args...; kwargs...) = _live_kind(args...; kind=:used, kwargs...)
live_free(args...; kwargs...) = _live_kind(args...; kind=:free, kwargs...)

_getbaldict(s) = get(something(get_balance(s), (;)), :balance, (;))
_getval(_) = ZERO
_getval(c::AbstractCash) = c.value
_getval(ai::AssetInstance) = _getval(cash(ai))
_getbal(bal, ai::AssetInstance) = get(bal, bc(ai), (;))
_getbal(bal, c) = get(bal, nameof(c), (;))
_gettotal(bal, obj) = @get(_getbal(bal, obj), :total, _getval(obj))
function current_total(
    s::LiveStrategy{N,E,M}; price_func=lastprice, local_bal=false
) where {N,E<:ExchangeID,M<:WithMargin}
    tot = Ref(zero(DFT))
    get_amount, s_tot = if local_bal
        ((ai) -> cash(ai)), s.cash.value
    else
        let bal = _getbaldict(s), s_tot = _gettotal(bal, cash(s))
            ((ai) -> _gettotal(bal, something(cash(ai), ai))), s_tot
        end
    end
    @sync for ai in s.universe
        amount = @something get_amount(ai) zero(s_tot)
        @async let v = @something(price_func(ai), zero(s_tot)) * amount
            tot[] += v
        end
    end
    tot[] + s_tot
end

function current_total(
    s::LiveStrategy{N,E,NoMargin}; price_func=lastprice, local_bal=false
) where {N,E<:ExchangeID}
    get_amount, tot = if local_bal
        ((ai) -> cash(ai)), cash(s).value
    else
        let bal = _getbaldict(s), tot = _gettotal(bal, cash(s))
            ((ai) -> _gettotal(bal, something(cash(ai), ai))), tot
        end
    end
    @sync for ai in s.universe
        amount = @something get_amount(ai) zero(tot)
        @async let v = @something(
                try
                    price_func(ai)
                catch
                end,
                zero(tot)
            ) * amount
            # NOTE: `x += y` is rewritten as x = x + y
            # Because `price_func` can be async, the value of `x` might be stale by
            # the time `y` is fetched, and the assignment might clobber the most
            # recent value of `x`
            tot += v
        end
    end
    tot
end
