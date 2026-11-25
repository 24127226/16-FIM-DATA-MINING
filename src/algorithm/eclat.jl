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

"""Tên phiên bản dùng khi không chỉ định cấu hình: bản lai v6 (tidset gọn nhất; E8 cho thấy không bản nào nhanh nhất trên mọi dữ liệu)."""
const DEFAULT_VARIANT = "v6"
"""Cấu hình của phiên bản mặc định (`VARIANTS[DEFAULT_VARIANT]`); là tham số mặc định của `eclat!`, `eclat`."""
const DEFAULT_CONFIG = VARIANTS[DEFAULT_VARIANT]

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

# Đếm một lần bản lai (v6) chuyển lớp từ bitset sang vector.
@inline _st_switch!(::Nothing) = nothing
@inline _st_switch!(st::EclatStats) = (st.n_switch += 1; nothing)

# Đếm số cặp mức 2 bị loại nhờ mảng tam giác (v5, v6), tức số phép giao tiết kiệm được.
@inline _st_skip!(::Nothing, n) = nothing
@inline _st_skip!(st::EclatStats, n) = (st.n_skipped_pairs += n; nothing)

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
# Động cơ dùng lại buffer (v2–v6): cấu trúc dữ liệu
# ---------------------------------------------------------------------------
# Ý tưởng v2: duyệt theo chiều sâu nên ở MỖI độ sâu d, tại một thời điểm chỉ có MỘT lớp đang sống
# (lớp con của atom đang xét). Khi chuyển sang atom kế tiếp, lớp con cũ không còn cần nữa.
# Vậy mỗi độ sâu chỉ cần một vùng nhớ, các lớp con lần lượt ghi đè lên nhau. Vùng nhớ chỉ được
# nới rộng vài lần lúc đầu; sau đó vòng lặp nóng không xin bộ nhớ mới, GC không phải chạy.

"""
Một lớp dạng **vector** trong vùng nhớ dùng lại của một độ sâu. Tidset của atom `k` là đoạn
`buf[offs[k] : offs[k]+lens[k]-1]`; `lens[k]` chính là support.
"""
mutable struct VecLevel
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
mutable struct BitLevel
    items::Vector{Int32}     # items[k]: item cuối của atom k
    sups::Vector{Int32}      # sups[k]: support của atom k (đếm sẵn, không phải đếm lại bit)
    pool::Vector{BitVector}  # các bitset đã cấp; giữ lại giữa các lần dùng để khỏi cấp lại
end
BitLevel() = BitLevel(Int32[], Int32[], BitVector[])

# Xóa nội dung một lớp để chuẩn bị ghi lớp con mới. empty! giữ nguyên vùng nhớ đã cấp,
# và buf / pool KHÔNG bị xóa: chúng chính là phần được dùng lại.
_reset!(l::VecLevel) = (empty!(l.items); empty!(l.offs); empty!(l.lens); l)
_reset!(l::BitLevel) = (empty!(l.items); empty!(l.sups); l)

# Số byte tidset thật sự đang dùng của một lớp (cho E10):
#   dạng vector: 4 byte mỗi tid; dạng bitset: mỗi atom một BitVector N bit = cld(N, 64) word × 8 byte.
_live_bytes(l::VecLevel) = 4 * Int(sum(l.lens; init = Int32(0)))
_live_bytes(l::BitLevel, N::Int) = 8 * cld(N, 64) * length(l.items)

"""Vùng nhớ dùng lại: vec[d], bit[d] chứa lớp ở độ sâu d (d = 1 là lớp gốc)."""
struct Workspace
    vec::Vector{VecLevel}   # vùng nhớ dạng vector của từng độ sâu
    bit::Vector{BitLevel}   # vùng nhớ dạng bitset của từng độ sâu
    N::Int                  # số giao dịch (độ dài mỗi bitset)
    switch_at::Float64      # bản lai: chuyển bitset → vector khi chặn trên support < switch_at; < 0: không chuyển
    cand::Vector{Int}       # danh sách atom đứng sau đủ ngưỡng (chỉ dùng ở lớp gốc với mảng tam giác)
end

# Lấy vùng nhớ dạng vector của độ sâu d; lần đầu xuống tới độ sâu d thì tạo thêm.
function _vec_level!(ws::Workspace, d::Int)
    while length(ws.vec) < d
        push!(ws.vec, VecLevel())
    end
    return ws.vec[d]
end

# Như trên, cho dạng bitset.
function _bit_level!(ws::Workspace, d::Int)
    while length(ws.bit) < d
        push!(ws.bit, BitLevel())
    end
    return ws.bit[d]
end

"""Bitset thứ `k` của lớp (cấp phát thêm nếu vùng nhớ chưa đủ chỗ)."""
function _slot!(l::BitLevel, k::Int, N::Int)
    while length(l.pool) < k
        push!(l.pool, falses(N))     # chỉ cấp khi lớp này lần đầu cần nhiều bitset như vậy
    end
    return @inbounds l.pool[k]
end

# ---------------------------------------------------------------------------
# Dựng lớp gốc
# ---------------------------------------------------------------------------

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

"""Lớp gốc dạng bitset: bật bit `tid` trong bitset của mọi item phổ biến có trong giao dịch `tid`."""
function _root_bit(db::TransactionDB, freq::Vector{Int32}, supp::Vector{Int})
    N = n_transactions(db)
    rank = item_ranks(n_items(db), freq)
    pool = [falses(N) for _ in freq]         # mỗi item phổ biến một BitVector N bit, ban đầu toàn 0
    @inbounds for (tid, t) in enumerate(db.transactions)
        w = ((tid - 1) >> 6) + 1             # tid nằm ở word thứ w: ⌊(tid - 1) / 64⌋ + 1
        bit = UInt64(1) << ((tid - 1) & 63)  # mặt nạ có đúng một bit 1 ở vị trí (tid - 1) mod 64
        for x in t
            r = rank[x]
            r == 0 && continue
            pool[r].chunks[w] |= bit         # bật bit của giao dịch tid trong bitset của item x
        end
    end
    return BitLevel(copy(freq), Int32[supp[x] for x in freq], pool)
end

# ---------------------------------------------------------------------------
# Dựng lớp con của atom i với các atom j ∈ js đứng sau nó
# (js là (i+1):k, hoặc danh sách cặp đã biết là phổ biến nhờ mảng tam giác)
# ---------------------------------------------------------------------------

# Chọn phép giao theo cấu hình: v2 dùng trộn hai con trỏ, v3 trở đi dùng giao thích ứng.
@inline _isect_into!(dst, dpos, a, ao, la, b, bo, lb, minsup, ::Val{:merge}) =
    isect_merge!(dst, dpos, a, ao, la, b, bo, lb)
@inline _isect_into!(dst, dpos, a, ao, la, b, bo, lb, minsup, ::Val{:adaptive}) =
    isect_adaptive!(dst, dpos, a, ao, la, b, bo, lb, minsup)

"""vector → vector."""
function _vec_from_vec!(child::VecLevel, parent::VecLevel, i::Int, js, minsup::Int, isect::Val, st)
    _reset!(child)                                    # ghi đè lớp con cũ ở độ sâu này
    @inbounds la = Int(parent.lens[i])                # độ dài tidset của atom i
    @inbounds ao = parent.offs[i]                     # vị trí của nó trong buffer của lớp cha
    # Nới buffer một lần trước vòng lặp, đủ cho trường hợp xấu nhất (mọi phép giao đều đủ ngưỡng):
    # mỗi tidset con dài tối đa min(la, lens[j]).
    need = 0                                          # chặn trên tổng độ dài các tidset con
    @inbounds for j in js
        need += min(la, Int(parent.lens[j]))
    end
    length(child.buf) < need && resize!(child.buf, need)   # chỉ nới khi thiếu; đủ rồi thì dùng lại nguyên
    pos = 1                                           # ô trống đầu tiên trong buffer của lớp con
    pbuf = parent.buf                                 # gán ra biến cục bộ cho trình biên dịch tối ưu dễ hơn
    cbuf = child.buf
    @inbounds for j in js
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

"""bitset → bitset."""
function _bit_from_bit!(child::BitLevel, parent::BitLevel, i::Int, js, minsup::Int, st, N::Int)
    _reset!(child)
    @inbounds a = parent.pool[i]                          # bitset của atom i
    @inbounds for j in js
        dst = _slot!(child, length(child.items) + 1, N)   # ô bị trượt ngưỡng sẽ được ghi đè ở j sau
        c = and_count!(dst, a, parent.pool[j])            # dst = a AND bitset của j; c = support
        ok = c >= minsup
        _st_isect!(st, ok)
        if ok
            push!(child.items, parent.items[j])           # ô dst được giữ lại cho atom mới này
            push!(child.sups, Int32(c))
        end
    end
    return child
end

"""bitset → vector (bản lai chuyển biểu diễn khi lớp con đủ thưa)."""
function _vec_from_bit!(child::VecLevel, parent::BitLevel, i::Int, js, minsup::Int, st)
    _reset!(child)
    @inbounds si = Int(parent.sups[i])                # support của atom i
    need = 0                                          # chặn trên tổng độ dài tidset con, như _vec_from_vec!
    @inbounds for j in js
        need += min(si, Int(parent.sups[j]))
    end
    length(child.buf) < need && resize!(child.buf, need)
    pos = 1
    cbuf = child.buf
    @inbounds a = parent.pool[i]
    @inbounds for j in js
        c = and_extract!(cbuf, pos, a, parent.pool[j])    # AND hai bitset, ghi kết quả thành danh sách tid
        ok = c >= minsup
        _st_isect!(st, ok)
        if ok
            push!(child.items, parent.items[j])
            push!(child.offs, pos)
            push!(child.lens, Int32(c))
            pos += c
        end
    end
    return child
end

# Lớp con chỉ có một atom: atom đó được xuất (tập của nó là phổ biến), nhưng không còn atom nào
# để ghép cặp, nên không bao giờ cần tidset của nó. Chỉ cần ghi item và support (đã biết từ mảng tam giác).
# offs = 1 chỉ để các mảng đủ độ dài; tidset không được đọc.
"""Lớp con chỉ có một atom: không bao giờ cần tidset của nó (không còn cặp nào để giao)."""
_single!(child::VecLevel, item, sup) = (_reset!(child); push!(child.items, item); push!(child.offs, 1);
                                       push!(child.lens, Int32(sup)); child)
_single!(child::BitLevel, item, sup) = (_reset!(child); push!(child.items, item); push!(child.sups, Int32(sup)); child)

# Vì sao bản lai v6 chuyển sang vector: một bitset luôn tốn N bit, còn một tidset vector tốn
# 32 bit cho mỗi tid. Hai cách tốn bằng nhau khi support = N/32. Dưới mức đó, vector vừa nhỏ hơn
# vừa giao nhanh hơn (chi phí tỉ lệ với support, không phải N). Vậy hybrid_ratio = 1/32.
# Chặn trên support của mọi tidset con: |t_i ∩ t_j| ≤ min(sup_i, sup_j) ≤ min(sup_i, max_j sup_j).
# Nếu chặn trên này đã < switch_at thì MỌI tidset con đều thưa → lưu cả lớp con dạng vector.
"""Bản lai: lớp con của atom i có nên lưu dạng vector không (chặn trên support < ngưỡng)?"""
@inline function _should_switch(ws::Workspace, lvl::BitLevel, i::Int, js)
    ws.switch_at < 0 && return false                  # v4, v5: không bao giờ chuyển
    mx = 0                                            # support lớn nhất trong các atom j
    @inbounds for j in js
        mx = max(mx, Int(lvl.sups[j]))
    end
    @inbounds return min(Int(lvl.sups[i]), mx) < ws.switch_at
end

# ---------------------------------------------------------------------------
# Duyệt đệ quy (độ sâu d ≥ 2) — một phương thức cho mỗi dạng lớp
# ---------------------------------------------------------------------------
# Hai hàm _mine_vec! và _mine_bit! có cùng khung như _mine_alloc!: xuất atom i, dựng lớp con
# vào vùng nhớ của độ sâu d + 1, đi xuống. Tách hai hàm theo dạng lớp để trong mỗi hàm
# mọi biến đều có kiểu cố định (ổn định kiểu), Julia sinh được mã máy nhanh.

function _mine_vec!(sink, prefix::Vector{Int32}, ws::Workspace, d::Int, minsup::Int, isect::Val, st, maxlen::Int)
    lvl = ws.vec[d]                          # lớp đang duyệt nằm trong vùng nhớ vector của độ sâu d
    k = length(lvl.items)
    @inbounds for i in 1:k
        push!(prefix, lvl.items[i])
        depth = length(prefix)
        _st_itemset!(st, depth)
        sink(prefix, Int(lvl.lens[i]))       # support = độ dài tidset
        if depth < maxlen && i < k
            child = _vec_level!(ws, d + 1)   # vùng nhớ của độ sâu kế tiếp (ghi đè lớp con trước đó)
            _vec_from_vec!(child, lvl, i, (i + 1):k, minsup, isect, st)
            _descend_vec!(sink, prefix, ws, d + 1, child, minsup, isect, st, maxlen)
        end
        pop!(prefix)
    end
    return nothing
end

function _mine_bit!(sink, prefix::Vector{Int32}, ws::Workspace, d::Int, minsup::Int, isect::Val, st, maxlen::Int)
    lvl = ws.bit[d]                          # lớp đang duyệt nằm trong vùng nhớ bitset của độ sâu d
    k = length(lvl.items)
    @inbounds for i in 1:k
        push!(prefix, lvl.items[i])
        depth = length(prefix)
        _st_itemset!(st, depth)
        sink(prefix, Int(lvl.sups[i]))       # support đã lưu sẵn trong sups
        if depth < maxlen && i < k
            _expand_bit!(sink, prefix, ws, d, lvl, i, (i + 1):k, minsup, isect, st, maxlen)
        end
        pop!(prefix)
    end
    return nothing
end

"""Dựng lớp con của một atom dạng bitset (giữ bitset, hoặc chuyển sang vector) rồi đi xuống."""
function _expand_bit!(sink, prefix, ws::Workspace, d::Int, lvl::BitLevel, i::Int, js, minsup::Int,
                      isect::Val, st, maxlen::Int)
    if _should_switch(ws, lvl, i, js)
        # Lớp con đủ thưa (chỉ xảy ra ở v6): dựng nó dạng vector; từ đây trở xuống nhánh này đi theo _mine_vec!.
        child = _vec_level!(ws, d + 1)
        _vec_from_bit!(child, lvl, i, js, minsup, st)
        isempty(child.items) || _st_switch!(st)
        _descend_vec!(sink, prefix, ws, d + 1, child, minsup, isect, st, maxlen)
    else
        # Lớp con còn dày: giữ dạng bitset.
        child = _bit_level!(ws, d + 1)
        _bit_from_bit!(child, lvl, i, js, minsup, st, ws.N)
        _descend_bit!(sink, prefix, ws, d + 1, child, minsup, isect, st, maxlen)
    end
    return nothing
end

# Đi xuống một lớp con vừa dựng (nếu nó khác rỗng), kèm cập nhật bộ đếm bộ nhớ trước và sau.
@inline function _descend_vec!(sink, prefix, ws, d, child::VecLevel, minsup, isect, st, maxlen)
    isempty(child.items) && return nothing
    _st_class!(st)
    nb = _live_bytes(child)
    _st_alloc!(st, nb)
    _mine_vec!(sink, prefix, ws, d, minsup, isect, st, maxlen)
    _st_free!(st, nb)
    return nothing
end

@inline function _descend_bit!(sink, prefix, ws, d, child::BitLevel, minsup, isect, st, maxlen)
    isempty(child.items) && return nothing
    _st_class!(st)
    nb = _live_bytes(child, ws.N)
    _st_alloc!(st, nb)
    _mine_bit!(sink, prefix, ws, d, minsup, isect, st, maxlen)
    _st_free!(st, nb)
    return nothing
end

# ---------------------------------------------------------------------------
# Lớp gốc (độ sâu 1): nơi duy nhất dùng mảng tam giác (v5, v6)
# ---------------------------------------------------------------------------
# Lớp con của lớp gốc chính là các tập 2 item. Với mảng tam giác (tri), ta đã biết support của mọi
# cặp, nên với atom i chỉ cần giao với những j mà cặp (i, j) đủ ngưỡng; các cặp khác bỏ qua luôn.

"""Các atom j > i mà cặp (i, j) đủ ngưỡng theo mảng tam giác; ghi vào `cand`."""
function _candidates!(cand::Vector{Int}, tri::Vector{UInt32}, i::Int, k::Int, minsup::Int, st)
    empty!(cand)                             # dùng lại mảng cand, không cấp phát
    base = (i - 1) * (2k - i) ÷ 2 - i        # base + j = tri_index(i, j, k): vị trí ô (i, j) trong mảng tam giác
    @inbounds for j in (i + 1):k
        tri[base+j] >= minsup && push!(cand, j)      # cặp (i, j) đủ ngưỡng thì mới cần giao
    end
    _st_skip!(st, (k - i) - length(cand))    # số cặp bị loại = số phép giao tiết kiệm được
    return cand
end

"""Các atom j > i cần xét ở lớp gốc: tất cả, hoặc chỉ các cặp đủ ngưỡng theo mảng tam giác."""
function _root_js!(ws::Workspace, tri, i::Int, k::Int, minsup::Int, st)
    if tri === nothing                       # v2–v4 (hoặc mảng tam giác quá lớn): xét mọi j đứng sau
        empty!(ws.cand)
        append!(ws.cand, (i + 1):k)
        return ws.cand
    end
    return _candidates!(ws.cand, tri, i, k, minsup, st)
end

# Lớp gốc dạng vector (v2, v3; hoặc v6 trên dữ liệu thưa).
function _mine_root!(sink, prefix::Vector{Int32}, ws::Workspace, root::VecLevel, tri, minsup::Int,
                     isect::Val, st, maxlen::Int)
    k = length(root.items)
    @inbounds for i in 1:k
        push!(prefix, root.items[i])
        _st_itemset!(st, 1)
        sink(prefix, Int(root.lens[i]))      # xuất tập 1 item
        if maxlen > 1 && i < k
            t0 = _now(st)                    # bấm giờ phần tính tập 2 item
            js = _root_js!(ws, tri, i, k, minsup, st)    # các atom j cần giao với i
            child = _vec_level!(ws, 2)
            if tri !== nothing && length(js) == 1
                # Chỉ một cặp đủ ngưỡng: lớp con có một atom, không cần giao (xem _single!).
                _single!(child, root.items[js[1]], tri[tri_index(i, js[1], k)])
            else
                _vec_from_vec!(child, root, i, js, minsup, isect, st)
            end
            _st_level2_time!(st, _now(st) - t0)
            _descend_vec!(sink, prefix, ws, 2, child, minsup, isect, st, maxlen)
        end
        pop!(prefix)
    end
    return nothing
end

# Lớp gốc dạng bitset (v4, v5; hoặc v6 trên dữ liệu dày). Có thêm nhánh bản lai chuyển sang vector.
function _mine_root!(sink, prefix::Vector{Int32}, ws::Workspace, root::BitLevel, tri, minsup::Int,
                     isect::Val, st, maxlen::Int)
    k = length(root.items)
    @inbounds for i in 1:k
        push!(prefix, root.items[i])
        _st_itemset!(st, 1)
        sink(prefix, Int(root.sups[i]))
        if maxlen > 1 && i < k
            t0 = _now(st)
            js = _root_js!(ws, tri, i, k, minsup, st)
            if tri !== nothing && length(js) == 1
                # Một cặp duy nhất: như nhánh tương ứng ở bản vector.
                child = _bit_level!(ws, 2)
                _single!(child, root.items[js[1]], tri[tri_index(i, js[1], k)])
                _st_level2_time!(st, _now(st) - t0)
                _descend_bit!(sink, prefix, ws, 2, child, minsup, isect, st, maxlen)
            elseif _should_switch(ws, root, i, js)
                # Bản lai: lớp con đủ thưa → dựng dạng vector.
                child = _vec_level!(ws, 2)
                _vec_from_bit!(child, root, i, js, minsup, st)
                isempty(child.items) || _st_switch!(st)
                _st_level2_time!(st, _now(st) - t0)
                _descend_vec!(sink, prefix, ws, 2, child, minsup, isect, st, maxlen)
            else
                # Còn dày → giữ dạng bitset.
                child = _bit_level!(ws, 2)
                _bit_from_bit!(child, root, i, js, minsup, st, ws.N)
                _st_level2_time!(st, _now(st) - t0)
                _descend_bit!(sink, prefix, ws, 2, child, minsup, isect, st, maxlen)
            end
        end
        pop!(prefix)
    end
    return nothing
end

# Điểm vào của v2–v6: chuẩn bị, chọn dạng lớp gốc theo cấu hình, rồi duyệt.
function _eclat_ws!(sink, db::TransactionDB, minsup::Int, cfg::EclatConfig, st, maxlen::Int)
    supp = item_supports(db)
    freq = frequent_items(supp, minsup, cfg.order)
    isempty(freq) && return nothing
    N = n_transactions(db)
    # Mật độ = support trung bình của item phổ biến chia cho N (0..1). Dữ liệu dày như Chess có mật độ cao.
    density = sum(x -> supp[x], freq) / (length(freq) * N)       # mật độ trung bình của lớp gốc
    # Dùng bitset ở lớp gốc nếu cấu hình là :bitset (v4, v5), hoặc :hybrid (v6) và dữ liệu đủ dày.
    use_bits = cfg.tidset == :bitset || (cfg.tidset == :hybrid && density >= cfg.hybrid_ratio)
    # Ngưỡng support để bản lai chuyển sang vector (N/32 giao dịch); -1 nghĩa là không bao giờ chuyển.
    switch_at = cfg.tidset == :hybrid ? cfg.hybrid_ratio * N : -1.0
    ws = Workspace(VecLevel[], BitLevel[], N, switch_at, Int[])  # vùng nhớ dùng lại, ban đầu rỗng
    tri = nothing                                    # nothing = không dùng mảng tam giác
    if cfg.level2 == :triangular && maxlen > 1 && length(freq) > 1
        t0 = _now(st)
        tri = pair_counts(db, item_ranks(n_items(db), freq), length(freq))   # đếm mọi cặp (level2.jl)
        _st_level2_time!(st, _now(st) - t0)
    end
    if use_bits
        root = _root_bit(db, freq, supp)
        push!(ws.bit, root)                          # lớp gốc là vùng nhớ bitset của độ sâu 1
        nb = _live_bytes(root, N)
    else
        root = _root_vec(db, freq, supp)
        push!(ws.vec, root)                          # lớp gốc là vùng nhớ vector của độ sâu 1
        nb = _live_bytes(root)
    end
    _st_alloc!(st, nb)
    # "Rào chắn hàm" (function barrier): kiểu của root (VecLevel hay BitLevel) chỉ biết lúc chạy.
    # Truyền root vào một hàm khác thì Julia biên dịch riêng _mine_root! cho từng kiểu, và bên trong
    # hàm đó mọi thứ đều ổn định kiểu, nên chạy nhanh.
    _mine_root!(sink, Int32[], ws, root, tri, minsup, Val(cfg.isect), st, maxlen)   # rào chắn hàm
    _st_free!(st, nb)
    return nothing
end

# ---------------------------------------------------------------------------
# Giao diện công khai
# ---------------------------------------------------------------------------

# Bắt sớm cấu hình sai (gõ nhầm tên, hoặc tổ hợp chưa được cài đặt) với thông báo rõ ràng,
# thay vì để lỗi lạ xảy ra sâu bên trong thuật toán.
"""Kiểm tra cấu hình hợp lệ và đã được cài đặt."""
function check_config(cfg::EclatConfig)
    cfg.tidset in (:vector, :bitset, :hybrid) || throw(ArgumentError("tidset không hợp lệ: $(cfg.tidset)"))
    cfg.order in (:lexical, :support_asc) || throw(ArgumentError("order không hợp lệ: $(cfg.order)"))
    cfg.isect in (:merge, :adaptive) || throw(ArgumentError("isect không hợp lệ: $(cfg.isect)"))
    cfg.level2 in (:intersect, :triangular) || throw(ArgumentError("level2 không hợp lệ: $(cfg.level2)"))
    # Động cơ cấp phát (reuse = false) chỉ có tidset vector và giao từng cặp.
    if !cfg.reuse && (cfg.tidset != :vector || cfg.level2 != :intersect)
        throw(ArgumentError("tidset dạng bitset/lai và mảng tam giác chỉ được cài với reuse = true"))
    end
    cfg.hybrid_ratio > 0 || throw(ArgumentError("hybrid_ratio phải > 0"))
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
    # Chọn động cơ theo cấu hình: v2–v6 dùng lại buffer, v0–v1 cấp phát.
    if cfg.reuse
        _eclat_ws!(sink, db, Int(minsup), cfg, stats, Int(maxlen))
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
