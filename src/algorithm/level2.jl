# Tính các tập 2 item bằng mảng tam giác trên (phần của A).
#
# Bài báo gốc (Zaki, 2000, §5.1): giao từng cặp item để tìm tập 2 item tốn C(m_f, 2) phép giao,
# rất chậm khi có nhiều item phổ biến. Thay vào đó, đổi dữ liệu về dạng ngang và ĐẾM mọi cặp
# item phổ biến trong một mảng hai chiều tam giác trên. Sau đó chỉ cần giao tidset cho những cặp
# đã biết chắc là phổ biến.
#
# Chi phí: Σ_j C(|T_j ∩ F1|, 2) = O(N · L̄²) phép cộng, cần m_f·(m_f-1)/2 bộ đếm.

"""
Vị trí của cặp `(r, s)`, `1 ≤ r < s ≤ mf`, trong mảng tam giác trên lưu theo hàng:
hàng r có `mf - r` ô, nên trước hàng r có `(r-1)(2mf-r)/2` ô.
"""
@inline tri_index(r::Integer, s::Integer, mf::Integer) = (r - 1) * (2mf - r) ÷ 2 + (s - r)

"""Giới hạn số bộ đếm (≈ 1 GiB); vượt quá thì quay về giao từng cặp."""
const TRI_MAX_CELLS = 1 << 28

"""
    pair_counts(db, rank, mf) -> Vector{UInt32} hoặc nothing

Đếm support của mọi cặp item phổ biến. `rank[x]` là vị trí của item `x` trong lớp gốc (0 nếu
không phổ biến). Trả về `nothing` nếu mảng quá lớn (`TRI_MAX_CELLS`).
"""
function pair_counts(db::TransactionDB, rank::Vector{Int32}, mf::Int)
    cells = mf * (mf - 1) ÷ 2
    cells > TRI_MAX_CELLS && return nothing
    counts = zeros(UInt32, cells)
    buf = Int32[]
    @inbounds for t in db.transactions
        empty!(buf)
        for x in t
            r = rank[x]
            r > 0 && push!(buf, r)
        end
        L = length(buf)
        L < 2 && continue
        sort!(buf; alg = InsertionSort)        # mảng ngắn: sắp xếp chèn, không cấp phát
        for p in 1:(L-1)
            r = Int(buf[p])
            base = (r - 1) * (2mf - r) ÷ 2 - r
            for q in (p+1):L
                counts[base+buf[q]] += UInt32(1)
            end
        end
    end
    return counts
end
