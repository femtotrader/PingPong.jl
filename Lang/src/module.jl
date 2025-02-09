using Distributed: Distributed, @distributed
using Logging: Logging, with_logger, NullLogger
using PrecompileTools
using DocStringExtensions
using Preferences: Preferences

const Option{T} = Union{Nothing,T} where {T}

@doc "Calls PrecompileTools.@setup_workload"
macro preset(code)
    :(@setup_workload $(esc(code)))
end
@doc "Calls PrecompileTools.@compile_workload"
macro precomp(code)
    :(@compile_workload $(esc(code)))
end

@doc "Run `body` in parallel if `flag` is `true`, otherwise run sequentially."
macro parallel(flag, body)
    b = esc(body)
    db = esc(:(@distributed $body))
    quote
        if $(esc(flag))
            $db
        else
            $b
        end
    end
end

passkwargs(args...) = [Expr(:kw, a.args[1], a.args[2]) for a in args]

macro passkwargs(args...)
    kwargs = [Expr(:kw, a.args[1], a.args[2]) for a in args]
    return esc(:($(kwargs...)))
end

@doc "Returns only the keywords `kws...` from all the `kwargs`"
filterkws(kws...; kwargs, pred=∈) = begin
    ((k, v) for (k, v) in kwargs if pred(k, (kws...,)))
end

@doc "Splits the keywords `kws...` from all the `kwargs`, returning the tuple `(filtered, rest)`."
function splitkws(kws...; kwargs)
    (filtered=filterkws(kws...; kwargs), rest=filterkws(kws...; kwargs, pred=∉))
end

@doc "Returns `kwargs` without `kws...`"
withoutkws(kws...; kwargs) = splitkws(kws...; kwargs).rest

@doc """Get a value from a container that *should not contain* `nothing`, lazily evaluating the default value.
```julia
> @get Dict("a" => false) "a" (println("hello"); true)
false
> Lang.@get Dict("a" => false) "b" (println("hello"); true)
hello
true
```
"""
macro get(dict, k, expr)
    dict = esc(dict)
    expr = esc(expr)
    k = esc(k)
    :(@coalesce get($dict, $k, missing) $expr)
end

@doc "Lazy *get or set* for a container key-value pair that *should not contain* `missing`."
macro lget!(dict, k, expr)
    dict = esc(dict)
    expr = esc(expr)
    k = esc(k)
    quote
        @coalesce get($dict, $k, missing) $dict[$k] = $expr
    end
end

@doc """Get the first available key from a container, or a default (last) value.
```julia
> @multiget Dict("k" => 1) "a" "b" false
false
> @multiget Dict("k" => 1, "b" => 2) "a" "b" false
2
```
"""
macro multiget(dict, args...)
    dict = esc(dict)
    if length(args) < 2
        throw(ArgumentError("Not enough args in macro call."))
    end
    expr = esc(args[end])
    result = :(@coalesce)
    for k in args[begin:(end-1)]
        push!(result.args, :(get($dict, $(esc(k)), missing)))
    end
    push!(result.args, expr)
    result
end

@doc "Use this in loops instead of `@lget!`"
macro kget!(dict, k, expr)
    dict = esc(dict)
    expr = esc(expr)
    k = esc(k)
    quote
        if haskey($dict, $k)
            $dict[$k]
        else
            v = $expr
            $dict[$k] = v
            v
        end
    end
end

@doc "Define a new symbol with given value if it is not already defined."
macro ifundef(name, val, mod=__module__)
    name_var = esc(name)
    name_sym = esc(:(Symbol($(string(name)))))
    quote
        if isdefined($mod, $name_sym)
            $name_var = getproperty($mod, $name_sym)
        else
            $name_var = $val
        end
    end
end

macro as(sym, val)
    s = esc(sym)
    v = esc(val)
    quote
        $s = $v
        true
    end
end

@doc "`fromdict` tries to fill a _known_ `NamedTuple` from an _unknown_ `Dict`."
@generated function fromdict(tuple, key, di, kconvfunc=convert, convfunc=convert)
    params = Expr(:parameters)
    ex = Expr(:tuple, params)
    ttype = first(tuple.parameters)
    ktype = isempty(key.parameters) ? key : first(key.parameters)
    for (fi, ty) in zip(fieldnames(ttype), fieldtypes(ttype))
        p = Expr(:kw, fi, :(convfunc($ty, (di[kconvfunc($ktype, $(QuoteNode(fi)))]))))
        push!(params.args, p)
    end
    ex
end

@doc "Converts a struct into a named tuple."
function fromstruct(c::T) where {T}
    names = fieldnames(T)
    nt = NamedTuple{names,Tuple{fieldtypes(T)...}}
    t = (getfield(c, f) for f in names)
    nt(t)
end

@doc "A string literal as a symbol."
macro sym_str(s)
    :(Symbol($s))
end

@doc "A `MatchString` should be used to dispatch string specific functions with some supertype context."
struct MatchString{S<:AbstractString}
    s::S
end
@doc "A string literal as a `MatchString`."
macro m_str(s)
    :(MatchString($s))
end

_asbool(v::Bool, args...) = v
function _asbool(v::String, name)
    @something tryparse(Bool, v) occursin(name, v) v == "all"
end
function _isdebug(name)
    @something _asbool((@something get(ENV, "JULIA_DEBUG", nothing) false), name) false
end

@doc """A macro to conditionally execute code in debug mode.

$(TYPEDSIGNATURES)

If the current module is in debug mode, execute `a`, otherwise execute `b`.
"""
macro ifdebug(m, a=nothing, b=nothing)
    name = string(
        if m isa Symbol
            m
        else
            b = a
            a = m
            __module__
        end,
    )
    esc(_isdebug(name) ? a : b)
end

@doc """A macro to conditionally assert a condition in debug mode.

$(TYPEDSIGNATURES)

If the current module is in debug mode, it asserts the given condition. Optionally, it can include a custom error message msg.
"""
macro deassert(mod, condition=nothing, msg=nothing)
    name = string(
        if mod isa Symbol
            mod
        else
            msg = condition
            condition = mod
            __module__
        end,
    )
    if _isdebug(name)
        if isnothing(msg)
            quote
                @assert $(esc(condition)) $(string(condition))
            end
        else
            quote
                @assert $(esc(condition)) $(esc(msg))
            end
        end
    end
end

@doc "`errormonitor` wrapped `@async` call."
macro asyncm(expr)
    :(errormonitor(@async $(esc(expr))))
end

@doc "Sets property `prop` on object `a` to value `val` if `op(a.prop, val)` is `true`."
function ifproperty!(op, a, prop, val)
    op(getproperty(a, prop), val) && setproperty!(a, prop, val)
end
@doc "Sets key `k` on object `a` to value `val` if `op(a[k], val)` is `true`."
function ifkey!(op, a, k, val)
    op(get!(a, k, val), val) && setindex!(a, val, k)
end

@doc "Notify a condition with locks."
safenotify(cond, args...; kwargs...) = @lock cond notify(cond, args...; kwargs...)
@doc "Wait a condition with locks."
safewait(cond) = @lock cond wait(cond)
@doc "Same as `@lock` but with `acquire` and `release`."
macro acquire(cond, code)
    quote
        temp = $(esc(cond))
        Base.acquire(temp)
        try
            $(esc(code))
        catch e
            e
        finally
            Base.release(temp)
        end
    end
end

@doc """Create an IOBuffer with the given initial value `v` and execute the code in `code` block.

$(TYPEDSIGNATURES)
"""
macro buffer!(v, code)
    quote
        buf = IOBuffer($(esc(v)))
        try
            $(esc(code))
        finally
            close(buf)
        end
    end
end

@doc """Create a function `fname` that accepts `args` of type `type` and keyword arguments `kwargs` and applies the function `[fname]([args...]; kwargs...)`.

$(TYPEDSIGNATURES)
"""
macro argstovec(fname, type, outf=identity)
    fname = esc(fname)
    type = esc(type)
    quote
        $fname(args::$type...; kwargs...) = $outf($fname([args...]; kwargs...))
    end
end

@doc "Toggles a boolean property."
function toggle!(value, name)
    setproperty!(value, name, ifelse(getproperty(value, name), false, true))
end

@doc "Waits for ref to be true."
function waitref(flag::Ref)
    while !(flag[])
        sleep(0.001)
    end
end

@doc "Waits for function to return true."
function waitfunc(flag::Function)
    while !(flag())
        sleep(0.001)
    end
end

@doc "Throws if all inputs aren't positive (only in debug)."
macro posassert(args...)
    quote
        @ifdebug for a in $(esc.(args)...)
            @assert a >= 0.0
        end
    end
end

@doc """Log an error message `msg` using the logging system.

$(TYPEDSIGNATURES)
"""
macro logerror(fileexpr)
    quote
        open($(esc(fileexpr)), "a") do f
            $(@__MODULE__).@writeerror(f)
        end
    end
end

@doc """Write an error message `e` to the given file handle `filehandle` using the logging system.

$(TYPEDSIGNATURES)
"""
macro writeerror(filehandle)
    quote
        f = $(esc(filehandle))
        println(f, string($(__module__).Dates.now()))
        Base.showerror(f, $(esc(:e)))
        Base.show_backtrace(f, Base.catch_backtrace())
        flush(f)
    end
end

@doc """Get the backtrace of the current execution context as an array of `StackTraceFrame` objects.

$(TYPEDSIGNATURES)
"""
macro debug_backtrace(mod=__module__, msg="")
    file = string(__source__.file)
    line = __source__.line
    mod = esc(mod)
    msg = esc(msg)
    quote
        @debug $msg _module = $mod _file = $file _line = $line exception = (
            first(Base.catch_stack())...,
        )
    end
end

function _dedup_funcs(st::Vector{Base.StackFrame})
    fnames = NTuple{2,String}[]
    for frame in st
        name = string(frame.func)
        if occursin("#", name)
            name = split(name, "#")[2]
        end
        push!(fnames, (name, string(":", frame.line)))
    end
    unique!(x -> x[1], fnames) .|> join
end

@doc """Get a formatted string representing the call stack leading up to the current execution context.

$(TYPEDSIGNATURES)
"""
macro caller(n=4)
    quote
        let funcs = stacktrace() |> $_dedup_funcs
            if length(funcs) > 2
                join(reverse!(@view(funcs[(begin+1):min(length(funcs), $n)])), " > ")
            else
                ""
            end
        end
    end
end

@doc """Create a macro that ignores any exceptions that occur during the execution of the provided expression `expr`.

$(TYPEDSIGNATURES)

"""
macro ignore(expr)
    ex = if expr.head == :for
        body = expr.args[2]
        expr.args[2] = :(
            try
                $body
            catch
            end
        )
        quote
            try
                $expr
            catch
            end
        end
    elseif expr.head == :let
        let_vars = expr.args[1]
        quote
            try
                $(if let_vars.head == :(=)
                    (let_vars,)
                elseif isempty(let_vars.args)
                    ()
                else
                    let_vars.args
                end...)
                $(@__MODULE__).@ignore $(expr.args[2])
            catch
            end
        end
    elseif expr.head == :block
        this_expr = :(
            begin end
        )
        args = this_expr.args
        for line in expr.args
            line isa LineNumberNode && continue
            push!(args, :($(@__MODULE__).@ignore($line)))
        end
        this_expr
    else
        quote
            try
                $expr
            catch
            end
        end
    end
    esc(ex)
end

export @preset, @precomp
export @kget!, @lget!
export @passkwargs, passkwargs, filterkws, splitkws, withoutkws
export @as, @sym_str, @caller
export Option, @asyncm, @ifdebug, @deassert, @argstovec, @debug_backtrace
