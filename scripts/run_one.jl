# Chạy MỘT lần đo trong một tiến trình Julia mới (dùng cho E8, scripts/bench_ablation.jl).
# Giao thức giống bench.jl của B: tiến trình mới, khởi động (warm-up) trước, đo bằng time_ns(),
# không bật bộ đếm khi đo thời gian (quyết định D20).
#
#   julia --project=. scripts/run_one.jl <input> <minsup> <phiên bản> <output|NUL> [--stats]
#
# - Khởi động trên dữ liệu toy với CÙNG phiên bản, để thời gian đo không chứa thời gian biên dịch JIT.
# - Đo riêng hai phần: đọc file; khai thác + ghi kết quả ra file.
# - --stats: chạy thêm MỘT lần có bộ đếm EclatStats (không tính giờ), in các bộ đếm.
# Kết quả in ra một dòng "RESULT k=v k=v ..." để tiến trình cha đọc.

using EclatFIM   # gói của nhóm

const ROOT = normpath(joinpath(@__DIR__, ".."))    # thư mục gốc repo (file này nằm trong scripts/)

"""Khai thác `db` và ghi mọi tập phổ biến ra `path` theo định dạng SPMF (bộ ghi có đệm của B). Trả về số tập."""
function mine_to_file(db, σ, path, cfg)   # khai thác và ghi kết quả như chương trình thật
    open(path, "w") do io   # mở file kết quả
        w = SPMFWriter(io, db)                     # bộ ghi có đệm 1 MiB, đổi mã nội bộ → mã gốc
        eclat!((items, s) -> write_itemset!(w, items, s), db, σ, cfg)   # sink: ghi từng tập ngay khi tìm được
        close_writer!(w)                           # ghi phần còn trong đệm ra file
        return w.count                             # số tập đã ghi
    end
end

"""Chạy thử toàn bộ đường đi (đọc, khai thác, ghi, bộ đếm) trên dữ liệu nhỏ để Julia biên dịch xong trước khi đo."""
function warmup(cfg)   # khởi động: để Julia biên dịch xong trước khi đo
    db = read_spmf(joinpath(ROOT, "data", "toy", "bookstore.txt"))   # dữ liệu nhỏ (hiệu sách)
    out = tempname()   # file tạm
    mine_to_file(db, 2, out, cfg)   # chạy thử đường đi đọc → khai thác → ghi
    eclat!((i, s) -> nothing, db, 2, cfg; stats = EclatStats())   # chạy thử cả nhánh có bộ đếm
    rm(out)   # xóa file tạm
    return nothing   # không trả gì
end

# [VẤN ĐÁP] run_one.jl — giao thức đo một lần
# HỎI–ĐÁP   : H: Vì sao thời gian đo gồm cả ghi file? Đ: giống chương trình thật (và giống cách đo của B, SPMF); việc đọc file
#             như nhau ở mọi phiên bản nên được đo riêng (t_read) và không tính vào t_mine.
#             H: GC.gc() để làm gì? Đ: dọn bộ nhớ của lần khởi động, để bộ dọn rác không chạy giữa lúc đo vì rác cũ.
function main(args)   # một lần đo
    input, ms, vname, output = args[1:4]           # 4 tham số bắt buộc
    want_stats = "--stats" in args   # có cần lần chạy bộ đếm không
    cfg = VARIANTS[vname]                          # cấu hình của phiên bản cần đo (structures.jl)
    warmup(cfg)   # khởi động với CÙNG phiên bản sẽ đo
    GC.gc()                                        # dọn bộ nhớ của lần khởi động để không ảnh hưởng phép đo
    t0 = time_ns()   # mốc bắt đầu (nano giây)
    db = read_spmf(input)                          # phần 1: đọc file
    t1 = time_ns()   # mốc sau khi đọc file
    σ = minsup_count(parse_minsup(ms), n_transactions(db))   # "1%" → số đếm, đúng quy tắc của SPMF
    sink_path = output == "NUL" ? (Sys.iswindows() ? "NUL" : "/dev/null") : output   # NUL: bỏ kết quả (Windows NUL, Linux /dev/null)
    n = mine_to_file(db, σ, sink_path, cfg)        # phần 2: khai thác + ghi kết quả
    t2 = time_ns()   # mốc sau khi khai thác + ghi
    rss = Sys.maxrss()                             # RAM đỉnh của tiến trình (byte)
    fields = ["ntx=$(n_transactions(db))", "nitems=$(n_items(db))", "sigma=$σ", "n=$n",   # các trường kết quả
              "t_read=$((t1 - t0) / 1e9)", "t_mine=$((t2 - t1) / 1e9)", "maxrss=$rss"]   # ns → giây
    if want_stats                                  # lần chạy riêng để lấy bộ đếm (không tính giờ)
        st = EclatStats()   # bộ đếm mới
        eclat!((i, s) -> nothing, db, σ, cfg; stats = st)   # lần chạy có bộ đếm, không tính giờ
        for f in fieldnames(EclatStats)   # mọi trường của bộ đếm
            push!(fields, "$(f)=$(getfield(st, f))")   # tên=giá trị
        end
    end
    println("RESULT ", join(fields, " "))   # một dòng để tiến trình cha đọc
end

main(ARGS)   # chạy với tham số dòng lệnh
