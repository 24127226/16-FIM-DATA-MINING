# E7: biểu diễn tidset theo mật độ (phần của A). Kiểm chứng giả thuyết H2:
#   bộ nhớ: tidset dạng vector tốn 4σ byte, dạng bitset tốn N/8 byte → bằng nhau khi ρ = σ/N = 1/32;
#   thời gian: phép giao vector tốn O(σ_a + σ_b) (có ngắt sớm, tìm kiếm nhảy), bitset tốn O(N/64)
#   bất kể support, nên điểm cân bằng về thời gian có thể khác 1/32.
#
#   julia --project=. scripts/bench_density.jl
#
# Hai nguồn điểm đo (cùng một tiến trình, đã khởi động, lấy thời gian nhỏ nhất trong 3 lần):
#   1. dữ liệu tổng hợp có mật độ điều khiển được: m = 30 item, N = 50.000 giao dịch, mỗi item có mặt
#      độc lập với xác suất p; σ = ⌈0,8·p²·N⌉ để tập 2 item phổ biến còn tập 3 item thì không;
#   2. dữ liệu thật: 5 bộ benchmark ở mọi mức trong lưới minsup, Groceries và các phương án của
#      Ứng dụng 2 (nếu đã chạy). Mật độ x = support trung bình của item phổ biến / N.
# Kết quả: results/density.csv, results/density_E7.md

using EclatFIM, Random, Statistics, Printf
include(joinpath(@__DIR__, "config.jl"))

const RES = results_dir()
const VARS = ["v2", "v3", "v4", "v6"]

"""Thời gian nhỏ nhất trong `reps` lần (đã chạy khởi động) và byte tidset đỉnh."""
function measure(db, σ, v; reps = 3, limit = 60.0)
    cfg = VARIANTS[v]
    st = EclatStats()
    eclat!((i, s) -> nothing, db, σ, cfg; stats = st)               # khởi động + bộ đếm
    best = Inf
    for _ in 1:reps
        t = @elapsed eclat!((i, s) -> nothing, db, σ, cfg)
        best = min(best, t)
        t > limit && break                                           # quá lâu: không lặp thêm
    end
    return best, st.bytes_peak, st.n_itemsets
end

function root_density(db, σ)
    supp = zeros(Int, n_items(db))
    for t in db.transactions, x in t
        supp[x] += 1
    end
    f = filter(>=(σ), supp)
    return isempty(f) ? NaN : mean(f) / n_transactions(db)
end

const HEADER = ["source", "dataset", "minsup", "density", "n_itemsets", "t_v2", "t_v3", "t_v4", "t_v6",
                "bytes_v3", "bytes_v4"]

function record!(path, source, ds, ms, db, σ)
    res = Dict(v => measure(db, σ, v) for v in VARS)
    ρ = root_density(db, σ)
    append_csv(path, HEADER, [source, ds, ms, ρ, res["v6"][3], (res[v][1] for v in VARS)...,
                              res["v3"][2], res["v4"][2]])
    @printf("  %-10s %-12s %-7s ρ = %.4f  v3/v4 = %6.2f  bộ nhớ v3/v4 = %6.3f\n", source, ds, ms, ρ,
            res["v3"][1] / res["v4"][1], res["v3"][2] / max(res["v4"][2], 1))
end

function main()
    path = joinpath(RES, "density.csv")
    isfile(path) && rm(path)
    warm = TransactionDB([Int32[1, 2], Int32[2, 3], Int32[1, 2, 3]], [1, 2, 3])
    for v in VARS
        eclat(warm, 1, VARIANTS[v])
    end
    println("== Dữ liệu tổng hợp (mật độ điều khiển được)")
    for p in (0.003, 0.006, 0.01, 0.02, 0.03125, 0.05, 0.1, 0.2, 0.4)
        rng = MersenneTwister(SEED)
        N, m = 50_000, 30
        db = TransactionDB([Int32[x for x in 1:m if rand(rng) < p] for _ in 1:N], collect(Int64, 1:m))
        σ = max(1, ceil(Int, 0.8 * p^2 * N))
        record!(path, "tong_hop", "uniform_p$(p)", "σ=$σ", db, σ)
    end
    println("== Dữ liệu thật")
    grid = load_grid()
    for (ds, _, _) in DATASETS
        isfile(dataset_path(ds)) && haskey(grid, ds) || continue
        db = read_spmf(dataset_path(ds))
        for ms in unique([grid[ds][1], median_minsup(grid[ds]), grid[ds][end]])   # mức cao, giữa, thấp
            record!(path, "benchmark", ds, ms, db, minsup_count(parse_minsup(ms), n_transactions(db)))
        end
    end
    gpath = rootpath("data", "apps", "groceries", "groceries.txt")
    if isfile(gpath)
        db = read_spmf(gpath)
        for ms in ("2%", "1%", "0.5%")
            record!(path, "ung_dung_1", "groceries", ms, db, minsup_count(parse_minsup(ms), n_transactions(db)))
        end
    end
    txdir = rootpath("data", "apps", "caltech101", "transactions")
    for f in (isdir(txdir) ? sort(readdir(txdir; join = true)) : String[])
        endswith(f, ".txt") || continue
        db = read_spmf(f)
        record!(path, "ung_dung_2", replace(basename(f), ".txt" => ""), "30%", db,
                minsup_count(parse_minsup("30%"), n_transactions(db)))
    end
    summarize(path)
end

"""Ước lượng điểm cân bằng (tỉ số = 1) trên dữ liệu tổng hợp bằng nội suy tuyến tính trên thang log."""
function crossing(xs, ys)
    for i in 1:length(xs)-1
        if (ys[i] - 1) * (ys[i+1] - 1) <= 0
            lx1, lx2 = log(xs[i]), log(xs[i+1])
            ly1, ly2 = log(ys[i]), log(ys[i+1])
            return exp(lx1 + (0 - ly1) * (lx2 - lx1) / (ly2 - ly1))
        end
    end
    return NaN
end

function summarize(path)
    lines = collect(eachline(path))
    header = split(lines[1], ",")
    rows = [Dict(zip(header, split(l, ","))) for l in lines[2:end]]
    syn = [r for r in rows if r["source"] == "tong_hop"]
    xs = [parse(Float64, r["density"]) for r in syn]
    tr = [parse(Float64, r["t_v3"]) / parse(Float64, r["t_v4"]) for r in syn]
    mr = [parse(Float64, r["bytes_v3"]) / parse(Float64, r["bytes_v4"]) for r in syn]
    io = IOBuffer()
    println(io, "# E7: biểu diễn tidset theo mật độ (giả thuyết H2)\n")
    println(io, "Sinh bởi `scripts/bench_density.jl`. Tỉ số > 1 nghĩa là bitset (v4) có lợi hơn vector (v3).\n")
    println(io, "| Nguồn | Bộ | minsup | Mật độ ρ | Thời gian v3 / v4 | Bộ nhớ tidset v3 / v4 | Bản lai v6 so với bản tốt hơn trong v3, v4 |")
    println(io, "|---|---|---|---|---|---|---|")
    for r in rows
        t3, t4, t6 = parse(Float64, r["t_v3"]), parse(Float64, r["t_v4"]), parse(Float64, r["t_v6"])
        @printf(io, "| %s | %s | %s | %.4f | %.2f | %.3f | %.2f× |\n", r["source"], r["dataset"], r["minsup"],
                parse(Float64, r["density"]), t3 / t4, parse(Float64, r["bytes_v3"]) / max(parse(Float64, r["bytes_v4"]), 1),
                t6 / min(t3, t4))
    end
    println(io, "\n**Điểm cân bằng ước lượng trên dữ liệu tổng hợp:** về thời gian ρ ≈ ",
            @sprintf("%.4f", crossing(xs, tr)), "; về bộ nhớ ρ ≈ ", @sprintf("%.4f", crossing(xs, mr)),
            " (lý thuyết: 1/32 = 0,03125).")
    write(joinpath(RES, "density_E7.md"), String(take!(io)))
    println(read(joinpath(RES, "density_E7.md"), String))
end

let t0 = time()
    main()
    log_run("scripts/bench_density.jl", ARGS, time() - t0)
end
