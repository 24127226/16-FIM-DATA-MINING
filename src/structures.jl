# Hợp đồng giao diện giữa A (thuật toán) và B (đọc/ghi, kiểm chứng, thực nghiệm).
# Mọi thay đổi ở file này phải qua một Pull Request riêng, được cả hai người duyệt
# (KE_HOACH_DU_AN.md, mục 6.3).
#
# [VẤN ĐÁP] CẢ FILE
# LÀM GÌ    : định nghĩa các kiểu dữ liệu và hằng số dùng chung: TransactionDB (dữ liệu vào), EclatConfig +
#             VARIANTS (7 phiên bản v0–v6), EclatStats (bộ đếm cho E8, E10). Không có thuật toán.
# VÌ SAO    : phần đọc file của B TẠO TransactionDB, phần thuật toán của A NHẬN nó; định nghĩa chung một chỗ
#             (hợp đồng giao diện) thì hai người làm song song mà không làm hỏng phần của nhau.
#             File được nạp ĐẦU TIÊN trong src/EclatFIM.jl vì mọi file khác dùng các kiểu ở đây.
# HỎI–ĐÁP   : H: Vì sao tách cấu hình thành 6 trường thay vì viết 7 hàm eclat riêng?
#             Đ: Mỗi trường là một kỹ thuật tối ưu độc lập; hai phiên bản liền nhau khác đúng một trường, nên
#                chênh lệch đo được ở E8 là đóng góp riêng của kỹ thuật đó (nghiên cứu loại bỏ, ablation study),
#                và cả 7 phiên bản dùng chung một mã nguồn, một bộ test.

# [VẤN ĐÁP] TransactionDB
# LÀM GÌ    : CSDL dạng ngang: transactions[j] = các item của giao dịch j (tid = j).
# VÌ SAO    : đổi mã item gốc (có thể lớn, không liên tiếp) thành mã nội bộ 1..m để dùng mã làm CHỈ SỐ MẢNG
#             (supp[x], rank[x]) thay vì bảng băm Dict: truy cập O(1) không băm, bộ nhớ liền nhau.
# BẤT BIẾN  : (1) mã nội bộ trong 1..m; (2) giao dịch không có item trùng (nếu trùng, support bị đếm thừa:
#             đã thử, giao dịch [1,1,2] làm support({1}) sai thành 3); (3) item_ids tăng dần nên sắp theo mã nội bộ
#             cũng là sắp theo mã gốc, đúng định dạng đầu ra của SPMF.
# HỎI–ĐÁP   : H: Vì sao Int32 cho giao dịch mà Int64 cho item_ids?
#             Đ: transactions chứa rất nhiều số (Retail ~900 nghìn) nhưng chỉ từ 1..m, Int32 đủ và tốn nửa bộ nhớ;
#                item_ids chỉ có m số nhưng là mã gốc có thể rất lớn.
#             H: Thứ tự item trong một giao dịch có ảnh hưởng kết quả không?
#             Đ: Không: đã thử đảo thứ tự trong mọi giao dịch của 50 CSDL ngẫu nhiên, 7 phiên bản cho kết quả y hệt.
#                Tidset tăng dần là do duyệt tid tăng dần (vertical_tidsets), không do thứ tự item.
"""
    TransactionDB(transactions, item_ids)

CSDL giao dịch ở dạng ngang, đã đổi mã item về `1..m`.

- `transactions[j]`: giao dịch thứ `j` (tid = `j`), là vector mã nội bộ **tăng dần, không trùng**.
- `item_ids[k]`: mã gốc (trong file) của mã nội bộ `k`. `item_ids` tăng dần, nên thứ tự
  theo mã nội bộ trùng với thứ tự theo mã gốc.
"""
struct TransactionDB                         # struct: giá trị các trường không gán lại được sau khi tạo → CSDL chỉ đọc khi khai thác
    transactions::Vector{Vector{Int32}}      # transactions[j]: mã nội bộ các item của giao dịch j; Int32 vì mã chỉ từ 1 đến m
    item_ids::Vector{Int64}                  # item_ids[k]: mã gốc trong file của item có mã nội bộ k; Int64 để chứa mã gốc lớn bất kỳ
end                                          # hết định nghĩa TransactionDB

"""Số giao dịch N."""
n_transactions(db::TransactionDB) = length(db.transactions)   # N = số giao dịch; hàm riêng để file khác không phụ thuộc tên trường

"""Số item phân biệt m."""
n_items(db::TransactionDB) = length(db.item_ids)              # m = số mã nội bộ = số item phân biệt

# [VẤN ĐÁP] EclatConfig
# LÀM GÌ    : một giá trị EclatConfig xác định đầy đủ một phiên bản cài đặt; eclat! đọc các trường để chọn đoạn mã.
# VÌ SAO    : mỗi trường ứng với đúng một kỹ thuật tối ưu → làm được ablation (E8). Trường kiểu Symbol được chuyển
#             thành kiểu Val{...} trong eclat.jl, nên lựa chọn được quyết định lúc biên dịch, vòng lặp nóng không rẽ nhánh.
# HỎI–ĐÁP   : H: Vì sao hybrid_ratio = 1/32?
#             Đ: tidset danh sách tốn 32 bit/tid, dãy bit tốn 1 bit/giao dịch: bằng nhau khi support = N/32 (ρ = 1/32).
#                E7 cho thấy đây là điểm cân bằng BỘ NHỚ; điểm cân bằng THỜI GIAN thấp hơn nhiều (ρ ≈ 0,004).
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
Base.@kwdef struct EclatConfig               # @kwdef: sinh hàm tạo theo TÊN tham số; trường không ghi lấy giá trị mặc định
    tidset::Symbol = :vector                 # cách lưu tidset: :vector (v0–v3), :bitset (v4, v5), :hybrid (v6)
    order::Symbol = :lexical                 # thứ tự item: :lexical chỉ ở v0; từ v1 là :support_asc
    reuse::Bool = false                      # dùng lại vùng nhớ theo độ sâu: false ở v0, v1; true từ v2
    isect::Symbol = :merge                   # phép giao danh sách: :merge ở v0–v2; :adaptive từ v3
    level2::Symbol = :intersect              # tập 2 item: giao từng cặp ở v0–v4; :triangular (mảng tam giác) ở v5, v6
    hybrid_ratio::Float64 = 1 / 32           # ngưỡng mật độ của bản lai: điểm cân bằng bộ nhớ giữa danh sách và dãy bit
end                                          # hết định nghĩa EclatConfig

# [VẤN ĐÁP] VARIANTS, VARIANT_NAMES
# LÀM GÌ    : 7 cấu hình đặt tên "v0".."v6"; mỗi dòng chỉ ghi các trường khác mặc định.
# BẰNG CHỨNG: máy đã so từng cặp liền nhau: mỗi cặp khác đúng một trường (order, reuse, isect, tidset, level2, tidset).
# HỎI–ĐÁP   : H: Vì sao cần VARIANT_NAMES khi đã có VARIANTS?
#             Đ: Dict không giữ thứ tự (máy in keys ra v6, v4, v2, ...); bảng, hình và test cần thứ tự v0 → v6.
"""
Các phiên bản dùng trong báo cáo. Mỗi phiên bản thêm **đúng một** thay đổi so với bản trước
(xem KE_HOACH_DU_AN.md, mục 6.4).
"""
const VARIANTS = Dict{String,EclatConfig}(   # const: hằng toàn cục, trình biên dịch biết chắc kiểu; Dict: tên → cấu hình
    "v0" => EclatConfig(),                   # v0: mọi trường mặc định (bản cơ bản, đúng Algorithm 1 trong báo cáo)
    "v1" => EclatConfig(order = :support_asc),                                   # v1 = v0 + item theo support tăng dần
    "v2" => EclatConfig(order = :support_asc, reuse = true),                     # v2 = v1 + dùng lại vùng nhớ theo độ sâu
    "v3" => EclatConfig(order = :support_asc, reuse = true, isect = :adaptive),  # v3 = v2 + giao thích ứng
    "v4" => EclatConfig(tidset = :bitset, order = :support_asc, reuse = true, isect = :adaptive),   # v4 = v3 + tidset dãy bit
    "v5" => EclatConfig(tidset = :bitset, order = :support_asc, reuse = true, isect = :adaptive,    # v5 = v4 + mảng tam giác
                        level2 = :triangular),                                   # (tiếp dòng trên)
    "v6" => EclatConfig(tidset = :hybrid, order = :support_asc, reuse = true, isect = :adaptive,    # v6 = v5, dãy bit → bản lai
                        level2 = :triangular),                                   # (tiếp dòng trên)
)                                            # hết bảng VARIANTS

"""Thứ tự các phiên bản (dùng khi in bảng, vẽ hình)."""
const VARIANT_NAMES = ["v0", "v1", "v2", "v3", "v4", "v5", "v6"]   # Dict không giữ thứ tự → cần danh sách để duyệt v0 → v6

# [VẤN ĐÁP] EclatStats
# LÀM GÌ    : 10 bộ đếm (số phép giao, số phép giao trượt ngưỡng, byte tidset đang sống, ...) cho E8 (bảng B04) và E10.
# VÌ SAO    : giải thích VÌ SAO thời gian thay đổi giữa các phiên bản (ví dụ retail 0,1%: v5 bỏ qua 2.236.526 cặp).
# HỎI–ĐÁP   : H: Bộ đếm có làm sai thời gian đo không?
#             Đ: Không: khi đo thời gian ta truyền stats = nothing, các lời gọi đếm có kiểu Nothing và bị trình biên dịch
#                loại bỏ; ngoài ra bộ đếm luôn chạy ở một lần chạy riêng không tính giờ (quyết định D20).
"""
    EclatStats()

Bộ đếm nội bộ, **chỉ dùng ở lần chạy đo bộ đếm**, không dùng khi đo thời gian (quyết định D20).
"""
Base.@kwdef mutable struct EclatStats        # mutable: các trường được cộng dồn trong lúc chạy; EclatStats() cho mọi bộ đếm = 0
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
end                              # hết định nghĩa EclatStats
