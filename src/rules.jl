# Mô-đun sinh luật kết hợp và trích xuất top-k luật bằng đống nhị phân (BinaryMinHeap).

"""
    Rule(antecedent, consequent, support_count, support, confidence, lift)

Mục đích cấu trúc: Biểu diễn một luật kết hợp `antecedent ⇒ consequent` (mã item nội bộ của
`TransactionDB`, sắp tăng dần) cùng đầy đủ 4 thước đo đánh giá.
"""
struct Rule
    antecedent::Vector{Int32}                                # Vế trái X (tiền đề)
    consequent::Vector{Int32}                                # Vế phải Y (hệ quả), rời nhau với X
    support_count::Int                                       # Độ hỗ trợ tuyệt đối σ(X ∪ Y)
    support::Float64                                         # Độ hỗ trợ tương đối s(X ∪ Y) = σ(X ∪ Y) / N
    confidence::Float64                                      # Độ tin cậy conf(X ⇒ Y) = σ(X ∪ Y) / σ(X)
    lift::Float64                                            # Hệ số nâng lift(X ⇒ Y) = conf(X ⇒ Y) / s(Y)
end

"""
    _proper_splits(items::Vector{Int32})

Mục đích hàm: Dùng mặt nạ bit (bitmask) từ `1` đến `2^k - 2` để sinh toàn bộ cách chia tập `items`
thành hai tập con khác rỗng rời nhau `(X, I \\ X)` phục vụ tạo luật kết hợp `X ⇒ Y`.
Trả về generator expression để không cấp phát sẵn toàn bộ 2^k - 2 cặp trong bộ nhớ.
"""
function _proper_splits(items::Vector{Int32})
    k = length(items)                                        # Độ dài tập phổ biến (phải ≥ 2 mới tách được luật)
    @assert k >= 2
    if k <= 62                                               # Hỗ trợ an toàn tới k = 62 trên số nguyên 64-bit không dấu
        limit = (UInt64(1) << k) - UInt64(2)                 # Loại bỏ mask = 0 (X rỗng) và mask = 2^k - 1 (Y rỗng)
        return (                                             # Generator expression duyệt từng mặt nạ bit
            (
                Int32[items[b] for b in 1:k if (mask & (UInt64(1) << (b - 1))) != 0], # Các vị trí bit = 1 -> vế trái X
                Int32[items[b] for b in 1:k if (mask & (UInt64(1) << (b - 1))) == 0], # Các vị trí bit = 0 -> vế phải Y
            )
            for mask in UInt64(1):limit
        )
    end
    throw(ArgumentError("Tập phổ biến dài $k > 62 quá lớn để liệt kê toàn bộ 2^k - 2 luật"))
end

"""
    rules(itemsets, n; minconf = 0.0) -> Vector{Rule}

Mục đích hàm: Sinh toàn bộ luật kết hợp `X ⇒ Y` từ từ điển tập phổ biến `itemsets` (tổng số
giao dịch `n`) thỏa mãn ngưỡng độ tin cậy `conf(X ⇒ Y) ≥ minconf`.
"""
function rules(itemsets::AbstractDict{Vector{Int32},Int}, n::Integer;
               minconf::Real = 0.0)::Vector{Rule}
    n >= 0 || throw(ArgumentError("Số giao dịch n phải ≥ 0, nhận được: $n")) # Kiểm tra số giao dịch hợp lệ
    mc = Float64(minconf)                                    # Ép ngưỡng tin cậy về Float64
    (isfinite(mc) && 0.0 <= mc <= 1.0) ||                    # Kiểm tra minconf nằm trong [0, 1]
        throw(ArgumentError("minconf phải nằm trong [0, 1], nhận được: $minconf"))

    out = Rule[]                                             # Danh sách chứa các luật đạt ngưỡng
    (n == 0 || isempty(itemsets)) && return out              # CSDL rỗng hoặc không có tập phổ biến -> trả mảng rỗng

    inv_n = 1.0 / Float64(n)                                 # Tính sẵn 1/N để thay phép chia bằng phép nhân
    for (iset, sup_xy) in itemsets                           # Duyệt từng tập phổ biến I = X ∪ Y và σ(I)
        length(iset) < 2 && continue                         # Tập có 1 item không thể tách thành luật X ⇒ Y
        sorted_iset = issorted(iset) ? iset : sort(iset)     # Đảm bảo khóa tập con luôn sắp tăng dần để khớp khóa Dict
        for (ant, cons) in _proper_splits(sorted_iset)       # Duyệt mọi cặp phân hoạch (X, Y) khác rỗng
            sup_x = get(itemsets, ant, 0)                    # Tra σ(X) từ từ điển tập phổ biến (luôn có nhờ tính phản đơn điệu)
            sup_y = get(itemsets, cons, 0)                   # Tra σ(Y) từ từ điển tập phổ biến
            (sup_x > 0 && sup_y > 0) || continue             # Bỏ qua nếu thiếu thông tin hỗ trợ tập con

            conf = sup_xy / sup_x                            # Tính độ tin cậy P(Y | X) = σ(X ∪ Y) / σ(X)
            if conf >= mc                                    # Chỉ giữ các luật đạt ngưỡng minconf
                supp = sup_xy * inv_n                        # Độ hỗ trợ tương đối s(X ∪ Y)
                s_y = sup_y * inv_n                          # Xác suất nền s(Y) = σ(Y) / N
                lift = conf / s_y                            # Hệ số nâng: lift > 1 chứng tỏ X và Y liên kết dương
                push!(out, Rule(ant, cons, sup_xy, supp, conf, lift)) # Lưu luật vào kết quả
            end
        end
    end
    return out
end

"""Mục đích hàm: Lấy giá trị số của tiêu chí xếp hạng (`:lift`, `:confidence`, `:support`, `:support_count`) từ một luật."""
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

Mục đích hàm: Trích xuất tối đa `k` luật tốt nhất theo tiêu chí `by` (thứ tự giảm dần).
Sử dụng `BinaryMinHeap` (đống nhị phân tối thiểu) của `DataStructures.jl` để chỉ giữ `k` luật
mạnh nhất, đạt độ phức tạp O(|rs| log k) thay vì sắp xếp toàn bộ O(|rs| log |rs|).
"""
function top_k(rs::AbstractVector{Rule}, k::Integer; by::Symbol = :lift)::Vector{Rule}
    k >= 0 || throw(ArgumentError("k phải ≥ 0, nhận được: $k")) # Kiểm tra k không âm
    by in (:lift, :confidence, :support, :support_count) ||  # Kiểm tra tiêu chí hợp lệ ngay cả khi rs rỗng
        throw(ArgumentError("Tiêu chí xếp hạng không hợp lệ: $by"))
    (k == 0 || isempty(rs)) && return Rule[]                 # Nếu k = 0 hoặc không có luật -> trả mảng rỗng

    k_eff = min(Int(k), length(rs))                          # Số luật thực tế cần lấy không vượt quá tổng số luật
    heap = BinaryMinHeap{Tuple{Float64,Float64,Int,Int}}()   # Đống tối thiểu: phần tử yếu nhất trong top-k luôn ở đỉnh
    for (idx, r) in enumerate(rs)                            # Duyệt qua từng luật trong danh sách
        # Khóa so sánh gồm 4 thành phần: (tiêu chí chính, confidence phá hòa 1, support_count phá hòa 2, -idx giữ thứ tự ổn định)
        key = (_rule_metric(r, by), r.confidence, r.support_count, -idx)
        if length(heap) < k_eff                              # Đống chưa đủ k phần tử -> đẩy thẳng vào
            push!(heap, key)
        elseif key > first(heap)                             # Luật hiện tại mạnh hơn luật yếu nhất đang nằm ở đỉnh đống
            pop!(heap)                                       # Loại bỏ luật yếu nhất ở đỉnh đống
            push!(heap, key)                                 # Chèn luật mới vào đống
        end
    end

    selected = Vector{Rule}(undef, length(heap))             # Mảng kết quả trả về theo thứ tự giảm dần
    for pos in length(heap):-1:1                             # Rút lần lượt từ nhỏ nhất (đỉnh min-heap) điền ngược từ cuối về đầu
        _, _, _, neg_idx = pop!(heap)                        # Lấy lại chỉ số gốc của luật trong mảng `rs`
        selected[pos] = rs[-neg_idx]                         # Gán vào đúng vị trí giảm dần
    end
    return selected
end
