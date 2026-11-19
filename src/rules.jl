# Sinh luật kết hợp từ tập phổ biến (phần của B).
#
# Luật X ⇒ Y (X, Y khác rỗng, rời nhau) sinh từ tập phổ biến Z = X ∪ Y (Agrawal và cộng sự, 1993):
#   support(X ⇒ Y)    = σ(Z) / N
#   confidence(X ⇒ Y) = σ(Z) / σ(X)               xác suất có Y khi đã có X
#   lift(X ⇒ Y)       = confidence / (σ(Y) / N)    > 1: X và Y đi cùng nhau nhiều hơn mức ngẫu nhiên
# (Brin và cộng sự, 1997 gọi lift là "interest").

using DataStructures: nlargest

"""Một luật kết hợp; tập item là mã nội bộ của `TransactionDB`, đã sắp tăng dần."""
struct Rule
    antecedent::Vector{Int32}
    consequent::Vector{Int32}
    support_count::Int
    support::Float64
    confidence::Float64
    lift::Float64
end

"""Giới hạn kích thước tập dùng để sinh luật: một tập k item cho 2^k − 2 luật."""
const RULES_MAX_LEN = 16

"""
    rules(itemsets, n; minconf) -> Vector{Rule}

Sinh mọi luật X ⇒ Y có confidence ≥ `minconf` từ `itemsets` (kết quả của `eclat`: khóa là mã nội
bộ đã sắp tăng dần, giá trị là support dạng đếm). `n` là số giao dịch.

Vì mọi tập con của tập phổ biến cũng phổ biến (tính chất Apriori), σ(X) và σ(Y) luôn có sẵn
trong `itemsets`, không cần quét lại dữ liệu. Độ phức tạp O(Σ_Z 2^|Z| · |Z|).
"""
function rules(itemsets::AbstractDict{Vector{Int32},Int}, n::Integer; minconf::Real)
    out = Rule[]
    for (Z, sz) in itemsets
        k = length(Z)
        k < 2 && continue
        k > RULES_MAX_LEN && throw(ArgumentError("tập $(k) item quá dài để sinh luật (tối đa $RULES_MAX_LEN)"))
        for mask in 1:(1 << k)-2                       # mọi tập con X khác rỗng, khác Z
            X = Int32[Z[b] for b in 1:k if (mask >> (b - 1)) & 1 == 1]
            sx = itemsets[X]
            conf = sz / sx
            conf >= minconf || continue
            Y = Int32[Z[b] for b in 1:k if (mask >> (b - 1)) & 1 == 0]
            sy = itemsets[Y]
            push!(out, Rule(X, Y, sz, sz / n, conf, conf / (sy / n)))
        end
    end
    return out
end

"""Khóa sắp xếp có phá hòa, để thứ tự luôn xác định."""
_rule_key(r::Rule, by::Symbol) =
    by == :lift ? (r.lift, r.confidence, r.support_count, -length(r.antecedent), reverse(r.antecedent), reverse(r.consequent)) :
    by == :confidence ? (r.confidence, r.lift, r.support_count, -length(r.antecedent), reverse(r.antecedent), reverse(r.consequent)) :
    by == :support ? (r.support_count, r.lift, r.confidence, -length(r.antecedent), reverse(r.antecedent), reverse(r.consequent)) :
    throw(ArgumentError("by phải là :lift, :confidence hoặc :support"))

"""
    top_k(rs, k; by = :lift) -> Vector{Rule}

`k` luật lớn nhất theo `by`, xếp giảm dần. Dùng heap (`nlargest` của DataStructures.jl):
O(n log k) thay vì sắp xếp toàn bộ O(n log n).
"""
top_k(rs::Vector{Rule}, k::Integer; by::Symbol = :lift) = nlargest(k, rs; by = r -> _rule_key(r, by))

"""
    format_rule(r, names) -> String

Chuỗi `{a, b} ⇒ {c}` với `names[x]` là tên (hoặc mã gốc) của item nội bộ `x`.
"""
format_rule(r::Rule, names) = "{" * join(names[r.antecedent], ", ") * "} ⇒ {" * join(names[r.consequent], ", ") * "}"
