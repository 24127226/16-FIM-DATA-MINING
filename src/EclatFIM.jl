"""
    EclatFIM

Cài đặt thuật toán **Eclat** khai thác tập phổ biến theo bài báo gốc:

> M. J. Zaki, "Scalable Algorithms for Association Mining",
> IEEE Transactions on Knowledge and Data Engineering 12(3):372–390, 2000.

Đồ án môn Khai thác dữ liệu và ứng dụng (HCMUS).
"""
module EclatFIM

using DataStructures: BinaryMinHeap   # Dùng đống nhị phân tối thiểu để lọc top-k luật trong O(n log k)

# Xuất (export) các kiểu dữ liệu và hàm công khai của gói EclatFIM
export TransactionDB, n_transactions, n_items               # Cấu trúc CSDL giao dịch
export EclatConfig, VARIANTS, VARIANT_NAMES, EclatStats     # Cấu hình 7 biến thể v0..v6 và bộ đếm nội bộ
export read_spmf, parse_spmf, parse_minsup, minsup_count, write_itemset  # I/O chuẩn SPMF & quy đổi ngưỡng
export SPMFWriter, write_itemset!, flush_writer!, close_writer!          # Bộ ghi kết quả có đệm 1 MiB
export DEFAULT_VARIANT, DEFAULT_CONFIG, eclat!, eclat                    # Hàm khai thác Eclat chính
export Rule, rules, top_k                                                # Sinh luật kết hợp và lọc top-k

# Nạp các tệp thành phần theo đúng thứ tự phụ thuộc
include("structures.jl")           # Định nghĩa TransactionDB, EclatConfig, EclatStats, VARIANTS
include("utils.jl")                # Đọc/ghi tệp SPMF cấp byte và chuyển đổi minsup
include("algorithm/tidsets.jl")    # Các phép giao tidset (danh sách Int32, dừng sớm, galloping, BitVector)
include("algorithm/level2.jl")     # Đếm 2-itemset bằng mảng tam giác trên (tối ưu v5)
include("algorithm/eclat.jl")      # Thuật toán duyệt chiều sâu theo lớp tương đương tiền tố
include("rules.jl")                # Sinh luật kết hợp và trích xuất top-k theo lift/confidence

end # module
