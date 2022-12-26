import Base: length, iterate, collect
const OptDate = Union{Nothing,DateTime}
struct DateRange12
    current_date::Vector{OptDate}
    start::OptDate
    stop::OptDate
    step::Union{Nothing,Period}
    function DateRange12(start::OptDate, stop::OptDate, step=nothing)
        begin
            new([start], start, stop, step)
        end
    end
    function DateRange12(start::OptDate, stop::OptDate, tf::TimeFrame)
        begin
            new([start], start, stop, tf.period)
        end
    end
end
DateRange = DateRange12

Base.show(dr::DateRange) = begin
    Base.print("start: $(dr.start)\nstop:  $(dr.stop)\nstep:  $(dr.step)")
end
Base.display(dr::DateRange) = Base.show(dr)
iterate(dr::DateRange) = begin
    @assert !isnothing(dr.start) && !isnothing(dr.stop)
    dr.current_date[1] = dr.start + dr.step
    (dr.start, dr)
end

iterate(dr::DateRange, ::DateRange) = begin
    now = dr.current_date[1]
    dr.current_date[1] += dr.step
    dr.current_date[1] > dr.stop && return nothing
    (now, dr)
end

length(dr::DateRange) = begin
    (dr.stop - dr.start) ÷ dr.step
end

collect(dr::DateRange) = begin
    out = []
    for d in dr
        push!(out, d)
    end
    out
end

@doc """Create a `DateRange` using notation `FROM..TO;STEP`.

example:
1999-..2000-;1d
1999-12-01..2000-02-01;1d
1999-12-01T12..2000-02-01T10;1d
"""
macro dtr_str(s::String)
    local to = step = ""
    (from, tostep) = split(s, "..")
    if !isempty(tostep)
        try
            (to, step) = split(tostep, ";")
        catch error
            if error isa BoundsError
                to = tostep
                step = ""
            else
                rethrow(error)
            end
        end
    end
    args = [isempty(from) ? nothing : todatetime(from),
        isempty(to) ? nothing : todatetime(to)]
    if !isempty(step)
        push!(args, convert(TimeFrame, step))
    end
    dr = DateRange(args...)
    :($dr)
end

export DateRange, @dtr_str
