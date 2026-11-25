# Thuật toán Eclat (phần của A).
#
# Theo bài báo gốc (Zaki, 2000):
#   §4.1  support của một tập = độ dài phần giao tidset của hai tập con kích thước k-1;
#   §4.2  không gian tìm kiếm chia thành các lớp tương đương theo tiền tố, giải độc lập;
#   §5.2  duyệt từ dưới lên: giao mọi cặp atom trong lớp, tập đủ ngưỡng thành atom của lớp con.
# Bản cơ bản không kiểm tra tập con (bài báo §5.2: cắt tỉa gần như không có lợi vì bổ đề 6).
#
# Có hai "động cơ" duyệt:
#   - động cơ cấp phát (v0, v1): mỗi atom giữ tidset riêng, mỗi phép giao tạo một mảng mới;
#   - động cơ dùng lại buffer (v2 trở đi): mỗi độ sâu đệ quy có một vùng nhớ riêng, lớp con
#     của mọi atom cùng độ sâu lần lượt ghi đè lên vùng nhớ đó, nên vòng lặp nóng không cấp phát.
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
#   4. Động cơ dùng lại buffer          — v2 (dùng lại vùng nhớ), v3 (giao thích ứng, ở tidsets.jl);
#   5. Giao diện công khai              — eclat!, eclat.

"""Tên phiên bản dùng khi không chỉ định cấu hình (bản tốt nhất đã cài đặt)."""
const DEFAULT_VARIANT = "v3"
const DEFAULT_CONFIG = VARIANTS[DEFAULT_VARIANT]   # cấu hình tương ứng; là tham số mặc định của eclat!, eclat

# ---------------------------------------------------------------------------
# Bộ đếm: khi stats === nothing, các lời gọi dưới đây không làm gì và bị trình biên dịch
# loại bỏ (multiple dispatch theo kiểu Nothing / EclatStats), nên không tốn chi phí khi đo thời gian.
# ---------------------------------------------------------------------------
# Mỗi bộ đếm có HAI phương thức cùng tên. Julia chọn phương thức theo KIỂU của tham số đầu:
#   - st là nothing (kiểu Nothing)  → phương thức rỗng, trả về nothing; sau khi chép thân hàm
#     vào chỗ gọi (@inline), không còn lệnh nào: lần chạy đo thời gian không bị chậm đi;
#   - st là EclatStats              → phương thức cộng bộ đếm thật (lần chạy đo bộ đếm, E8/E10).
# Nhờ vậy chỉ cần MỘT bản code thuật toán cho cả hai mục đích, không phải rải "if" khắp nơi.

# Đếm một tập phổ biến vừa xuất, và ghi nhận độ sâu lớn nhất đã gặp.
@inline _st_itemset!(::Nothing, depth) = nothing
@inline function _st_itemset!(st::EclatStats, depth)
    st.n_itemsets += 1
    depth > st.max_depth && (st.max_depth = depth)   # cú pháp "a && b": chỉ chạy b khi a đúng
    return nothing
end

# Đếm một phép giao tidset; ok = false nghĩa là kết quả trượt ngưỡng (phép giao "phí công").
@inline _st_isect!(::Nothing, ok::Bool) = nothing
@inline function _st_isect!(st::EclatStats, ok::Bool)
    st.n_intersections += 1
    ok || (st.n_failed += 1)                         # "a || b": chỉ chạy b khi a sai
    return nothing
end

# Ghi nhận có thêm nbytes byte tidset đang sống, và cập nhật đỉnh bộ nhớ (E10).
@inline _st_alloc!(::Nothing, nbytes) = nothing
@inline function _st_alloc!(st::EclatStats, nbytes)
    st.bytes_current += nbytes
    st.bytes_current > st.bytes_peak && (st.bytes_peak = st.bytes_current)
    return nothing
end

# Ghi nhận nbytes byte tidset không còn dùng nữa (khi đệ quy quay lên).
@inline _st_free!(::Nothing, nbytes) = nothing
@inline _st_free!(st::EclatStats, nbytes) = (st.bytes_current -= nbytes; nothing)

# Đếm một lớp tương đương khác rỗng đã dựng.
@inline _st_class!(::Nothing) = nothing
@inline _st_class!(st::EclatStats) = (st.n_classes += 1; nothing)

# Cộng dồn thời gian tính các tập 2 item (ns), để so mảng tam giác với giao từng cặp.
@inline _st_level2_time!(::Nothing, ns) = nothing
@inline _st_level2_time!(st::EclatStats, ns) = (st.time_level2_ns += ns; nothing)

# Đồng hồ: chỉ đọc giờ khi có đo bộ đếm; khi không đo thì trả về 0, không tốn lời gọi time_ns().
@inline _now(::Nothing) = UInt64(0)
@inline _now(::EclatStats) = time_ns()

# ---------------------------------------------------------------------------
# Chuẩn bị: đếm support, chọn item phổ biến, sắp thứ tự, dựng tidset dạng dọc
# ---------------------------------------------------------------------------

"""Support của từng item (mã nội bộ 1..m): một lần quét dữ liệu ngang."""
function item_supports(db::TransactionDB)
    supp = zeros(Int, n_items(db))           # supp[x] = số giao dịch chứa item x
    @inbounds for t in db.transactions, x in t   # duyệt mọi giao dịch t, mọi item x trong t
        supp[x] += 1                         # mỗi giao dịch không có item trùng, nên đếm đúng
    end
    return supp
end

# Vì sao v1 sắp item theo support TĂNG dần (heuristic quen thuộc của Eclat, Zaki 2000):
#   lớp con của atom i chỉ gồm các item đứng SAU i. Khi item hiếm đứng trước:
#   - lớp con của item hiếm có nhiều atom, nhưng tidset của nó ngắn: phép giao nhanh, và phần lớn
#     kết quả trượt ngưỡng ngay nên cây đệ quy bị cắt sớm;
#   - item phổ biến (tidset dài, giao đắt) đứng cuối nên lớp con của nó có ít atom.
#   Kết quả: ít phép giao trên tidset dài hơn, ít lớp con lớn hơn. Đo trong E8 (v0 → v1).
"""Các item phổ biến theo thứ tự xử lý của cấu hình (`:lexical` hoặc `:support_asc`)."""
function frequent_items(supp::Vector{Int}, minsup::Integer, order::Symbol)
    freq = Int32[x for x in eachindex(supp) if supp[x] >= minsup]   # chỉ giữ item đủ ngưỡng, theo mã tăng dần
    if order == :support_asc
        sort!(freq; by = x -> (supp[x], x))    # hòa support thì theo mã, để thứ tự luôn xác định
    elseif order != :lexical
        throw(ArgumentError("order không hợp lệ: $order"))
    end
    return freq
end

"""rank[x] = vị trí của item x trong `freq` (0 nếu không phổ biến)."""
function item_ranks(m::Int, freq::Vector{Int32})
    rank = zeros(Int32, m)               # mặc định 0 = không phổ biến
    for (r, x) in enumerate(freq)        # r = vị trí trong freq, x = mã item
        rank[x] = r
    end
    return rank
end

"""
    vertical_tidsets(db, freq, supp) -> Vector{Vector{Int32}}

Dựng tidset dạng vector cho các item phổ biến `freq` (theo đúng thứ tự trong `freq`).
Duyệt giao dịch theo tid tăng dần nên mỗi tidset tự động tăng dần. O(N·L̄).
"""
function vertical_tidsets(db::TransactionDB, freq::Vector{Int32}, supp::Vector{Int})
    rank = item_ranks(n_items(db), freq)     # tra nhanh "item x là item phổ biến thứ mấy"
    tids = [Vector{Int32}(undef, supp[x]) for x in freq]   # biết trước support nên cấp đúng số ô cần
    fill_pos = zeros(Int, length(freq))      # fill_pos[r] = số ô đã điền của tidset thứ r
    @inbounds for (tid, t) in enumerate(db.transactions)   # tid = số thứ tự giao dịch (1, 2, ...)
        for x in t
            r = rank[x]
            r == 0 && continue                   # item không phổ biến: bỏ qua
            p = fill_pos[r] += 1                 # tăng bộ đếm và lấy ô kế tiếp
            tids[r][p] = Int32(tid)              # tid tăng dần nên tidset tự tăng dần, không cần sắp xếp
        end
    end
    return tids
end

# ---------------------------------------------------------------------------
# Động cơ cấp phát (v0, v1): mỗi atom giữ tidset riêng, mỗi phép giao tạo mảng mới
# ---------------------------------------------------------------------------
# Đây là cách viết thẳng theo bài báo, dễ hiểu nhất. Nhược điểm: mỗi phép giao xin một mảng mới
# từ bộ nhớ; hàng triệu lần xin như vậy làm bộ dọn rác (GC) của Julia phải chạy liên tục. v2 sửa đúng
# điểm này (xem động cơ dùng lại buffer bên dưới).

"""Lớp tương đương: các cặp (item cuối, tidset). Tiền tố nằm ở ngăn xếp `prefix` dùng chung."""
struct AllocClass
    items::Vector{Int32}                 # items[k]: item cuối của atom k
    tidsets::Vector{Vector{Int32}}       # tidsets[k]: tidset của atom k (một mảng riêng cho mỗi atom)
end

# Số byte tidset của một lớp: mỗi tid Int32 chiếm 4 byte (dùng cho bộ đếm bộ nhớ, E10).
_bytes(tids::Vector{Vector{Int32}}) = 4 * sum(length, tids; init = 0)

# Val{:merge} / Val{:adaptive}: đưa lựa chọn của cấu hình vào KIỂU, để Julia biên dịch riêng một bản
# cho mỗi lựa chọn. Khi đó trong vòng lặp không còn phép so sánh "đang dùng phép giao nào".
"""Phép giao của động cơ cấp phát, chọn theo cấu hình (Val để chuyên biệt hóa lúc biên dịch)."""
_isect_alloc(a, b, ::Val{:merge}, minsup) = intersect_merge(a, b)
function _isect_alloc(a, b, ::Val{:adaptive}, minsup)
    out = Vector{Int32}(undef, min(length(a), length(b)))      # cấp mảng kết quả (đủ cho trường hợp xấu nhất)
    return resize!(out, isect_adaptive!(out, 1, a, 1, length(a), b, 1, length(b), minsup))   # cắt về đúng độ dài
end

"""Lớp con của atom thứ `i`: giao tidset của nó với tidset của mọi atom đứng sau."""
function _child_alloc(cls::AllocClass, i::Int, minsup::Int, isect::Val, st)
    items = Int32[]                          # atom của lớp con (chỉ những atom đủ ngưỡng)
    tids = Vector{Vector{Int32}}()           # tidset tương ứng
    tx = cls.tidsets[i]                      # tidset của atom i (tiền tố mới)
    @inbounds for j in (i + 1):length(cls.items)     # chỉ atom đứng sau: mỗi tập sinh đúng một lần
        t = _isect_alloc(tx, cls.tidsets[j], isect, minsup)   # t(P ∪ {x_i, x_j}) = t_i ∩ t_j
        ok = length(t) >= minsup             # support = độ dài phần giao
        _st_isect!(st, ok)
        if ok                                # đủ ngưỡng: x_j thành atom của lớp con
            push!(items, cls.items[j])
            push!(tids, t)
        end                                  # trượt ngưỡng: bỏ (mảng t sẽ bị GC dọn sau)
    end
    return AllocClass(items, tids)
end

# Duyệt đệ quy một lớp: xuất từng atom, rồi dựng lớp con của nó và đi xuống (duyệt theo chiều sâu).
# prefix là ngăn xếp tiền tố dùng chung: push! khi đi xuống, pop! khi quay lên, không tạo mảng mới.
function _mine_alloc!(sink, prefix::Vector{Int32}, cls::AllocClass, minsup::Int, isect::Val, st, maxlen::Int)
    k = length(cls.items)                    # số atom của lớp
    @inbounds for i in 1:k
        push!(prefix, cls.items[i])          # tập đang xét = tiền tố + item cuối của atom i
        depth = length(prefix)
        _st_itemset!(st, depth)
        sink(prefix, length(cls.tidsets[i]))                 # xuất tập prefix với support |t(prefix)|
        # Chỉ đi xuống khi chưa đạt độ dài tối đa và còn atom đứng sau để ghép cặp.
        if depth < maxlen && i < k
            t0 = depth == 1 ? _now(st) : UInt64(0)           # bấm giờ khi đang ở lớp gốc (sắp tính tập 2 item)
            child = _child_alloc(cls, i, minsup, isect, st)
            depth == 1 && _st_level2_time!(st, _now(st) - t0)  # lớp con của lớp gốc = tập 2 item
            if !isempty(child.items)         # lớp con rỗng thì không có gì để duyệt
                _st_class!(st)
                nb = _bytes(child.tidsets)
                _st_alloc!(st, nb)           # lớp con bắt đầu "sống"
                _mine_alloc!(sink, prefix, child, minsup, isect, st, maxlen)   # đệ quy xuống lớp con
                _st_free!(st, nb)            # xong lớp con: tidset của nó không còn dùng nữa
            end
        end
        pop!(prefix)                         # bỏ item cuối, quay lại tiền tố cũ cho atom tiếp theo
    end
    return nothing
end

# Điểm vào của v0, v1: chuẩn bị lớp gốc [∅] rồi duyệt đệ quy.
function _eclat_alloc!(sink, db::TransactionDB, minsup::Int, cfg::EclatConfig, st, maxlen::Int)
    supp = item_supports(db)                         # bước 1: support từng item
    freq = frequent_items(supp, minsup, cfg.order)   # bước 2: item phổ biến, theo thứ tự cấu hình
    isempty(freq) && return nothing                  # không có item phổ biến thì không có tập nào
    root = AllocClass(freq, vertical_tidsets(db, freq, supp))   # bước 3: lớp gốc, mỗi item một tidset
    nb = _bytes(root.tidsets)
    _st_alloc!(st, nb)
    _mine_alloc!(sink, Int32[], root, minsup, Val(cfg.isect), st, maxlen)   # bước 4: duyệt, tiền tố rỗng
    _st_free!(st, nb)
    return nothing
end

# ---------------------------------------------------------------------------
# Động cơ dùng lại buffer, tidset dạng vector (v2, v3)
# ---------------------------------------------------------------------------
# Ý tưởng v2: duyệt theo chiều sâu nên ở MỖI độ sâu d, tại một thời điểm chỉ có MỘT lớp đang sống
# (lớp con của atom đang xét). Khi chuyển sang atom kế tiếp, lớp con cũ không còn cần nữa.
# Vậy mỗi độ sâu chỉ cần một vùng nhớ, các lớp con lần lượt ghi đè lên nhau. Vùng nhớ chỉ được
# nới rộng vài lần lúc đầu; sau đó vòng lặp nóng không xin bộ nhớ mới, GC không phải chạy.
# v3 giữ nguyên động cơ này, chỉ đổi phép giao sang isect_adaptive! (tidsets.jl).

"""
Một lớp tương đương dạng vector đặt trong vùng nhớ dùng lại của một độ sâu.
Tidset của atom `k` là đoạn `buf[offs[k] : offs[k]+lens[k]-1]`; `lens[k]` chính là support.
"""
mutable struct VecLevel
    items::Vector{Int32}     # items[k]: item cuối của atom k
    offs::Vector{Int}        # offs[k]: tidset của atom k bắt đầu ở ô nào của buf
    lens::Vector{Int32}      # lens[k]: độ dài tidset của atom k (= support)
    buf::Vector{Int32}       # MỘT mảng chứa liền nhau tidset của mọi atom trong lớp
end
VecLevel() = VecLevel(Int32[], Int[], Int32[], Int32[])   # lớp rỗng, dùng khi cần thêm độ sâu mới

# Xóa nội dung một lớp để chuẩn bị ghi lớp con mới. empty! giữ nguyên vùng nhớ đã cấp,
# và buf KHÔNG bị xóa: nó chính là phần được dùng lại.
function _reset!(l::VecLevel)
    empty!(l.items)
    empty!(l.offs)
    empty!(l.lens)
    return l
end

# Số byte tidset thật sự đang dùng của một lớp (cho E10): 4 byte mỗi tid.
_live_bytes(l::VecLevel) = 4 * sum(l.lens; init = Int32(0))

"""Lớp gốc dạng vector: tidset của mọi item phổ biến nằm liền nhau trong một buffer."""
function _root_vec(db::TransactionDB, freq::Vector{Int32}, supp::Vector{Int})
    k = length(freq)
    lens = Int32[supp[x] for x in freq]      # độ dài tidset của từng item = support của nó
    offs = Vector{Int}(undef, k)
    # Tính vị trí bắt đầu: tidset thứ r đứng ngay sau tidset thứ r - 1.
    p = 1
    for r in 1:k
        offs[r] = p
        p += lens[r]
    end
    buf = Vector{Int32}(undef, p - 1)        # p - 1 = tổng độ dài mọi tidset
    rank = item_ranks(n_items(db), freq)
    fill_pos = copy(offs)                    # fill_pos[r] = ô kế tiếp cần ghi của tidset thứ r
    @inbounds for (tid, t) in enumerate(db.transactions)
        for x in t
            r = rank[x]
            r == 0 && continue               # item không phổ biến
            buf[fill_pos[r]] = Int32(tid)    # như vertical_tidsets, nhưng ghi vào buffer chung
            fill_pos[r] += 1
        end
    end
    return VecLevel(copy(freq), offs, lens, buf)
end

# Chọn phép giao theo cấu hình: v2 dùng trộn hai con trỏ, v3 trở đi dùng giao thích ứng.
@inline _isect_into!(dst, dpos, a, ao, la, b, bo, lb, minsup, ::Val{:merge}) =
    isect_merge!(dst, dpos, a, ao, la, b, bo, lb)
@inline _isect_into!(dst, dpos, a, ao, la, b, bo, lb, minsup, ::Val{:adaptive}) =
    isect_adaptive!(dst, dpos, a, ao, la, b, bo, lb, minsup)

"""Dựng lớp con của atom `i` của `parent` vào `child` (ghi đè vùng nhớ của độ sâu kế tiếp)."""
function _child_vec!(child::VecLevel, parent::VecLevel, i::Int, minsup::Int, isect::Val, st)
    _reset!(child)                                    # ghi đè lớp con cũ ở độ sâu này
    k = length(parent.items)
    @inbounds la = Int(parent.lens[i])                # độ dài tidset của atom i
    @inbounds ao = parent.offs[i]                     # vị trí của nó trong buffer của lớp cha
    # Nới buffer một lần trước vòng lặp, đủ cho trường hợp xấu nhất (mọi phép giao đều đủ ngưỡng):
    # mỗi tidset con dài tối đa min(la, lens[j]).
    need = 0                                          # chặn trên tổng độ dài các tidset con
    @inbounds for j in (i + 1):k
        need += min(la, Int(parent.lens[j]))
    end
    length(child.buf) < need && resize!(child.buf, need)   # chỉ nới khi thiếu; đủ rồi thì dùng lại nguyên
    pos = 1                                           # ô trống đầu tiên trong buffer của lớp con
    pbuf = parent.buf                                 # gán ra biến cục bộ cho trình biên dịch tối ưu dễ hơn
    cbuf = child.buf
    @inbounds for j in (i + 1):k
        # Giao tidset của atom i với atom j, ghi thẳng vào buffer lớp con từ ô pos.
        c = _isect_into!(cbuf, pos, pbuf, ao, la, pbuf, parent.offs[j], Int(parent.lens[j]), minsup, isect)
        ok = c >= minsup
        _st_isect!(st, ok)
        if ok
            push!(child.items, parent.items[j])
            push!(child.offs, pos)
            push!(child.lens, Int32(c))
            pos += c                                  # chỉ giữ chỗ khi tidset con đủ ngưỡng
        end                                           # trượt ngưỡng: lần giao sau ghi đè lên đúng chỗ đó
    end
    return child
end

"""Vùng nhớ dùng lại: levels[d] chứa lớp ở độ sâu d (d = 1 là lớp gốc)."""
struct VecWorkspace
    levels::Vector{VecLevel}
end

# Duyệt đệ quy: cùng khung như _mine_alloc!, nhưng lớp con được dựng vào vùng nhớ ws.levels[d + 1].
function _mine_vec!(sink, prefix::Vector{Int32}, ws::VecWorkspace, d::Int, minsup::Int,
                    isect::Val, st, maxlen::Int)
    lvl = ws.levels[d]                       # lớp đang duyệt nằm trong vùng nhớ của độ sâu d
    k = length(lvl.items)
    @inbounds for i in 1:k
        push!(prefix, lvl.items[i])
        depth = length(prefix)
        _st_itemset!(st, depth)
        sink(prefix, Int(lvl.lens[i]))       # support = độ dài tidset
        if depth < maxlen && i < k
            d + 1 > length(ws.levels) && push!(ws.levels, VecLevel())   # lần đầu xuống độ sâu này: tạo vùng nhớ
            child = ws.levels[d+1]           # vùng nhớ của độ sâu kế tiếp (ghi đè lớp con trước đó)
            t0 = d == 1 ? _now(st) : UInt64(0)
            _child_vec!(child, lvl, i, minsup, isect, st)
            d == 1 && _st_level2_time!(st, _now(st) - t0)   # lớp con của lớp gốc = tập 2 item
            if !isempty(child.items)
                _st_class!(st)
                nb = _live_bytes(child)
                _st_alloc!(st, nb)
                _mine_vec!(sink, prefix, ws, d + 1, minsup, isect, st, maxlen)   # đệ quy xuống lớp con
                _st_free!(st, nb)
            end
        end
        pop!(prefix)
    end
    return nothing
end

# Điểm vào của v2, v3: chuẩn bị lớp gốc trong vùng nhớ của độ sâu 1 rồi duyệt.
function _eclat_vec!(sink, db::TransactionDB, minsup::Int, cfg::EclatConfig, st, maxlen::Int)
    supp = item_supports(db)
    freq = frequent_items(supp, minsup, cfg.order)
    isempty(freq) && return nothing
    root = _root_vec(db, freq, supp)
    ws = VecWorkspace([root])                # độ sâu 1 = lớp gốc; các độ sâu sau được tạo khi cần
    nb = _live_bytes(root)
    _st_alloc!(st, nb)
    _mine_vec!(sink, Int32[], ws, 1, minsup, Val(cfg.isect), st, maxlen)
    _st_free!(st, nb)
    return nothing
end

# ---------------------------------------------------------------------------
# Giao diện công khai
# ---------------------------------------------------------------------------

# Bắt sớm cấu hình sai hoặc chưa được cài đặt (ở bước này: bitset và mảng tam giác chưa có)
# với thông báo rõ ràng, thay vì để lỗi lạ xảy ra sâu bên trong thuật toán.
"""Kiểm tra cấu hình có được cài đặt ở phiên bản code hiện tại không."""
function check_config(cfg::EclatConfig)
    cfg.tidset == :vector || throw(ArgumentError("tidset = $(cfg.tidset) chưa được cài đặt"))
    cfg.order in (:lexical, :support_asc) || throw(ArgumentError("order không hợp lệ: $(cfg.order)"))
    cfg.isect in (:merge, :adaptive) || throw(ArgumentError("isect không hợp lệ: $(cfg.isect)"))
    cfg.level2 == :intersect || throw(ArgumentError("level2 = $(cfg.level2) chưa được cài đặt"))
    return nothing
end

"""
    eclat!(sink, db, minsup, cfg = DEFAULT_CONFIG; stats = nothing, maxlen = typemax(Int))

Khai thác **mọi** tập phổ biến của `db` có support ≥ `minsup` (số đếm, xem `minsup_count`).

Mỗi tập phổ biến (không rỗng) được báo **đúng một lần** qua `sink(items, support)`:
- `items` là mã nội bộ của `db`, không bảo đảm thứ tự;
- `items` là **buffer được dùng lại**: `sink` phải `copy` nếu muốn giữ;
- thứ tự gọi là xác định (cùng input và cấu hình thì cùng thứ tự).

`stats::EclatStats` (tùy chọn) nhận các bộ đếm; `maxlen` giới hạn kích thước tập.
"""
function eclat!(sink, db::TransactionDB, minsup::Integer, cfg::EclatConfig = DEFAULT_CONFIG;
                stats::Union{Nothing,EclatStats} = nothing, maxlen::Integer = typemax(Int))
    minsup >= 1 || throw(ArgumentError("minsup (số đếm) phải ≥ 1"))   # minsup = 0 sẽ sinh mọi tập con: vô nghĩa
    check_config(cfg)
    # Chọn động cơ theo cấu hình: v2, v3 dùng lại buffer, v0–v1 cấp phát.
    if cfg.reuse
        _eclat_vec!(sink, db, Int(minsup), cfg, stats, Int(maxlen))
    else
        _eclat_alloc!(sink, db, Int(minsup), cfg, stats, Int(maxlen))
    end
    return nothing
end

"""
    eclat(db, minsup, cfg = DEFAULT_CONFIG; maxlen) -> Dict{Vector{Int32},Int}

Tiện ích cho kiểm thử: gom mọi tập phổ biến vào `Dict` (khóa là mã nội bộ đã sắp tăng dần).
"""
function eclat(db::TransactionDB, minsup::Integer, cfg::EclatConfig = DEFAULT_CONFIG;
               maxlen::Integer = typemax(Int))
    res = Dict{Vector{Int32},Int}()
    # sink ở đây: sort(items) tạo bản sao đã sắp (buffer items bị dùng lại nên phải sao chép), lưu kèm support.
    eclat!((items, s) -> (res[sort(items)] = s), db, minsup, cfg; maxlen = maxlen)
    return res
end
