
struct Cash8{S,T} <: Number
    value::Vector{T}
    Cash8{C,N}(val) where {C,N} = new{C,N}([val])
    Cash8(s, val::R) where {R} = new{Symbol(uppercase(string(s))),R}([val])
    Cash8(_::Cash8{C,N}, val::R) where {C,N,R} = new{C,N}([convert(N, val)])
end

@doc """A variable quantity of some currency.

```julia
> ca = c"USDT"
> typeof(ca)
# Instruments.Cash{:USDT}
```

"""
Cash = Cash8
Base.nameof(_::Cash{S}) where {S} = S
Base.hash(c::Cash, h::UInt) = hash(c.name, h)
Base.setproperty!(c::Cash, ::Symbol, v::Real) = getfield(c, :value)[1] = v
Base.getproperty(c::Cash, s::Symbol) = begin
    if s === :value
        getfield(c, :value)[1]
    elseif s === :id
        c.name
    else
        getfield(c, s) ## throws
    end
end
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
prettycash(c::Cash) = begin
    val = c.value
    if val < 1e3
        "$val"
    elseif val < 1e6
        q, r = divrem(val, 1e3)
        "$(Int(q)),$(Int(r))(K)"
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
end
Base.show(io::IO, c::Cash{C}) where {C} = write(io, "$C: $(prettycash(c))")

# Base.promote(a::C, b::C) where {C<:Cash} = (a.value, b.value)
# Base.promote(c::C, n::N) where {C<:Cash,N<:Real} = (c.value, n)
# NOTE: we *demote* Cash to the other number for speed
Base.promote_rule(::Type{C}, ::Type{N}) where {C<:Cash,N<:Real} = N # C
Base.convert(::Type{Cash{S}}, c::Real) where {S} = Cash(S, c)
Base.convert(::Type{T}, c::Cash) where {T<:Real} = convert(T, c.value)
Base.isless(a::Cash{T}, b::Cash{T}) where {T} = isless(a.value, b.value)
Base.isless(a::Cash, b) = isless(promote(a, b)...)
Base.isless(b, a::Cash) = isless(promote(b, a)...)

Base.abs(c::Cash) = abs(c.value)
Base.real(c::Cash) = real(c.value)

-(a::Cash, b::Real) = a.value - b
÷(a::Cash, b::Real) = a.value ÷ b

==(a::Cash{S}, b::Cash{S}) where {S} = b.value == a.value
÷(a::Cash{S}, b::Cash{S}) where {S} = a.value ÷ b.value
*(a::Cash{S}, b::Cash{S}) where {S} = a.value * b.value
/(a::Cash{S}, b::Cash{S}) where {S} = a.value / b.value
+(a::Cash{S}, b::Cash{S}) where {S} = a.value + b.value

add!(c::Cash, v) = (getfield(c, :value)[1] += v; c)
sub!(c::Cash, v) = (getfield(c, :value)[1] -= v; c)
mul!(c::Cash, v) = (getfield(c, :value)[1] *= v; c)
rdiv!(c::Cash, v) = (getfield(c, :value)[1] /= v; c)
div!(c::Cash, v) = (getfield(c, :value)[1] ÷= v; c)
mod!(c::Cash, v) = (getfield(c, :value)[1] %= v; c)
cash!(c::Cash, v) = (getfield(c, :value)[1] = v; c)

export add!, sub!, mul!, rdiv!, div!, mod!, cash!
