# Thuật toán Eclat (phần của A).
#
# Theo bài báo gốc (Zaki, 2000):
#   §4.1  support của một tập = độ dài phần giao tidset của hai tập con kích thước k-1;
#   §4.2  không gian tìm kiếm chia thành các lớp tương đương theo tiền tố, giải độc lập;
#   §5.1  tập 2 item có thể đếm bằng mảng tam giác trên thay vì giao từng cặp (v5);
#   §5.2  duyệt từ dưới lên: giao mọi cặp atom trong lớp, tập đủ ngưỡng thành atom của lớp con.
# Bản cơ bản không kiểm tra tập con (bài báo §5.2: cắt tỉa gần như không có lợi vì bổ đề 6).
#
# Hai "động cơ" duyệt:
#   - động cơ cấp phát (v0, v1): mỗi atom giữ tidset riêng, mỗi phép giao tạo một mảng mới;
#   - động cơ dùng lại buffer (v2–v6): mỗi độ sâu đệ quy có vùng nhớ riêng (dạng vector và dạng
#     bitset); lớp con của mọi atom cùng độ sâu lần lượt ghi đè lên vùng nhớ đó, nên vòng lặp nóng
#     không cấp phát. Lớp dạng vector và lớp dạng bitset được xử lý bởi các phương thức khác nhau
#     (multiple dispatch); bản lai (v6) chuyển một lớp từ bitset sang vector khi nó đủ thưa.
#
# Từ ngữ dùng trong file:
#   - lớp (tương đương) [P]: mọi tập có chung tiền tố P. Mỗi phần tử của lớp gọi là một atom,
#     gồm item cuối x và tidset t(P ∪ {x}).
#   - lớp con của atom i: tiền tố mới là P ∪ {x_i}; các atom của nó là những x_j đứng SAU x_i
#     (j > i) mà P ∪ {x_i, x_j} đủ ngưỡng. Chỉ lấy j > i để mỗi tập được sinh đúng một lần.
#   - độ sâu d: kích thước của tập đang xét (lớp gốc chứa các tập 1 item, độ sâu 1).
#   - sink(items, support): hàm do người gọi truyền vào, nhận từng tập phổ biến tìm được.
#
# Bản đồ file (đọc theo thứ tự này):
#   1. Bộ đếm (stats)                   — dùng cho thí nghiệm E8, E10;
#   2. Chuẩn bị                         — đếm support item, chọn và sắp thứ tự item (v1), dựng tidset;
#   3. Động cơ cấp phát                 — v0, v1;
#   4. Động cơ dùng lại buffer          — cấu trúc dữ liệu (v2), dựng lớp gốc, dựng lớp con,
#                                         duyệt đệ quy, lớp gốc với mảng tam giác (v5), bản lai (v6);
#   5. Giao diện công khai              — eclat!, eclat.
#
# [VẤN ĐÁP] CẢ FILE
# HỎI–ĐÁP   : H: Cài đặt khác bài báo ở đâu? Đ: (i) đọc file dạng ngang rồi tự dựng dạng dọc bằng 2 lần quét;
#                (ii) v0 giao từng cặp ở lớp gốc, mảng tam giác là tối ưu riêng v5; (iii) ĐỆ QUY NGAY sau khi dựng
#                mỗi lớp con (bài báo dựng xong mọi lớp con rồi mới đệ quy) → mỗi độ sâu chỉ một lớp đang sống;
#                (iv) v0 dùng thứ tự mã, từ v1 dùng support tăng dần. Không điểm nào làm đổi tập kết quả.
#             H: Vì sao không cắt tỉa bằng cách kiểm tra mọi tập con (như Apriori)?
#             Đ: Bài báo §5.2: gần như không có lợi, vì theo bổ đề 6 tidset co lại khi đi sâu nên phép giao ở mức sâu
#                vốn đã rẻ; kiểm tra tập con lại cần tra cứu thêm.
#             H: Đúng chưa? Đ: khớp 100% SPMF trên 56 lần chạy (E1), oracle vét cạn 200 CSDL, 10.474 test qua.

# [VẤN ĐÁP] DEFAULT_VARIANT
# VÌ SAO    : chọn v6 vì không bao giờ cần nhiều bộ nhớ tidset hơn dạng gọn hơn trong hai dạng, và nhanh hơn SPMF
#             Eclat 3,8–48 lần ở minsup thấp nhất (E2). E8 cho thấy không bản nào nhanh nhất mọi nơi: v4 thắng dữ liệu
#             dày, v5 thắng dữ liệu thưa.
"""Tên phiên bản dùng khi không chỉ định cấu hình: bản lai v6 (tidset gọn nhất; E8 cho thấy không bản nào nhanh nhất trên mọi dữ liệu)."""
const DEFAULT_VARIANT = "v6"   # bản mặc định của CLI và của eclat!
"""Cấu hình của phiên bản mặc định (`VARIANTS[DEFAULT_VARIANT]`); là tham số mặc định của `eclat!`, `eclat`."""
const DEFAULT_CONFIG = VARIANTS[DEFAULT_VARIANT]   # cấu hình tương ứng

# ---------------------------------------------------------------------------
# Bộ đếm: khi stats === nothing, các lời gọi dưới đây không làm gì và bị trình biên dịch
# loại bỏ (multiple dispatch theo kiểu Nothing / EclatStats), nên không tốn chi phí khi đo thời gian.
# ---------------------------------------------------------------------------
# Mỗi bộ đếm có HAI phương thức cùng tên. Julia chọn phương thức theo KIỂU của tham số đầu:
#   - st là nothing (kiểu Nothing)  → phương thức rỗng, trả về nothing; sau khi chép thân hàm
#     vào chỗ gọi (@inline), không còn lệnh nào: lần chạy đo thời gian không bị chậm đi;
#   - st là EclatStats              → phương thức cộng bộ đếm thật (lần chạy đo bộ đếm, E8/E10).
# Nhờ vậy chỉ cần MỘT bản code thuật toán cho cả hai mục đích, không phải rải "if" khắp nơi.
#
# [VẤN ĐÁP] BỘ ĐẾM
# HỎI–ĐÁP   : H: Đây là đặc trưng nào của Julia? Đ: multiple dispatch: cùng tên hàm, Julia chọn phương thức theo kiểu
#                tham số lúc biên dịch. Đề yêu cầu tận dụng multiple dispatch; đây là một chỗ dùng thật.
#             H: Sao biết các lời gọi bị loại bỏ thật? Đ: phương thức ::Nothing chỉ trả nothing và được @inline; ngoài ra
#                khi đo thời gian vẫn không bật bộ đếm (D20), nên dù không loại bỏ thì số đo cũng không bị ảnh hưởng.

# Đếm một tập phổ biến vừa xuất, và ghi nhận độ sâu lớn nhất đã gặp.
@inline _st_itemset!(::Nothing, depth) = nothing                 # không đo bộ đếm: không làm gì
@inline function _st_itemset!(st::EclatStats, depth)   # bản thật: có đo bộ đếm
    st.n_itemsets += 1                                           # thêm một tập phổ biến
    depth > st.max_depth && (st.max_depth = depth)   # cú pháp "a && b": chỉ chạy b khi a đúng
    return nothing   # không trả giá trị
end

# Đếm một phép giao tidset; ok = false nghĩa là kết quả trượt ngưỡng (phép giao "phí công").
@inline _st_isect!(::Nothing, ok::Bool) = nothing
@inline function _st_isect!(st::EclatStats, ok::Bool)   # bản thật
    st.n_intersections += 1                                      # thêm một phép giao
    ok || (st.n_failed += 1)                         # "a || b": chỉ chạy b khi a sai
    return nothing   # không trả giá trị
end

# Ghi nhận có thêm nbytes byte tidset đang sống, và cập nhật đỉnh bộ nhớ (E10).
@inline _st_alloc!(::Nothing, nbytes) = nothing
@inline function _st_alloc!(st::EclatStats, nbytes)   # bản thật
    st.bytes_current += nbytes                                   # tidset của lớp mới bắt đầu sống
    st.bytes_current > st.bytes_peak && (st.bytes_peak = st.bytes_current)   # cập nhật đỉnh
    return nothing   # không trả giá trị
end

# Ghi nhận nbytes byte tidset không còn dùng nữa (khi đệ quy quay lên).
@inline _st_free!(::Nothing, nbytes) = nothing
@inline _st_free!(st::EclatStats, nbytes) = (st.bytes_current -= nbytes; nothing)   # giảm byte đang sống

# Đếm một lớp tương đương khác rỗng đã dựng.
@inline _st_class!(::Nothing) = nothing
@inline _st_class!(st::EclatStats) = (st.n_classes += 1; nothing)   # thêm một lớp

# Đếm một lần bản lai (v6) chuyển lớp từ bitset sang vector.
@inline _st_switch!(::Nothing) = nothing
@inline _st_switch!(st::EclatStats) = (st.n_switch += 1; nothing)   # thêm một lần chuyển

# Đếm số cặp mức 2 bị loại nhờ mảng tam giác (v5, v6), tức số phép giao tiết kiệm được.
@inline _st_skip!(::Nothing, n) = nothing
@inline _st_skip!(st::EclatStats, n) = (st.n_skipped_pairs += n; nothing)   # cộng số cặp bị bỏ qua

# Cộng dồn thời gian tính các tập 2 item (ns), để so mảng tam giác với giao từng cặp.
@inline _st_level2_time!(::Nothing, ns) = nothing
@inline _st_level2_time!(st::EclatStats, ns) = (st.time_level2_ns += ns; nothing)   # cộng thời gian mức 2

# Đồng hồ: chỉ đọc giờ khi có đo bộ đếm; khi không đo thì trả về 0, không tốn lời gọi time_ns().
@inline _now(::Nothing) = UInt64(0)
@inline _now(::EclatStats) = time_ns()   # đồng hồ nano giây

# ---------------------------------------------------------------------------
# Chuẩn bị: đếm support, chọn item phổ biến, sắp thứ tự, dựng tidset dạng dọc
# ---------------------------------------------------------------------------

# [VẤN ĐÁP] item_supports
# LÀM GÌ    : một lần quét dữ liệu ngang, supp[x] = số giao dịch chứa x. CHI PHÍ: O(N·L̄).
# HỎI–ĐÁP   : H: Vì sao đếm đúng mà không cần kiểm tra trùng? Đ: bất biến của TransactionDB: giao dịch không có item trùng.
"""Support của từng item (mã nội bộ 1..m): một lần quét dữ liệu ngang."""
function item_supports(db::TransactionDB)   # support của từng item
    supp = zeros(Int, n_items(db))           # supp[x] = số giao dịch chứa item x
    @inbounds for t in db.transactions, x in t   # duyệt mọi giao dịch t, mọi item x trong t
        supp[x] += 1                         # mỗi giao dịch không có item trùng, nên đếm đúng
    end
    return supp   # supp[x] = support của item x
end

# Vì sao v1 sắp item theo support TĂNG dần (heuristic quen thuộc của Eclat, Zaki 2000):
#   lớp con của atom i chỉ gồm các item đứng SAU i. Khi item hiếm đứng trước:
#   - lớp con của item hiếm có nhiều atom, nhưng tidset của nó ngắn: phép giao nhanh, và phần lớn
#     kết quả trượt ngưỡng ngay nên cây đệ quy bị cắt sớm;
#   - item phổ biến (tidset dài, giao đắt) đứng cuối nên lớp con của nó có ít atom.
#   Kết quả: ít phép giao trên tidset dài hơn, ít lớp con lớn hơn. Đo trong E8 (v0 → v1).
#
# [VẤN ĐÁP] frequent_items (tối ưu v1)
# BẰNG CHỨNG: E8 minsup thấp nhất (B04): số phép giao giảm 19% (chess), 10% (mushroom), 43% (retail); phép giao trượt
#             ngưỡng giảm 10,6 lần trên chess (29.532 → 2.797); thời gian nhanh hơn 1,6 lần (retail), 1,2 lần (mushroom),
#             gần như không đổi trên chess và T10I4D100K (ở đó thời gian chủ yếu do cấp phát bộ nhớ và giao mức 2).
# HỎI–ĐÁP   : H: Vì sao hòa support phải xét thêm mã? Đ: để thứ tự luôn xác định → cùng input cho cùng thứ tự xuất.
"""Các item phổ biến theo thứ tự xử lý của cấu hình (`:lexical` hoặc `:support_asc`)."""
function frequent_items(supp::Vector{Int}, minsup::Integer, order::Symbol)   # item phổ biến theo thứ tự cấu hình
    freq = Int32[x for x in eachindex(supp) if supp[x] >= minsup]   # chỉ giữ item đủ ngưỡng, theo mã tăng dần
    if order == :support_asc                 # v1 trở đi
        sort!(freq; by = x -> (supp[x], x))    # hòa support thì theo mã, để thứ tự luôn xác định
    elseif order != :lexical                 # giá trị không hợp lệ
        throw(ArgumentError("order không hợp lệ: $order"))   # báo lỗi rõ ràng
    end
    return freq   # danh sách item phổ biến đã sắp
end

"""rank[x] = vị trí của item x trong `freq` (0 nếu không phổ biến)."""
function item_ranks(m::Int, freq::Vector{Int32})   # mã item → vị trí trong lớp gốc
    rank = zeros(Int32, m)               # mặc định 0 = không phổ biến
    for (r, x) in enumerate(freq)        # r = vị trí trong freq, x = mã item
        rank[x] = r                      # tra ngược mã item → vị trí trong lớp gốc
    end
    return rank   # rank[x] (0 nếu không phổ biến)
end

# [VẤN ĐÁP] vertical_tidsets — chuyển dạng ngang → dạng dọc
# LÀM GÌ    : tidset của mỗi item phổ biến; biết trước support nên cấp đúng số ô.
# HỎI–ĐÁP   : H: Vì sao tidset tự tăng dần mà không cần sort? Đ: duyệt giao dịch theo tid tăng dần, tid được ghi
#                nối vào cuối → luôn tăng dần. Điều này là điều kiện để phép giao hai con trỏ đúng.
"""
    vertical_tidsets(db, freq, supp) -> Vector{Vector{Int32}}

Dựng tidset dạng vector cho các item phổ biến `freq` (theo đúng thứ tự trong `freq`).
Duyệt giao dịch theo tid tăng dần nên mỗi tidset tự động tăng dần. O(N·L̄).
"""
function vertical_tidsets(db::TransactionDB, freq::Vector{Int32}, supp::Vector{Int})   # dạng ngang → dạng dọc
    rank = item_ranks(n_items(db), freq)     # tra nhanh "item x là item phổ biến thứ mấy"
    tids = [Vector{Int32}(undef, supp[x]) for x in freq]   # biết trước support nên cấp đúng số ô cần
    fill_pos = zeros(Int, length(freq))      # fill_pos[r] = số ô đã điền của tidset thứ r
    @inbounds for (tid, t) in enumerate(db.transactions)   # tid = số thứ tự giao dịch (1, 2, ...)
        for x in t                               # mỗi item của giao dịch
            r = rank[x]                          # vị trí trong lớp gốc
            r == 0 && continue                   # item không phổ biến: bỏ qua
            p = fill_pos[r] += 1                 # tăng bộ đếm và lấy ô kế tiếp
            tids[r][p] = Int32(tid)              # tid tăng dần nên tidset tự tăng dần, không cần sắp xếp
        end
    end
    return tids   # tidset của từng item phổ biến
end

# ---------------------------------------------------------------------------
# Động cơ cấp phát (v0, v1): mỗi atom giữ tidset riêng, mỗi phép giao tạo mảng mới
# ---------------------------------------------------------------------------
# Đây là cách viết thẳng theo bài báo, dễ hiểu nhất. Nhược điểm: mỗi phép giao xin một mảng mới
# từ bộ nhớ; hàng triệu lần xin như vậy làm bộ dọn rác (GC) của Julia phải chạy liên tục. v2 sửa đúng
# điểm này (xem động cơ dùng lại buffer bên dưới).

"""Lớp tương đương: các cặp (item cuối, tidset). Tiền tố nằm ở ngăn xếp `prefix` dùng chung."""
struct AllocClass   # lớp tương đương của động cơ cấp phát
    items::Vector{Int32}                 # items[k]: item cuối của atom k
    tidsets::Vector{Vector{Int32}}       # tidsets[k]: tidset của atom k (một mảng riêng cho mỗi atom)
end

# Số byte tidset của một lớp: mỗi tid Int32 chiếm 4 byte (dùng cho bộ đếm bộ nhớ, E10).
_bytes(tids::Vector{Vector{Int32}}) = 4 * sum(length, tids; init = 0)

# Val{:merge} / Val{:adaptive}: đưa lựa chọn của cấu hình vào KIỂU, để Julia biên dịch riêng một bản
# cho mỗi lựa chọn. Khi đó trong vòng lặp không còn phép so sánh "đang dùng phép giao nào".
"""Phép giao của động cơ cấp phát, chọn theo cấu hình (Val để chuyên biệt hóa lúc biên dịch)."""
_isect_alloc(a, b, ::Val{:merge}, minsup) = intersect_merge(a, b)          # v0, v1: trộn hai con trỏ, cấp phát kết quả
function _isect_alloc(a, b, ::Val{:adaptive}, minsup)   # v3 dùng động cơ cấp phát (không có trong VARIANTS, giữ cho đủ tổ hợp)
    out = Vector{Int32}(undef, min(length(a), length(b)))      # cấp mảng kết quả (đủ cho trường hợp xấu nhất)
    return resize!(out, isect_adaptive!(out, 1, a, 1, length(a), b, 1, length(b), minsup))   # cắt về đúng độ dài
end

# [VẤN ĐÁP] _child_alloc, _mine_alloc! (v0, v1) — đúng Algorithm 1 trong báo cáo
# LÀM GÌ    : với atom i, giao tidset của i với mọi atom j > i; cặp đủ ngưỡng thành atom của lớp con; đệ quy ngay.
# VÌ SAO    : chỉ lấy j > i → mỗi tập sinh đúng một lần ({A, C} chỉ sinh ở lớp [A], không sinh lại ở lớp [C]).
# CHI PHÍ   : số phép giao I = Σ_lớp C(|lớp|, 2) ≤ |F|·m_f; mỗi phép giao O(|t_i| + |t_j|) và một lần cấp phát.
# BẰNG CHỨNG: chạy tay ví dụ hiệu sách: 19 tập, 17 phép giao (3 trượt ngưỡng), khớp máy và khớp bài báo (hình F01).
# HỎI–ĐÁP   : H: prefix là gì? Đ: một mảng dùng chung làm ngăn xếp tiền tố: push! khi đi xuống, pop! khi quay lên,
#                không tạo mảng mới cho mỗi tập; vì vậy sink phải copy nếu muốn giữ items.
"""Lớp con của atom thứ `i`: giao tidset của nó với tidset của mọi atom đứng sau."""
function _child_alloc(cls::AllocClass, i::Int, minsup::Int, isect::Val, st)   # dựng lớp con của atom i
    items = Int32[]                          # atom của lớp con (chỉ những atom đủ ngưỡng)
    tids = Vector{Vector{Int32}}()           # tidset tương ứng
    tx = cls.tidsets[i]                      # tidset của atom i (tiền tố mới)
    @inbounds for j in (i + 1):length(cls.items)     # chỉ atom đứng sau: mỗi tập sinh đúng một lần
        t = _isect_alloc(tx, cls.tidsets[j], isect, minsup)   # t(P ∪ {x_i, x_j}) = t_i ∩ t_j
        ok = length(t) >= minsup             # support = độ dài phần giao
        _st_isect!(st, ok)                   # bộ đếm (bị loại bỏ khi st = nothing)
        if ok                                # đủ ngưỡng: x_j thành atom của lớp con
            push!(items, cls.items[j])   # thêm atom
            push!(tids, t)   # và tidset của nó
        end                                  # trượt ngưỡng: bỏ (mảng t sẽ bị GC dọn sau)
    end
    return AllocClass(items, tids)   # lớp con
end

# Duyệt đệ quy một lớp: xuất từng atom, rồi dựng lớp con của nó và đi xuống (duyệt theo chiều sâu).
# prefix là ngăn xếp tiền tố dùng chung: push! khi đi xuống, pop! khi quay lên, không tạo mảng mới.
function _mine_alloc!(sink, prefix::Vector{Int32}, cls::AllocClass, minsup::Int, isect::Val, st, maxlen::Int)
    k = length(cls.items)                    # số atom của lớp
    @inbounds for i in 1:k   # từng atom của lớp
        push!(prefix, cls.items[i])          # tập đang xét = tiền tố + item cuối của atom i
        depth = length(prefix)               # kích thước tập
        _st_itemset!(st, depth)   # đếm một tập (E8)
        sink(prefix, length(cls.tidsets[i]))                 # xuất tập prefix với support |t(prefix)|
        # Chỉ đi xuống khi chưa đạt độ dài tối đa và còn atom đứng sau để ghép cặp.
        if depth < maxlen && i < k   # còn atom đứng sau
            t0 = depth == 1 ? _now(st) : UInt64(0)           # bấm giờ khi đang ở lớp gốc (sắp tính tập 2 item)
            child = _child_alloc(cls, i, minsup, isect, st)   # dựng lớp con (mỗi phép giao cấp phát một mảng)
            depth == 1 && _st_level2_time!(st, _now(st) - t0)  # lớp con của lớp gốc = tập 2 item
            if !isempty(child.items)         # lớp con rỗng thì không có gì để duyệt
                _st_class!(st)   # đếm một lớp
                nb = _bytes(child.tidsets)   # byte tidset của lớp con
                _st_alloc!(st, nb)           # lớp con bắt đầu "sống"
                _mine_alloc!(sink, prefix, child, minsup, isect, st, maxlen)   # đệ quy xuống lớp con
                _st_free!(st, nb)            # xong lớp con: tidset của nó không còn dùng nữa
            end
        end
        pop!(prefix)                         # bỏ item cuối, quay lại tiền tố cũ cho atom tiếp theo
    end
    return nothing   # không trả giá trị
end

# Điểm vào của v0, v1: chuẩn bị lớp gốc [∅] rồi duyệt đệ quy.
function _eclat_alloc!(sink, db::TransactionDB, minsup::Int, cfg::EclatConfig, st, maxlen::Int)
    supp = item_supports(db)                         # bước 1: support từng item
    freq = frequent_items(supp, minsup, cfg.order)   # bước 2: item phổ biến, theo thứ tự cấu hình
    isempty(freq) && return nothing                  # không có item phổ biến thì không có tập nào
    root = AllocClass(freq, vertical_tidsets(db, freq, supp))   # bước 3: lớp gốc, mỗi item một tidset
    nb = _bytes(root.tidsets)                        # byte tidset của lớp gốc (cho E10)
    _st_alloc!(st, nb)   # bộ nhớ đang sống tăng (E10)
    _mine_alloc!(sink, Int32[], root, minsup, Val(cfg.isect), st, maxlen)   # bước 4: duyệt, tiền tố rỗng
    _st_free!(st, nb)   # bộ nhớ đang sống giảm
    return nothing   # không trả giá trị
end

# ---------------------------------------------------------------------------
# Động cơ dùng lại buffer (v2–v6): cấu trúc dữ liệu
# ---------------------------------------------------------------------------
# Ý tưởng v2: duyệt theo chiều sâu nên ở MỖI độ sâu d, tại một thời điểm chỉ có MỘT lớp đang sống
# (lớp con của atom đang xét). Khi chuyển sang atom kế tiếp, lớp con cũ không còn cần nữa.
# Vậy mỗi độ sâu chỉ cần một vùng nhớ, các lớp con lần lượt ghi đè lên nhau. Vùng nhớ chỉ được
# nới rộng vài lần lúc đầu; sau đó vòng lặp nóng không xin bộ nhớ mới, GC không phải chạy.
#
# [VẤN ĐÁP] ĐỘNG CƠ DÙNG LẠI BUFFER (tối ưu v2)
# BẰNG CHỨNG: test_performance.jl: cấp phát giảm từ 9,91 MiB (v0) xuống 0,27 MiB (v2); E8 minsup thấp nhất: v1 → v2
#             nhanh hơn 3,5 lần (chess, 114.007 phép giao) và 3,4 lần (mushroom); dữ liệu thưa chỉ 5–9% vì thời gian
#             nằm ở giao các tidset dài mức 2, không ở cấp phát.
# HỎI–ĐÁP   : H: Ghi đè lên vùng nhớ cũ có làm hỏng dữ liệu đang dùng không?
#             Đ: Không, vì duyệt theo chiều sâu: khi dựng lớp con của atom i+1 ở độ sâu d+1, lớp con của atom i ở cùng
#                độ sâu đã duyệt xong hoàn toàn. Nếu duyệt theo chiều rộng thì điều này không còn đúng.

"""
Một lớp dạng **vector** trong vùng nhớ dùng lại của một độ sâu. Tidset của atom `k` là đoạn
`buf[offs[k] : offs[k]+lens[k]-1]`; `lens[k]` chính là support.
"""
mutable struct VecLevel   # mutable: các trường được ghi lại mỗi lần dùng lại
    items::Vector{Int32}     # items[k]: item cuối của atom k
    offs::Vector{Int}        # offs[k]: tidset của atom k bắt đầu ở ô nào của buf
    lens::Vector{Int32}      # lens[k]: độ dài tidset của atom k (= support)
    buf::Vector{Int32}       # MỘT mảng chứa liền nhau tidset của mọi atom trong lớp
end
VecLevel() = VecLevel(Int32[], Int[], Int32[], Int32[])   # lớp rỗng, dùng khi cần thêm độ sâu mới

"""
Một lớp dạng **bitset** trong vùng nhớ dùng lại của một độ sâu. Tidset của atom `k` là
`pool[k]` (BitVector dài N); `sups[k]` là support. `pool` chỉ lớn thêm, không bao giờ thu nhỏ.
"""
mutable struct BitLevel   # mutable
    items::Vector{Int32}     # items[k]: item cuối của atom k
    sups::Vector{Int32}      # sups[k]: support của atom k (đếm sẵn, không phải đếm lại bit)
    pool::Vector{BitVector}  # các bitset đã cấp; giữ lại giữa các lần dùng để khỏi cấp lại
end
BitLevel() = BitLevel(Int32[], Int32[], BitVector[])     # lớp rỗng

# Xóa nội dung một lớp để chuẩn bị ghi lớp con mới. empty! giữ nguyên vùng nhớ đã cấp,
# và buf / pool KHÔNG bị xóa: chúng chính là phần được dùng lại.
_reset!(l::VecLevel) = (empty!(l.items); empty!(l.offs); empty!(l.lens); l)
_reset!(l::BitLevel) = (empty!(l.items); empty!(l.sups); l)   # giữ pool để dùng lại

# Số byte tidset thật sự đang dùng của một lớp (cho E10):
#   dạng vector: 4 byte mỗi tid; dạng bitset: mỗi atom một BitVector N bit = cld(N, 64) word × 8 byte.
_live_bytes(l::VecLevel) = 4 * Int(sum(l.lens; init = Int32(0)))
_live_bytes(l::BitLevel, N::Int) = 8 * cld(N, 64) * length(l.items)   # byte của mọi bitset trong lớp

"""Vùng nhớ dùng lại: vec[d], bit[d] chứa lớp ở độ sâu d (d = 1 là lớp gốc)."""
struct Workspace   # toàn bộ vùng nhớ dùng lại của một lần chạy
    vec::Vector{VecLevel}   # vùng nhớ dạng vector của từng độ sâu
    bit::Vector{BitLevel}   # vùng nhớ dạng bitset của từng độ sâu
    N::Int                  # số giao dịch (độ dài mỗi bitset)
    switch_at::Float64      # bản lai: chuyển bitset → vector khi chặn trên support < switch_at; < 0: không chuyển
    cand::Vector{Int}       # danh sách atom đứng sau đủ ngưỡng (chỉ dùng ở lớp gốc với mảng tam giác)
end

# Lấy vùng nhớ dạng vector của độ sâu d; lần đầu xuống tới độ sâu d thì tạo thêm.
function _vec_level!(ws::Workspace, d::Int)
    while length(ws.vec) < d   # thiếu độ sâu d
        push!(ws.vec, VecLevel())        # chỉ xảy ra lần đầu đi tới độ sâu này
    end
    return ws.vec[d]   # vùng nhớ vector của độ sâu d
end

# Như trên, cho dạng bitset.
function _bit_level!(ws::Workspace, d::Int)
    while length(ws.bit) < d   # thiếu độ sâu d
        push!(ws.bit, BitLevel())   # tạo thêm
    end
    return ws.bit[d]   # vùng nhớ bitset của độ sâu d
end

"""Bitset thứ `k` của lớp (cấp phát thêm nếu vùng nhớ chưa đủ chỗ)."""
function _slot!(l::BitLevel, k::Int, N::Int)   # lấy (hoặc cấp) bitset thứ k
    while length(l.pool) < k   # chưa đủ bitset
        push!(l.pool, falses(N))     # chỉ cấp khi lớp này lần đầu cần nhiều bitset như vậy
    end
    return @inbounds l.pool[k]       # bitset thứ k (dùng lại nếu đã có)
end

# ---------------------------------------------------------------------------
# Dựng lớp gốc
# ---------------------------------------------------------------------------

"""Lớp gốc dạng vector: tidset của mọi item phổ biến nằm liền nhau trong một buffer."""
function _root_vec(db::TransactionDB, freq::Vector{Int32}, supp::Vector{Int})   # lớp gốc trong MỘT buffer liền nhau
    k = length(freq)                         # số item phổ biến
    lens = Int32[supp[x] for x in freq]      # độ dài tidset của từng item = support của nó
    offs = Vector{Int}(undef, k)             # vị trí bắt đầu của từng tidset
    # Tính vị trí bắt đầu: tidset thứ r đứng ngay sau tidset thứ r - 1.
    p = 1
    for r in 1:k   # tính offset từng tidset
        offs[r] = p   # tidset r bắt đầu ở p
        p += lens[r]   # tidset sau bắt đầu ngay sau nó
    end
    buf = Vector{Int32}(undef, p - 1)        # p - 1 = tổng độ dài mọi tidset
    rank = item_ranks(n_items(db), freq)   # mã item → vị trí
    fill_pos = copy(offs)                    # fill_pos[r] = ô kế tiếp cần ghi của tidset thứ r
    @inbounds for (tid, t) in enumerate(db.transactions)   # duyệt giao dịch theo tid tăng dần
        for x in t   # từng item
            r = rank[x]   # vị trí trong lớp gốc
            r == 0 && continue               # item không phổ biến
            buf[fill_pos[r]] = Int32(tid)    # như vertical_tidsets, nhưng ghi vào buffer chung
            fill_pos[r] += 1   # ô kế tiếp
        end
    end
    return VecLevel(copy(freq), offs, lens, buf)   # lớp gốc dạng vector
end

# [VẤN ĐÁP] _root_bit
# HỎI–ĐÁP   : H: Giải thích hai dòng tính w và bit? Đ: tid t nằm ở word ⌊(t-1)/64⌋+1 (dịch phải 6 bit = chia 64), tại bit
#                (t-1) mod 64 (AND với 63); "|=" bật đúng bit đó mà không đổi các bit khác.
"""Lớp gốc dạng bitset: bật bit `tid` trong bitset của mọi item phổ biến có trong giao dịch `tid`."""
function _root_bit(db::TransactionDB, freq::Vector{Int32}, supp::Vector{Int})   # lớp gốc dạng dãy bit
    N = n_transactions(db)                   # độ dài mỗi bitset
    rank = item_ranks(n_items(db), freq)   # mã item → vị trí
    pool = [falses(N) for _ in freq]         # mỗi item phổ biến một BitVector N bit, ban đầu toàn 0
    @inbounds for (tid, t) in enumerate(db.transactions)   # duyệt giao dịch theo tid tăng dần
        w = ((tid - 1) >> 6) + 1             # tid nằm ở word thứ w: ⌊(tid - 1) / 64⌋ + 1
        bit = UInt64(1) << ((tid - 1) & 63)  # mặt nạ có đúng một bit 1 ở vị trí (tid - 1) mod 64
        for x in t   # từng item
            r = rank[x]   # vị trí trong lớp gốc
            r == 0 && continue   # item không phổ biến
            pool[r].chunks[w] |= bit         # bật bit của giao dịch tid trong bitset của item x
        end
    end
    return BitLevel(copy(freq), Int32[supp[x] for x in freq], pool)   # lớp gốc dạng bitset, support đếm sẵn
end

# ---------------------------------------------------------------------------
# Dựng lớp con của atom i với các atom j ∈ js đứng sau nó
# (js là (i+1):k, hoặc danh sách cặp đã biết là phổ biến nhờ mảng tam giác)
# ---------------------------------------------------------------------------

# Chọn phép giao theo cấu hình: v2 dùng trộn hai con trỏ, v3 trở đi dùng giao thích ứng.
@inline _isect_into!(dst, dpos, a, ao, la, b, bo, lb, minsup, ::Val{:merge}) =
    isect_merge!(dst, dpos, a, ao, la, b, bo, lb)   # v2: trộn hai con trỏ
@inline _isect_into!(dst, dpos, a, ao, la, b, bo, lb, minsup, ::Val{:adaptive}) =   # phương thức cho :adaptive
    isect_adaptive!(dst, dpos, a, ao, la, b, bo, lb, minsup)   # v3 trở đi: giao thích ứng

# [VẤN ĐÁP] _vec_from_vec!
# LÀM GÌ    : dựng lớp con dạng vector vào vùng nhớ của độ sâu kế tiếp, không cấp phát trong vòng lặp.
# HỎI–ĐÁP   : H: need tính để làm gì? Đ: chặn trên tổng độ dài tidset con (mỗi phần giao ≤ min(la, lens[j])); nới buf
#                MỘT lần trước vòng lặp nên bên trong chắc chắn đủ chỗ.
#             H: Phép giao trượt ngưỡng đã ghi rác vào buf, có sao không? Đ: không, vì pos chỉ tiến khi đủ ngưỡng;
#                lần giao sau ghi đè lên đúng chỗ đó.
"""vector → vector."""
function _vec_from_vec!(child::VecLevel, parent::VecLevel, i::Int, js, minsup::Int, isect::Val, st)   # lớp con dạng vector
    _reset!(child)                                    # ghi đè lớp con cũ ở độ sâu này
    @inbounds la = Int(parent.lens[i])                # độ dài tidset của atom i
    @inbounds ao = parent.offs[i]                     # vị trí của nó trong buffer của lớp cha
    # Nới buffer một lần trước vòng lặp, đủ cho trường hợp xấu nhất (mọi phép giao đều đủ ngưỡng):
    # mỗi tidset con dài tối đa min(la, lens[j]).
    need = 0                                          # chặn trên tổng độ dài các tidset con
    @inbounds for j in js   # các atom j cần ghép với i
        need += min(la, Int(parent.lens[j]))   # phần giao ≤ tidset ngắn hơn
    end
    length(child.buf) < need && resize!(child.buf, need)   # chỉ nới khi thiếu; đủ rồi thì dùng lại nguyên
    pos = 1                                           # ô trống đầu tiên trong buffer của lớp con
    pbuf = parent.buf                                 # gán ra biến cục bộ cho trình biên dịch tối ưu dễ hơn
    cbuf = child.buf   # biến cục bộ
    @inbounds for j in js   # các atom j cần ghép với i
        # Giao tidset của atom i với atom j, ghi thẳng vào buffer lớp con từ ô pos.
        c = _isect_into!(cbuf, pos, pbuf, ao, la, pbuf, parent.offs[j], Int(parent.lens[j]), minsup, isect)
        ok = c >= minsup                              # đủ ngưỡng?
        _st_isect!(st, ok)   # đếm phép giao (E8)
        if ok   # đủ ngưỡng
            push!(child.items, parent.items[j])       # x_j thành atom của lớp con
            push!(child.offs, pos)                    # tidset của nó bắt đầu ở pos
            push!(child.lens, Int32(c))               # và dài c (= support)
            pos += c                                  # chỉ giữ chỗ khi tidset con đủ ngưỡng
        end                                           # trượt ngưỡng: lần giao sau ghi đè lên đúng chỗ đó
    end
    return child   # lớp con đã dựng
end

"""bitset → bitset."""
function _bit_from_bit!(child::BitLevel, parent::BitLevel, i::Int, js, minsup::Int, st, N::Int)   # lớp con dạng bitset
    _reset!(child)   # ghi đè lớp con cũ
    @inbounds a = parent.pool[i]                          # bitset của atom i
    @inbounds for j in js   # các atom j cần ghép với i
        dst = _slot!(child, length(child.items) + 1, N)   # ô bị trượt ngưỡng sẽ được ghi đè ở j sau
        c = and_count!(dst, a, parent.pool[j])            # dst = a AND bitset của j; c = support
        ok = c >= minsup   # đủ ngưỡng?
        _st_isect!(st, ok)   # đếm phép giao (E8)
        if ok   # đủ ngưỡng
            push!(child.items, parent.items[j])           # ô dst được giữ lại cho atom mới này
            push!(child.sups, Int32(c))   # support của atom mới
        end
    end
    return child   # lớp con đã dựng
end

"""bitset → vector (bản lai chuyển biểu diễn khi lớp con đủ thưa)."""
function _vec_from_bit!(child::VecLevel, parent::BitLevel, i::Int, js, minsup::Int, st)   # bitset cha → lớp con vector
    _reset!(child)   # ghi đè lớp con cũ
    @inbounds si = Int(parent.sups[i])                # support của atom i
    need = 0                                          # chặn trên tổng độ dài tidset con, như _vec_from_vec!
    @inbounds for j in js   # các atom j cần ghép với i
        need += min(si, Int(parent.sups[j]))   # chặn trên độ dài phần giao
    end
    length(child.buf) < need && resize!(child.buf, need)   # nới buffer một lần
    pos = 1   # ô trống đầu tiên
    cbuf = child.buf   # biến cục bộ
    @inbounds a = parent.pool[i]                      # bitset của atom i
    @inbounds for j in js   # các atom j cần ghép với i
        c = and_extract!(cbuf, pos, a, parent.pool[j])    # AND hai bitset, ghi kết quả thành danh sách tid
        ok = c >= minsup   # đủ ngưỡng?
        _st_isect!(st, ok)   # đếm phép giao (E8)
        if ok   # đủ ngưỡng
            push!(child.items, parent.items[j])   # atom mới
            push!(child.offs, pos)   # vị trí tidset
            push!(child.lens, Int32(c))   # độ dài = support
            pos += c   # giữ chỗ
        end
    end
    return child   # lớp con đã dựng
end

# Lớp con chỉ có một atom: atom đó được xuất (tập của nó là phổ biến), nhưng không còn atom nào
# để ghép cặp, nên không bao giờ cần tidset của nó. Chỉ cần ghi item và support (đã biết từ mảng tam giác).
# offs = 1 chỉ để các mảng đủ độ dài; tidset không được đọc.
"""Lớp con chỉ có một atom: không bao giờ cần tidset của nó (không còn cặp nào để giao)."""
_single!(child::VecLevel, item, sup) = (_reset!(child); push!(child.items, item); push!(child.offs, 1);   # lớp một atom, dạng vector
                                       push!(child.lens, Int32(sup)); child)   # (tiếp)
_single!(child::BitLevel, item, sup) = (_reset!(child); push!(child.items, item); push!(child.sups, Int32(sup)); child)   # lớp một atom, dạng bitset

# Vì sao bản lai v6 chuyển sang vector: một bitset luôn tốn N bit, còn một tidset vector tốn
# 32 bit cho mỗi tid. Hai cách tốn bằng nhau khi support = N/32. Dưới mức đó, vector vừa nhỏ hơn
# vừa giao nhanh hơn (chi phí tỉ lệ với support, không phải N). Vậy hybrid_ratio = 1/32.
# Chặn trên support của mọi tidset con: |t_i ∩ t_j| ≤ min(sup_i, sup_j) ≤ min(sup_i, max_j sup_j).
# Nếu chặn trên này đã < switch_at thì MỌI tidset con đều thưa → lưu cả lớp con dạng vector.
#
# [VẤN ĐÁP] _should_switch (tối ưu v6)
# BẰNG CHỨNG: E8 minsup thấp nhất: tidset đỉnh retail 22,45 → 2,66 MiB, T10I4D100K 9,34 → 3,85 MiB (về mức của v3),
#             nhưng chậm hơn v5 2,4 lần (retail) và 3,6 lần (T10I4D100K). Trên dữ liệu dày v6 giữ dãy bit, ngang v4/v5.
# HỎI–ĐÁP   : H: Câu "dưới N/32 vector giao nhanh hơn" có đúng không? Đ: chỉ đúng về BỘ NHỚ. E7 đo được điểm cân bằng
#                THỜI GIAN thấp hơn nhiều (ρ ≈ 0,004), nên v6 đổi thời gian lấy bộ nhớ trên dữ liệu thưa; hướng cải tiến
#                là chuyển theo mô hình chi phí thời gian (mục đề xuất trong Chương 2).
#             H: Vì sao chỉ chuyển bitset → vector mà không chuyển ngược? Đ: support không bao giờ tăng khi đi sâu (bổ đề 6).
"""Bản lai: lớp con của atom i có nên lưu dạng vector không (chặn trên support < ngưỡng)?"""
@inline function _should_switch(ws::Workspace, lvl::BitLevel, i::Int, js)   # quyết định của bản lai
    ws.switch_at < 0 && return false                  # v4, v5: không bao giờ chuyển
    mx = 0                                            # support lớn nhất trong các atom j
    @inbounds for j in js   # các atom j cần ghép với i
        mx = max(mx, Int(lvl.sups[j]))   # support lớn nhất
    end
    @inbounds return min(Int(lvl.sups[i]), mx) < ws.switch_at   # chặn trên support mọi tidset con < N/32?
end

# ---------------------------------------------------------------------------
# Duyệt đệ quy (độ sâu d ≥ 2) — một phương thức cho mỗi dạng lớp
# ---------------------------------------------------------------------------
# Hai hàm _mine_vec! và _mine_bit! có cùng khung như _mine_alloc!: xuất atom i, dựng lớp con
# vào vùng nhớ của độ sâu d + 1, đi xuống. Tách hai hàm theo dạng lớp để trong mỗi hàm
# mọi biến đều có kiểu cố định (ổn định kiểu), Julia sinh được mã máy nhanh.

function _mine_vec!(sink, prefix::Vector{Int32}, ws::Workspace, d::Int, minsup::Int, isect::Val, st, maxlen::Int)   # duyệt lớp vector ở độ sâu d
    lvl = ws.vec[d]                          # lớp đang duyệt nằm trong vùng nhớ vector của độ sâu d
    k = length(lvl.items)                    # số atom
    @inbounds for i in 1:k   # từng atom của lớp
        push!(prefix, lvl.items[i])          # tập đang xét
        depth = length(prefix)   # kích thước tập
        _st_itemset!(st, depth)   # đếm một tập (E8)
        sink(prefix, Int(lvl.lens[i]))       # support = độ dài tidset
        if depth < maxlen && i < k           # còn atom đứng sau thì mới có lớp con
            child = _vec_level!(ws, d + 1)   # vùng nhớ của độ sâu kế tiếp (ghi đè lớp con trước đó)
            _vec_from_vec!(child, lvl, i, (i + 1):k, minsup, isect, st)   # dựng lớp con
            _descend_vec!(sink, prefix, ws, d + 1, child, minsup, isect, st, maxlen)   # đi xuống
        end
        pop!(prefix)                         # quay lại tiền tố cũ
    end
    return nothing   # không trả giá trị
end

function _mine_bit!(sink, prefix::Vector{Int32}, ws::Workspace, d::Int, minsup::Int, isect::Val, st, maxlen::Int)   # duyệt lớp bitset ở độ sâu d
    lvl = ws.bit[d]                          # lớp đang duyệt nằm trong vùng nhớ bitset của độ sâu d
    k = length(lvl.items)   # số atom
    @inbounds for i in 1:k   # từng atom của lớp
        push!(prefix, lvl.items[i])   # tập đang xét
        depth = length(prefix)   # kích thước tập
        _st_itemset!(st, depth)   # đếm một tập (E8)
        sink(prefix, Int(lvl.sups[i]))       # support đã lưu sẵn trong sups
        if depth < maxlen && i < k   # còn atom đứng sau
            _expand_bit!(sink, prefix, ws, d, lvl, i, (i + 1):k, minsup, isect, st, maxlen)   # giữ bitset hay chuyển
        end
        pop!(prefix)   # quay lại tiền tố cũ
    end
    return nothing   # không trả giá trị
end

"""Dựng lớp con của một atom dạng bitset (giữ bitset, hoặc chuyển sang vector) rồi đi xuống."""
function _expand_bit!(sink, prefix, ws::Workspace, d::Int, lvl::BitLevel, i::Int, js, minsup::Int,   # giữ bitset hay chuyển vector
                      isect::Val, st, maxlen::Int)   # (tiếp tham số)
    if _should_switch(ws, lvl, i, js)   # lớp con đủ thưa?
        # Lớp con đủ thưa (chỉ xảy ra ở v6): dựng nó dạng vector; từ đây trở xuống nhánh này đi theo _mine_vec!.
        child = _vec_level!(ws, d + 1)
        _vec_from_bit!(child, lvl, i, js, minsup, st)   # dựng dạng vector
        isempty(child.items) || _st_switch!(st)       # đếm một lần chuyển (cho bảng B04)
        _descend_vec!(sink, prefix, ws, d + 1, child, minsup, isect, st, maxlen)   # đi xuống
    else
        # Lớp con còn dày: giữ dạng bitset.
        child = _bit_level!(ws, d + 1)
        _bit_from_bit!(child, lvl, i, js, minsup, st, ws.N)   # dựng dạng bitset
        _descend_bit!(sink, prefix, ws, d + 1, child, minsup, isect, st, maxlen)   # đi xuống
    end
    return nothing   # không trả giá trị
end

# Đi xuống một lớp con vừa dựng (nếu nó khác rỗng), kèm cập nhật bộ đếm bộ nhớ trước và sau.
@inline function _descend_vec!(sink, prefix, ws, d, child::VecLevel, minsup, isect, st, maxlen)
    isempty(child.items) && return nothing   # lớp con rỗng: không có gì để duyệt
    _st_class!(st)   # đếm một lớp
    nb = _live_bytes(child)                  # byte tidset của lớp con (E10)
    _st_alloc!(st, nb)   # bộ nhớ đang sống tăng (E10)
    _mine_vec!(sink, prefix, ws, d, minsup, isect, st, maxlen)   # đệ quy
    _st_free!(st, nb)   # bộ nhớ đang sống giảm
    return nothing   # không trả giá trị
end

@inline function _descend_bit!(sink, prefix, ws, d, child::BitLevel, minsup, isect, st, maxlen)   # đi xuống lớp con bitset
    isempty(child.items) && return nothing   # lớp rỗng
    _st_class!(st)   # đếm một lớp
    nb = _live_bytes(child, ws.N)   # byte của lớp con
    _st_alloc!(st, nb)   # bộ nhớ đang sống tăng (E10)
    _mine_bit!(sink, prefix, ws, d, minsup, isect, st, maxlen)   # đệ quy
    _st_free!(st, nb)   # bộ nhớ đang sống giảm
    return nothing   # không trả giá trị
end

# ---------------------------------------------------------------------------
# Lớp gốc (độ sâu 1): nơi duy nhất dùng mảng tam giác (v5, v6)
# ---------------------------------------------------------------------------
# Lớp con của lớp gốc chính là các tập 2 item. Với mảng tam giác (tri), ta đã biết support của mọi
# cặp, nên với atom i chỉ cần giao với những j mà cặp (i, j) đủ ngưỡng; các cặp khác bỏ qua luôn.

"""Các atom j > i mà cặp (i, j) đủ ngưỡng theo mảng tam giác; ghi vào `cand`."""
function _candidates!(cand::Vector{Int}, tri::Vector{UInt32}, i::Int, k::Int, minsup::Int, st)   # lọc cặp bằng mảng tam giác
    empty!(cand)                             # dùng lại mảng cand, không cấp phát
    base = (i - 1) * (2k - i) ÷ 2 - i        # base + j = tri_index(i, j, k): vị trí ô (i, j) trong mảng tam giác
    @inbounds for j in (i + 1):k   # mọi atom đứng sau
        tri[base+j] >= minsup && push!(cand, j)      # cặp (i, j) đủ ngưỡng thì mới cần giao
    end
    _st_skip!(st, (k - i) - length(cand))    # số cặp bị loại = số phép giao tiết kiệm được
    return cand   # các j cần giao
end

"""Các atom j > i cần xét ở lớp gốc: tất cả, hoặc chỉ các cặp đủ ngưỡng theo mảng tam giác."""
function _root_js!(ws::Workspace, tri, i::Int, k::Int, minsup::Int, st)   # các j cần xét ở lớp gốc
    if tri === nothing                       # v2–v4 (hoặc mảng tam giác quá lớn): xét mọi j đứng sau
        empty!(ws.cand)   # dùng lại mảng
        append!(ws.cand, (i + 1):k)   # mọi j > i
        return ws.cand   # danh sách j
    end
    return _candidates!(ws.cand, tri, i, k, minsup, st)   # v5, v6: chỉ các cặp đủ ngưỡng
end

# [VẤN ĐÁP] _mine_root!
# LÀM GÌ    : duyệt lớp gốc; dựng các tập 2 item (chỉ giao các cặp đủ ngưỡng nếu có mảng tam giác).
# HỎI–ĐÁP   : H: _single! để làm gì? Đ: atom i chỉ còn MỘT cặp đủ ngưỡng → lớp con có một atom: nó được xuất nhưng
#                không còn cặp nào để giao tiếp, nên bỏ qua phép giao, lấy support thẳng từ mảng tam giác.
# Lớp gốc dạng vector (v2, v3; hoặc v6 trên dữ liệu thưa).
function _mine_root!(sink, prefix::Vector{Int32}, ws::Workspace, root::VecLevel, tri, minsup::Int,
                     isect::Val, st, maxlen::Int)   # (tiếp tham số)
    k = length(root.items)                   # số item phổ biến
    @inbounds for i in 1:k   # từng atom của lớp
        push!(prefix, root.items[i])   # tập 1 item
        _st_itemset!(st, 1)   # đếm
        sink(prefix, Int(root.lens[i]))      # xuất tập 1 item
        if maxlen > 1 && i < k   # còn cặp để ghép
            t0 = _now(st)                    # bấm giờ phần tính tập 2 item
            js = _root_js!(ws, tri, i, k, minsup, st)    # các atom j cần giao với i
            child = _vec_level!(ws, 2)       # vùng nhớ độ sâu 2
            if tri !== nothing && length(js) == 1   # chỉ một cặp đủ ngưỡng
                # Chỉ một cặp đủ ngưỡng: lớp con có một atom, không cần giao (xem _single!).
                _single!(child, root.items[js[1]], tri[tri_index(i, js[1], k)])   # support lấy từ mảng tam giác
            else
                _vec_from_vec!(child, root, i, js, minsup, isect, st)   # giao các cặp còn lại
            end
            _st_level2_time!(st, _now(st) - t0)   # cộng thời gian mức 2
            _descend_vec!(sink, prefix, ws, 2, child, minsup, isect, st, maxlen)   # đi xuống độ sâu 2
        end
        pop!(prefix)   # quay lại tiền tố cũ
    end
    return nothing   # không trả giá trị
end

# Lớp gốc dạng bitset (v4, v5; hoặc v6 trên dữ liệu dày). Có thêm nhánh bản lai chuyển sang vector.
function _mine_root!(sink, prefix::Vector{Int32}, ws::Workspace, root::BitLevel, tri, minsup::Int,
                     isect::Val, st, maxlen::Int)   # (tiếp tham số)
    k = length(root.items)   # số item phổ biến
    @inbounds for i in 1:k   # từng atom của lớp
        push!(prefix, root.items[i])   # tập 1 item
        _st_itemset!(st, 1)   # đếm
        sink(prefix, Int(root.sups[i]))      # xuất tập 1 item
        if maxlen > 1 && i < k   # còn cặp để ghép
            t0 = _now(st)   # bấm giờ
            js = _root_js!(ws, tri, i, k, minsup, st)   # các j cần giao
            if tri !== nothing && length(js) == 1   # chỉ một cặp đủ ngưỡng
                # Một cặp duy nhất: như nhánh tương ứng ở bản vector.
                child = _bit_level!(ws, 2)
                _single!(child, root.items[js[1]], tri[tri_index(i, js[1], k)])   # support lấy từ mảng tam giác
                _st_level2_time!(st, _now(st) - t0)   # cộng thời gian mức 2
                _descend_bit!(sink, prefix, ws, 2, child, minsup, isect, st, maxlen)   # đi xuống độ sâu 2
            elseif _should_switch(ws, root, i, js)   # bản lai: chuyển?
                # Bản lai: lớp con đủ thưa → dựng dạng vector.
                child = _vec_level!(ws, 2)
                _vec_from_bit!(child, root, i, js, minsup, st)   # dựng dạng vector
                isempty(child.items) || _st_switch!(st)   # đếm một lần chuyển
                _st_level2_time!(st, _now(st) - t0)   # cộng thời gian mức 2
                _descend_vec!(sink, prefix, ws, 2, child, minsup, isect, st, maxlen)   # đi xuống độ sâu 2
            else
                # Còn dày → giữ dạng bitset.
                child = _bit_level!(ws, 2)
                _bit_from_bit!(child, root, i, js, minsup, st, ws.N)   # dựng dạng bitset
                _st_level2_time!(st, _now(st) - t0)   # cộng thời gian mức 2
                _descend_bit!(sink, prefix, ws, 2, child, minsup, isect, st, maxlen)   # đi xuống độ sâu 2
            end
        end
        pop!(prefix)   # quay lại tiền tố cũ
    end
    return nothing   # không trả giá trị
end

# [VẤN ĐÁP] _eclat_ws! (điểm vào v2–v6)
# HỎI–ĐÁP   : H: "Rào chắn hàm" (function barrier) là gì, vì sao cần? Đ: biến root có kiểu VecLevel HOẶC BitLevel tùy
#                dữ liệu (chỉ biết lúc chạy) → trong _eclat_ws! nó không ổn định kiểu. Truyền root vào hàm khác
#                (_mine_root!) thì Julia biên dịch riêng một bản cho từng kiểu, bên trong mọi biến ổn định kiểu → nhanh.
#             H: density tính thế nào? Đ: support trung bình của item phổ biến chia N; ≥ 1/32 thì lớp gốc dùng dãy bit (v6).
# Điểm vào của v2–v6: chuẩn bị, chọn dạng lớp gốc theo cấu hình, rồi duyệt.
function _eclat_ws!(sink, db::TransactionDB, minsup::Int, cfg::EclatConfig, st, maxlen::Int)
    supp = item_supports(db)                         # support từng item
    freq = frequent_items(supp, minsup, cfg.order)   # item phổ biến theo thứ tự cấu hình
    isempty(freq) && return nothing   # không có item phổ biến
    N = n_transactions(db)   # số giao dịch
    # Mật độ = support trung bình của item phổ biến chia cho N (0..1). Dữ liệu dày như Chess có mật độ cao.
    density = sum(x -> supp[x], freq) / (length(freq) * N)       # mật độ trung bình của lớp gốc
    # Dùng bitset ở lớp gốc nếu cấu hình là :bitset (v4, v5), hoặc :hybrid (v6) và dữ liệu đủ dày.
    use_bits = cfg.tidset == :bitset || (cfg.tidset == :hybrid && density >= cfg.hybrid_ratio)
    # Ngưỡng support để bản lai chuyển sang vector (N/32 giao dịch); -1 nghĩa là không bao giờ chuyển.
    switch_at = cfg.tidset == :hybrid ? cfg.hybrid_ratio * N : -1.0
    ws = Workspace(VecLevel[], BitLevel[], N, switch_at, Int[])  # vùng nhớ dùng lại, ban đầu rỗng
    tri = nothing                                    # nothing = không dùng mảng tam giác
    if cfg.level2 == :triangular && maxlen > 1 && length(freq) > 1   # v5, v6
        t0 = _now(st)   # bấm giờ
        tri = pair_counts(db, item_ranks(n_items(db), freq), length(freq))   # đếm mọi cặp (level2.jl)
        _st_level2_time!(st, _now(st) - t0)   # cộng thời gian mức 2
    end
    if use_bits   # lớp gốc dạng bitset?
        root = _root_bit(db, freq, supp)   # dựng dạng bitset
        push!(ws.bit, root)                          # lớp gốc là vùng nhớ bitset của độ sâu 1
        nb = _live_bytes(root, N)   # byte lớp gốc
    else
        root = _root_vec(db, freq, supp)   # dựng dạng vector
        push!(ws.vec, root)                          # lớp gốc là vùng nhớ vector của độ sâu 1
        nb = _live_bytes(root)   # byte lớp gốc
    end
    _st_alloc!(st, nb)   # bộ nhớ đang sống tăng (E10)
    # "Rào chắn hàm" (function barrier): kiểu của root (VecLevel hay BitLevel) chỉ biết lúc chạy.
    # Truyền root vào một hàm khác thì Julia biên dịch riêng _mine_root! cho từng kiểu, và bên trong
    # hàm đó mọi thứ đều ổn định kiểu, nên chạy nhanh.
    _mine_root!(sink, Int32[], ws, root, tri, minsup, Val(cfg.isect), st, maxlen)   # rào chắn hàm
    _st_free!(st, nb)   # bộ nhớ đang sống giảm
    return nothing   # không trả giá trị
end

# ---------------------------------------------------------------------------
# Giao diện công khai
# ---------------------------------------------------------------------------

# Bắt sớm cấu hình sai (gõ nhầm tên, hoặc tổ hợp chưa được cài đặt) với thông báo rõ ràng,
# thay vì để lỗi lạ xảy ra sâu bên trong thuật toán.
"""Kiểm tra cấu hình hợp lệ và đã được cài đặt."""
function check_config(cfg::EclatConfig)   # kiểm tra cấu hình
    cfg.tidset in (:vector, :bitset, :hybrid) || throw(ArgumentError("tidset không hợp lệ: $(cfg.tidset)"))   # giá trị hợp lệ
    cfg.order in (:lexical, :support_asc) || throw(ArgumentError("order không hợp lệ: $(cfg.order)"))   # giá trị hợp lệ
    cfg.isect in (:merge, :adaptive) || throw(ArgumentError("isect không hợp lệ: $(cfg.isect)"))   # giá trị hợp lệ
    cfg.level2 in (:intersect, :triangular) || throw(ArgumentError("level2 không hợp lệ: $(cfg.level2)"))   # giá trị hợp lệ
    # Động cơ cấp phát (reuse = false) chỉ có tidset vector và giao từng cặp.
    if !cfg.reuse && (cfg.tidset != :vector || cfg.level2 != :intersect)
        throw(ArgumentError("tidset dạng bitset/lai và mảng tam giác chỉ được cài với reuse = true"))   # tổ hợp chưa cài đặt
    end
    cfg.hybrid_ratio > 0 || throw(ArgumentError("hybrid_ratio phải > 0"))   # ngưỡng phải dương
    return nothing   # không trả giá trị
end

# [VẤN ĐÁP] eclat!
# LÀM GÌ    : hàm công khai: khai thác mọi tập phổ biến, báo từng tập qua sink(items, support).
# VÌ SAO    : dùng sink thay vì trả về danh sách: ở minsup thấp có thể có hàng triệu tập; sink cho phép ghi thẳng ra file
#             (demo.jl, SPMFWriter) mà không giữ mọi tập trong bộ nhớ.
# HỎI–ĐÁP   : H: minsup ở đây là số đếm hay tỉ lệ? Đ: số đếm σ_min; người gọi đổi "60%" → σ_min bằng minsup_count
#                (làm tròn lên trên Float64, đúng như SPMF, đã kiểm 10 trường hợp biên).
"""
    eclat!(sink, db, minsup, cfg = DEFAULT_CONFIG; stats = nothing, maxlen = typemax(Int))

Khai thác **mọi** tập phổ biến của `db` có support ≥ `minsup` (số đếm, xem `minsup_count`).

Mỗi tập phổ biến (không rỗng) được báo **đúng một lần** qua `sink(items, support)`:
- `items` là mã nội bộ của `db`, không bảo đảm thứ tự;
- `items` là **buffer được dùng lại**: `sink` phải `copy` nếu muốn giữ;
- thứ tự gọi là xác định (cùng input và cấu hình thì cùng thứ tự).

`stats::EclatStats` (tùy chọn) nhận các bộ đếm; `maxlen` giới hạn kích thước tập.
"""
function eclat!(sink, db::TransactionDB, minsup::Integer, cfg::EclatConfig = DEFAULT_CONFIG;   # hàm công khai
                stats::Union{Nothing,EclatStats} = nothing, maxlen::Integer = typemax(Int))   # mặc định: không đếm, không giới hạn độ dài
    minsup >= 1 || throw(ArgumentError("minsup (số đếm) phải ≥ 1"))   # minsup = 0 sẽ sinh mọi tập con: vô nghĩa
    check_config(cfg)                                # báo lỗi rõ ràng nếu cấu hình sai
    # Chọn động cơ theo cấu hình: v2–v6 dùng lại buffer, v0–v1 cấp phát.
    if cfg.reuse
        _eclat_ws!(sink, db, Int(minsup), cfg, stats, Int(maxlen))   # v2–v6
    else
        _eclat_alloc!(sink, db, Int(minsup), cfg, stats, Int(maxlen))   # v0, v1
    end
    return nothing   # không trả giá trị
end

"""
    eclat(db, minsup, cfg = DEFAULT_CONFIG; maxlen) -> Dict{Vector{Int32},Int}

Tiện ích cho kiểm thử: gom mọi tập phổ biến vào `Dict` (khóa là mã nội bộ đã sắp tăng dần).
"""
function eclat(db::TransactionDB, minsup::Integer, cfg::EclatConfig = DEFAULT_CONFIG;   # tiện ích cho test
               maxlen::Integer = typemax(Int))   # (tiếp tham số)
    res = Dict{Vector{Int32},Int}()                  # tập (đã sắp) → support
    # sink ở đây: sort(items) tạo bản sao đã sắp (buffer items bị dùng lại nên phải sao chép), lưu kèm support.
    eclat!((items, s) -> (res[sort(items)] = s), db, minsup, cfg; maxlen = maxlen)
    return res   # mọi tập phổ biến
end
