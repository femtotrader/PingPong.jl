import Fetch.Exchanges.ExchangeTypes: exchange, exchangeid

exchange(w::Watcher) = get(getfield(w, :attrs), :exc, nothing)
exchangeid(w::Watcher) =
    let e = exchange(w)
        isnothing(e) ? nothing : nameof(e)
    end

@doc "Delete watcher data from storage backend within the date range specified."
function Base.deleteat!(w::Watcher, range::DateTuple)
    _deleteat!(w, w._val; from=range.start, to=range.stop)
end

@doc "Flush the watcher. If wait is `true`, block until flush completes."
function flush!(w::Watcher; force=true, sync=false)
    time_now = now()
    if force || time_now - w.last_flush > w.interval.flush
        t = @async begin
            result = @lock w._exec.buffer_lock begin
                w.last_flush = time_now
                _flush!(w, w._val)
            end
            ifelse(result isa Exception, logerror(w, result), result)
        end
    end
    sync && wait(t)
    nothing
end
@doc "Fetches a new value from the watcher ignoring the timer. If `reset` is `true` the timer is reset and
polling will resume after the watcher `interval`."
function fetch!(w::Watcher; reset=false, kwargs...)
    try
        _schedule_fetch(w, w.interval.timeout, w._exec.threads; kwargs...)
        reset && _timer!(w)
    catch e
        logerror(w, e, stacktrace(catch_backtrace()))
    finally
        return isempty(w.buffer) ? nothing : last(w.buffer).value
    end
end

function process!(w::Watcher, args...; kwargs...)
    @logerror w _process!(w, w._val, args...; kwargs...)
end
load!(w::Watcher, args...; kwargs...) = _load!(w, w._val, args...; kwargs...)
init!(w::Watcher, args...; kwargs...) = _init!(w, w._val, args...; kwargs...)
@doc "Add `v` to the things the watcher is fetching."
function Base.push!(w::Watcher, v, args...; kwargs...)
    _push!(w, w._val, v, args...; kwargs...)
end
@doc "Remove `v` from the things the watcher is fetching."
function Base.pop!(w::Watcher, v, args...; kwargs...)
    _pop!(w, w._val, v, args...; kwargs...)
end

@doc "True if last available data entry is older than `now() + fetch_interval + fetch_timeout`."
function isstale(w::Watcher)
    w.attempts > 0 ||
        w.last_fetch < now() - w.interval.fetch_interval - w.interval.fetch_timeout
end
Base.last(w::Watcher) = last(w.buffer)
Base.length(w::Watcher) = length(w.buffer)
function Base.close(w::Watcher; doflush=true) # @lock w._exec.fetch_lock begin
    l = w._exec.fetch_lock
    if trylock(l)
        try
            isstopped(w) || stop!(w)
            doflush && flush!(w)
            let name = w.name
                haskey(WATCHERS, name) && delete!(WATCHERS, name)
            end
            nothing
        finally
            unlock(l)
        end
    else
        w._stop = true
    end
end
Base.empty!(w::Watcher) = empty!(w.buffer)
Base.getproperty(w::Watcher, p::Symbol) = begin
    if p == :view
        Base.get(w)
    else
        getfield(w, p)
    end
end
@doc "Stops the watcher timer."
stop!(w::Watcher) = begin
    @assert isstarted(w) "Tried to stop an already stopped watcher."
    Base.close(w._timer)
    _stop!(w, w._val)
    nothing
end
@doc "Resets the watcher timer."
start!(w::Watcher) = begin
    @assert isstopped(w) "Tried to start an already started watcher."
    empty!(w._exec.errors)
    _start!(w, w._val)
    _timer!(w)
    w._stop = false
    nothing
end
@doc "True if timer is not running."
isstopped(w::Watcher) = isnothing(w._timer) || !isopen(w._timer)
@doc "True if timer is running."
isstarted(w::Watcher) = !isnothing(w._timer) && isopen(w._timer)

function Base.show(out::IO, w::Watcher)
    tps = "$(typeof(w))"
    write(out, "$(length(w.buffer))-element ")
    if length(tps) > 80
        write(out, @view(tps[begin:40]))
        write(out, "...")
        write(out, @view(tps[(end - 40):end]))
    else
        write(out, tps)
    end
    write(out, "\nName: ")
    write(out, w.name)
    write(out, "\nIntervals: ")
    write(out, "$(compact(w.interval.timeout))(TO)")
    write(out, ", $(compact(w.interval.fetch))(FE)")
    write(out, ", $(compact(w.interval.flush))(FL)")
    write(out, "\nFetched: ")
    write(out, "$(w.last_fetch) busy: $(islocked(w._exec.fetch_lock))")
    write(out, "\nFlushed: ")
    write(out, "$(w.last_flush)")
    write(out, "\nActive: ")
    write(out, "$(isstarted(w))")
    write(out, "\nAttemps: ")
    write(out, "$(w.attempts)")
    e = lasterror(w)
    if !isnothing(e)
        write(out, "\nErrors: ")
        Base.show_backtrace(out, e[2])
        # avoid recursion
        if isempty(Base.catch_stack())
            Base.showerror(out, e[1])
        end
    end
end
Base.display(w::Watcher) =
    try
        buf = IOBuffer()
        show(buf, w)
        Base.println(String(take!(buf)))
    catch
        close(buf)
    end
