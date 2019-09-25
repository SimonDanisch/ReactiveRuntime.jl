using ReactiveRuntime
using Test
using ReactiveRuntime: @cell


@cell test = begin
    77
end

@cell test3 = begin
    "1 + 44"
end
@cell test2 = begin
    string(test * 20, " ", test3)
end

ReactiveRuntime.on(println, test2)
