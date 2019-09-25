using ReactiveRuntime
using Test
using ReactiveRuntime: @variable


@variable test = begin
    77
end

@variable test3 = begin
    "1 + 44"
end
@variable test2 = begin
    string(test * 20, " ", test3)
end

ReactiveRuntime.on(println, test2)
