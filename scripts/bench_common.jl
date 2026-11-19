# Hàm đo dùng chung cho các script thực nghiệm (bench.jl của B; bench_ablation.jl,
# bench_density.jl, bench_memory_trace.jl của A). Mỗi lần đo chạy trong một tiến trình Julia mới
# (scripts/run_one.jl) theo giao thức ở KE_HOACH_DU_AN.md mục 8.5.
# Yêu cầu: script gọi file này phải `using EclatFIM` và đã include config.jl.

const JULIA_BIN = joinpath(Sys.BINDIR, Base.julia_exename())
const RUN_ONE = rootpath("scripts", "run_one.jl")
const RES = results_dir()

# ---------------------------------------------------------------------------
# Chạy một lần đo
# ---------------------------------------------------------------------------

"""Chạy code của nhóm trong một tiến trình mới (scripts/run_one.jl). Trả về Dict các trường."""
function run_ours(input, ms, variant; out = "NUL", stats = false, maxlen = nothing, timeout = TIMEOUT_S)
    args = String[input, ms, variant, out]
    stats && push!(args, "--stats")
    maxlen === nothing || append!(args, ["--maxlen", string(maxlen)])
    r = run_with_timeout(`$(JULIA_BIN) --project=$(ROOT) $(RUN_ONE) $(args)`; timeout = timeout)
    res = Dict{String,String}("status" => string(r.status), "wall" => string(r.wall_s))
    if r.status == :ok
        m = match(r"RESULT (.*)", r.output)
        m === nothing && (res["status"] = "error"; return res)
        for kv in split(m.captures[1])
            k, v = split(kv, "=", limit = 2)
            res[k] = v
        end
    else
        res["error"] = first(replace(r.output, '\n' => ' '), 300)
    end
    return res
end

"""RAM nền của một tiến trình Julia đã nạp gói và khởi động xong (byte)."""
function baseline_rss(variant)
    r = run_with_timeout(`$(JULIA_BIN) --project=$(ROOT) $(RUN_ONE) --baseline $(variant)`; timeout = 300)
    m = match(r"maxrss=(\d+)", r.output)
    return m === nothing ? -1 : parse(Int, m.captures[1])
end

repeats_for(seconds, base) = seconds < 1 ? max(base, REPEATS_SHORT) : base

"""Chạy code của nhóm, ghi kết quả ra file tạm (như SPMF) rồi xóa file đó."""
function ours_tmp(input, ms, variant; kw...)
    out = tempname()
    try
        return run_ours(input, ms, variant; out = out, kw...)
    finally
        isfile(out) && rm(out)
    end
end

"""Chạy SPMF, ghi kết quả ra file tạm rồi xóa file đó."""
function spmf_tmp(algo, input, ms)
    out = tempname()
    try
        return run_spmf(algo, input, out, ms; xmx = JAVA_XMX, timeout = TIMEOUT_S)
    finally
        isfile(out) && rm(out)
    end
end

# ---------------------------------------------------------------------------
# Các thí nghiệm
# ---------------------------------------------------------------------------

const HEADER_RUN = ["experiment", "dataset", "kind", "minsup", "sigma", "impl", "variant", "repeat",
                    "status", "n_itemsets", "t_read_s", "t_algo_s", "t_wall_s", "maxrss_mb",
                    "heap_mb", "commit", "machine", "date"]

function record_ours!(path, exp, ds, ms, variant, rep, r)
    p = provenance()
    ok = r["status"] == "ok"
    append_csv(path, HEADER_RUN, [exp, ds, dataset_kind_or(ds), ms, get(r, "sigma", ""), "nhom", variant, rep,
        r["status"], ok ? r["n"] : "", ok ? r["t_read"] : "", ok ? r["t_mine"] : "", r["wall"],
        ok ? round(parse(Int, r["maxrss"]) / 2^20; digits = 1) : "", "", p.commit, p.machine, p.date])
end

function record_spmf!(path, exp, ds, ms, algo, rep, s::SPMFRun)
    p = provenance()
    ok = s.status == :ok
    append_csv(path, HEADER_RUN, [exp, ds, dataset_kind_or(ds), ms, "", "spmf", algo, rep, string(s.status),
        ok ? s.n_itemsets : "", "", ok ? s.algo_ms / 1000 : "", s.wall_s, "", ok ? s.heap_mb : "",
        p.commit, p.machine, p.date])
end

"""
Đo một cấu hình của nhóm theo giao thức: chạy lần 1, rồi lặp thêm cho đủ `repeats` lần
(`REPEATS_SHORT` lần nếu lần 1 dưới 1 giây). Trả về kết quả lần 1.
"""
function measure_ours!(path, exp, ds, input, ms, variant, repeats, quick)
    r = ours_tmp(input, ms, variant)
    record_ours!(path, exp, ds, ms, variant, 1, r)
    r["status"] == "ok" || return r
    nrep = quick ? 1 : repeats_for(parse(Float64, r["t_mine"]), repeats)
    for rep in 2:nrep
        record_ours!(path, exp, ds, ms, variant, rep, ours_tmp(input, ms, variant))
    end
    return r
end

"""Như `measure_ours!` nhưng cho SPMF; dừng lặp nếu một lần chạy lỗi hoặc quá thời gian."""
function measure_spmf!(path, exp, ds, input, ms, algo, repeats, quick)
    s = spmf_tmp(algo, input, ms)
    record_spmf!(path, exp, ds, ms, algo, 1, s)
    s.status == :ok || return s
    nrep = quick ? 1 : repeats_for(s.algo_ms / 1000, repeats)
    for rep in 2:nrep
        s2 = spmf_tmp(algo, input, ms)
        record_spmf!(path, exp, ds, ms, algo, rep, s2)
        s2.status == :ok || break
    end
    return s
end

dataset_kind_or(ds) = any(d -> d[1] == ds, DATASETS) ? dataset_kind(ds) : "tổng hợp"

function levels_for(grid, ds, quick)
    lv = grid[ds]
    quick ? unique([lv[1], median_minsup(lv), lv[end]]) : lv
end
