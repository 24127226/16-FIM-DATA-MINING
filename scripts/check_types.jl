# Kiểm tra ổn định kiểu của các hàm nóng bằng code_warntype (phần của B, nhận thêm khi chia lại; yêu cầu R22 của đề:
# không dùng biến global không định kiểu, không dùng abstract type trong vòng lặp nóng).
#
#   julia --project=. scripts/check_types.jl
#
# Một hàm "ổn định kiểu" khi trình biên dịch suy ra được kiểu cụ thể cho mọi biến và giá trị trả về,
# nhờ vậy sinh được mã máy nhanh. Kết quả ghi vào results/type_stability.md.

using EclatFIM, InteractiveUtils
const E = EclatFIM
include(joinpath(@__DIR__, "common.jl"))

function main()
    db = read_spmf(rootpath("data", "toy", "bookstore.txt"))
    supp = E.item_supports(db)
    fr = E.frequent_items(supp, 3, :support_asc)
    ws = E.Workspace(E.VecLevel[], E.BitLevel[], 6, 6 / 32, Int[])
    root = E._root_vec(db, fr, supp)
    broot = E._root_bit(db, fr, supp)
    push!(ws.vec, root)
    push!(ws.bit, broot)
    sink = (i, s) -> nothing
    checks = [
        ("isect_merge!", E.isect_merge!, (Int32[0, 0], 1, Int32[1, 2], 1, 2, Int32[2, 3], 1, 2)),
        ("isect_adaptive!", E.isect_adaptive!, (Int32[0, 0], 1, Int32[1, 2], 1, 2, Int32[2, 3], 1, 2, 1)),
        ("and_count!", E.and_count!, (falses(6), trues(6), trues(6))),
        ("and_extract!", E.and_extract!, (zeros(Int32, 6), 1, trues(6), trues(6))),
        ("_vec_from_vec!", E._vec_from_vec!, (E.VecLevel(), root, 1, 2:3, 3, Val(:adaptive), nothing)),
        ("_bit_from_bit!", E._bit_from_bit!, (E.BitLevel(), broot, 1, 2:3, 3, nothing, 6)),
        ("_vec_from_bit!", E._vec_from_bit!, (E.VecLevel(), broot, 1, 2:3, 3, nothing)),
        ("_mine_vec!", E._mine_vec!, (sink, Int32[], ws, 1, 3, Val(:adaptive), nothing, 10)),
        ("_mine_bit!", E._mine_bit!, (sink, Int32[], ws, 1, 3, Val(:adaptive), nothing, 10)),
        ("_mine_vec! (có bộ đếm)", E._mine_vec!, (sink, Int32[], ws, 1, 3, Val(:adaptive), EclatStats(), 10)),
        ("pair_counts", E.pair_counts, (db, zeros(Int32, 5), 0)),
        ("parse_spmf", E.parse_spmf, (UInt8[0x31, 0x0a],)),
    ]
    out = IOBuffer()
    println(out, "# Ổn định kiểu của các hàm nóng\n")
    println(out, "Sinh bởi `scripts/check_types.jl` (code_warntype, Julia ", VERSION, ").\n")
    println(out, "| Hàm | Kết quả | Kiểu trả về |")
    println(out, "|---|---|---|")
    ok_all = true
    for (name, f, args) in checks
        io = IOBuffer()
        code_warntype(io, f, Base.typesof(args...))
        s = String(take!(io))
        body = split(s, "Body::")[2]
        unstable = occursin(r"::Any\b", body) || occursin(r"::Union\{(?!Nothing, ?(EclatStats|Vector\{UInt32\}))", body)
        ok_all &= !unstable
        ret = strip(split(body, "\n")[1])
        println(out, "| `", name, "` | ", unstable ? "⚠ không ổn định" : "✓ ổn định", " | `", ret, "` |")
    end
    println(out, "\n`pair_counts` trả về `Union{Nothing, Vector{UInt32}}` có chủ đích (`nothing` khi mảng tam giác ",
            "vượt giới hạn bộ nhớ); đây là union nhỏ, Julia xử lý bằng tách nhánh theo kiểu (union splitting) nên không ",
            "làm chậm vòng lặp nóng.")
    path = rootpath("results", "type_stability.md")
    write(path, String(take!(out)))
    println(read(path, String))
    ok_all || error("Có hàm nóng không ổn định kiểu")
end

main()
