# Ổn định kiểu của các hàm nóng

Sinh bởi `scripts/check_types.jl` (code_warntype, Julia 1.11.4).

| Hàm | Kết quả | Kiểu trả về |
|---|---|---|
| `isect_merge!` | ✓ ổn định | `Int64` |
| `isect_adaptive!` | ✓ ổn định | `Int64` |
| `and_count!` | ✓ ổn định | `Int64` |
| `and_extract!` | ✓ ổn định | `Int64` |
| `_vec_from_vec!` | ✓ ổn định | `EclatFIM.VecLevel` |
| `_bit_from_bit!` | ✓ ổn định | `EclatFIM.BitLevel` |
| `_vec_from_bit!` | ✓ ổn định | `EclatFIM.VecLevel` |
| `_mine_vec!` | ✓ ổn định | `Nothing` |
| `_mine_bit!` | ✓ ổn định | `Nothing` |
| `_mine_vec! (có bộ đếm)` | ✓ ổn định | `Nothing` |
| `pair_counts` | ✓ ổn định | `UNION{NOTHING, VECTOR{UINT32}}` |
| `parse_spmf` | ✓ ổn định | `TransactionDB` |

`pair_counts` trả về `Union{Nothing, Vector{UInt32}}` có chủ đích (`nothing` khi mảng tam giác vượt giới hạn bộ nhớ); đây là union nhỏ, Julia xử lý bằng tách nhánh theo kiểu (union splitting) nên không làm chậm vòng lặp nóng.
