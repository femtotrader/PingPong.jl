module Pairs

using Misc: PairData
using StaticStrings: StaticString

@doc "A string checked to be a valid pair."
const Pair = StaticString
@doc "A string checked to be a valid quote currency."
const QuoteCurrency = StaticString
@doc "A string checked to be a valid base currency."
const BaseCurrency = StaticString

include("consts.jl")

has_punct(s::AbstractString) = !isnothing(match(r"[[:punct:]]", s))

struct Asset
    pair::Pair
    bc::BaseCurrency
    qc::QuoteCurrency
    Asset(s::AbstractString) = begin
        pair = split_pair(s)
        if length(pair) > 2 || has_punct(pair[1]) || has_punct(pair[2])
            throw(InexactError(:Asset, Asset, s))
        end
        new(
            StaticString(pair),
            StaticString(pair[1]),
            StaticString(pair[2]),
        )
    end
end


const leverage_pair_rgx =
    r"(?:(?:BULL)|(?:BEAR)|(?:[0-9]+L)|(?:[0-9]+S)|(?:UP)|(?:DOWN)|(?:[0-9]+LONG)|(?:[0-9+]SHORT))([\/\-\_\.])"

@doc "Test if pair has leveraged naming."
function is_leveraged_pair(pair)
    !isnothing(match(leverage_pair_rgx, pair))
end

@inline split_pair(pair::AbstractString) = split(pair, r"\/|\-|\_|\.")

@doc "Remove leveraged pair pre/suffixes from base currency."
function deleverage_pair(pair)
    dlv = replace(pair, leverage_pair_rgx => s"\1")
    # HACK: assume that BEAR/BULL represent BTC
    pair = split_pair(dlv)
    if pair[1] |> isempty
        "BTC" * dlv
    else
        dlv
    end
end

@doc "Check if both base and quote are fiat currencies."
function is_fiat_pair(pair)
    p = split_pair(pair)
    p[1] ∈ fiatnames && p[2] ∈ fiatnames
end

export Asset, is_fiat_pair, deleverage_pair, is_leveraged_pair

end # module Pairs
