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

"""
Vị trí của cặp `(r, s)`, `1 ≤ r < s ≤ mf`, trong mảng tam giác trên lưu theo hàng:
hàng r có `mf - r` ô, nên trước hàng r có `(r-1)(2mf-r)/2` ô.
"""
@inline tri_index(r::Integer, s::Integer, mf::Integer) = (r - 1) * (2mf - r) ÷ 2 + (s - r)

"""Giới hạn số bộ đếm (≈ 1 GiB); vượt quá thì quay về giao từng cặp."""
const TRI_MAX_CELLS = 1 << 28      # 2^28 ô × 4 byte (UInt32) = 1 GiB

"""
    pair_counts(db, rank, mf) -> Vector{UInt32} hoặc nothing

Đếm support của mọi cặp item phổ biến. `rank[x]` là vị trí của item `x` trong lớp gốc (0 nếu
không phổ biến). Trả về `nothing` nếu mảng quá lớn (`TRI_MAX_CELLS`).
"""
function pair_counts(db::TransactionDB, rank::Vector{Int32}, mf::Int)
    cells = mf * (mf - 1) ÷ 2            # số cặp = C(mf, 2) = số ô của mảng tam giác
    cells > TRI_MAX_CELLS && return nothing      # quá nhiều item phổ biến: không đủ RAM, để lớp gốc giao từng cặp
    # UInt32 (4 byte) là đủ: support của một cặp không vượt quá số giao dịch N.
    counts = zeros(UInt32, cells)
    buf = Int32[]                        # vị trí (rank) các item phổ biến của giao dịch đang xét; dùng lại cho mọi giao dịch
    @inbounds for t in db.transactions   # một lần quét dữ liệu dạng ngang
        empty!(buf)                      # xóa nội dung nhưng giữ vùng nhớ: không cấp phát lại
        for x in t
            r = rank[x]
            r > 0 && push!(buf, r)       # chỉ giữ item phổ biến (rank > 0)
        end
        L = length(buf)
        L < 2 && continue                # giao dịch có ít hơn 2 item phổ biến thì không góp cặp nào
        # Sắp xếp để mỗi cặp (buf[p], buf[q]) với p < q luôn có rank nhỏ đứng trước, đúng dạng (r, s) với r < s.
        sort!(buf; alg = InsertionSort)        # mảng ngắn: sắp xếp chèn, không cấp phát
        for p in 1:(L-1)                 # mọi cặp p < q trong giao dịch này
            r = Int(buf[p])
            # base + s = tri_index(r, s, mf): tính phần chỉ phụ thuộc r một lần cho cả hàng.
            base = (r - 1) * (2mf - r) ÷ 2 - r
            for q in (p+1):L
                counts[base+buf[q]] += UInt32(1)   # cặp (r, buf[q]) xuất hiện thêm một lần
            end
        end
    end
    return counts
end
