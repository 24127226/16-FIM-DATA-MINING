"""
    EclatFIM

Cài đặt thuật toán **Eclat** khai thác tập phổ biến theo bài báo gốc:

> M. J. Zaki, "Scalable Algorithms for Association Mining",
> IEEE Transactions on Knowledge and Data Engineering 12(3):372–390, 2000.

Đồ án môn Khai thác dữ liệu và ứng dụng (HCMUS).
"""
module EclatFIM

export TransactionDB, n_transactions, n_items
export EclatConfig, VARIANTS, VARIANT_NAMES, EclatStats

include("structures.jl")

end # module
