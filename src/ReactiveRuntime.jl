module ReactiveRuntime

using WebSockets, WebIO, MacroTools, Observables

const cell_outputs = Set{Symbol}()

function collect_globals!(globals, expr, current)
    vars = Symbol[]
    MacroTools.postwalk(expr) do var
        var isa Symbol && var != current && var in globals && push!(vars, var)
    end
    return vars
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
    varesc = esc(varname)
    lifted = quote
        function f($(obs_vars...))
            $(body)
        end
        if isdefined(Main, $(QuoteNode(varname)))
            $(varesc)[] = f(getindex.(($(obs_vars...),))...)
        else
            $(varesc) = Observable(f(getindex.(($(obs_vars...),))...))
            onany($(obs_vars...)) do args...
                $(varesc)[] = f(args...)
            end
        end
    		$(varesc)
    end
    if var !== nothing
        push!(cell_outputs, var)
    end
    return lifted
end

end # module
