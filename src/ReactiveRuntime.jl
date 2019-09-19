module ReactiveRuntime

using WebSockets, MacroTools, Observables, JSServe
using JSServe.DOM
using JSServe: @js_str

Base.write(io::JSServe.JavascriptSerializer, x::Array) = write(JSServe.io_object(io), x)
function JSServe.jsrender(session::JSServe.Session, obs::Observable)
    html = map(obs) do value
        JSServe.repr_richest(value)
    end
    dom = DOM.div(html[])
    JSServe.onjs(session, html, js"""
        function (html){
            var dom = $(dom);
            if(dom){
                dom.innerHTML = html;
                return true;
            }else{
                //deregister the callback if the observable dom is gone
                return false;
            }
        }
    """)
    return dom
end
function Base.show(io::IO, m::MIME"application/vnd.webio.application+html", x::Observable)
    s = JSServe.with_session() do session
        JSServe.jsrender(session, x)
    end
    show(io, m, s)
end


const cell_outputs = Set{Symbol}()

function collect_globals!(globals, expr, current)
    vars = Set{Symbol}()
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
    varesc = (varname)
    lifted = quote
        function f($(obs_vars...))
            $(body)
        end
        if isdefined(Main, $(QuoteNode(varname)))
            $(varesc)[] = f(getindex.(($(obs_vars...),))...)
        else
            $(varesc) = ReactiveRuntime.Observable(f(getindex.(($(obs_vars...),))...))
            ReactiveRuntime.onany($(obs_vars...)) do args...
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


macro cell(expr)
    expr = macroexpand(__module__, expr)
    return esc(lift_cell_reactive(expr))
end

end # module
