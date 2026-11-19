# Bộ kiểm thử tự động của EclatFIM.
#
# Chạy từ gốc repo:   julia --project test/runtests.jl
# (hoặc:              julia --project -e "using Pkg; Pkg.test()")
#
# Phần "Benchmark" cần dữ liệu thật (scripts/fetch_data.jl); nếu chưa tải thì được bỏ qua.

using EclatFIM
using Test
using Random

@testset verbose = true "EclatFIM" begin
    @testset "Đọc/ghi và minsup" begin
        include("test_io.jl")
    end
    @testset "Tính đúng" begin
        include("test_correctness.jl")
    end
    @testset "Hàm lõi và hiệu năng" begin
        include("test_performance.jl")
    end
    @testset "Luật kết hợp" begin
        include("test_rules.jl")
    end
    @testset "Benchmark (đối chiếu dấu vân tay SPMF)" begin
        include("test_benchmark.jl")
    end
end
