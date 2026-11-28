# Dữ liệu khởi động (warm-up) dùng chung cho các script đo thời gian:
#   - scripts/run_one.jl (E8 của A, gọi qua scripts/bench_common.jl);
#   - scripts/bench.jl   (E2–E6, E9 của B).
#
# Vì sao cần file này: Julia biên dịch (JIT) một phương thức ở lần gọi đầu tiên với mỗi bộ kiểu đối số.
# Phương thức nào chưa được gọi thì chưa được biên dịch. Bản lai v6 có hai nhánh chỉ chạy trên dữ liệu thưa:
#   (1) lớp gốc dạng vector: khi mật độ trung bình của lớp gốc < hybrid_ratio = 1/32 (`_mine_root!` cho VecLevel);
#   (2) chuyển lớp con bitset → vector: khi chặn trên support của lớp con < N/32 (`_mine_vec!` dưới lớp gốc bitset).
# Dữ liệu toy chỉ có 5–6 giao dịch (N/32 < 1), nên không bao giờ đi vào hai nhánh này. Trước bản sửa, phần biên dịch
# của hai nhánh rơi vào lần đo được bấm giờ: khoảng 0,2 s với v6 trên retail và T10I4D100K, máy i5-6200U.
# Hai CSDL sinh trong file này buộc mọi nhánh chạy ít nhất một lần trước khi bấm giờ.

const WARMUP_N = 640        # số giao dịch của mỗi CSDL khởi động; ngưỡng chuyển của v6 là N/32 = 20
const WARMUP_MINSUP = 5     # minsup (số đếm) khi khởi động; item thưa (support 8–10) vẫn phổ biến

# [VẤN ĐÁP] write_warmup_dbs — dữ liệu khởi động đi qua mọi nhánh code
# LÀM GÌ    : ghi 2 CSDL dạng SPMF, mỗi CSDL 640 giao dịch.
#             - "mixed": 4 item dày, 8 item thưa (support 10) và item 13 có mặt ở mọi giao dịch.
#             - "sparse": 100 item, mỗi item support 8.
# VÌ SAO    : "mixed": mật độ lớp gốc ≈ 0,30 ≥ 1/32, nên v6 dựng lớp gốc bitset. Item thưa có support 10 < N/32 = 20,
#             nên v6 chuyển lớp con sang vector (nhánh 2). Tidset dày (320–640 tid) so với tidset thưa (10 tid) chênh
#             hơn 16 lần, nên v3 đi vào nhánh tìm kiếm nhảy (galloping).
#             "sparse": mật độ lớp gốc = 8/640 = 0,0125 < 1/32, nên v6 dựng lớp gốc dạng vector (nhánh 1).
# BẰNG CHỨNG: sau bản sửa, cột t_compile_s (thời gian biên dịch trong lần đo được bấm giờ) của results/e8_ablation*.csv
#             bằng 0 ở cả 7 phiên bản trên 4 bộ benchmark.
# HỎI–ĐÁP   : H: Sao không khởi động trên chính dữ liệu cần đo?
#             Đ: Như vậy tốn gấp đôi thời gian (v0 trên retail 0,1% mất khoảng 10 s). JIT biên dịch theo kiểu dữ liệu,
#             không theo kích thước dữ liệu, nên một CSDL nhỏ đi qua đủ các nhánh là đủ.
#             H: Vì sao số giao dịch là 640?
#             Đ: 640 = 32 × 20, nên ngưỡng chuyển N/32 = 20 lớn hơn support 8–10 của item thưa, mà dữ liệu vẫn rất nhỏ.
"""
    write_warmup_dbs(dir) -> Vector{String}

Ghi hai CSDL khởi động (`warmup_mixed.txt`, `warmup_sparse.txt`) vào thư mục `dir` theo định dạng SPMF
và trả về đường dẫn của hai file.
"""
function write_warmup_dbs(dir::AbstractString)
    mixed = joinpath(dir, "warmup_mixed.txt")          # CSDL 1: lớp gốc bitset và chuyển lớp con sang vector
    open(mixed, "w") do io                             # mỗi dòng của file là một giao dịch
        for t in 1:WARMUP_N                            # giao dịch thứ t
            items = Int[13]                            # item 13 có mặt ở mọi giao dịch, nên không có dòng rỗng
            for k in 1:4                               # 4 item dày: item k vắng ở giao dịch có t chia hết cho k + 1
                t % (k + 1) != 0 && push!(items, k)    # support của item k: 320, 427, 480, 512
            end
            for s in 0:7                               # 8 item thưa 5..12: item 5 + s có mặt khi t mod 64 = s
                t % 64 == s && push!(items, 5 + s)     # support = 640 / 64 = 10 < N/32 = 20, nên v6 chuyển sang vector
            end
            println(io, join(sort!(items), ' '))       # một dòng SPMF: item tăng dần, cách nhau dấu cách
        end
    end
    sparse = joinpath(dir, "warmup_sparse.txt")        # CSDL 2: lớp gốc dạng vector
    open(sparse, "w") do io                            # mỗi dòng của file là một giao dịch
        for t in 1:WARMUP_N                            # giao dịch thứ t
            items = [j for j in 1:100 if (t + 7j) % 80 == 0]   # item j có mặt khi t + 7j chia hết cho 80: support 8
            println(io, join(items, ' '))              # j tăng dần nên dòng đã đúng thứ tự; mỗi t luôn có ít nhất một j
        end
    end
    return [mixed, sparse]                             # đường dẫn của hai file
end
