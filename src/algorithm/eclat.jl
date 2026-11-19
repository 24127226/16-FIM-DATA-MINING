# Thuật toán Eclat (phần của A).
#
# Theo bài báo gốc (Zaki, 2000):
#   §4.1  support của một tập = độ dài phần giao tidset của hai tập con kích thước k-1;
#   §4.2  không gian tìm kiếm chia thành các lớp tương đương theo tiền tố, giải độc lập;
#   §5.2  duyệt từ dưới lên: giao mọi cặp atom trong lớp, tập đủ ngưỡng thành atom của lớp con.
# Bản cơ bản không kiểm tra tập con (bài báo §5.2: cắt tỉa gần như không có lợi vì bổ đề 6).

"""Tên phiên bản dùng khi không chỉ định cấu hình (bản tốt nhất đã cài đặt)."""
const DEFAULT_VARIANT = "v0"
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

"""
    vertical_tidsets(db, freq, supp) -> Vector{Vector{Int32}}

Dựng tidset dạng vector cho các item phổ biến `freq` (theo đúng thứ tự trong `freq`).
Duyệt giao dịch theo tid tăng dần nên mỗi tidset tự động tăng dần. O(N·L̄).
"""
function vertical_tidsets(db::TransactionDB, freq::Vector{Int32}, supp::Vector{Int})
    rank = zeros(Int32, n_items(db))           # rank[x] = vị trí của item x trong freq (0: không phổ biến)
    for (r, x) in enumerate(freq)
        rank[x] = r
    end
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
# Bản cấp phát (v0, v1): mỗi atom giữ tidset riêng, mỗi phép giao tạo mảng mới
# ---------------------------------------------------------------------------

"""Lớp tương đương: các cặp (item cuối, tidset). Tiền tố nằm ở ngăn xếp `prefix` dùng chung."""
struct AllocClass
    items::Vector{Int32}
    tidsets::Vector{Vector{Int32}}
end

_bytes(tids::Vector{Vector{Int32}}) = 4 * sum(length, tids; init = 0)

"""Lớp con của atom thứ `i`: giao tidset của nó với tidset của mọi atom đứng sau."""
function _child_alloc(cls::AllocClass, i::Int, minsup::Integer, st)
    items = Int32[]
    tids = Vector{Vector{Int32}}()
    tx = cls.tidsets[i]
    @inbounds for j in (i + 1):length(cls.items)
        t = intersect_merge(tx, cls.tidsets[j])
        ok = length(t) >= minsup
        _st_isect!(st, ok)
        if ok
            push!(items, cls.items[j])
            push!(tids, t)
        end
    end
    return AllocClass(items, tids)
end

function _mine_alloc!(sink, prefix::Vector{Int32}, cls::AllocClass, minsup::Integer, st, maxlen::Int)
    k = length(cls.items)
    @inbounds for i in 1:k
        push!(prefix, cls.items[i])
        depth = length(prefix)
        _st_itemset!(st, depth)
        sink(prefix, length(cls.tidsets[i]))                 # xuất tập prefix với support |t(prefix)|
        if depth < maxlen && i < k
            t0 = depth == 1 ? _now(st) : UInt64(0)
            child = _child_alloc(cls, i, minsup, st)
            depth == 1 && _st_level2_time!(st, _now(st) - t0)  # các lớp con của lớp gốc = tập 2 item
            if !isempty(child.items)
                _st_class!(st)
                nb = _bytes(child.tidsets)
                _st_alloc!(st, nb)
                _mine_alloc!(sink, prefix, child, minsup, st, maxlen)
                _st_free!(st, nb)
            end
        end
        pop!(prefix)
    end
    return nothing
end

function _eclat_alloc!(sink, db::TransactionDB, minsup::Integer, cfg::EclatConfig, st, maxlen::Int)
    supp = item_supports(db)
    freq = frequent_items(supp, minsup, cfg.order)
    isempty(freq) && return nothing
    root = AllocClass(freq, vertical_tidsets(db, freq, supp))
    nb = _bytes(root.tidsets)
    _st_alloc!(st, nb)
    _mine_alloc!(sink, Int32[], root, minsup, st, maxlen)
    _st_free!(st, nb)
    return nothing
end

# ---------------------------------------------------------------------------
# Giao diện công khai
# ---------------------------------------------------------------------------

"""Kiểm tra cấu hình có được cài đặt ở phiên bản code hiện tại không."""
function check_config(cfg::EclatConfig)
    cfg.tidset == :vector || throw(ArgumentError("tidset = $(cfg.tidset) chưa được cài đặt"))
    cfg.order in (:lexical, :support_asc) || throw(ArgumentError("order không hợp lệ: $(cfg.order)"))
    cfg.reuse && throw(ArgumentError("reuse = true chưa được cài đặt"))
    cfg.isect == :merge || throw(ArgumentError("isect = $(cfg.isect) chưa được cài đặt"))
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
    minsup >= 1 || throw(ArgumentError("minsup (số đếm) phải ≥ 1"))
    check_config(cfg)
    _eclat_alloc!(sink, db, minsup, cfg, stats, Int(maxlen))
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
