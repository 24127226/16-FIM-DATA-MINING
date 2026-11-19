# Ứng dụng 2, bước 2: biến ảnh thành giao dịch, khai thác bằng Eclat của nhóm, tìm mẫu trực quan đặc
# trưng cho từng lớp và dùng chúng làm đặc trưng cho một bộ phân lớp (phần của A).
#
#   julia --project=apps apps/bovw/analyze.jl          (chạy sau apps/bovw/prepare.jl)
#
# Đầu ra (results/apps/bovw/):
#   B11_bien_doi.md/.csv   các phương án biến đổi: k × cách mã hóa → m, L̄, mật độ, số tập, thời gian,
#                          độ chính xác validation; phương án được chọn
#   B12_mau_dac_trung.md   các tập visual word đặc trưng cho từng lớp (tỉ lệ tăng, emerging patterns)
#   B13_phan_lop.md        bộ phân lớp: histogram bag of visual words / đặc trưng itemset / kết hợp
# Trạng thái phân tích (để vẽ hình F12, F13) lưu ở data/apps/caltech101/cache/analysis.jls.

using EclatFIM, Random, Serialization, Printf, Statistics, LinearAlgebra
include(joinpath(@__DIR__, "..", "..", "scripts", "common.jl"))

const SEED = 42
const KS = [100, 200, 500]
const SCHEMES = [:presence_all, :presence, :count2, :quadrant]
const SCHEME_LABEL = Dict(:presence_all => "có mặt, giữ mọi từ",
                          :presence => "có mặt, bỏ từ quá phổ biến",
                          :count2 => "bỏ từ quá phổ biến, thêm \"xuất hiện ≥ 2 lần\"",
                          :quadrant => "bỏ từ quá phổ biến, từ kèm góc phần tư")
const STOP_DF = 0.5            # bỏ visual word có mặt ở > 50% ảnh huấn luyện (giống bỏ stop word)
const MINSUP_GLOBAL = "30%"    # cho bảng B11 (khai thác trên mọi ảnh huấn luyện)
const MINSUP_CLASS = "30%"     # tìm mẫu đặc trưng trong từng lớp
const MAXLEN = 3               # tập tối đa 3 visual word: đủ để diễn giải, tránh bùng nổ tổ hợp
const TOP_PER_CLASS = 20

const BASE = rootpath("data", "apps", "caltech101")
const CACHE = joinpath(BASE, "cache")
const OUT = rootpath("results", "apps", "bovw")

# ---------------------------------------------------------------------------
# Ảnh → giao dịch
# ---------------------------------------------------------------------------

"""Visual word "quá phổ biến": có mặt ở hơn STOP_DF số ảnh huấn luyện."""
function stopwords(F, words, k)
    df = zeros(Int, k)
    seen = Set{Tuple{Int,Int}}()
    for (j, w) in enumerate(words)
        i = F.owner[j]
        F.train[i] || continue
        (i, w) in seen && continue
        push!(seen, (i, w))
        df[w] += 1
    end
    return df .> STOP_DF * count(F.train)
end

"""Các item của từng ảnh theo một phương án biến đổi."""
function image_items(F, words, k, scheme, stop::BitVector)
    nimg = length(F.files)
    items = [Int32[] for _ in 1:nimg]
    counts = [Dict{Int,Int}() for _ in 1:nimg]
    for (j, w) in enumerate(words)
        i = F.owner[j]
        scheme != :presence_all && stop[w] && continue
        if scheme == :quadrant
            y, x = F.pos[j]
            h, wd = F.sizes[i]
            q = (y + 8 > h / 2 ? 2 : 0) + (x + 8 > wd / 2 ? 1 : 0)    # tâm mảnh nằm ở góc phần tư nào
            push!(items[i], Int32((w - 1) * 4 + q + 1))
        else
            push!(items[i], Int32(w))
            counts[i][w] = get(counts[i], w, 0) + 1
        end
    end
    if scheme == :count2
        for i in 1:nimg, (w, c) in counts[i]
            c >= 2 && push!(items[i], Int32(k + w))
        end
    end
    return [sort!(unique!(t)) for t in items]
end

"""Nhãn dễ đọc của một item: ở phương án "≥ 2 lần", item k + w được ghi là "w×2" (từ w xuất hiện từ 2 lần trở lên)."""
item_label(item, k, scheme) = scheme == :count2 && item > k ? "$(item - k)×2" : string(item)

"""Dựng TransactionDB qua đúng bộ đọc định dạng SPMF của nhóm (mã item gốc được giữ trong item_ids)."""
to_db(txs) = parse_spmf(Vector{UInt8}(join((join(t, ' ') for t in txs), '\n') * "\n"))

"""Support (số giao dịch chứa tập đã sắp xếp `items`)."""
function count_support(txs, items)
    c = 0
    for t in txs
        i = 1
        for x in t
            i <= length(items) && x == items[i] && (i += 1)
        end
        i > length(items) && (c += 1)
    end
    return c
end

# ---------------------------------------------------------------------------
# Mẫu đặc trưng cho lớp: tỉ lệ tăng GR = s_c(X) / s_khác(X) (Dong & Li, 1999)
# ---------------------------------------------------------------------------

function discriminative(txs, labels, idx, c; top = TOP_PER_CLASS)
    inc = [txs[i] for i in idx if labels[i] == c]
    outc = [txs[i] for i in idx if labels[i] != c]
    db = to_db(inc)
    σ = minsup_count(parse_minsup(MINSUP_CLASS), length(inc))
    fis = eclat(db, σ; maxlen = MAXLEN)
    res = NamedTuple[]
    for (key, sc) in fis
        length(key) >= 2 || continue
        items = sort!(Int32[db.item_ids[x] for x in key])
        so = count_support(outc, items)
        s_c = sc / length(inc)
        s_o = so / max(length(outc), 1)
        gr = so == 0 ? Inf : s_c / s_o
        push!(res, (items = items, s_c = s_c, s_o = s_o, gr = gr))
    end
    sort!(res; by = r -> (-r.gr, -r.s_c, r.items))
    return res[1:min(top, length(res))], length(fis)
end

# ---------------------------------------------------------------------------
# Bộ phân lớp: hồi quy logistic đa lớp (softmax) + chuẩn hóa L2, tự viết, huấn luyện bằng gradient
# ---------------------------------------------------------------------------

function standardize(Xtr, Xte)
    μ = mean(Xtr; dims = 2)
    σ = std(Xtr; dims = 2) .+ 1e-6
    return (Xtr .- μ) ./ σ, (Xte .- μ) ./ σ
end

function train_softmax(X, y, ncls; λ = 1e-2, iters = 1500, lr = 0.5)
    d, n = size(X)
    Xb = vcat(X, ones(1, n))
    W = zeros(ncls, d + 1)
    Y = zeros(ncls, n)
    for j in 1:n
        Y[y[j], j] = 1
    end
    for _ in 1:iters
        S = W * Xb
        S .-= maximum(S; dims = 1)
        P = exp.(S)
        P ./= sum(P; dims = 1)
        G = (P - Y) * Xb' ./ n
        G[:, 1:d] .+= λ .* W[:, 1:d]
        W .-= lr .* G
    end
    return W
end

predict(W, X) = [argmax(view(W * vcat(X, ones(1, size(X, 2))), :, j)) for j in 1:size(X, 2)]

"""Histogram bag of visual words (đếm số mảnh mỗi từ, chuẩn hóa L1) của từng ảnh."""
function histograms(F, words, k)
    H = zeros(k, length(F.files))
    for (j, w) in enumerate(words)
        H[w, F.owner[j]] += 1
    end
    return H ./ max.(sum(H; dims = 1), 1)
end

"""Đặc trưng nhị phân: ảnh có chứa tập visual word đặc trưng hay không."""
itemset_features(txs, patterns) = Float64[issubset(p.items, t) for p in patterns, t in txs]

function evaluate(Xtr, ytr, Xte, yte, ncls)
    A, B = standardize(Xtr, Xte)
    W = train_softmax(A, ytr, ncls)
    pred = predict(W, B)
    return mean(pred .== yte), pred
end

function confusion(pred, y, ncls)
    M = zeros(Int, ncls, ncls)
    for (p, t) in zip(pred, y)
        M[t, p] += 1
    end
    return M
end

# ---------------------------------------------------------------------------

function main()
    mkpath(OUT)
    F = deserialize(joinpath(CACHE, "features.jls"))
    ncls = length(F.classes)
    labels = F.labels
    tr = findall(F.train)
    te = findall(.!F.train)
    # tách 25% ảnh huấn luyện làm tập validation (theo từng lớp) để CHỌN phương án; tập kiểm tra chỉ dùng ở cuối
    rng = MersenneTwister(SEED)
    sub, val = Int[], Int[]
    for c in 1:ncls
        ids = shuffle(rng, [i for i in tr if labels[i] == c])
        nv = round(Int, 0.25 * length(ids))
        append!(val, ids[1:nv])
        append!(sub, ids[nv+1:end])
    end
    sort!(sub); sort!(val)

    # --- B11: các phương án biến đổi ---
    rows = []
    warm = to_db([Int32[1, 2], Int32[2, 3]])
    for v in ("v3", "v4", "v6")
        eclat(warm, 1, VARIANTS[v])                     # chạy khởi động
    end
    for k in KS
        cb = deserialize(joinpath(CACHE, "codebook_k$(k).jls"))
        stop = stopwords(F, cb.words, k)
        H = histograms(F, cb.words, k)
        acc_hist_val, _ = evaluate(H[:, sub], labels[sub], H[:, val], labels[val], ncls)
        for scheme in SCHEMES
            txs = image_items(F, cb.words, k, scheme, stop)
            mkpath(joinpath(BASE, "transactions"))
            open(joinpath(BASE, "transactions", "k$(k)_$(scheme).txt"), "w") do f   # để E7 và SPMF dùng lại
                for t in txs[tr]
                    println(f, join(t, ' '))
                end
            end
            dbtr = to_db(txs[tr])
            N = n_transactions(dbtr)
            m = n_items(dbtr)
            L = sum(length, dbtr.transactions) / N
            σ = minsup_count(parse_minsup(MINSUP_GLOBAL), N)
            st = EclatStats()
            nfi = Ref(0)
            eclat!((i, s) -> (nfi[] += 1), dbtr, σ, VARIANTS["v6"]; stats = st, maxlen = 4)
            times = Dict(v => minimum(@elapsed(eclat!((i, s) -> nothing, dbtr, σ, VARIANTS[v]; maxlen = 4)) for _ in 1:3)
                         for v in ("v3", "v4", "v6"))
            pats = vcat([discriminative(txs, labels, sub, c)[1] for c in 1:ncls]...)
            acc_items_val = isempty(pats) ? 0.0 :
                evaluate(itemset_features(txs[sub], pats), labels[sub], itemset_features(txs[val], pats), labels[val], ncls)[1]
            push!(rows, (k = k, scheme = scheme, m = m, L = L, density = L / m, nfi = nfi[], t3 = times["v3"],
                         t4 = times["v4"], t6 = times["v6"], acc_items = acc_items_val, acc_hist = acc_hist_val))
            @printf("k=%3d %-13s m=%4d L̄=%6.1f mật độ=%5.1f%% tập=%8d v3=%.4fs v4=%.4fs v6=%.4fs val(itemset)=%.3f val(hist)=%.3f\n",
                    k, scheme, m, L, 100L / m, nfi[], times["v3"], times["v4"], times["v6"], acc_items_val, acc_hist_val)
        end
    end
    # Chọn phương án có độ chính xác validation cao nhất khi chỉ dùng đặc trưng itemset;
    # hòa thì chọn k nhỏ hơn (codebook gọn hơn, dễ diễn giải hơn).
    best = first(sort(rows; by = r -> (-r.acc_items, r.k, findfirst(==(r.scheme), SCHEMES))))
    open(joinpath(OUT, "B11_bien_doi.csv"), "w") do f
        println(f, "k,scheme,m,avg_len,density,n_itemsets,t_v3,t_v4,t_v6,val_acc_itemset,val_acc_hist")
        for r in rows
            println(f, join((r.k, r.scheme, r.m, r.L, r.density, r.nfi, r.t3, r.t4, r.t6, r.acc_items, r.acc_hist), ","))
        end
    end
    io = IOBuffer()
    println(io, "# Ứng dụng 2: các phương án biến đổi ảnh thành giao dịch\n")
    println(io, "Khai thác trên $(length(tr)) ảnh huấn luyện, minsup = $MINSUP_GLOBAL, tập tối đa 4 visual word. ",
            "Thời gian là thời gian khai thác nhỏ nhất trong 3 lần (đã khởi động). Độ chính xác đo trên tập validation ",
            "($(length(val)) ảnh tách từ tập huấn luyện), không dùng tập kiểm tra.\n")
    println(io, "| k | Cách mã hóa | m | L̄ | Mật độ | Số tập | v3 (vector) | v4 (bitset) | v6 (lai) | Val. itemset | Val. histogram |")
    println(io, "|---|---|---|---|---|---|---|---|---|---|---|")
    for r in rows
        mark = r === best ? " **(chọn)**" : ""
        @printf(io, "| %d | %s%s | %d | %.1f | %.1f%% | %d | %.2f ms | %.2f ms | %.2f ms | %.3f | %.3f |\n",
                r.k, SCHEME_LABEL[r.scheme], mark, r.m, r.L, 100r.density, r.nfi, 1000r.t3, 1000r.t4, 1000r.t6,
                r.acc_items, r.acc_hist)
    end
    println(io, "\n**Phương án chọn:** k = $(best.k), ", SCHEME_LABEL[best.scheme],
            ". Quy tắc chọn: độ chính xác validation cao nhất khi chỉ dùng đặc trưng itemset; hòa thì lấy k nhỏ hơn.")
    write(joinpath(OUT, "B11_bien_doi.md"), String(take!(io)))

    # --- Phương án đã chọn: mẫu đặc trưng (B12) và bộ phân lớp (B13) trên tập kiểm tra ---
    k = best.k
    cb = deserialize(joinpath(CACHE, "codebook_k$(k).jls"))
    stop = stopwords(F, cb.words, k)
    txs = image_items(F, cb.words, k, best.scheme, stop)
    per_class = [discriminative(txs, labels, tr, c) for c in 1:ncls]
    pats = vcat([p[1] for p in per_class]...)
    io = IOBuffer()
    println(io, "# Ứng dụng 2: tập visual word đặc trưng cho từng lớp\n")
    println(io, "Phương án: k = $k, ", SCHEME_LABEL[best.scheme], ". Khai thác riêng từng lớp trên ảnh huấn luyện ",
            "(minsup = $MINSUP_CLASS của lớp, tập 2–$MAXLEN từ). Xếp theo tỉ lệ tăng GR = s_lớp / s_lớp-khác ",
            "(∞: không xuất hiện ở lớp khác, \"jumping emerging pattern\").",
            best.scheme == :count2 ? " Ký hiệu `w×2`: visual word w xuất hiện ít nhất 2 lần trong ảnh (mã item $k + w)." : "",
            "\n")
    for c in 1:ncls
        top, nfi = per_class[c]
        println(io, "## ", F.classes[c], " ($(nfi) tập phổ biến trong lớp)\n")
        println(io, "| # | Visual word | s (lớp này) | s (lớp khác) | GR |")
        println(io, "|---|---|---|---|---|")
        for (r, p) in enumerate(top[1:min(5, length(top))])
            @printf(io, "| %d | %s | %.2f | %.3f | %s |\n", r, join((item_label(x, k, best.scheme) for x in p.items), ", "), p.s_c, p.s_o,
                    isinf(p.gr) ? "∞" : @sprintf("%.1f", p.gr))
        end
        println(io)
    end
    write(joinpath(OUT, "B12_mau_dac_trung.md"), String(take!(io)))

    H = histograms(F, cb.words, k)
    acc_h, pred_h = evaluate(H[:, tr], labels[tr], H[:, te], labels[te], ncls)
    Itr, Ite = itemset_features(txs[tr], pats), itemset_features(txs[te], pats)
    acc_i, pred_i = evaluate(Itr, labels[tr], Ite, labels[te], ncls)
    acc_b, pred_b = evaluate(vcat(H[:, tr], Itr), labels[tr], vcat(H[:, te], Ite), labels[te], ncls)
    io = IOBuffer()
    println(io, "# Ứng dụng 2: dùng mẫu trực quan phổ biến làm đặc trưng cho bộ phân lớp\n")
    println(io, "Hồi quy logistic đa lớp (tự viết), $(length(tr)) ảnh huấn luyện, $(length(te)) ảnh kiểm tra, $(ncls) lớp. ",
            "Mẫu đặc trưng chỉ được tìm trên ảnh huấn luyện.\n")
    println(io, "| Đặc trưng | Số chiều | Độ chính xác (kiểm tra) |")
    println(io, "|---|---|---|")
    @printf(io, "| Histogram bag of visual words (k = %d) | %d | %.3f |\n", k, k, acc_h)
    @printf(io, "| Itemset đặc trưng (%d tập/lớp) | %d | %.3f |\n", TOP_PER_CLASS, length(pats), acc_i)
    @printf(io, "| Kết hợp hai loại | %d | %.3f |\n", k + length(pats), acc_b)
    println(io, "\nMa trận nhầm lẫn của đặc trưng itemset (hàng: lớp thật, cột: lớp dự đoán; thứ tự ",
            join(F.classes, ", "), "):\n")
    M = confusion(pred_i, labels[te], ncls)
    println(io, "| | ", join(F.classes, " | "), " |")
    println(io, "|---|", repeat("---|", ncls))
    for c in 1:ncls
        println(io, "| ", F.classes[c], " | ", join(M[c, :], " | "), " |")
    end
    write(joinpath(OUT, "B13_phan_lop.md"), String(take!(io)))

    serialize(joinpath(CACHE, "analysis.jls"), (k = k, scheme = best.scheme, txs = txs, per_class = per_class,
                                                 classes = F.classes))
    for f in ("B11_bien_doi.md", "B12_mau_dac_trung.md", "B13_phan_lop.md")
        println(read(joinpath(OUT, f), String))
    end
end

main()
