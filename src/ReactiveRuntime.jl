module ReactiveRuntime

using WebSockets, MacroTools, Observables, JSServe
using JSServe.DOM
using JSServe: @js_str



function Base.show(io::IO, m::MIME"application/vnd.webio.application+html", x::Observable)
    s = JSServe.with_session() do session
        JSServe.jsrender(session, x)
    end
    show(io, m, s)
end


const cell_outputs = Dict{Symbol, Any}()
const obs_func_names = Dict{Symbol, Symbol}()
const channels = Dict{Symbol, Channel}()

function collect_globals!(globals, expr, current)
    vars = Set{Symbol}()
    MacroTools.postwalk(expr) do var
        var isa Symbol && var != current && haskey(globals, var) && push!(vars, var)
    end
    return vars
end

struct OnUpdater{F}
    f::F
    name::Symbol
    observable::Observable{Any}
end

function (f::OnUpdater)(val)
    newval = f.f()
    if haskey(channels, f.name)
        close(pop!(channels, f.name))
    end
    if newval isa Channel
        channels[f.name] = newval
    end
    f.observable[] = newval
end

function lift_cell_reactive(expr)
    var = nothing
    body = if @capture(expr, var_ = begin; body__; end)
        Expr(:block, body...)
    elseif @capture(expr, var_ = simple_)
        simple
    else
        # Don't modify
        expr
    end
    obs_vars = collect_globals!(cell_outputs, body, var)
    varname = var === nothing ? gensym("tmp") : var
    funcname = get!(obs_func_names, varname, gensym(varname))
    var_quote = QuoteNode(varname)
    func_quote = QuoteNode(funcname)
    lifted = quote
        $(varname) = let
            function $(funcname)($(obs_vars...))
                $(body)
            end
            new_parents = ($(obs_vars...),)
            observable, old_parents = get!(ReactiveRuntime.cell_outputs, $(var_quote)) do
                ReactiveRuntime.Observable{Any}(nothing), new_parents
            end
            observable, old_parents = ReactiveRuntime.cell_outputs[$(var_quote)]
            new_updater = ReactiveRuntime.OnUpdater($(func_quote), observable) do
                 Base.invokelatest($(funcname), getindex.(new_parents)...)
            end
            # remove old listeners
            for old_parent in old_parents
                filter!(old_parent.listeners) do callback
                    !(callback isa ReactiveRuntime.OnUpdater && callback.name == $(func_quote))
                end
            end
            # add new listeners
            for new_parent in new_parents
                ReactiveRuntime.on(new_updater, new_parent)
            end
            # call the updater, to update value with the new function body
            new_updater(nothing)
            observable
        end
    end

    return lifted
end


macro cell(expr)
    expr = macroexpand(__module__, expr)
    return esc(lift_cell_reactive(expr))
end

end # module
