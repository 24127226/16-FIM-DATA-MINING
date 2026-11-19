# Đối chiếu kết quả của nhóm với SPMF trên một CSDL và một mức minsup.
#
# Cách dùng (từ gốc repo):
#   julia --project=. scripts/compare_spmf.jl <file_input> <minsup> [--variant v0] [--algo Eclat] [--keep]
# Ví dụ:
#   julia --project=. scripts/compare_spmf.jl data/benchmark/chess.txt 80%
#
# - Hai bên nhận CÙNG MỘT chuỗi minsup (ví dụ "80%"), để σ_min tính ra giống hệt nhau.
# - Kết quả ≤ 3 triệu tập: so chi tiết từng tập (tỉ lệ khớp theo mục 7.2 của kế hoạch).
#   Lớn hơn: so dấu vân tay (số tập + tổng băm), không cần nạp vào bộ nhớ.
# - Mã thoát 0 nếu khớp 100%, 1 nếu không.

using EclatFIM
include(joinpath(@__DIR__, "common.jl"))

const DETAIL_LIMIT = 3_000_000

function parse_cli(args)
    length(args) >= 2 || error("cần <file_input> <minsup>")
    opts = Dict{String,String}("variant" => "v0", "algo" => "Eclat")
    keep = false
    rest = String[]
    i = 1
    while i <= length(args)
        a = args[i]
        if a in ("--variant", "--algo")
            opts[a[3:end]] = args[i+1]; i += 2
        elseif a == "--keep"
            keep = true; i += 1
        else
            push!(rest, a); i += 1
        end
    end
    return (input = rest[1], minsup = rest[2], variant = opts["variant"], algo = opts["algo"], keep = keep)
end

function main(args)
    o = parse_cli(args)
    cfg = VARIANTS[o.variant]
    dir = mktempdir()
    ours_path = joinpath(dir, "ours.txt")
    ref_path = joinpath(dir, "spmf.txt")

    t0 = time_ns()
    db = read_spmf(o.input)
    σ = minsup_count(parse_minsup(o.minsup), n_transactions(db))
    t1 = time_ns()
    n_ours = mine_to_file(db, σ, ours_path, cfg)
    t2 = time_ns()
    r = run_spmf(o.algo, o.input, ref_path, o.minsup)
    r.status == :ok || error("SPMF lỗi:\n" * r.output)

    println("Input        : ", o.input, "  (N = ", n_transactions(db), ", m = ", n_items(db), ")")
    println("minsup       : ", o.minsup, "  → σ_min = ", σ)
    println("Nhóm (", o.variant, ")   : ", n_ours, " tập; đọc ", round((t1 - t0) / 1e9; digits = 3),
            " s, khai thác + ghi ", round((t2 - t1) / 1e9; digits = 3), " s (gồm biên dịch JIT lần đầu)")
    println("SPMF ", rpad(o.algo, 8), ": ", r.n_itemsets, " tập; thuật toán ", r.algo_ms, " ms, tiến trình ",
            round(r.wall_s; digits = 3), " s; N SPMF đếm = ", r.n_tx)

    ok = false
    if n_ours <= DETAIL_LIMIT && r.n_itemsets <= DETAIL_LIMIT
        c = compare_itemsets(load_itemsets(ours_path), load_itemsets(ref_path))
        ok = c.rate == 1.0
        println("So chi tiết  : khớp ", c.matched, "/", c.n_ours + c.only_ref,
                " (", round(100c.rate; digits = 4), "%); lệch support ", c.diff_support,
                ", chỉ nhóm có ", c.only_ours, ", chỉ SPMF có ", c.only_ref)
    else
        fo, fr = fingerprint(ours_path), fingerprint(ref_path)
        ok = fo == fr
        println("Dấu vân tay  : nhóm ", fo, " | SPMF ", fr, ok ? "  → KHỚP" : "  → KHÁC")
    end
    if o.keep
        println("Giữ file kết quả ở ", dir)
    else
        rm(dir; recursive = true)
    end
    println(ok ? "✅ KHỚP 100%" : "❌ KHÔNG KHỚP")
    return ok ? 0 : 1
end

exit(main(ARGS))
