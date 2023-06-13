using Lang: @deassert, @ifdebug
using Misc: ATOL
abstract type AbstractCash <: Number end

@doc """A variable quantity of some currency.
```julia
> ca = c"USDT"
> typeof(ca)
# Instruments.Cash{:USDT}
```

"""
struct Cash{S,T} <: AbstractCash
    value::Vector{T}
    Cash{C,N}(val) where {C,N} = new{C,N}([val])
    Cash(s, val::R) where {R} = new{Symbol(uppercase(string(s))),R}([val])
    function Cash(_::Cash{C,N}, val::R) where {C,N,R}
        new{C,N}([convert(eltype(N), val)])
    end
end

cash(args...; kwargs...) = error("not implemented")
freecash(args...; kwargs...) = error("not implemented")
_fvalue(c::Cash) = getfield(c, :value)
value(c::Cash) = _fvalue(c)[]
Base.nameof(_::Cash{S}) where {S} = S
Base.hash(c::Cash, h::UInt) = hash(nameof(c), h)
Base.setproperty!(::Cash, ::Symbol, v) = error("Cash is private.")
Base.getproperty(c::Cash, s::Symbol) = begin
    if s === :value
        value(c)
    elseif s === :id
        nameof(c)
    else
        getfield(c, s) ## throws
    end
end
Base.zero(::Union{C,Type{C}}) where {C<:Cash{S where S,T}} where {T} = zero(T)
Base.iszero(c::Cash{<:Any,T}) where {T} = isapprox(value(c), zero(T); atol=ATOL)

@doc """Macro to instantiate `Cash` statically.

Don't put spaces between the id and the value.

```julia
> ca = c"USDT"1000
USDT: 1000.0
```
"""
macro c_str(sym, val=0.0)
    :($(Cash(Symbol(sym), val)))
end
compactnum(val::Number) =
    if val < 1e-12
        "$(round(val, digits=3))"
    elseif val < 1e-9
        q, r = divrem(val, 1e-10)
        "$(Int(q)),$(round(Int, r))(n)"
    elseif val < 1e-6
        q, r = divrem(val, 1e-7)
        "$(Int(q)),$(round(Int, r))(μ)"
    elseif val < 1e-2
        q, r = divrem(val, 1e-4)
        "$(Int(q)),$(round(Int, r))(m)"
    elseif val < 1e3
        "$(round(val, digits=3))"
    elseif val < 1e6
        q, r = divrem(val, 1e3)
        "$(Int(q)),$(round(Int, r))(K)"
    elseif val < 1e9
        q, r = divrem(val, 1e6)
        r /= 1e3
        "$(Int(q)),$(round(Int, r))(M)"
    elseif val < 1e12
        q, r = divrem(val, 1e9)
        r /= 1e6
        "$(Int(q)),$(round(Int, r))(B)"
    elseif val < 1e15
        q, r = divrem(val, 1e12)
        r /= 1e9
        "$(Int(q)),$(round(Int, r))(T)"
    elseif val < 1e18
        q, r = divrem(val, 1e15)
        r /= 1e12
        "$(Int(q)),$(round(Int, r))(Q)"
    else
        "$val"
    end

compactnum(c::Cash) = compactnum(value(c))
compactnum(val, n) = split(compactnum(val), ".")[n]
compactnum(s) = string(s)
Base.string(c::Cash{C}) where {C} = "$C: $(compactnum(c.value))"
Base.show(io::IO, c::Cash) = write(io, string(c))

leaq(a, b) = a <= b || isapprox(a, b; atol=ATOL)
⪅(a::T, b::T) where {T<:AbstractCash} = leaq(value(a), value(b))
⪅(a::T, b::N) where {T<:AbstractCash,N<:Real} = leaq(value(a), b)
⪅(a::N, b::T) where {T<:AbstractCash,N<:Real} = leaq(a, value(b))
⪆(a, b) = b ⪅ a

# Base.promote(a::C, b::C) where {C<:Cash} = (a.value, b.value)
Base.promote(c::C, n::N) where {C<:Cash,N<:Real} = (value(c), n)
Base.promote(n::N, c::C) where {C<:Cash,N<:Real} = (n, value(c))
# NOTE: we *demote* Cash to the other number for speed (but it still slower than dispatching promotion function directly)
# Base.promote_rule(::Type{C}, ::Type{N}) where {C<:Cash,N<:Real} = N # C
Base.convert(::Type{Cash{S}}, c::Real) where {S} = Cash(S, c)
Base.convert(::Type{T}, c::Cash) where {T<:Real} = convert(T, value(c))
Base.isless(a::Cash{T}, b::Cash{T}) where {T} = isless(value(a), value(b))
Base.isless(a::Cash, b::Number) = isless(promote(a, b)...)
Base.isless(b::Number, a::Cash) = isless(promote(b, a)...)

Base.abs(c::Cash) = abs(value(c))
Base.real(c::Cash) = real(value(c))

-(a::Cash, b::Real) = value(a) - b
÷(a::Cash, b::Real) = value(a) ÷ b
/(a::Cash, b::Real) = value(a) / b

==(a::Cash{S}, b::Cash{S}) where {S} = value(b) == value(a)
÷(a::Cash{S}, b::Cash{S}) where {S} = value(a) ÷ value(b)
*(a::Cash{S}, b::Cash{S}) where {S} = value(a) * value(b)
/(a::Cash{S}, b::Cash{S}) where {S} = value(a) / value(b)
+(a::Cash{S}, b::Cash{S}) where {S} = value(a) + value(b)
-(a::Cash{S}, b::Cash{S}) where {S} = value(a) - value(b)
function Base.isapprox(a::C, b::C; kwargs...) where {C<:AbstractCash}
    isapprox(value(a), value(b); atol=ATOL, kwargs...)
end

const mylock = Base.ReentrantLock()

add!(c::Cash, v, args...; kwargs...) = (_fvalue(c)[] += v; c)
sub!(c::Cash, v, args...; kwargs...) = (_fvalue(c)[] -= v; c)
function atleast!(c::AbstractCash, v=zero(c), args...; atol=ATOL, kwargs...)
    let val = value(c)
        if val > v
            c
        elseif isapprox(val, v; atol)
            cash!(c, v)
        else
            @ifdebug -atol < value(c) < atol || begin
                @debug value(c)
                # st = stacktrace()
                # throw(st[5])
                # Base.show_backtrace(stdout, st[1:min(lastindex(st), 10)])
            end
            throw("$(val) <  $(value(v)) + $atol")
        end
    end
end
@doc "Add v to cash, approximating to zero if cash is a small value."
addzero!(c::Cash, v, args...; kwargs...) = begin
    add!(c, v)
    atleast!(c; kwargs...)
    @deassert c >= 0.0 v
    c
end
@doc "Sub v to cash, approximating to zero if cash is a small value."
subzero!(c::AbstractCash, v, args...; kwargs...) = addzero!(c, -v; kwargs...)
mul!(c::Cash, v, args...; kwargs...) = (_fvalue(c)[] *= v; c)
rdiv!(c::Cash, v, args...; kwargs...) = (_fvalue(c)[] /= v; c)
div!(c::Cash, v, args...; kwargs...) = (_fvalue(c)[] ÷= v; c)
mod!(c::Cash, v, args...; kwargs...) = (_fvalue(c)[] %= v; c)
cash!(c::Cash, v, args...; kwargs...) = (_fvalue(c)[] = v; c)

export value, cash

@doc """Cash should not be edited by a strategy, therefore functions that mutate its value should be
explicitly imported.
"""
macro importcash!()
    quote
        import .Instruments: add!, sub!, subzero!, mul!, rdiv!, div!, mod!, cash!
    end
end
