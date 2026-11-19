# E8: ablation v0 → v6 (phần của A). Mỗi phiên bản thêm ĐÚNG MỘT tối ưu so với bản trước
# (src/structures.jl, VARIANTS), nên chênh lệch thời gian giữa hai bản liền nhau là tác dụng riêng
# của tối ưu đó. Kiểm chứng giả thuyết H3 (thứ tự item), H2 (bitset), H8 (mảng tam giác).
#
#   julia --project=. scripts/bench_ablation.jl [--repeats 3] [--datasets chess,retail]
#
# Đo tại minsup trung bình của từng bộ (results/minsup_grid.csv). Mỗi lần đo một tiến trình mới,
# có warm-up, ghi output ra file như mọi thí nghiệm khác; bộ đếm chạy riêng (không tính giờ).
# Kết quả: results/ablation.csv, results/ablation_stats.csv, results/ablation_B03.md, results/ablation_B04.md

using EclatFIM, Statistics, Printf
include(joinpath(@__DIR__, "config.jl"))
include(joinpath(@__DIR__, "bench_common.jl"))

const STATS_FIELDS = ["n_itemsets", "n_intersections", "n_failed", "n_skipped_pairs", "n_classes",
                      "n_switch", "max_depth", "bytes_peak", "time_level2_ns"]

"""Đọc CSV đơn giản (không có dấu phẩy trong ô) thành vector các Dict."""
function read_csv(path)
    lines = collect(eachline(path))
    header = split(lines[1], ",")
    return [Dict(zip(header, split(l, ","))) for l in lines[2:end] if !isempty(strip(l))]
end

const VERSION_DESC = Dict(
    "v0" => "cơ bản: tidset vector, cấp phát mới mỗi phép giao, thứ tự theo mã",
    "v1" => "+ thứ tự item theo support tăng dần",
    "v2" => "+ dùng lại buffer theo độ sâu (không cấp phát)",
    "v3" => "+ giao thích ứng (ngắt sớm, tìm kiếm nhảy)",
    "v4" => "+ tidset dạng bitset (BitVector)",
    "v5" => "+ mảng tam giác cho tập 2 item",
    "v6" => "+ biểu diễn lai bitset → vector")

function write_tables(datasets, grid)
    rows = read_csv(joinpath(RES, "ablation.csv"))
    med = Dict{Tuple{String,String},Float64}()
    for ds in datasets, v in VARIANT_NAMES
        ts = [parse(Float64, r["t_algo_s"]) for r in rows if r["dataset"] == ds && r["variant"] == v && r["status"] == "ok"]
        med[(ds, v)] = isempty(ts) ? NaN : median(ts)
    end
    io = IOBuffer()
    println(io, "# B03: ablation v0 → v6 (thời gian khai thác + ghi kết quả, trung vị)\n")
    println(io, "Tại minsup trung bình của mỗi bộ. Trong ngoặc: tăng tốc so với v0. Sinh bởi `scripts/bench_ablation.jl`.\n")
    println(io, "| Phiên bản | Thay đổi | ", join(["$ds ($(median_minsup(grid[ds])))" for ds in datasets], " | "), " |")
    println(io, "|---|---|", repeat("---|", length(datasets)))
    for v in VARIANT_NAMES
        cells = String[]
        for ds in datasets
            t, t0 = med[(ds, v)], med[(ds, "v0")]
            push!(cells, isnan(t) ? "timeout" : @sprintf("%.3f s (×%.1f)", t, t0 / t))
        end
        println(io, "| ", v, " | ", VERSION_DESC[v], " | ", join(cells, " | "), " |")
    end
    write(joinpath(RES, "ablation_B03.md"), String(take!(io)))

    srows = read_csv(joinpath(RES, "ablation_stats.csv"))
    io = IOBuffer()
    println(io, "# B04: bộ đếm của từng phiên bản (một lần chạy có bộ đếm, không tính giờ)\n")
    for ds in datasets
        println(io, "## ", ds, " (minsup ", median_minsup(grid[ds]), ")\n")
        println(io, "| Phiên bản | Số tập | Phép giao | Dưới ngưỡng | Cặp mức 2 bỏ qua nhờ mảng tam giác | Thời gian mức 2 | Tidset đỉnh | Lần chuyển bitset → vector |")
        println(io, "|---|---|---|---|---|---|---|---|")
        for r in srows
            r["dataset"] == ds || continue
            @printf(io, "| %s | %s | %s | %s | %s | %.1f ms | %.2f MiB | %s |\n", r["variant"], r["n_itemsets"],
                    r["n_intersections"], r["n_failed"], r["n_skipped_pairs"], parse(Float64, r["time_level2_ns"]) / 1e6,
                    parse(Float64, r["bytes_peak"]) / 2^20, r["n_switch"])
        end
        println(io)
    end
    write(joinpath(RES, "ablation_B04.md"), String(take!(io)))
    println(read(joinpath(RES, "ablation_B03.md"), String))
end

function main(args)
    k = findfirst(==("--repeats"), args)
    repeats = k === nothing ? REPEATS : parse(Int, args[k+1])
    k = findfirst(==("--datasets"), args)
    grid = load_grid()
    datasets = k === nothing ? [d[1] for d in DATASETS] : String.(split(args[k+1], ","))
    datasets = [d for d in datasets if isfile(dataset_path(d)) && haskey(grid, d)]
    "--tables-only" in args && return write_tables(datasets, grid)
    path = joinpath(RES, "ablation.csv")
    spath = joinpath(RES, "ablation_stats.csv")
    for p in (path, spath)                     # đo lại từ đầu: không trộn với số liệu của lần chạy trước
        isfile(p) && rm(p)
    end
    for ds in datasets
        ms = median_minsup(grid[ds])
        for v in VARIANT_NAMES
            # lặp 3 lần, hoặc 5 lần nếu một lần chạy dưới 1 giây (giao thức đo, như E2)
            r = measure_ours!(path, "E8", ds, dataset_path(ds), ms, v, repeats, repeats == 1)
            println("  E8 $ds $ms $v: ", r["status"] == "ok" ? r["t_mine"] * " s" : r["status"])
            s = run_ours(dataset_path(ds), ms, v; out = "NUL", stats = true)
            if s["status"] == "ok"
                append_csv(spath, vcat(["dataset", "minsup", "variant"], STATS_FIELDS),
                           vcat([ds, ms, v], [s[f] for f in STATS_FIELDS]))
            end
        end
    end
    write_tables(datasets, grid)
end

let t0 = time()
    main(ARGS)
    log_run("scripts/bench_ablation.jl", ARGS, time() - t0)
end
