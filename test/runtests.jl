# Bộ kiểm thử tự động ba tầng cho gói EclatFIM (tổng 10.474 khẳng định trên v0..v6).
#
# Cú pháp thực thi:
#   julia --project=. test/runtests.jl
#   julia --project=. --check-bounds=yes test/runtests.jl

using Test                                                   # Thư viện kiểm thử chuẩn của Julia
using Random                                                 # Cố định seed cho các bài test ngẫu nhiên
using EclatFIM                                               # Gói Eclat tự cài đặt của nhóm

const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))         # Đường dẫn thư mục gốc kho mã nguồn

"""
    available_variants() -> Vector{Tuple{String,EclatConfig}}

Mục đích hàm: Liệt kê các biến thể Eclat (`v0`..`v6`) đã được cài đặt hợp lệ trong bản mã hiện tại
để toàn bộ bộ kiểm thử tự động chạy kiểm tra đồng nhất trên tất cả biến thể.
"""
function available_variants()
    res = Tuple{String,EclatConfig}[]
    for name in VARIANT_NAMES                                # Duyệt lần lượt v0, v1, ..., v6
        cfg = VARIANTS[name]
        try
            EclatFIM.check_config(cfg)                       # Kiểm tra biến thể đã hỗ trợ đầy đủ chưa
            push!(res, (name, cfg))
        catch
            # Bỏ qua nếu biến thể chưa được cài đặt ở mốc phát triển hiện tại
        end
    end
    return res
end

# Thực thi lần lượt 5 nhóm kiểm thử tự động (I/O, đúng đắn, luật kết hợp, benchmark, hiệu năng)
@testset "EclatFIM" begin
    @testset "I/O và minsup (test_io.jl)" begin
        include("test_io.jl")                                # Kiểm tra đọc/ghi SPMF và 10 ca biên minsup_count
    end
    @testset "Tính đúng thuật toán (test_correctness.jl)" begin
        include("test_correctness.jl")                       # Kiểm tra oracle vét cạn 200 CSDL, tập chuẩn và trường hợp biên
    end
    @testset "Luật kết hợp (test_rules.jl)" begin
        include("test_rules.jl")                             # Kiểm tra sinh luật kết hợp và lọc top-k bằng BinaryMinHeap
    end
    @testset "Benchmark (test_benchmark.jl)" begin
        include("test_benchmark.jl")                         # Kiểm tra đồng nhất giữa v0..v6 và đối chiếu SPMF trên 4 benchmark
    end
    @testset "Hiệu năng: không cấp phát, ổn định kiểu (test_performance.jl)" begin
        include("test_performance.jl")                       # Kiểm tra @allocated == 0, @inferred và độ đúng nhân giao ngẫu nhiên
    end
end
