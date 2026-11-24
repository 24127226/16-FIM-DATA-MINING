# Sinh luật kết hợp và chọn top-k theo lift bằng heap của DataStructures.jl
# (phần của B, KE_HOACH_DU_AN.md mục 6.3, 6.5, R18).

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

"""Tạo toàn bộ tập con thực sự khác rỗng `(X, I \\ X)` của tập item `items` đã sắp tăng dần."""
function _proper_splits(items::Vector{Int32})
    k = length(items)
    @assert k >= 2
    if k <= 62
        limit = (UInt64(1) << k) - UInt64(2)
        return (
            (
                Int32[items[b] for b in 1:k if (mask & (UInt64(1) << (b - 1))) != 0],
                Int32[items[b] for b in 1:k if (mask & (UInt64(1) << (b - 1))) == 0],
            )
            for mask in UInt64(1):limit
        )
    end
    throw(ArgumentError("Tập phổ biến dài $k > 62 quá lớn để liệt kê toàn bộ 2^k - 2 luật"))
end

"""
    rules(itemsets, n; minconf = 0.0) -> Vector{Rule}

Sinh toàn bộ luật kết hợp `X ⇒ Y` từ tập các tập phổ biến `itemsets` (tổng số giao dịch `n`)
có độ tin cậy `conf(X ⇒ Y) = σ(X ∪ Y) / σ(X) ≥ minconf`.

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

    inv_n = 1.0 / Float64(n)
    for (iset, sup_xy) in itemsets
        length(iset) < 2 && continue
        sorted_iset = issorted(iset) ? iset : sort(iset)
        for (ant, cons) in _proper_splits(sorted_iset)
            sup_x = get(itemsets, ant, 0)
            sup_y = get(itemsets, cons, 0)
            (sup_x > 0 && sup_y > 0) || continue

            conf = sup_xy / sup_x
            if conf >= mc
                supp = sup_xy * inv_n
                s_y = sup_y * inv_n
                lift = conf / s_y
                push!(out, Rule(ant, cons, sup_xy, supp, conf, lift))
            end
        end
    end
    return out
end

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

Trả về tối đa `k` luật tốt nhất theo tiêu chí `by` (`:lift`, `:confidence`, `:support`,
`:support_count`), giảm dần. Sử dụng `BinaryMinHeap` của `DataStructures.jl` nên độ phức tạp
là O(|rs| log k) thay vì sắp xếp toàn bộ O(|rs| log |rs|).
"""
function top_k(rs::AbstractVector{Rule}, k::Integer; by::Symbol = :lift)::Vector{Rule}
    k >= 0 || throw(ArgumentError("k phải ≥ 0, nhận được: $k"))
    # Kiểm tra tham số `by` ngay cả khi rs rỗng
    by in (:lift, :confidence, :support, :support_count) ||
        throw(ArgumentError("Tiêu chí xếp hạng không hợp lệ: $by"))
    (k == 0 || isempty(rs)) && return Rule[]

    k_eff = min(Int(k), length(rs))
    heap = BinaryMinHeap{Tuple{Float64,Float64,Int,Int}}()
    for (idx, r) in enumerate(rs)
        key = (_rule_metric(r, by), r.confidence, r.support_count, -idx)
        if length(heap) < k_eff
            push!(heap, key)
        elseif key > first(heap)
            pop!(heap)
            push!(heap, key)
        end
    end

    selected = Vector{Rule}(undef, length(heap))
    for pos in length(heap):-1:1
        _, _, _, neg_idx = pop!(heap)
        selected[pos] = rs[-neg_idx]
    end
    return selected
end
