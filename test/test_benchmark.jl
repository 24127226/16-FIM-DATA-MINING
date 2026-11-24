# Kiểm thử trên các bộ dữ liệu benchmark (mục 6.1, 7.3).
#
# Nếu chưa tải dữ liệu benchmark (`julia --project=. scripts/fetch_data.jl benchmark`),
# các test benchmark sẽ tự bỏ qua kèm thông báo và vẫn tính là pass.
# Khi có dữ liệu:
#   1. Kiểm tra thống kê (N, m) khớp bảng của đề.
#   2. Kiểm tra mọi phiên bản đã cài đặt cho ra tập kết quả giống hệt nhau.
#   3. Nếu có đáp án trong `test/expected/` hoặc có `spmf.jar` + Java ≥ 25, đối chiếu 100% với SPMF.

include(joinpath(REPO_ROOT, "scripts", "common.jl"))

const BENCHMARK_CASES = [
    (name = "chess",      file = "data/benchmark/chess.txt",      n = 3196,   m = 75,    minsup = "90%"),
    (name = "mushroom",   file = "data/benchmark/mushroom.txt",   n = 8124,   m = 119,   minsup = "60%"),
    (name = "retail",     file = "data/benchmark/retail.txt",     n = 88162,  m = 16470, minsup = "10%"),
    (name = "T10I4D100K", file = "data/benchmark/T10I4D100K.txt", n = 100000, m = 870,   minsup = "5%"),
]

const CAN_RUN_SPMF = isfile(spmf_jar()) && java_major_version() >= 25

@testset "Benchmark (tầng 2–3)" begin
    any_present = false
    for bc in BENCHMARK_CASES
        path = joinpath(REPO_ROOT, bc.file)
        if !isfile(path)
            @info "Bỏ qua test benchmark $(bc.name): chưa có $(bc.file) (chạy `julia --project=. scripts/fetch_data.jl benchmark` để tải)."
            continue
        end
        any_present = true
        @testset "$(bc.name) (minsup=$(bc.minsup))" begin
            db = read_spmf(path)
            @test n_transactions(db) == bc.n
            @test n_items(db) == bc.m

            sigma_min = minsup_count(bc.minsup, n_transactions(db))
            base_name, base_cfg = first(VARIANTS_TO_TEST)
            base_res = eclat(db, sigma_min, base_cfg)
            @test !isempty(base_res)

            # Mọi phiên bản đã cài phải cho output giống hệt nhau
            for (vname, cfg) in VARIANTS_TO_TEST[2:end]
                @test eclat(db, sigma_min, cfg) == base_res
            end

            # Đối chiếu với file đáp án SPMF cố định hoặc chạy SPMF trực tiếp nếu có
            expected_path = joinpath(REPO_ROOT, "test", "expected",
                                     "$(bc.name)_$(replace(bc.minsup, "%" => "pct")).txt")
            if isfile(expected_path) || CAN_RUN_SPMF
                dir = mktempdir()
                ours_out = joinpath(dir, "ours.txt")
                open(ours_out, "w") do io
                    buf = Int32[]
                    eclat!(db, sigma_min, base_cfg) do items, sup
                        write_itemset(io, items, sup, db, buf)
                    end
                end
                ref_out = if isfile(expected_path)
                    expected_path
                else
                    spmf_out = joinpath(dir, "spmf.txt")
                    r = run_spmf("Eclat", path, spmf_out, bc.minsup; timeout = 120)
                    @test r.status == :ok
                    spmf_out
                end
                cmp_exact = compare_files(ours_out, ref_out)
                @test cmp_exact.exact_match
                @test cmp_exact.match_pct == 100.0
                cmp_fp = compare_files(ours_out, ref_out; force_fingerprint = true)
                @test cmp_fp.exact_match
            else
                @info "Đã kiểm tra thống kê & đồng nhất giữa các biến thể trên $(bc.name); bỏ qua đối chiếu SPMF (chưa có spmf.jar/Java ≥ 25)."
            end
        end
    end
    if !any_present
        @test true  # không lỗi khi chưa tải dữ liệu benchmark
    end
end
