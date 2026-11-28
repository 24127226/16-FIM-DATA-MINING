# Kịch bản điều phối chạy toàn bộ thực nghiệm Chương 2 (E1, E2, E3, E4, E5, E6, E9).
#
# Cú pháp:
#   julia --project=. scripts/run_chapter2.jl --only e1,e2,e4 --repeats 3
#   julia --project=. scripts/run_chapter2.jl --only e5,e6,e9 --repeats 3

using Dates
using EclatFIM
include(joinpath(@__DIR__, "bench.jl"))
include(joinpath(@__DIR__, "compare_spmf.jl"))

"""Đo RAM nền (baseline RSS) của tiến trình Julia rỗng và JVM rỗng."""
function measure_baseline_rss()
    julia_exe = Base.julia_cmd()[1]
    r_j = run_with_timeout(`$julia_exe --project=$(ROOT) -e "println(Sys.maxrss() / 2^20)"`; timeout = 60)
    m_j = match(r"([\d.]+)", r_j.output)
    julia_base = m_j === nothing ? NaN : parse(Float64, m_j.captures[1])
    return (julia_mb = julia_base,)
end

"""E1: Kiểm tra tính đúng đắn 100% giữa EclatFIM (v0, v6) và SPMF Eclat trên toàn bộ lưới."""
function run_e1()
    grid = load_minsup_grid()
    out_csv = joinpath(RESULTS_DIR, "e1_correctness.csv")
    tmp_dir = joinpath(RESULTS_DIR, "tmp", "e1")
    mkpath(tmp_dir)
    open(out_csv, "w") do io
        println(io, "dataset,minsup,sigma_min,variant,n_ours,n_spmf,match_pct,only_ours,only_spmf,diff_support,mode,exact_match")
        for ds in BENCHMARK_DATASETS
            isfile(ds.path) || continue
            db = read_spmf(ds.path)
            n = n_transactions(db)
            for ms in get(grid, ds.name, String[])
                sig = minsup_count(ms, n)
                spmf_out = joinpath(tmp_dir, "spmf_$(ds.name).txt")
                r = run_spmf("Eclat", ds.path, spmf_out, ms; xmx = SPMF_XMX, timeout = 180)
                if r.status != :ok
                    println("  ! E1 bỏ qua $(ds.name) minsup=$ms (SPMF $(r.status))")
                    continue
                end
                for v in ("v0", "v6")
                    ours_out = joinpath(tmp_dir, "ours_$(ds.name)_$(v).txt")
                    open(ours_out, "w") do wio
                        w = SPMFWriter(wio, db)
                        eclat!((items, sup) -> write_itemset!(w, items, sup), db, sig, VARIANTS[v])
                        close_writer!(w)
                    end
                    cmp = compare_files(ours_out, spmf_out)
                    println(io, join([ds.name, ms, sig, v, cmp.n_ours, cmp.n_ref,
                                      isnan(cmp.match_pct) ? "" : round(cmp.match_pct; digits = 4),
                                      cmp.only_ours, cmp.only_ref, cmp.diff_support,
                                      cmp.mode, cmp.exact_match], ','))
                    flush(io)
                    rm(ours_out; force = true)
                    println("  E1 $(ds.name) $ms [$v]: n=$(cmp.n_ours), match=$(cmp.exact_match ? "100%" : "DIFF")")
                end
                rm(spmf_out; force = true)
            end
        end
    end
    println("Hoàn tất E1 -> $out_csv")
end

"""E2 & E3: Thời gian chạy và số tập phổ biến theo minsup (v0, v6, SPMF Eclat, SPMF Eclat_bitset)."""
function run_e2(; repeats::Int = 3)
    grid = load_minsup_grid()
    commit = git_short_commit()
    machine = machine_tag()
    date_str = Dates.format(today(), "yyyy-mm-dd")
    out_csv = joinpath(RESULTS_DIR, "e2_time.csv")
    tmp_dir = joinpath(RESULTS_DIR, "tmp", "e2")
    mkpath(tmp_dir)

    open(out_csv, "w") do io
        println(io, CSV_HEADER)
        for ds in BENCHMARK_DATASETS
            isfile(ds.path) || continue
            for ms in get(grid, ds.name, String[])
                for v in ("v0", "v6")
                    for rep in 1:repeats
                        out_tmp = joinpath(tmp_dir, "j_$(ds.name)_$(v)_$(rep).txt")
                        m = measure_julia_once(ds.path, ms, v, out_tmp; timeout = 180)
                        write_csv_row(io, ds.name, ms, "julia", v, rep, m, commit, machine, date_str)
                        rm(out_tmp; force = true)
                    end
                end
                for algo in ("Eclat", "Eclat_bitset")
                    for rep in 1:repeats
                        out_tmp = joinpath(tmp_dir, "s_$(ds.name)_$(algo)_$(rep).txt")
                        m = measure_spmf_once(algo, ds.path, ms, out_tmp; timeout = 180)
                        write_csv_row(io, ds.name, ms, "spmf", algo, rep, m, commit, machine, date_str)
                        rm(out_tmp; force = true)
                    end
                end
                println("  E2 xong $(ds.name) minsup=$ms ($repeats repeats)")
            end
        end
    end
    append_log(commit, "run_chapter2.jl --only e2 --repeats $repeats", "E2 & E3 -> $out_csv")
    println("Hoàn tất E2/E3 -> $out_csv")
end

"""E4: Bộ nhớ đỉnh tại minsup trung bình (mức thứ 4/7), gồm cả tidset_peak_bytes từ EclatStats."""
function run_e4()
    grid = load_minsup_grid()
    base = measure_baseline_rss()
    out_csv = joinpath(RESULTS_DIR, "e4_memory.csv")
    tmp_dir = joinpath(RESULTS_DIR, "tmp", "e4")
    mkpath(tmp_dir)

    open(out_csv, "w") do io
        println(io, "dataset,minsup,impl,variant,peak_rss_mb,baseline_rss_mb,delta_rss_mb,tidset_peak_bytes,n_itemsets")
        for ds in BENCHMARK_DATASETS
            isfile(ds.path) || continue
            ms_list = get(grid, ds.name, String[])
            length(ms_list) >= 4 || continue
            ms = ms_list[4]   # minsup trung vị (mức 4 trong 7 mức)

            db = read_spmf(ds.path)
            sig = minsup_count(ms, n_transactions(db))

            for v in ("v0", "v6")
                out_tmp = joinpath(tmp_dir, "j_$(ds.name)_$(v).txt")
                m = measure_julia_once(ds.path, ms, v, out_tmp; timeout = 180)
                rm(out_tmp; force = true)

                # Đo riêng tidset_peak_bytes bằng EclatStats (D20)
                st = EclatStats()
                eclat!((items, sup) -> nothing, db, sig, VARIANTS[v]; stats = st)
                delta = m.peak_rss_mb - base.julia_mb
                println(io, join([ds.name, ms, "julia", v,
                                  round(m.peak_rss_mb; digits = 3),
                                  round(base.julia_mb; digits = 3),
                                  round(delta; digits = 3),
                                  st.bytes_peak, m.n_itemsets], ','))
                flush(io)
            end
            for algo in ("Eclat", "Eclat_bitset")
                out_tmp = joinpath(tmp_dir, "s_$(ds.name)_$(algo).txt")
                m = measure_spmf_once(algo, ds.path, ms, out_tmp; timeout = 180)
                rm(out_tmp; force = true)
                println(io, join([ds.name, ms, "spmf", algo,
                                  round(m.peak_rss_mb; digits = 3), "", "", "", m.n_itemsets], ','))
                flush(io)
            end
            println("  E4 xong $(ds.name) minsup=$ms")
        end
    end
    println("Hoàn tất E4 -> $out_csv")
end

"""E5: Scalability trên Retail (10%, 25%, 50%, 75%, 100%) tại minsup = 0.2%."""
function run_e5(; repeats::Int = 3, ms::String = "0.2%")
    commit = git_short_commit()
    machine = machine_tag()
    date_str = Dates.format(today(), "yyyy-mm-dd")
    out_csv = joinpath(RESULTS_DIR, "e5_scalability.csv")
    tmp_dir = joinpath(RESULTS_DIR, "tmp", "e5")
    mkpath(tmp_dir)

    open(out_csv, "w") do io
        println(io, CSV_HEADER)
        for f in SUBSAMPLE_FRACS
            pct = round(Int, f * 100)
            path = joinpath(SUBSETS_DIR, "retail_$(pct)pct.txt")
            isfile(path) || continue
            ds_label = "retail_$(pct)pct"
            for v in ("v0", "v6")
                for rep in 1:repeats
                    out_tmp = joinpath(tmp_dir, "j_$(pct)_$(v)_$(rep).txt")
                    m = measure_julia_once(path, ms, v, out_tmp; timeout = 180)
                    write_csv_row(io, ds_label, ms, "julia", v, rep, m, commit, machine, date_str)
                    rm(out_tmp; force = true)
                end
            end
            for algo in ("Eclat", "Eclat_bitset")
                for rep in 1:repeats
                    out_tmp = joinpath(tmp_dir, "s_$(pct)_$(algo)_$(rep).txt")
                    m = measure_spmf_once(algo, path, ms, out_tmp; timeout = 180)
                    write_csv_row(io, ds_label, ms, "spmf", algo, rep, m, commit, machine, date_str)
                    rm(out_tmp; force = true)
                end
            end
            println("  E5 xong retail $(pct)%")
        end
    end
    append_log(commit, "run_chapter2.jl --only e5 --repeats $repeats", "E5 -> $out_csv")
    println("Hoàn tất E5 -> $out_csv")
end

"""E6: Ảnh hưởng độ dài giao dịch trung bình L̄ ∈ {5..30} trên dữ liệu tổng hợp."""
function run_e6(; repeats::Int = 3, ms::String = "1%")
    commit = git_short_commit()
    machine = machine_tag()
    date_str = Dates.format(today(), "yyyy-mm-dd")
    out_csv = joinpath(RESULTS_DIR, "e6_tx_length.csv")
    tmp_dir = joinpath(RESULTS_DIR, "tmp", "e6")
    mkpath(tmp_dir)

    open(out_csv, "w") do io
        println(io, "avg_len,actual_avg_len,max_itemset_len," * CSV_HEADER)
        for L in SYNTHETIC_AVG_LENS
            path = joinpath(SYNTHETIC_DIR, "synth_L$(L).txt")
            isfile(path) || continue
            db = read_spmf(path)
            actual_avg = round(sum(length(t) for t in db.transactions) / n_transactions(db); digits = 3)
            sig = minsup_count(ms, n_transactions(db))
            st = EclatStats()
            eclat!((items, sup) -> nothing, db, sig, VARIANTS["v6"]; stats = st)

            for v in ("v0", "v6")
                for rep in 1:repeats
                    out_tmp = joinpath(tmp_dir, "j_L$(L)_$(v)_$(rep).txt")
                    m = measure_julia_once(path, ms, v, out_tmp; timeout = 180)
                    print(io, "$L,$actual_avg,$(st.max_depth),")
                    write_csv_row(io, "synth_L$(L)", ms, "julia", v, rep, m, commit, machine, date_str)
                    rm(out_tmp; force = true)
                end
            end
            for algo in ("Eclat",)
                for rep in 1:repeats
                    out_tmp = joinpath(tmp_dir, "s_L$(L)_$(algo)_$(rep).txt")
                    m = measure_spmf_once(algo, path, ms, out_tmp; timeout = 180)
                    print(io, "$L,$actual_avg,$(st.max_depth),")
                    write_csv_row(io, "synth_L$(L)", ms, "spmf", algo, rep, m, commit, machine, date_str)
                    rm(out_tmp; force = true)
                end
            end
            println("  E6 xong L̄=$L (actual=$actual_avg, n_itemsets=$(st.n_itemsets), max_len=$(st.max_depth))")
        end
    end
    append_log(commit, "run_chapter2.jl --only e6 --repeats $repeats", "E6 -> $out_csv")
    println("Hoàn tất E6 -> $out_csv")
end

"""E9: So sánh EclatFIM (v6) với SPMF Apriori và FPGrowth_itemsets (H6)."""
function run_e9(; repeats::Int = 3)
    grid = load_minsup_grid()
    commit = git_short_commit()
    machine = machine_tag()
    date_str = Dates.format(today(), "yyyy-mm-dd")
    out_csv = joinpath(RESULTS_DIR, "e9_vs_apriori_fp.csv")
    tmp_dir = joinpath(RESULTS_DIR, "tmp", "e9")
    mkpath(tmp_dir)

    open(out_csv, "w") do io
        println(io, CSV_HEADER)
        for ds in BENCHMARK_DATASETS
            isfile(ds.path) || continue
            # Lấy 5 mức đại diện (mức 1, 2, 4, 6, 7) để Apriori trên dữ liệu dày không kéo dài quá lâu
            all_ms = get(grid, ds.name, String[])
            pick_idx = filter(k -> k <= length(all_ms), [1, 2, 4, 6, 7])
            for ms in all_ms[pick_idx]
                for rep in 1:repeats
                    out_tmp = joinpath(tmp_dir, "j_$(ds.name)_v6_$(rep).txt")
                    m = measure_julia_once(ds.path, ms, "v6", out_tmp; timeout = 60)
                    write_csv_row(io, ds.name, ms, "julia", "v6", rep, m, commit, machine, date_str)
                    rm(out_tmp; force = true)
                end
                for algo in ("Apriori", "FPGrowth_itemsets")
                    for rep in 1:repeats
                        out_tmp = joinpath(tmp_dir, "s_$(ds.name)_$(algo)_$(rep).txt")
                        m = measure_spmf_once(algo, ds.path, ms, out_tmp; timeout = 60)
                        write_csv_row(io, ds.name, ms, "spmf", algo, rep, m, commit, machine, date_str)
                        rm(out_tmp; force = true)
                        m.status == :timeout && break   # quá 60s thì không lặp thêm
                    end
                end
                println("  E9 xong $(ds.name) minsup=$ms")
            end
        end
    end
    append_log(commit, "run_chapter2.jl --only e9 --repeats $repeats", "E9 -> $out_csv")
    println("Hoàn tất E9 -> $out_csv")
end

function run_cli(args::Vector{String})
    only = Set(["e1", "e2", "e4", "e5", "e6", "e9"])
    repeats = 3
    i = 1
    while i <= length(args)
        if args[i] == "--only" && i < length(args)
            only = Set(lowercase.(split(args[i + 1], ','))); i += 2
        elseif args[i] == "--repeats" && i < length(args)
            repeats = parse(Int, args[i + 1]); i += 2
        else
            error("Tham số không hợp lệ: $(args[i])")
        end
    end
    "e1" in only && run_e1()
    "e2" in only && run_e2(; repeats = repeats)
    "e4" in only && run_e4()
    "e5" in only && run_e5(; repeats = repeats)
    "e6" in only && run_e6(; repeats = repeats)
    "e9" in only && run_e9(; repeats = repeats)
    return 0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(run_cli(ARGS))
end
