# Bộ kiểm thử tự động cho gói EclatFIM.
#
# Cú pháp thực thi:
#   julia --project=. test/runtests.jl
#   julia --project=. --check-bounds=yes test/runtests.jl

using Test
using Random
using EclatFIM

const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))

"""Các phiên bản trong VARIANT_NAMES đã được cài đặt ở bản code hiện tại."""
function available_variants()
    res = Tuple{String,EclatConfig}[]
    for name in VARIANT_NAMES
        cfg = VARIANTS[name]
        try
            EclatFIM.check_config(cfg)
            push!(res, (name, cfg))
        catch
            # phiên bản chưa cài đặt ở mốc hiện tại
        end
    end
    return res
end

@testset "EclatFIM" begin
    @testset "I/O và minsup (test_io.jl)" begin
        include("test_io.jl")
    end
    @testset "Tính đúng thuật toán (test_correctness.jl)" begin
        include("test_correctness.jl")
    end
    @testset "Luật kết hợp (test_rules.jl)" begin
        include("test_rules.jl")
    end
    @testset "Benchmark (test_benchmark.jl)" begin
        include("test_benchmark.jl")
    end
    @testset "Hiệu năng: không cấp phát, ổn định kiểu (test_performance.jl)" begin
        include("test_performance.jl")
    end
end
