"""
    EclatFIM

Cài đặt thuật toán **Eclat** khai thác tập phổ biến theo bài báo gốc:

> M. J. Zaki, "Scalable Algorithms for Association Mining",
> IEEE Transactions on Knowledge and Data Engineering 12(3):372–390, 2000.

Đồ án môn Khai thác dữ liệu và ứng dụng (HCMUS).
"""
module EclatFIM

export TransactionDB, n_transactions, n_items
export EclatConfig, VARIANTS, VARIANT_NAMES, EclatStats, DEFAULT_CONFIG, DEFAULT_VARIANT
export parse_minsup, minsup_count, read_spmf, parse_spmf
export write_itemset, SPMFWriter, write_itemset!, flush_writer!, close_writer!, mine_to_file
export load_itemsets, compare_itemsets, fingerprint, itemset_hash
export eclat!, eclat
export Rule, rules, top_k, format_rule

include("structures.jl")
include("utils.jl")
include("algorithm/tidsets.jl")
include("algorithm/level2.jl")
include("algorithm/eclat.jl")
include("rules.jl")

end # module
