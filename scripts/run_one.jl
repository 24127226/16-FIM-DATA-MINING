# Chạy MỘT lần đo trong một tiến trình Julia mới (giao thức đo, KE_HOACH_DU_AN.md mục 8.5).
# Được scripts/bench*.jl gọi; ít khi cần chạy tay.
#
#   julia --project=. scripts/run_one.jl <input> <minsup> <phiên bản> <output|NUL> [--stats] [--maxlen K]
#   julia --project=. scripts/run_one.jl --baseline <phiên bản>
#
# - Chạy khởi động (warm-up) trên dữ liệu toy với CÙNG phiên bản, để thời gian đo không chứa JIT.
# - Đo riêng: đọc file; khai thác + ghi kết quả.
# - --stats: chạy thêm một lần có bộ đếm (không tính giờ), in số phép giao, byte tidset đỉnh...
# - --baseline: chỉ khởi động, để đo RAM nền của tiến trình Julia.
# Kết quả in ra một dòng "RESULT k=v k=v ...".

using EclatFIM

const ROOT = normpath(joinpath(@__DIR__, ".."))

function warmup(cfg)
    db = read_spmf(joinpath(ROOT, "data", "toy", "bookstore.txt"))
    out = tempname()
    mine_to_file(db, 2, out, cfg)
    eclat!((i, s) -> nothing, db, 2, cfg; stats = EclatStats())
    rm(out)
    return nothing
end

function main(args)
    if !isempty(args) && args[1] == "--baseline"
        warmup(VARIANTS[args[2]])
        println("RESULT maxrss=", Sys.maxrss())
        return
    end
    input, ms, vname, output = args[1:4]
    want_stats = "--stats" in args
    k = findfirst(==("--maxlen"), args)
    maxlen = k === nothing ? typemax(Int) : parse(Int, args[k+1])
    cfg = VARIANTS[vname]
    warmup(cfg)
    GC.gc()
    t0 = time_ns()
    db = read_spmf(input)
    t1 = time_ns()
    σ = minsup_count(parse_minsup(ms), n_transactions(db))
    sink_path = output == "NUL" ? (Sys.iswindows() ? "NUL" : "/dev/null") : output
    n = mine_to_file(db, σ, sink_path, cfg; maxlen = maxlen)
    t2 = time_ns()
    rss = Sys.maxrss()
    fields = ["ntx=$(n_transactions(db))", "nitems=$(n_items(db))", "sigma=$σ", "n=$n",
              "t_read=$((t1 - t0) / 1e9)", "t_mine=$((t2 - t1) / 1e9)", "maxrss=$rss"]
    if want_stats
        st = EclatStats()
        eclat!((i, s) -> nothing, db, σ, cfg; stats = st, maxlen = maxlen)
        for f in fieldnames(EclatStats)
            push!(fields, "$(f)=$(getfield(st, f))")
        end
    end
    println("RESULT ", join(fields, " "))
end

main(ARGS)
