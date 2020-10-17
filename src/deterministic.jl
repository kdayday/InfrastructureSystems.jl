convert_data(data::AbstractDict{Dates.DateTime, T}) where {T <: Vector{<:Real}} =
    SortedDict{Dates.DateTime, Vector{CONSTANT}}(data...)
convert_data(data::AbstractDict{Dates.DateTime, T}) where {T <: Vector{<:Tuple}} =
    SortedDict{Dates.DateTime, Vector{POLYNOMIAL}}(data...)
convert_data(data::AbstractDict{Dates.DateTime, T}) where {T <: Vector{<:Vector{<:Tuple}}} =
    SortedDict{Dates.DateTime, Vector{PWL}}(data...)

# Workaround for what appears to be a bug in SortedDict. If a user tries to construct
# SortedDict(i => ones(2) for i in 1:2)
# it won't discern the types and will return SortedDict{Any,Any,Base.Order.ForwardOrdering}
# This will only work for the most common use case of Vector{CONSTANT}.
convert_data(data::AbstractDict) = SortedDict{Dates.DateTime, Vector{CONSTANT}}(data...)

function Deterministic(
    name::AbstractString,
    input_data::AbstractDict,
    resolution::Dates.Period;
    normalization_factor::NormalizationFactor = 1.0,
    scaling_factor_multiplier::Union{Nothing, Function} = nothing,
)
    data = convert_data(input_data)
    data = handle_normalization_factor(data, normalization_factor)
    return Deterministic(name, data, resolution, scaling_factor_multiplier)
end

"""
Construct Deterministic from a Dict of TimeArrays.

# Arguments
- `name::AbstractString`: user-defined name
- `input_data::AbstractDict{Dates.DateTime, TimeSeries.TimeArray}`: time series data.
- `normalization_factor::NormalizationFactor = 1.0`: optional normalization factor to apply
  to each data entry
- `scaling_factor_multiplier::Union{Nothing, Function} = nothing`: If the data are scaling
  factors then this function will be called on the component and applied to the data when
  [`get_time_series_array`](@ref) is called.
- `timestamp = :timestamp`: If the values are DataFrames is passed then this must be the
  column name that contains timestamps.
"""
function Deterministic(
    name::AbstractString,
    input_data::AbstractDict{Dates.DateTime, <:TimeSeries.TimeArray};
    normalization_factor::NormalizationFactor = 1.0,
    scaling_factor_multiplier::Union{Nothing, Function} = nothing,
)
    data_type = eltype(TimeSeries.values(first(values(input_data))))
    data = SortedDict{Dates.DateTime, Vector{data_type}}()
    resolution =
        TimeSeries.timestamp(first(values(input_data)))[2] -
        TimeSeries.timestamp(first(values(input_data)))[1]
    for (k, v) in input_data
        if length(size(v)) > 1
            throw(ArgumentError("TimeArray with timestamp $k has more than one column)"))
        end
        data[k] = TimeSeries.values(v)
    end

    return Deterministic(
        name,
        data,
        resolution;
        normalization_factor = normalization_factor,
        scaling_factor_multiplier = scaling_factor_multiplier,
    )
end

"""
Construct Deterministic from a CSV file. The first column must be a timestamp in
DateTime format and the columns the values in the forecast window.

# Arguments
- `name::AbstractString`: user-defined name
- `filename::AbstractString`: name of CSV file containing data
- `component::InfrastructureSystemsComponent`: component associated with the data
- `normalization_factor::NormalizationFactor = 1.0`: optional normalization factor to apply
  to each data entry
- `scaling_factor_multiplier::Union{Nothing, Function} = nothing`: If the data are scaling
  factors then this function will be called on the component and applied to the data when
  [`get_time_series_array`](@ref) is called.
"""
function Deterministic(
    name::AbstractString,
    filename::AbstractString,
    component::InfrastructureSystemsComponent,
    resolution::Dates.Period;
    normalization_factor::NormalizationFactor = 1.0,
    scaling_factor_multiplier::Union{Nothing, Function} = nothing,
)
    component_name = get_name(component)
    raw_data = read_time_series(Deterministic, filename, component_name)
    return Deterministic(
        name,
        raw_data,
        resolution;
        normalization_factor = normalization_factor,
        scaling_factor_multiplier = scaling_factor_multiplier,
    )
end

"""
Construct Deterministic from RawTimeSeries.
"""
function Deterministic(
    name::AbstractString,
    series_data::RawTimeSeries,
    resolution::Dates.Period;
    normalization_factor::NormalizationFactor = 1.0,
    scaling_factor_multiplier::Union{Nothing, Function} = nothing,
)
    return Deterministic(
        name,
        series_data.data,
        resolution;
        normalization_factor = normalization_factor,
        scaling_factor_multiplier = scaling_factor_multiplier,
    )
end

function Deterministic(ts_metadata::DeterministicMetadata, data::SortedDict)
    return Deterministic(
        name = get_name(ts_metadata),
        resolution = get_resolution(ts_metadata),
        data = data,
        scaling_factor_multiplier = get_scaling_factor_multiplier(ts_metadata),
        internal = InfrastructureSystemsInternal(get_time_series_uuid(ts_metadata)),
    )
end

function Deterministic(info::TimeSeriesParsedInfo)
    return Deterministic(
        info.name,
        info.data,
        info.resolution;
        normalization_factor = info.normalization_factor,
        scaling_factor_multiplier = info.scaling_factor_multiplier,
    )
end

"""
Construct a new Deterministic from an existing instance and a subset of data.
"""
function Deterministic(forecast::Deterministic, data)
    vals = Dict{Symbol, Any}()
    for (fname, ftype) in zip(fieldnames(Deterministic), fieldtypes(Deterministic))
        if ftype <: SortedDict
            val = data
        elseif ftype <: InfrastructureSystemsInternal
            # Need to create a new UUID.
            val = InfrastructureSystemsInternal()
        else
            val = getfield(forecast, fname)
        end

        vals[fname] = val
    end

    return Deterministic(; vals...)
end

function get_array_for_hdf(forecast::Deterministic)
    return transform_array_for_hdf(forecast.data)
end

eltype_data(forecast::Deterministic) = eltype_data_common(forecast)
get_count(forecast::Deterministic) = get_count_common(forecast)
get_horizon(forecast::Deterministic) = get_horizon_common(forecast)
get_initial_times(forecast::Deterministic) = get_initial_times_common(forecast)
get_initial_timestamp(forecast::Deterministic) = get_initial_timestamp_common(forecast)
get_interval(forecast::Deterministic) = get_interval_common(forecast)
iterate_windows(forecast::Deterministic) = iterate_windows_common(forecast)
get_window(f::Deterministic, initial_time; len = nothing) =
    get_window_common(f, initial_time; len = len)

function make_time_array(forecast::Deterministic)
    # Artificial limitation to reduce scope.
    @assert get_count(forecast) == 1
    timestamps = range(
        get_initial_timestamp(forecast);
        step = get_resolution(forecast),
        length = get_horizon(forecast),
    )
    data = first(values(get_data(forecast)))
    return TimeSeries.TimeArray(timestamps, data)
end
