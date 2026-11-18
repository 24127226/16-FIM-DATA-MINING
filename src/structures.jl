# Hợp đồng giao diện giữa A (thuật toán) và B (đọc/ghi, kiểm chứng, thực nghiệm).
# Mọi thay đổi ở file này phải qua một Pull Request riêng, được cả hai người duyệt
# (KE_HOACH_DU_AN.md, mục 6.3).

"""
    TransactionDB(transactions, item_ids)

CSDL giao dịch ở dạng ngang, đã đổi mã item về `1..m`.

- `transactions[j]`: giao dịch thứ `j` (tid = `j`), là vector mã nội bộ **tăng dần, không trùng**.
- `item_ids[k]`: mã gốc (trong file) của mã nội bộ `k`. `item_ids` tăng dần, nên thứ tự
  theo mã nội bộ trùng với thứ tự theo mã gốc.
"""
struct TransactionDB
    transactions::Vector{Vector{Int32}}
    item_ids::Vector{Int64}
end

"""Số giao dịch N."""
n_transactions(db::TransactionDB) = length(db.transactions)

"""Số item phân biệt m."""
n_items(db::TransactionDB) = length(db.item_ids)

"""
    EclatConfig(; tidset, order, reuse, isect, level2, hybrid_ratio)

Cấu hình một phiên bản Eclat. Mỗi trường là một "trục" tối ưu độc lập, để thí nghiệm
ablation (E8) đo được tác dụng riêng của từng tối ưu.

| Trường | Giá trị | Ý nghĩa |
|---|---|---|
| `tidset` | `:vector`, `:bitset`, `:hybrid` | Cách lưu tidset: danh sách tid tăng dần; mảng bit (`BitVector`); hoặc bắt đầu bằng bitset rồi chuyển sang vector khi tidset đủ thưa |
| `order` | `:lexical`, `:support_asc` | Thứ tự item: theo mã; hay theo support tăng dần |
| `reuse` | `false`, `true` | Cấp phát mảng mới cho mỗi phép giao; hay dùng lại buffer theo độ sâu đệ quy |
| `isect` | `:merge`, `:adaptive` | Phép giao hai vector: trộn hai con trỏ; hay thích ứng (ngắt sớm + tìm kiếm nhảy) |
| `level2` | `:intersect`, `:triangular` | Tập 2 item: giao từng cặp; hay đếm bằng mảng tam giác trên |
| `hybrid_ratio` | số thực | Ngưỡng mật độ σ/N để chuyển bitset → vector (chỉ dùng khi `tidset = :hybrid`) |

Giá trị mặc định chính là phiên bản cơ bản `v0`.
"""
Base.@kwdef struct EclatConfig
    tidset::Symbol = :vector
    order::Symbol = :lexical
    reuse::Bool = false
    isect::Symbol = :merge
    level2::Symbol = :intersect
    hybrid_ratio::Float64 = 1 / 32
end

"""
Các phiên bản dùng trong báo cáo. Mỗi phiên bản thêm **đúng một** thay đổi so với bản trước
(xem KE_HOACH_DU_AN.md, mục 6.4).
"""
const VARIANTS = Dict{String,EclatConfig}(
    "v0" => EclatConfig(),
    "v1" => EclatConfig(order = :support_asc),
    "v2" => EclatConfig(order = :support_asc, reuse = true),
    "v3" => EclatConfig(order = :support_asc, reuse = true, isect = :adaptive),
    "v4" => EclatConfig(tidset = :bitset, order = :support_asc, reuse = true, isect = :adaptive),
    "v5" => EclatConfig(tidset = :bitset, order = :support_asc, reuse = true, isect = :adaptive,
                        level2 = :triangular),
    "v6" => EclatConfig(tidset = :hybrid, order = :support_asc, reuse = true, isect = :adaptive,
                        level2 = :triangular),
)

"""Thứ tự các phiên bản (dùng khi in bảng, vẽ hình)."""
const VARIANT_NAMES = ["v0", "v1", "v2", "v3", "v4", "v5", "v6"]

"""
    EclatStats()

Bộ đếm nội bộ, **chỉ dùng ở lần chạy đo bộ đếm**, không dùng khi đo thời gian (quyết định D20).
"""
Base.@kwdef mutable struct EclatStats
    n_itemsets::Int = 0          # số tập phổ biến đã xuất
    n_intersections::Int = 0     # số phép giao tidset đã thực hiện
    n_failed::Int = 0            # số phép giao cho kết quả dưới ngưỡng
    n_skipped_pairs::Int = 0     # số cặp mức 2 bị loại nhờ mảng tam giác (không cần giao)
    n_classes::Int = 0           # số lớp tương đương (khác rỗng) đã dựng
    n_switch::Int = 0            # số lần chuyển lớp từ bitset sang vector (hybrid)
    max_depth::Int = 0           # độ sâu đệ quy lớn nhất (= kích thước tập dài nhất)
    bytes_current::Int = 0       # số byte tidset đang sống
    bytes_peak::Int = 0          # đỉnh của bytes_current
    time_level2_ns::Int = 0      # thời gian tính các tập 2 item (ns)
end
