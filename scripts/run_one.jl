# Chạy MỘT lần đo trong một tiến trình Julia mới (dùng cho E8, scripts/bench_ablation.jl).
# Giao thức giống bench.jl của B: tiến trình mới, khởi động (warm-up) trước, đo bằng time_ns(),
# không bật bộ đếm khi đo thời gian (quyết định D20).
#
#   julia --project=. scripts/run_one.jl <input> <minsup> <phiên bản> <output|NUL> [--stats]
#
# - Khởi động bằng CÙNG hàm mine_to_file và CÙNG phiên bản, trên hiệu sách và 2 CSDL của scripts/warmup.jl.
#   Hai CSDL này đi qua mọi nhánh code, kể cả nhánh dữ liệu thưa của v6, nên thời gian đo không chứa thời gian
#   biên dịch JIT.
# - Đo riêng hai phần: đọc file; khai thác + ghi kết quả ra file.
# - Đo kèm thời gian biên dịch nằm trong lần đo (t_compile). Đúng giao thức thì bằng 0.
# - --stats: chạy thêm MỘT lần có bộ đếm EclatStats (không tính giờ), in các bộ đếm.
# Kết quả in ra một dòng "RESULT k=v k=v ..." để tiến trình cha đọc.

using EclatFIM   # gói của nhóm
include(joinpath(@__DIR__, "warmup.jl"))           # write_warmup_dbs, WARMUP_MINSUP: dữ liệu khởi động dùng chung với bench.jl

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

# [VẤN ĐÁP] warmup — khởi động trước khi đo
# LÀM GÌ    : trên 3 CSDL nhỏ, chạy thử: đọc file; đổi minsup → số đếm; khai thác + ghi bằng CÙNG hàm mine_to_file;
#             nhánh có bộ đếm.
# VÌ SAO    : Julia biên dịch theo kiểu đối số, và mỗi hàm ẩn danh là một kiểu riêng. Khi gọi đúng mine_to_file, lambda
#             sink bên trong có cùng kiểu với lúc đo, nên bản đã biên dịch được dùng lại.
#             CSDL của warmup.jl đưa v6 qua nhánh dữ liệu thưa (lớp gốc vector, chuyển bitset → vector). Hiệu sách thì
#             không: N = 6 nên N/32 < 1.
# BẰNG CHỨNG: khi chỉ khởi động trên hiệu sách (trước 28/11), lần đo của v6 chứa 219 ms biên dịch trên retail 0,2% và
#             202 ms trên T10I4D100K 0,2%. Sau bản sửa, t_compile = 0.
"""Chạy thử toàn bộ đường đi (đọc, đổi minsup, khai thác, ghi, bộ đếm) trên dữ liệu nhỏ, để Julia biên dịch xong mọi nhánh trước khi đo."""
function warmup(cfg)   # khởi động: để Julia biên dịch xong mọi nhánh code trước khi đo
    mktempdir() do dir   # thư mục tạm, tự xóa khi khối do kết thúc
        out = joinpath(dir, "out.txt")   # file kết quả tạm
        dbs = [(joinpath(ROOT, "data", "toy", "bookstore.txt"), 2)]   # hiệu sách (6 giao dịch), σ = 2
        append!(dbs, [(p, WARMUP_MINSUP) for p in write_warmup_dbs(dir)])   # thêm 2 CSDL đi qua nhánh dữ liệu thưa (warmup.jl)
        for (path, σ) in dbs   # từng CSDL khởi động
            db = read_spmf(path)   # chạy thử bộ đọc file
            minsup_count(parse_minsup("50%"), n_transactions(db))   # chạy thử phép đổi minsup → số đếm (main gọi nó trong lúc đo)
            mine_to_file(db, σ, out, cfg)   # chạy thử khai thác → ghi bằng CÙNG hàm sẽ đo
            eclat!((i, s) -> nothing, db, σ, cfg; stats = EclatStats())   # chạy thử cả nhánh có bộ đếm (--stats)
        end
    end
    return nothing   # không trả gì
end

# [VẤN ĐÁP] run_one.jl — giao thức đo một lần
# HỎI–ĐÁP   : H: Vì sao thời gian đo gồm cả ghi file? Đ: giống chương trình thật (và giống cách đo của B, SPMF); việc đọc file
#             như nhau ở mọi phiên bản nên được đo riêng (t_read) và không tính vào t_mine.
#             H: GC.gc() để làm gì? Đ: dọn bộ nhớ của lần khởi động, để bộ dọn rác không chạy giữa lúc đo vì rác cũ.
#             H: t_compile để làm gì? Đ: kiểm chứng lần đo không chứa thời gian biên dịch JIT. Nếu > 0 thì phần khởi động
#             chưa đi qua hết các nhánh code mà lần đo dùng.
function main(args)   # một lần đo
    input, ms, vname, output = args[1:4]           # 4 tham số bắt buộc
    want_stats = "--stats" in args   # có cần lần chạy bộ đếm không
    cfg = VARIANTS[vname]                          # cấu hình của phiên bản cần đo (structures.jl)
    Base.cumulative_compile_timing(true)           # bật bộ đếm tổng thời gian biên dịch của Julia (để kiểm chứng warm-up)
    warmup(cfg)   # khởi động với CÙNG phiên bản sẽ đo
    GC.gc()                                        # dọn bộ nhớ của lần khởi động để không ảnh hưởng phép đo
    c0 = Base.cumulative_compile_time_ns()[1]      # tổng thời gian biên dịch tính đến trước lần đo (ns)
    t0 = time_ns()   # mốc bắt đầu (nano giây)
    db = read_spmf(input)                          # phần 1: đọc file
    t1 = time_ns()   # mốc sau khi đọc file
    σ = minsup_count(parse_minsup(ms), n_transactions(db))   # "1%" → số đếm, đúng quy tắc của SPMF
    sink_path = output == "NUL" ? (Sys.iswindows() ? "NUL" : "/dev/null") : output   # NUL: bỏ kết quả (Windows NUL, Linux /dev/null)
    n = mine_to_file(db, σ, sink_path, cfg)        # phần 2: khai thác + ghi kết quả
    t2 = time_ns()   # mốc sau khi khai thác + ghi
    c1 = Base.cumulative_compile_time_ns()[1]      # tổng thời gian biên dịch sau lần đo (ns)
    rss = Sys.maxrss()                             # RAM đỉnh của tiến trình (byte)
    fields = ["ntx=$(n_transactions(db))", "nitems=$(n_items(db))", "sigma=$σ", "n=$n",   # các trường kết quả
              "t_read=$((t1 - t0) / 1e9)", "t_mine=$((t2 - t1) / 1e9)", "maxrss=$rss",   # ns → giây
              "t_compile=$((c1 - c0) / 1e9)"]      # thời gian biên dịch nằm trong lần đo (đúng giao thức thì = 0)
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
