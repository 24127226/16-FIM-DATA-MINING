# Sinh đáp án SPMF cho bộ kiểm thử (test/expected/). Chạy lại khi thêm ca kiểm thử mới.
#
# Cách dùng (từ gốc repo):  julia --project=. scripts/make_expected.jl
#
# - Ca nhỏ: lưu nguyên file output của SPMF (test/expected/<tên>.txt).
# - Ca benchmark: chỉ lưu dấu vân tay (số tập + tổng băm) vào test/expected/benchmark_fingerprints.txt,
#   vì output có thể rất lớn. Bỏ qua nếu chưa tải dữ liệu benchmark.

using EclatFIM
include(joinpath(@__DIR__, "common.jl"))

# (tên ca, file input tính từ gốc repo, minsup theo cú pháp SPMF)
const SMALL_CASES = [
    ("pasquier99_40", "data/toy/pasquier99.txt", "40%"),
    ("pasquier99_20", "data/toy/pasquier99.txt", "20%"),
    ("bookstore_50", "data/toy/bookstore.txt", "50%"),
    ("bookstore_30", "data/toy/bookstore.txt", "30%"),
    ("edge_identical_50", "test/data/edge_identical.txt", "50%"),
    ("edge_single_100", "test/data/edge_single.txt", "100%"),
    ("edge_sparse_ids_40", "test/data/edge_sparse_ids.txt", "40%"),
    ("edge_comments_40", "test/data/edge_comments.txt", "40%"),
    ("edge_none_50", "test/data/edge_none.txt", "50%"),
    ("edge_zero_40", "test/data/edge_zero.txt", "40%"),
    ("edge_unsorted_40", "test/data/edge_unsorted.txt", "40%"),
]

# Benchmark ở các mức minsup cho output vừa phải (để test chạy nhanh).
const BENCH_CASES = [
    ("chess_80", "data/benchmark/chess.txt", "80%"),
    ("mushroom_20", "data/benchmark/mushroom.txt", "20%"),
    ("retail_0.5", "data/benchmark/retail.txt", "0.5%"),
    ("T10I4D100K_0.5", "data/benchmark/T10I4D100K.txt", "0.5%"),
    ("accidents_80", "data/benchmark/accidents.txt", "80%"),
]

function main()
    dir = rootpath("test", "expected")
    mkpath(dir)
    open(joinpath(dir, "manifest.txt"), "w") do mf
        println(mf, "# tên | file input | minsup   (sinh bởi scripts/make_expected.jl)")
        for (name, input, ms) in SMALL_CASES
            out = joinpath(dir, name * ".txt")
            r = run_spmf("Eclat", rootpath(input), out, ms)
            r.status == :ok || error("SPMF lỗi ở ca $name:\n" * r.output)
            println(mf, name, " | ", input, " | ", ms)
            println(rpad(name, 22), r.n_itemsets, " tập")
        end
    end
    open(joinpath(dir, "benchmark_fingerprints.txt"), "w") do bf
        println(bf, "# tên | file input | minsup | số tập | tổng băm   (sinh bởi scripts/make_expected.jl)")
        for (name, input, ms) in BENCH_CASES
            if !isfile(rootpath(input))
                println(rpad(name, 22), "bỏ qua (chưa tải ", input, ")")
                continue
            end
            out = tempname()
            r = run_spmf("Eclat", rootpath(input), out, ms)
            r.status == :ok || error("SPMF lỗi ở ca $name:\n" * r.output)
            fp = fingerprint(out)
            rm(out)
            println(bf, name, " | ", input, " | ", ms, " | ", fp.count, " | ", fp.hash)
            println(rpad(name, 22), fp.count, " tập, băm ", fp.hash)
        end
    end
end

main()
