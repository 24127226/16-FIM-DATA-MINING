# Mô-đun sinh luật kết hợp và trích xuất top-k luật bằng đống nhị phân (BinaryMinHeap).

"""
    Rule(antecedent, consequent, support_count, support, confidence, lift)

Một luật kết hợp `antecedent ⇒ consequent` (mã item nội bộ của `TransactionDB`, tăng dần).
"""
struct Rule
    antecedent::Vector{Int32}
    consequent::Vector{Int32}
    support_count::Int
    support::Float64
    confidence::Float64
    lift::Float64
end

"""
    _proper_splits(items::Vector{Int32})

Mục đích: Dùng mặt nạ bit (bitmask) từ `1` đến `2^k - 2` để sinh toàn bộ cách chia tập `items`
thành hai tập con khác rỗng rời nhau `(X, I \\ X)` phục vụ bước tạo luật kết hợp `X ⇒ Y`.
Trả về một generator expression để không cấp phát sẵn toàn bộ danh sách tập con trong RAM.
"""
function _proper_splits(items::Vector{Int32})
    k = length(items)
    @assert k >= 2
    if k <= 62
        limit = (UInt64(1) << k) - UInt64(2)   # Bỏ mask = 0 (X rỗng) và mask = 2^k - 1 (Y rỗng)
        return (
            (
                Int32[items[b] for b in 1:k if (mask & (UInt64(1) << (b - 1))) != 0],  # Bit 1 -> vế trái X
                Int32[items[b] for b in 1:k if (mask & (UInt64(1) << (b - 1))) == 0],  # Bit 0 -> vế phải Y
            )
            for mask in UInt64(1):limit
        )
    end
    throw(ArgumentError("Tập phổ biến dài $k > 62 quá lớn để liệt kê toàn bộ 2^k - 2 luật"))
end

"""
    rules(itemsets, n; minconf = 0.0) -> Vector{Rule}

Mục đích: Sinh toàn bộ luật kết hợp `X ⇒ Y` từ từ điển tập phổ biến `itemsets` (tổng số giao dịch `n`)
thỏa mãn độ tin cậy `conf(X ⇒ Y) = σ(X ∪ Y) / σ(X) ≥ minconf`.

- `support(X ⇒ Y) = σ(X ∪ Y) / n`
- `confidence(X ⇒ Y) = σ(X ∪ Y) / σ(X)`
- `lift(X ⇒ Y) = confidence(X ⇒ Y) / (σ(Y) / n)`
"""
function rules(itemsets::AbstractDict{Vector{Int32},Int}, n::Integer;
               minconf::Real = 0.0)::Vector{Rule}
    n >= 0 || throw(ArgumentError("Số giao dịch n phải ≥ 0, nhận được: $n"))
    mc = Float64(minconf)
    (isfinite(mc) && 0.0 <= mc <= 1.0) ||
        throw(ArgumentError("minconf phải nằm trong [0, 1], nhận được: $minconf"))

    out = Rule[]
    (n == 0 || isempty(itemsets)) && return out

    inv_n = 1.0 / Float64(n)                    # Tính sẵn 1/n để thay phép chia bằng phép nhân
    for (iset, sup_xy) in itemsets
        length(iset) < 2 && continue            # Tập 1 phần tử không thể tách thành X ⇒ Y
        sorted_iset = issorted(iset) ? iset : sort(iset)
        for (ant, cons) in _proper_splits(sorted_iset)
            sup_x = get(itemsets, ant, 0)       # Tra độ hỗ trợ σ(X) của vế trái
            sup_y = get(itemsets, cons, 0)      # Tra độ hỗ trợ σ(Y) của vế phải
            (sup_x > 0 && sup_y > 0) || continue

            conf = sup_xy / sup_x               # Độ tin cậy P(Y | X)
            if conf >= mc
                supp = sup_xy * inv_n           # Độ hỗ trợ tương đối s(X ∪ Y)
                s_y = sup_y * inv_n             # Xác suất nền s(Y)
                lift = conf / s_y               # Hệ số nâng: > 1 nghĩa là X và Y liên kết dương
                push!(out, Rule(ant, cons, sup_xy, supp, conf, lift))
            end
        end
    end
    return out
end

"""Lấy giá trị thước đo xếp hạng (`:lift`, `:confidence`, `:support`, `:support_count`) của một luật."""
@inline function _rule_metric(r::Rule, by::Symbol)::Float64
    if by == :lift
        return r.lift
    elseif by == :confidence
        return r.confidence
    elseif by == :support
        return r.support
    elseif by == :support_count
        return Float64(r.support_count)
    else
        throw(ArgumentError("Tiêu chí xếp hạng không hợp lệ: $by (chọn trong :lift, :confidence, :support, :support_count)"))
    end
end

"""
    top_k(rs, k; by = :lift) -> Vector{Rule}

Mục đích: Trích xuất tối đa `k` luật tốt nhất theo tiêu chí `by` (giảm dần).
Sử dụng `BinaryMinHeap` của `DataStructures.jl` duy trì đúng `k` phần tử lớn nhất,
giảm độ phức tạp xuống O(|rs| log k) thay vì sắp xếp toàn bộ O(|rs| log |rs|).
"""
function top_k(rs::AbstractVector{Rule}, k::Integer; by::Symbol = :lift)::Vector{Rule}
    k >= 0 || throw(ArgumentError("k phải ≥ 0, nhận được: $k"))
    # Kiểm tra tham số `by` ngay cả khi rs rỗng
    by in (:lift, :confidence, :support, :support_count) ||
        throw(ArgumentError("Tiêu chí xếp hạng không hợp lệ: $by"))
    (k == 0 || isempty(rs)) && return Rule[]

    k_eff = min(Int(k), length(rs))
    heap = BinaryMinHeap{Tuple{Float64,Float64,Int,Int}}()   # Phần tử nhỏ nhất nằm ở đỉnh heap
    for (idx, r) in enumerate(rs)
        # Khóa phá hòa: (thước đo chính, confidence, support_count, -idx để giữ thứ tự ổn định)
        key = (_rule_metric(r, by), r.confidence, r.support_count, -idx)
        if length(heap) < k_eff
            push!(heap, key)
        elseif key > first(heap)                # Luật mới tốt hơn luật yếu nhất trong top-k -> thay thế
            pop!(heap)
            push!(heap, key)
        end
    end

    # Lấy ngược từ đỉnh min-heap ra cuối mảng để thu được thứ tự giảm dần
    selected = Vector{Rule}(undef, length(heap))
    for pos in length(heap):-1:1
        _, _, _, neg_idx = pop!(heap)
        selected[pos] = rs[-neg_idx]
    end
    return selected
end
