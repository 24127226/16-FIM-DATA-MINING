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

"""Tên phiên bản dùng khi không chỉ định cấu hình: bản lai v6 (tidset gọn nhất; E8 cho thấy không bản nào nhanh nhất trên mọi dữ liệu)."""
const DEFAULT_VARIANT = "v6"
"""Cấu hình của phiên bản mặc định (`VARIANTS[DEFAULT_VARIANT]`); là tham số mặc định của `eclat!`, `eclat`."""
const DEFAULT_CONFIG = VARIANTS[DEFAULT_VARIANT]

# ---------------------------------------------------------------------------
# Bộ đếm: khi stats === nothing, các lời gọi dưới đây không làm gì và bị trình biên dịch
# loại bỏ (multiple dispatch theo kiểu Nothing / EclatStats), nên không tốn chi phí khi đo thời gian.
# ---------------------------------------------------------------------------

@inline _st_itemset!(::Nothing, depth) = nothing
@inline function _st_itemset!(st::EclatStats, depth)
    st.n_itemsets += 1
    depth > st.max_depth && (st.max_depth = depth)
    return nothing
end

@inline _st_isect!(::Nothing, ok::Bool) = nothing
@inline function _st_isect!(st::EclatStats, ok::Bool)
    st.n_intersections += 1
    ok || (st.n_failed += 1)
    return nothing
end

@inline _st_alloc!(::Nothing, nbytes) = nothing
@inline function _st_alloc!(st::EclatStats, nbytes)
    st.bytes_current += nbytes
    st.bytes_current > st.bytes_peak && (st.bytes_peak = st.bytes_current)
    return nothing
end

@inline _st_free!(::Nothing, nbytes) = nothing
@inline _st_free!(st::EclatStats, nbytes) = (st.bytes_current -= nbytes; nothing)

@inline _st_class!(::Nothing) = nothing
@inline _st_class!(st::EclatStats) = (st.n_classes += 1; nothing)

@inline _st_switch!(::Nothing) = nothing
@inline _st_switch!(st::EclatStats) = (st.n_switch += 1; nothing)

@inline _st_skip!(::Nothing, n) = nothing
@inline _st_skip!(st::EclatStats, n) = (st.n_skipped_pairs += n; nothing)

@inline _st_level2_time!(::Nothing, ns) = nothing
@inline _st_level2_time!(st::EclatStats, ns) = (st.time_level2_ns += ns; nothing)

@inline _now(::Nothing) = UInt64(0)
@inline _now(::EclatStats) = time_ns()

# ---------------------------------------------------------------------------
# Chuẩn bị: đếm support, chọn item phổ biến, sắp thứ tự, dựng tidset dạng dọc
# ---------------------------------------------------------------------------

"""Support của từng item (mã nội bộ 1..m): một lần quét dữ liệu ngang."""
function item_supports(db::TransactionDB)
    supp = zeros(Int, n_items(db))
    @inbounds for t in db.transactions, x in t
        supp[x] += 1
    end
    return supp
end

"""Các item phổ biến theo thứ tự xử lý của cấu hình (`:lexical` hoặc `:support_asc`)."""
function frequent_items(supp::Vector{Int}, minsup::Integer, order::Symbol)
    freq = Int32[x for x in eachindex(supp) if supp[x] >= minsup]
    if order == :support_asc
        sort!(freq; by = x -> (supp[x], x))    # hòa support thì theo mã, để thứ tự luôn xác định
    elseif order != :lexical
        throw(ArgumentError("order không hợp lệ: $order"))
    end
    return freq
end

"""rank[x] = vị trí của item x trong `freq` (0 nếu không phổ biến)."""
function item_ranks(m::Int, freq::Vector{Int32})
    rank = zeros(Int32, m)
    for (r, x) in enumerate(freq)
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
    rank = item_ranks(n_items(db), freq)
    tids = [Vector{Int32}(undef, supp[x]) for x in freq]
    fill_pos = zeros(Int, length(freq))
    @inbounds for (tid, t) in enumerate(db.transactions)
        for x in t
            r = rank[x]
            r == 0 && continue
            p = fill_pos[r] += 1
            tids[r][p] = Int32(tid)
        end
    end
    return tids
end

# ---------------------------------------------------------------------------
# Động cơ cấp phát (v0, v1): mỗi atom giữ tidset riêng, mỗi phép giao tạo mảng mới
# ---------------------------------------------------------------------------

"""Lớp tương đương: các cặp (item cuối, tidset). Tiền tố nằm ở ngăn xếp `prefix` dùng chung."""
struct AllocClass
    items::Vector{Int32}
    tidsets::Vector{Vector{Int32}}
end

_bytes(tids::Vector{Vector{Int32}}) = 4 * sum(length, tids; init = 0)

"""Phép giao của động cơ cấp phát, chọn theo cấu hình (Val để chuyên biệt hóa lúc biên dịch)."""
_isect_alloc(a, b, ::Val{:merge}, minsup) = intersect_merge(a, b)
function _isect_alloc(a, b, ::Val{:adaptive}, minsup)
    out = Vector{Int32}(undef, min(length(a), length(b)))
    return resize!(out, isect_adaptive!(out, 1, a, 1, length(a), b, 1, length(b), minsup))
end

"""Lớp con của atom thứ `i`: giao tidset của nó với tidset của mọi atom đứng sau."""
function _child_alloc(cls::AllocClass, i::Int, minsup::Int, isect::Val, st)
    items = Int32[]
    tids = Vector{Vector{Int32}}()
    tx = cls.tidsets[i]
    @inbounds for j in (i + 1):length(cls.items)
        t = _isect_alloc(tx, cls.tidsets[j], isect, minsup)
        ok = length(t) >= minsup
        _st_isect!(st, ok)
        if ok
            push!(items, cls.items[j])
            push!(tids, t)
        end
    end
    return AllocClass(items, tids)
end

function _mine_alloc!(sink, prefix::Vector{Int32}, cls::AllocClass, minsup::Int, isect::Val, st, maxlen::Int)
    k = length(cls.items)
    @inbounds for i in 1:k
        push!(prefix, cls.items[i])
        depth = length(prefix)
        _st_itemset!(st, depth)
        sink(prefix, length(cls.tidsets[i]))                 # xuất tập prefix với support |t(prefix)|
        if depth < maxlen && i < k
            t0 = depth == 1 ? _now(st) : UInt64(0)
            child = _child_alloc(cls, i, minsup, isect, st)
            depth == 1 && _st_level2_time!(st, _now(st) - t0)  # lớp con của lớp gốc = tập 2 item
            if !isempty(child.items)
                _st_class!(st)
                nb = _bytes(child.tidsets)
                _st_alloc!(st, nb)
                _mine_alloc!(sink, prefix, child, minsup, isect, st, maxlen)
                _st_free!(st, nb)
            end
        end
        pop!(prefix)
    end
    return nothing
end

function _eclat_alloc!(sink, db::TransactionDB, minsup::Int, cfg::EclatConfig, st, maxlen::Int)
    supp = item_supports(db)
    freq = frequent_items(supp, minsup, cfg.order)
    isempty(freq) && return nothing
    root = AllocClass(freq, vertical_tidsets(db, freq, supp))
    nb = _bytes(root.tidsets)
    _st_alloc!(st, nb)
    _mine_alloc!(sink, Int32[], root, minsup, Val(cfg.isect), st, maxlen)
    _st_free!(st, nb)
    return nothing
end

# ---------------------------------------------------------------------------
# Động cơ dùng lại buffer (v2–v6): cấu trúc dữ liệu
# ---------------------------------------------------------------------------

"""
Một lớp dạng **vector** trong vùng nhớ dùng lại của một độ sâu. Tidset của atom `k` là đoạn
`buf[offs[k] : offs[k]+lens[k]-1]`; `lens[k]` chính là support.
"""
mutable struct VecLevel
    items::Vector{Int32}
    offs::Vector{Int}
    lens::Vector{Int32}
    buf::Vector{Int32}
end
VecLevel() = VecLevel(Int32[], Int[], Int32[], Int32[])

"""
Một lớp dạng **bitset** trong vùng nhớ dùng lại của một độ sâu. Tidset của atom `k` là
`pool[k]` (BitVector dài N); `sups[k]` là support. `pool` chỉ lớn thêm, không bao giờ thu nhỏ.
"""
mutable struct BitLevel
    items::Vector{Int32}
    sups::Vector{Int32}
    pool::Vector{BitVector}
end
BitLevel() = BitLevel(Int32[], Int32[], BitVector[])

_reset!(l::VecLevel) = (empty!(l.items); empty!(l.offs); empty!(l.lens); l)
_reset!(l::BitLevel) = (empty!(l.items); empty!(l.sups); l)

_live_bytes(l::VecLevel) = 4 * Int(sum(l.lens; init = Int32(0)))
_live_bytes(l::BitLevel, N::Int) = 8 * cld(N, 64) * length(l.items)

"""Vùng nhớ dùng lại: vec[d], bit[d] chứa lớp ở độ sâu d (d = 1 là lớp gốc)."""
struct Workspace
    vec::Vector{VecLevel}
    bit::Vector{BitLevel}
    N::Int
    switch_at::Float64      # bản lai: chuyển bitset → vector khi chặn trên support < switch_at; < 0: không chuyển
    cand::Vector{Int}       # danh sách atom đứng sau đủ ngưỡng (chỉ dùng ở lớp gốc với mảng tam giác)
end

function _vec_level!(ws::Workspace, d::Int)
    while length(ws.vec) < d
        push!(ws.vec, VecLevel())
    end
    return ws.vec[d]
end

function _bit_level!(ws::Workspace, d::Int)
    while length(ws.bit) < d
        push!(ws.bit, BitLevel())
    end
    return ws.bit[d]
end

"""Bitset thứ `k` của lớp (cấp phát thêm nếu vùng nhớ chưa đủ chỗ)."""
function _slot!(l::BitLevel, k::Int, N::Int)
    while length(l.pool) < k
        push!(l.pool, falses(N))
    end
    return @inbounds l.pool[k]
end

# ---------------------------------------------------------------------------
# Dựng lớp gốc
# ---------------------------------------------------------------------------

"""Lớp gốc dạng vector: tidset của mọi item phổ biến nằm liền nhau trong một buffer."""
function _root_vec(db::TransactionDB, freq::Vector{Int32}, supp::Vector{Int})
    k = length(freq)
    lens = Int32[supp[x] for x in freq]
    offs = Vector{Int}(undef, k)
    p = 1
    for r in 1:k
        offs[r] = p
        p += lens[r]
    end
    buf = Vector{Int32}(undef, p - 1)
    rank = item_ranks(n_items(db), freq)
    fill_pos = copy(offs)
    @inbounds for (tid, t) in enumerate(db.transactions)
        for x in t
            r = rank[x]
            r == 0 && continue
            buf[fill_pos[r]] = Int32(tid)
            fill_pos[r] += 1
        end
    end
    return VecLevel(copy(freq), offs, lens, buf)
end

"""Lớp gốc dạng bitset: bật bit `tid` trong bitset của mọi item phổ biến có trong giao dịch `tid`."""
function _root_bit(db::TransactionDB, freq::Vector{Int32}, supp::Vector{Int})
    N = n_transactions(db)
    rank = item_ranks(n_items(db), freq)
    pool = [falses(N) for _ in freq]
    @inbounds for (tid, t) in enumerate(db.transactions)
        w = ((tid - 1) >> 6) + 1
        bit = UInt64(1) << ((tid - 1) & 63)
        for x in t
            r = rank[x]
            r == 0 && continue
            pool[r].chunks[w] |= bit
        end
    end
    return BitLevel(copy(freq), Int32[supp[x] for x in freq], pool)
end

# ---------------------------------------------------------------------------
# Dựng lớp con của atom i với các atom j ∈ js đứng sau nó
# (js là (i+1):k, hoặc danh sách cặp đã biết là phổ biến nhờ mảng tam giác)
# ---------------------------------------------------------------------------

@inline _isect_into!(dst, dpos, a, ao, la, b, bo, lb, minsup, ::Val{:merge}) =
    isect_merge!(dst, dpos, a, ao, la, b, bo, lb)
@inline _isect_into!(dst, dpos, a, ao, la, b, bo, lb, minsup, ::Val{:adaptive}) =
    isect_adaptive!(dst, dpos, a, ao, la, b, bo, lb, minsup)

"""vector → vector."""
function _vec_from_vec!(child::VecLevel, parent::VecLevel, i::Int, js, minsup::Int, isect::Val, st)
    _reset!(child)
    @inbounds la = Int(parent.lens[i])
    @inbounds ao = parent.offs[i]
    need = 0                                          # chặn trên tổng độ dài các tidset con
    @inbounds for j in js
        need += min(la, Int(parent.lens[j]))
    end
    length(child.buf) < need && resize!(child.buf, need)
    pos = 1
    pbuf = parent.buf
    cbuf = child.buf
    @inbounds for j in js
        c = _isect_into!(cbuf, pos, pbuf, ao, la, pbuf, parent.offs[j], Int(parent.lens[j]), minsup, isect)
        ok = c >= minsup
        _st_isect!(st, ok)
        if ok
            push!(child.items, parent.items[j])
            push!(child.offs, pos)
            push!(child.lens, Int32(c))
            pos += c                                  # chỉ giữ chỗ khi tidset con đủ ngưỡng
        end
    end
    return child
end

"""bitset → bitset."""
function _bit_from_bit!(child::BitLevel, parent::BitLevel, i::Int, js, minsup::Int, st, N::Int)
    _reset!(child)
    @inbounds a = parent.pool[i]
    @inbounds for j in js
        dst = _slot!(child, length(child.items) + 1, N)   # ô bị trượt ngưỡng sẽ được ghi đè ở j sau
        c = and_count!(dst, a, parent.pool[j])
        ok = c >= minsup
        _st_isect!(st, ok)
        if ok
            push!(child.items, parent.items[j])
            push!(child.sups, Int32(c))
        end
    end
    return child
end

"""bitset → vector (bản lai chuyển biểu diễn khi lớp con đủ thưa)."""
function _vec_from_bit!(child::VecLevel, parent::BitLevel, i::Int, js, minsup::Int, st)
    _reset!(child)
    @inbounds si = Int(parent.sups[i])
    need = 0
    @inbounds for j in js
        need += min(si, Int(parent.sups[j]))
    end
    length(child.buf) < need && resize!(child.buf, need)
    pos = 1
    cbuf = child.buf
    @inbounds a = parent.pool[i]
    @inbounds for j in js
        c = and_extract!(cbuf, pos, a, parent.pool[j])
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

"""Lớp con chỉ có một atom: không bao giờ cần tidset của nó (không còn cặp nào để giao)."""
_single!(child::VecLevel, item, sup) = (_reset!(child); push!(child.items, item); push!(child.offs, 1);
                                       push!(child.lens, Int32(sup)); child)
_single!(child::BitLevel, item, sup) = (_reset!(child); push!(child.items, item); push!(child.sups, Int32(sup)); child)

"""Bản lai: lớp con của atom i có nên lưu dạng vector không (chặn trên support < ngưỡng)?"""
@inline function _should_switch(ws::Workspace, lvl::BitLevel, i::Int, js)
    ws.switch_at < 0 && return false
    mx = 0
    @inbounds for j in js
        mx = max(mx, Int(lvl.sups[j]))
    end
    @inbounds return min(Int(lvl.sups[i]), mx) < ws.switch_at
end

# ---------------------------------------------------------------------------
# Duyệt đệ quy (độ sâu d ≥ 2) — một phương thức cho mỗi dạng lớp
# ---------------------------------------------------------------------------

function _mine_vec!(sink, prefix::Vector{Int32}, ws::Workspace, d::Int, minsup::Int, isect::Val, st, maxlen::Int)
    lvl = ws.vec[d]
    k = length(lvl.items)
    @inbounds for i in 1:k
        push!(prefix, lvl.items[i])
        depth = length(prefix)
        _st_itemset!(st, depth)
        sink(prefix, Int(lvl.lens[i]))
        if depth < maxlen && i < k
            child = _vec_level!(ws, d + 1)
            _vec_from_vec!(child, lvl, i, (i + 1):k, minsup, isect, st)
            _descend_vec!(sink, prefix, ws, d + 1, child, minsup, isect, st, maxlen)
        end
        pop!(prefix)
    end
    return nothing
end

function _mine_bit!(sink, prefix::Vector{Int32}, ws::Workspace, d::Int, minsup::Int, isect::Val, st, maxlen::Int)
    lvl = ws.bit[d]
    k = length(lvl.items)
    @inbounds for i in 1:k
        push!(prefix, lvl.items[i])
        depth = length(prefix)
        _st_itemset!(st, depth)
        sink(prefix, Int(lvl.sups[i]))
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
        child = _vec_level!(ws, d + 1)
        _vec_from_bit!(child, lvl, i, js, minsup, st)
        isempty(child.items) || _st_switch!(st)
        _descend_vec!(sink, prefix, ws, d + 1, child, minsup, isect, st, maxlen)
    else
        child = _bit_level!(ws, d + 1)
        _bit_from_bit!(child, lvl, i, js, minsup, st, ws.N)
        _descend_bit!(sink, prefix, ws, d + 1, child, minsup, isect, st, maxlen)
    end
    return nothing
end

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

"""Các atom j > i mà cặp (i, j) đủ ngưỡng theo mảng tam giác; ghi vào `cand`."""
function _candidates!(cand::Vector{Int}, tri::Vector{UInt32}, i::Int, k::Int, minsup::Int, st)
    empty!(cand)
    base = (i - 1) * (2k - i) ÷ 2 - i
    @inbounds for j in (i + 1):k
        tri[base+j] >= minsup && push!(cand, j)
    end
    _st_skip!(st, (k - i) - length(cand))
    return cand
end

"""Các atom j > i cần xét ở lớp gốc: tất cả, hoặc chỉ các cặp đủ ngưỡng theo mảng tam giác."""
function _root_js!(ws::Workspace, tri, i::Int, k::Int, minsup::Int, st)
    if tri === nothing
        empty!(ws.cand)
        append!(ws.cand, (i + 1):k)
        return ws.cand
    end
    return _candidates!(ws.cand, tri, i, k, minsup, st)
end

function _mine_root!(sink, prefix::Vector{Int32}, ws::Workspace, root::VecLevel, tri, minsup::Int,
                     isect::Val, st, maxlen::Int)
    k = length(root.items)
    @inbounds for i in 1:k
        push!(prefix, root.items[i])
        _st_itemset!(st, 1)
        sink(prefix, Int(root.lens[i]))
        if maxlen > 1 && i < k
            t0 = _now(st)
            js = _root_js!(ws, tri, i, k, minsup, st)
            child = _vec_level!(ws, 2)
            if tri !== nothing && length(js) == 1
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
                child = _bit_level!(ws, 2)
                _single!(child, root.items[js[1]], tri[tri_index(i, js[1], k)])
                _st_level2_time!(st, _now(st) - t0)
                _descend_bit!(sink, prefix, ws, 2, child, minsup, isect, st, maxlen)
            elseif _should_switch(ws, root, i, js)
                child = _vec_level!(ws, 2)
                _vec_from_bit!(child, root, i, js, minsup, st)
                isempty(child.items) || _st_switch!(st)
                _st_level2_time!(st, _now(st) - t0)
                _descend_vec!(sink, prefix, ws, 2, child, minsup, isect, st, maxlen)
            else
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

function _eclat_ws!(sink, db::TransactionDB, minsup::Int, cfg::EclatConfig, st, maxlen::Int)
    supp = item_supports(db)
    freq = frequent_items(supp, minsup, cfg.order)
    isempty(freq) && return nothing
    N = n_transactions(db)
    density = sum(x -> supp[x], freq) / (length(freq) * N)       # mật độ trung bình của lớp gốc
    use_bits = cfg.tidset == :bitset || (cfg.tidset == :hybrid && density >= cfg.hybrid_ratio)
    switch_at = cfg.tidset == :hybrid ? cfg.hybrid_ratio * N : -1.0
    ws = Workspace(VecLevel[], BitLevel[], N, switch_at, Int[])
    tri = nothing
    if cfg.level2 == :triangular && maxlen > 1 && length(freq) > 1
        t0 = _now(st)
        tri = pair_counts(db, item_ranks(n_items(db), freq), length(freq))
        _st_level2_time!(st, _now(st) - t0)
    end
    if use_bits
        root = _root_bit(db, freq, supp)
        push!(ws.bit, root)
        nb = _live_bytes(root, N)
    else
        root = _root_vec(db, freq, supp)
        push!(ws.vec, root)
        nb = _live_bytes(root)
    end
    _st_alloc!(st, nb)
    _mine_root!(sink, Int32[], ws, root, tri, minsup, Val(cfg.isect), st, maxlen)   # rào chắn hàm
    _st_free!(st, nb)
    return nothing
end

# ---------------------------------------------------------------------------
# Giao diện công khai
# ---------------------------------------------------------------------------

"""Kiểm tra cấu hình hợp lệ và đã được cài đặt."""
function check_config(cfg::EclatConfig)
    cfg.tidset in (:vector, :bitset, :hybrid) || throw(ArgumentError("tidset không hợp lệ: $(cfg.tidset)"))
    cfg.order in (:lexical, :support_asc) || throw(ArgumentError("order không hợp lệ: $(cfg.order)"))
    cfg.isect in (:merge, :adaptive) || throw(ArgumentError("isect không hợp lệ: $(cfg.isect)"))
    cfg.level2 in (:intersect, :triangular) || throw(ArgumentError("level2 không hợp lệ: $(cfg.level2)"))
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
    minsup >= 1 || throw(ArgumentError("minsup (số đếm) phải ≥ 1"))
    check_config(cfg)
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
    eclat!((items, s) -> (res[sort(items)] = s), db, minsup, cfg; maxlen = maxlen)
    return res
end
