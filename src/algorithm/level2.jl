# Tính các tập 2 item bằng mảng tam giác trên (phần của A, dùng từ v5).
#
# Bài báo gốc (Zaki, 2000, §5.1): giao từng cặp item để tìm tập 2 item tốn C(m_f, 2) phép giao,
# rất chậm khi có nhiều item phổ biến. Thay vào đó, đổi dữ liệu về dạng ngang và ĐẾM mọi cặp
# item phổ biến trong một mảng hai chiều tam giác trên. Sau đó chỉ cần giao tidset cho những cặp
# đã biết chắc là phổ biến.
#
# Chi phí: Σ_j C(|T_j ∩ F1|, 2) = O(N · L̄²) phép cộng, cần m_f·(m_f-1)/2 bộ đếm.
#
# Vì sao có lợi: ở mức 2, phần lớn cặp item KHÔNG phổ biến. Bản giao từng cặp vẫn phải giao
# tidset (dài) của từng cặp rồi mới biết nó trượt ngưỡng. Mảng tam giác cho biết support của
# mọi cặp chỉ sau một lần quét dữ liệu, nên các cặp trượt ngưỡng bị loại mà không cần giao.
#
# Vì sao là "tam giác trên": cặp (r, s) và (s, r) là một, và không có cặp (r, r), nên chỉ cần
# các ô có r < s, tức nửa trên đường chéo của ma trận m_f × m_f. Lưu nửa đó liền nhau trong
# một mảng 1 chiều, theo từng hàng, để tiết kiệm một nửa bộ nhớ.
#
# Ví dụ với m_f = 4: hàng 1 có 3 ô (1,2) (1,3) (1,4) ở vị trí 1..3; hàng 2 có 2 ô (2,3) (2,4)
# ở vị trí 4..5; hàng 3 có 1 ô (3,4) ở vị trí 6.
#
# [VẤN ĐÁP] CẢ FILE (tối ưu v5)
# BẰNG CHỨNG: E8, minsup thấp nhất (bảng B03, B04): retail 0,1%: bỏ qua 2.236.526 cặp, số phép giao 2,24 triệu
#             → 8.038, nhanh hơn v4 24,5 lần; T10I4D100K 0,2%: 292.768 → 22.430 phép giao, nhanh hơn 4,2 lần.
#             Ngược lại chess, mushroom (ít item phổ biến, chỉ bỏ qua 98 và 558 cặp): chậm hơn v4 11–15%.
#             Retail 1% (minsup giữa): chậm hơn v4 (34,0 so với 20,5 ms) vì chỉ có 2.458 phép giao để tiết kiệm.
# HỎI–ĐÁP   : H: Khi nào mảng tam giác có lợi?
#             Đ: Khi số cặp C(m_f, 2) lớn so với chi phí quét N·L̄²/2 phép cộng, tức nhiều item phổ biến mà phần lớn
#                cặp trượt ngưỡng (dữ liệu thưa). Với ít item phổ biến, giao từng cặp bằng dãy bit đã rẻ hơn.
#             H: Bộ nhớ của mảng là bao nhiêu? Đ: C(m_f, 2) × 4 byte; ví dụ 870 item → 378.015 ô ≈ 1,5 MB.

# [VẤN ĐÁP] tri_index
# LÀM GÌ    : đổi cặp (r, s) với r < s thành vị trí trong mảng 1 chiều.
# VÌ SAO    : trước hàng r có (mf-1) + (mf-2) + ... + (mf-r+1) = (r-1)(2mf-r)/2 ô; ô (r, s) là ô thứ (s - r) của hàng r.
# HỎI–ĐÁP   : H: Kiểm tra công thức với mf = 4, cặp (2, 4)? Đ: (2-1)(8-2)/2 + (4-2) = 3 + 2 = 5, đúng vị trí 5.
"""
Vị trí của cặp `(r, s)`, `1 ≤ r < s ≤ mf`, trong mảng tam giác trên lưu theo hàng:
hàng r có `mf - r` ô, nên trước hàng r có `(r-1)(2mf-r)/2` ô.
"""
@inline tri_index(r::Integer, s::Integer, mf::Integer) = (r - 1) * (2mf - r) ÷ 2 + (s - r)   # số ô trước hàng r + vị trí trong hàng

# [VẤN ĐÁP] TRI_MAX_CELLS
# VÌ SAO    : chặn bộ nhớ của mảng ở 1 GiB; vượt quá thì pair_counts trả nothing và eclat.jl quay về giao từng cặp,
#             nên chương trình không bao giờ hết bộ nhớ vì tối ưu này (kết quả vẫn đúng, chỉ chậm hơn).
"""Giới hạn số bộ đếm (≈ 1 GiB); vượt quá thì quay về giao từng cặp."""
const TRI_MAX_CELLS = 1 << 28      # 2^28 ô × 4 byte (UInt32) = 1 GiB

# [VẤN ĐÁP] pair_counts
# LÀM GÌ    : một lần quét dữ liệu ngang, cộng 1 cho mọi cặp item phổ biến cùng xuất hiện trong một giao dịch.
# CHI PHÍ   : Σ_j C(|T_j ∩ F1|, 2) phép cộng ≤ N·L̄²/2; bộ nhớ C(m_f, 2) bộ đếm UInt32.
# HỎI–ĐÁP   : H: Vì sao sắp xếp buf? Đ: để mọi cặp lấy ra theo thứ tự p < q đều có rank nhỏ đứng trước (r < s),
#                đúng dạng ô của tam giác trên; giao dịch ngắn nên sắp xếp chèn rẻ và không cấp phát.
#             H: Vì sao UInt32? Đ: support của một cặp ≤ N, UInt32 đủ tới ~4,29 tỉ giao dịch và tốn nửa bộ nhớ so với Int64.
"""
    pair_counts(db, rank, mf) -> Vector{UInt32} hoặc nothing

Đếm support của mọi cặp item phổ biến. `rank[x]` là vị trí của item `x` trong lớp gốc (0 nếu
không phổ biến). Trả về `nothing` nếu mảng quá lớn (`TRI_MAX_CELLS`).
"""
function pair_counts(db::TransactionDB, rank::Vector{Int32}, mf::Int)   # đếm mọi cặp trong một lần quét
    cells = mf * (mf - 1) ÷ 2            # số cặp = C(mf, 2) = số ô của mảng tam giác
    cells > TRI_MAX_CELLS && return nothing      # quá nhiều item phổ biến: không đủ RAM, để lớp gốc giao từng cặp
    # UInt32 (4 byte) là đủ: support của một cặp không vượt quá số giao dịch N.
    counts = zeros(UInt32, cells)        # mọi bộ đếm cặp bắt đầu bằng 0
    buf = Int32[]                        # vị trí (rank) các item phổ biến của giao dịch đang xét; dùng lại cho mọi giao dịch
    @inbounds for t in db.transactions   # một lần quét dữ liệu dạng ngang
        empty!(buf)                      # xóa nội dung nhưng giữ vùng nhớ: không cấp phát lại
        for x in t                       # với mỗi item của giao dịch
            r = rank[x]                  # vị trí của item trong lớp gốc (0 = không phổ biến)
            r > 0 && push!(buf, r)       # chỉ giữ item phổ biến (rank > 0)
        end
        L = length(buf)                  # số item phổ biến trong giao dịch
        L < 2 && continue                # giao dịch có ít hơn 2 item phổ biến thì không góp cặp nào
        # Sắp xếp để mỗi cặp (buf[p], buf[q]) với p < q luôn có rank nhỏ đứng trước, đúng dạng (r, s) với r < s.
        sort!(buf; alg = InsertionSort)        # mảng ngắn: sắp xếp chèn, không cấp phát
        for p in 1:(L-1)                 # mọi cặp p < q trong giao dịch này
            r = Int(buf[p])              # item nhỏ hơn của cặp
            # base + s = tri_index(r, s, mf): tính phần chỉ phụ thuộc r một lần cho cả hàng.
            base = (r - 1) * (2mf - r) ÷ 2 - r
            for q in (p+1):L             # item lớn hơn của cặp
                counts[base+buf[q]] += UInt32(1)   # cặp (r, buf[q]) xuất hiện thêm một lần
            end
        end
    end
    return counts                        # counts[tri_index(r, s, mf)] = support của cặp (r, s)
end
