# Chạy các thí nghiệm của Chương 2 (phần của B): E1–E6, E9. Kết quả thô ghi vào results/*.csv.
#
#   julia --project=. scripts/bench.jl <thí nghiệm...> [--quick] [--datasets chess,retail] [--repeats 3] [--resume]
#
#   E1  tính đúng: mọi phiên bản × mọi mức minsup, so dấu vân tay với SPMF Eclat
#   E2  thời gian theo minsup: v0, bản mặc định, SPMF Eclat, SPMF Eclat_bitset (lặp, lấy trung vị)
#   E3  số tập phổ biến theo minsup: lấy từ E2 (không cần chạy riêng)
#   E4  bộ nhớ đỉnh tại minsup trung bình: v0 so với bản mặc định (+ RAM nền, byte tidset đỉnh)
#   E5  khả năng mở rộng: tập con 10/25/50/75/100% của Retail (0,05%) và Accidents (30%) (scripts/subsample.jl)
#   E6  độ dài giao dịch: dữ liệu tổng hợp (scripts/gen_synthetic.jl)
#   E9  so với Apriori và FP-Growth của SPMF
#
# --quick: mỗi bộ chỉ chạy mức minsup đầu, giữa, cuối và lặp 1 lần (dùng cho notebook Colab).
# Giao thức đo: KE_HOACH_DU_AN.md mục 8.5 (tiến trình mới, warm-up, trung vị, timeout).

using EclatFIM
include(joinpath(@__DIR__, "config.jl"))

include(joinpath(@__DIR__, "bench_common.jl"))

"""E1: mọi phiên bản cho đúng kết quả của SPMF ở mọi mức minsup."""
function e1(datasets, grid, quick)
    path = joinpath(RES, "e1_correctness.csv")
    header = ["dataset", "minsup", "sigma", "variant", "n_ours", "n_spmf", "fingerprint_match", "commit", "date", "status"]
    for ds in datasets, ms in levels_for(grid, ds, quick)
        ref = tempname()
        s = run_spmf("Eclat", dataset_path(ds), ref, ms; xmx = JAVA_XMX, timeout = TIMEOUT_S)
        if s.status != :ok
            println("  E1 $ds $ms: SPMF ", s.status, " → bỏ qua mức này")
            continue
        end
        fref = fingerprint(ref); rm(ref)
        for v in implemented_variants()
            out = tempname()
            r = run_ours(dataset_path(ds), ms, v; out = out)
            ok = r["status"] == "ok"
            f = ok ? fingerprint(out) : (count = -1, hash = UInt64(0))
            isfile(out) && rm(out)
            p = provenance()
            append_csv(path, header, [ds, ms, get(r, "sigma", ""), v, f.count, fref.count, f == fref, p.commit, p.date,
                                      r["status"]])
            println("  E1 $ds $ms $v: ", !ok ? r["status"] : (f == fref ? "khớp" : "KHÔNG KHỚP"), " (", f.count, " tập)")
        end
    end
end

"""Các mức (bộ dữ liệu, minsup) đã đo xong trong một file CSV của thí nghiệm (dùng cho `--resume`)."""
function done_levels(path)
    isfile(path) || return Set{Tuple{String,String}}()
    lines = collect(eachline(path))
    header = split(lines[1], ",")
    ids, im = findfirst(==("dataset"), header), findfirst(==("minsup"), header)
    return Set((String(split(l, ",")[ids]), String(split(l, ",")[im])) for l in lines[2:end] if !isempty(strip(l)))
end

"""
E2 (và E3): thời gian và số tập theo minsup. Với `resume = true`, bỏ qua các mức đã có trong CSV (dùng khi
lần chạy trước bị ngắt giữa chừng; phải xóa trước các dòng của mức đang đo dở).
"""
function e2(datasets, grid, quick, repeats; resume = false)
    path = joinpath(RES, "e2_runtime.csv")
    best = best_variant()
    skip = resume ? done_levels(path) : Set{Tuple{String,String}}()
    for ds in datasets, ms in levels_for(grid, ds, quick)
        (ds, ms) in skip && (println("  E2 $ds $ms: đã đo, bỏ qua"); continue)
        input = dataset_path(ds)
        for v in unique(["v0", best])
            r = measure_ours!(path, "E2", ds, input, ms, v, repeats, quick)
            println("  E2 $ds $ms $v: ", get(r, "t_mine", r["status"]), " s")
        end
        for algo in ("Eclat", "Eclat_bitset")
            s = measure_spmf!(path, "E2", ds, input, ms, algo, repeats, quick)
            println("  E2 $ds $ms SPMF $algo: ", s.status, " ", s.algo_ms, " ms")
        end
    end
end

"""E4: bộ nhớ đỉnh tại minsup trung bình (v0 so với bản mặc định), kèm RAM nền và byte tidset."""
function e4(datasets, grid, repeats)
    path = joinpath(RES, "e4_memory.csv")
    header = ["dataset", "minsup", "variant", "repeat", "maxrss_mb", "baseline_mb", "extra_mb",
              "tidset_peak_mb", "n_itemsets", "commit", "machine", "date"]
    best = best_variant()
    for ds in datasets
        ms = median_minsup(grid[ds])
        for v in unique(["v0", best])
            base = baseline_rss(v)
            st = run_ours(dataset_path(ds), ms, v; out = "NUL", stats = true)
            peak_tid = st["status"] == "ok" ? round(parse(Int, st["bytes_peak"]) / 2^20; digits = 3) : ""
            for rep in 1:repeats
                r = run_ours(dataset_path(ds), ms, v; out = "NUL")
                r["status"] == "ok" || continue
                rss = parse(Int, r["maxrss"])
                p = provenance()
                append_csv(path, header, [ds, ms, v, rep, round(rss / 2^20; digits = 1), round(base / 2^20; digits = 1),
                    round((rss - base) / 2^20; digits = 1), peak_tid, r["n"], p.commit, p.machine, p.date])
            end
            println("  E4 $ds $ms $v: tidset đỉnh ", peak_tid, " MiB")
        end
        s = spmf_tmp("Eclat", dataset_path(ds), ms)
        record_spmf!(joinpath(RES, "e4_memory_spmf.csv"), "E4", ds, ms, "Eclat", 1, s)
    end
end

"""
E5: khả năng mở rộng trên các tập con lồng nhau 10 ⊂ 25 ⊂ 50 ⊂ 75 ⊂ 100% (scripts/subsample.jl).
Mỗi trường hợp: (bộ dữ liệu, minsup tương đối cố định, thuật toán SPMF để so).
- Retail (thưa) ở 0,05%: σ của tập con 10% là 5, mức thấp nhất còn an toàn; lần chạy ngắn (dưới 1 giây).
- Accidents (dày, lớn) ở 30%: lần chạy đủ dài để thấy rõ xu hướng; so với Eclat_bitset vì SPMF Eclat
  ở mức này chạy quá lâu.
Chỉ chạy các bộ có trong `datasets`; `resume` bỏ qua tập con đã đo.
"""
const E5_CASES = [("retail", "0.05%", "Eclat"), ("accidents", "30%", "Eclat_bitset")]

function e5(datasets, repeats, quick; resume = false)
    path = joinpath(RES, "e5_scalability.csv")
    best = best_variant()
    skip = resume ? done_levels(path) : Set{Tuple{String,String}}()
    for (base, ms, algo) in E5_CASES
        base in datasets || continue
        for pct in (10, 25, 50, 75, 100)
            input = rootpath("data", "subsets", "$(base)_$(pct).txt")
            isfile(input) || error("Chưa có $input: chạy julia --project=. scripts/subsample.jl $base trước")
            ds = "$(base)_$(pct)"
            (ds, ms) in skip && (println("  E5 $ds $ms: đã đo, bỏ qua"); continue)
            r = measure_ours!(path, "E5", ds, input, ms, best, repeats, quick)
            s = measure_spmf!(path, "E5", ds, input, ms, algo, repeats, quick)
            println("  E5 $ds $ms: nhóm ", get(r, "t_mine", r["status"]), " s, SPMF $algo ", s.algo_ms, " ms")
        end
    end
end

"""E6: ảnh hưởng của độ dài giao dịch trung bình (scripts/gen_synthetic.jl)."""
function e6(minsup_e6, repeats, quick)
    path = joinpath(RES, "e6_length.csv")
    best = best_variant()
    files = sort(filter(f -> startswith(f, "synth_T"), readdir(rootpath("data", "synthetic"))))
    isempty(files) && error("Chưa có dữ liệu tổng hợp: chạy scripts/gen_synthetic.jl trước")
    for f in files
        input = rootpath("data", "synthetic", f)
        ds = replace(f, ".txt" => "")
        r = measure_ours!(path, "E6", ds, input, minsup_e6, best, repeats, quick)
        s = measure_spmf!(path, "E6", ds, input, minsup_e6, "Eclat", repeats, quick)
        println("  E6 $f: nhóm ", get(r, "t_mine", r["status"]), " s, SPMF ", s.status, " ", s.algo_ms, " ms")
    end
end

"""E9: so với Apriori và FP-Growth của SPMF (một lần mỗi mức; dừng sớm khi quá thời gian)."""
function e9(datasets, grid, quick)
    path = joinpath(RES, "e9_algorithms.csv")
    for ds in datasets
        for algo in ("Apriori", "FPGrowth_itemsets")
            for ms in levels_for(grid, ds, quick)
                s = spmf_tmp(algo, dataset_path(ds), ms)
                record_spmf!(path, "E9", ds, ms, algo, 1, s)
                println("  E9 $ds $algo $ms: ", s.status, " ", s.algo_ms, " ms")
                s.status == :ok || break          # mức thấp hơn còn lâu hơn: bỏ qua
            end
        end
    end
end

# ---------------------------------------------------------------------------

function main(args)
    quick = "--quick" in args
    k = findfirst(==("--datasets"), args)
    datasets = k === nothing ? [d[1] for d in DATASETS] : String.(split(args[k+1], ","))
    k = findfirst(==("--repeats"), args)
    repeats = k === nothing ? REPEATS : parse(Int, args[k+1])
    exps = [a for a in args if occursin(r"^E\d+$|^all$", a)]
    "all" in exps && (exps = ["E1", "E2", "E4", "E5", "E6", "E9"])
    grid = load_grid()
    datasets = [d for d in datasets if isfile(dataset_path(d)) && haskey(grid, d)]
    println("Thí nghiệm: ", join(exps, ", "), " | bộ dữ liệu: ", join(datasets, ", "),
            quick ? " | CHẾ ĐỘ NHANH" : "")
    for e in exps
        t = time()
        println("== ", e)
        e == "E1" && e1(datasets, grid, quick)
        e == "E2" && e2(datasets, grid, quick, repeats; resume = "--resume" in args)
        e == "E4" && e4(datasets, grid, quick ? 1 : repeats)
        e == "E5" && e5(datasets, repeats, quick; resume = "--resume" in args)
        e == "E6" && e6(get(ENV, "E6_MINSUP", "0.5%"), repeats, quick)
        e == "E9" && e9(datasets, grid, quick)
        println("   (", round(time() - t; digits = 1), " s)")
    end
end

let t0 = time()
    main(ARGS)
    log_run("scripts/bench.jl", ARGS, time() - t0)
end
