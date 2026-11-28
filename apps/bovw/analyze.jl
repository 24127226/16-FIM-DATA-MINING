# Ứng dụng 2, bước 2: biến ảnh thành giao dịch, khai thác bằng Eclat của nhóm, tìm mẫu trực quan đặc
# trưng cho từng lớp và dùng chúng làm đặc trưng cho một bộ phân lớp (phần của A).
#
#   julia --project=apps apps/bovw/analyze.jl          (chạy sau apps/bovw/prepare.jl)
#
# Đầu ra (results/, cùng chỗ với kết quả Ứng dụng 1 của B):
#   bovw_b11_transforms.md/.csv  các phương án biến đổi: k × cách mã hóa → m, L̄, mật độ, số tập, thời gian,
#                                độ chính xác validation; phương án được chọn
#   bovw_b12_patterns.md         các tập visual word đặc trưng cho từng lớp (tỉ lệ tăng, emerging patterns)
#   bovw_b13_classification.md   bộ phân lớp: histogram bag of visual words / đặc trưng itemset / kết hợp
#   bovw_summary.md              ghép ba bảng trên (notebook hiển thị file này)
# Trạng thái phân tích (để vẽ hình F12, F13) lưu ở data/apps/caltech101/cache/analysis.jls.

using EclatFIM, Random, Serialization, Printf, Statistics, LinearAlgebra   # EclatFIM: khai thác tập phổ biến của nhóm
include(joinpath(@__DIR__, "..", "..", "scripts", "common.jl"))   # rootpath

const SEED = 42   # seed cố định: chia tập validation tái lập được
const KS = [100, 200, 500]   # các kích thước codebook đã dựng ở prepare.jl
const SCHEMES = [:presence_all, :presence, :count2, :quadrant]   # 4 cách biến ảnh thành giao dịch (a), (b), (c), (d) trong báo cáo
const SCHEME_LABEL = Dict(:presence_all => "presence, all words",   # tên các cách mã hóa trong bảng B11: (a)
                          :presence => "presence, stop words removed",   # (b)
                          :count2 => "stop words removed, plus \"occurs ≥ 2 times\" items",   # (c)
                          :quadrant => "stop words removed, word × image quadrant")   # (d)
const STOP_DF = 0.5            # bỏ visual word có mặt ở > 50% ảnh huấn luyện (giống bỏ stop word)
const MINSUP_GLOBAL = "30%"    # cho bảng B11 (khai thác trên mọi ảnh huấn luyện)
const MINSUP_CLASS = "30%"     # tìm mẫu đặc trưng trong từng lớp
const MAXLEN = 3               # tập tối đa 3 visual word: đủ để diễn giải, tránh bùng nổ tổ hợp
const TOP_PER_CLASS = 20   # số mẫu đặc trưng giữ lại cho mỗi lớp (dùng làm đặc trưng phân lớp)

const BASE = rootpath("data", "apps", "caltech101")   # thư mục dữ liệu ảnh (không commit, tải bằng fetch_data.jl)
const CACHE = joinpath(BASE, "cache")   # descriptor và codebook do prepare.jl lưu
const OUT = rootpath("results")   # nơi ghi các bảng B11–B13

# ---------------------------------------------------------------------------
# Ảnh → giao dịch
# ---------------------------------------------------------------------------

"""Visual word "quá phổ biến": có mặt ở hơn STOP_DF số ảnh huấn luyện."""
function stopwords(F, words, k)   # tìm từ có mặt ở > 50% ảnh huấn luyện
    df = zeros(Int, k)   # df[w] = số ảnh huấn luyện có chứa từ w (document frequency)
    seen = Set{Tuple{Int,Int}}()   # các cặp (ảnh, từ) đã đếm, để mỗi ảnh chỉ đếm một từ một lần
    for (j, w) in enumerate(words)   # từng mảnh j và từ w của nó
        i = F.owner[j]   # ảnh chứa mảnh
        F.train[i] || continue   # chỉ đếm trên ảnh huấn luyện (không nhìn tập kiểm tra)
        (i, w) in seen && continue   # đã đếm cặp (ảnh, từ) này
        push!(seen, (i, w))   # đánh dấu
        df[w] += 1   # thêm một ảnh chứa từ w
    end
    return df .> STOP_DF * count(F.train)   # true nếu từ có mặt ở hơn 50% ảnh huấn luyện
end

# [VẤN ĐÁP] image_items — biến ảnh thành giao dịch (yêu cầu "phân tích quyết định biến đổi dữ liệu" của đề)
# LÀM GÌ    : (a) tập từ có mặt; (b) bỏ từ có mặt ở > 50% ảnh (như bỏ stop word); (c) như (b) + item "w xuất hiện ≥ 2 lần";
#             (d) như (b) nhưng gắn từ với góc phần tư ảnh.
# BẰNG CHỨNG: B11: k = 100 cách (a) dày 56%, 48.879 tập, dãy bit nhanh hơn danh sách 18 lần (đúng H2, H5); k = 500 hoặc (d)
#             gần như không còn tập phổ biến. Chọn k = 200, (c): độ chính xác validation cao nhất 0,708.
# HỎI–ĐÁP   : H: Vì sao (d) giữ vị trí mà lại kém? Đ: mỗi từ bị tách thành 4 item, support chia nhỏ tới mức không tập nào
#             đạt minsup 30%.
"""Các item của từng ảnh theo một phương án biến đổi."""
function image_items(F, words, k, scheme, stop::BitVector)   # biến mọi ảnh thành giao dịch theo cách mã hóa
    nimg = length(F.files)   # số ảnh
    items = [Int32[] for _ in 1:nimg]   # items[i] = các item của ảnh i
    counts = [Dict{Int,Int}() for _ in 1:nimg]   # counts[i][w] = số mảnh của ảnh i thuộc từ w
    for (j, w) in enumerate(words)   # từng mảnh j và từ w của nó
        i = F.owner[j]   # ảnh chứa mảnh
        scheme != :presence_all && stop[w] && continue   # cách (b), (c), (d): bỏ từ quá phổ biến
        if scheme == :quadrant   # cách (d): gắn vị trí
            y, x = F.pos[j]   # vị trí mảnh
            h, wd = F.sizes[i]   # kích thước ảnh
            q = (y + 8 > h / 2 ? 2 : 0) + (x + 8 > wd / 2 ? 1 : 0)    # tâm mảnh nằm ở góc phần tư nào
            push!(items[i], Int32((w - 1) * 4 + q + 1))   # cách (d): mỗi cặp (từ, góc phần tư) là một item riêng
        else
            push!(items[i], Int32(w))   # cách (a), (b), (c): item chính là từ w
            counts[i][w] = get(counts[i], w, 0) + 1   # đếm số lần từ w xuất hiện trong ảnh i
        end
    end
    if scheme == :count2   # cách (c)
        for i in 1:nimg, (w, c) in counts[i]   # mọi (ảnh, từ, số lần)
            c >= 2 && push!(items[i], Int32(k + w))   # cách (c): thêm item k + w nghĩa là "từ w xuất hiện ≥ 2 lần"
        end
    end
    return [sort!(unique!(t)) for t in items]   # giao dịch phải tăng dần, không trùng (bất biến của TransactionDB)
end

"""Nhãn dễ đọc của một item: ở phương án "≥ 2 lần", item k + w được ghi là "w×2" (từ w xuất hiện từ 2 lần trở lên)."""
item_label(item, k, scheme) = scheme == :count2 && item > k ? "$(item - k)×2" : string(item)   # item k + w → "w×2"

"""Dựng TransactionDB qua đúng bộ đọc định dạng SPMF của nhóm (mã item gốc được giữ trong item_ids)."""
to_db(txs) = parse_spmf(Vector{UInt8}(join((join(t, ' ') for t in txs), '\n') * "\n"))   # giao dịch → văn bản SPMF → TransactionDB qua ĐÚNG bộ đọc của nhóm

"""Support (số giao dịch chứa tập đã sắp xếp `items`)."""
function count_support(txs, items)   # support của một tập trong các giao dịch (dùng cho lớp khác)
    c = 0   # số giao dịch chứa đủ mọi item của `items`
    for t in txs   # từng giao dịch
        i = 1   # con trỏ trong items
        for x in t   # duyệt giao dịch (đã sắp tăng dần)
            i <= length(items) && x == items[i] && (i += 1)   # khớp item tiếp theo của tập
        end
        i > length(items) && (c += 1)   # khớp đủ mọi item → giao dịch chứa tập
    end
    return c   # support (số đếm)
end

# ---------------------------------------------------------------------------
# Mẫu đặc trưng cho lớp: tỉ lệ tăng GR = s_c(X) / s_khác(X) (Dong & Li, 1999)
# ---------------------------------------------------------------------------

# [VẤN ĐÁP] discriminative — nơi thuật toán Eclat của nhóm được dùng trong Ứng dụng 2
# LÀM GÌ    : khai thác tập phổ biến RIÊNG trong ảnh của lớp c (minsup 30% của lớp, tập 2–3 từ) bằng eclat() của nhóm,
#             rồi xếp theo tỉ lệ tăng GR = s_lớp / s_lớp-khác (emerging pattern, Dong & Li 1999).
# HỎI–ĐÁP   : H: GR = ∞ nghĩa là gì? Đ: tập không xuất hiện trong ảnh huấn luyện nào của lớp khác (210 ảnh); chưa chắc đúng
#             trên tập dữ liệu lớn hơn. H: Vì sao giới hạn 3 từ? Đ: đủ để diễn giải, tránh bùng nổ số tập trên dữ liệu dày.
function discriminative(txs, labels, idx, c; top = TOP_PER_CLASS)   # mẫu đặc trưng của lớp c
    inc = [txs[i] for i in idx if labels[i] == c]   # giao dịch (ảnh) của lớp c
    outc = [txs[i] for i in idx if labels[i] != c]   # giao dịch của các lớp còn lại
    db = to_db(inc)   # chỉ khai thác trên ảnh của lớp c
    σ = minsup_count(parse_minsup(MINSUP_CLASS), length(inc))   # 30% số ảnh của lớp, quy đổi đúng như SPMF
    fis = eclat(db, σ; maxlen = MAXLEN)   # KHAI THÁC BẰNG ECLAT CỦA NHÓM (phiên bản mặc định v6)
    res = NamedTuple[]   # các mẫu tìm được
    for (key, sc) in fis   # mỗi tập phổ biến trong lớp và support của nó
        length(key) >= 2 || continue   # bỏ tập 1 từ: một từ đơn lẻ ít mang tính cấu trúc
        items = sort!(Int32[db.item_ids[x] for x in key])   # đổi mã nội bộ → mã item gốc (số hiệu từ thị giác)
        so = count_support(outc, items)   # support của tập ở các lớp khác
        s_c = sc / length(inc)   # support tương đối trong lớp c
        s_o = so / max(length(outc), 1)   # support tương đối ở các lớp khác
        gr = so == 0 ? Inf : s_c / s_o   # tỉ lệ tăng GR; ∞ nếu không xuất hiện ở lớp khác
        push!(res, (items = items, s_c = s_c, s_o = s_o, gr = gr))   # lưu mẫu
    end
    sort!(res; by = r -> (-r.gr, -r.s_c, r.items))   # GR giảm dần; hòa thì support trong lớp giảm dần, rồi theo mã
    return res[1:min(top, length(res))], length(fis)   # 20 mẫu đầu và tổng số tập phổ biến của lớp
end

# ---------------------------------------------------------------------------
# Bộ phân lớp: hồi quy logistic đa lớp (softmax) + chuẩn hóa L2, tự viết, huấn luyện bằng gradient
# ---------------------------------------------------------------------------

function standardize(Xtr, Xte)   # chuẩn hóa từng đặc trưng về trung bình 0, độ lệch chuẩn 1
    μ = mean(Xtr; dims = 2)   # trung bình từng đặc trưng trên tập huấn luyện
    σ = std(Xtr; dims = 2) .+ 1e-6   # độ lệch chuẩn (cộng số nhỏ để không chia cho 0)
    return (Xtr .- μ) ./ σ, (Xte .- μ) ./ σ   # chuẩn hóa cả hai tập bằng thống kê của tập huấn luyện
end

# [VẤN ĐÁP] train_softmax — bộ phân lớp tự viết
# VÌ SAO    : hồi quy logistic đa lớp đơn giản, dễ giải thích, không cần thư viện học máy; mục tiêu là so SỨC MANG THÔNG TIN
#             của các loại đặc trưng chứ không phải đạt độ chính xác cao nhất.
# BẰNG CHỨNG: B13 (120 ảnh kiểm tra): histogram 0,858; 80 đặc trưng itemset 0,758 (ngẫu nhiên 0,25); kết hợp 0,867.
# HỎI–ĐÁP   : H: Kết hợp chỉ hơn 0,9 điểm, có ý nghĩa không? Đ: chỉ là đúng thêm 1/120 ảnh, chưa đủ để kết luận; giá trị chính
#             của mẫu là đọc được bằng mắt (hình F12, F13).
function train_softmax(X, y, ncls; λ = 1e-2, iters = 1500, lr = 0.5)   # hồi quy logistic đa lớp, gradient descent
    d, n = size(X)   # d đặc trưng, n ảnh
    Xb = vcat(X, ones(1, n))   # thêm hàng 1 để có hệ số chặn (bias)
    W = zeros(ncls, d + 1)   # trọng số của hồi quy logistic đa lớp
    Y = zeros(ncls, n)   # nhãn dạng one-hot
    for j in 1:n   # đặt nhãn one-hot
        Y[y[j], j] = 1   # (tiếp)
    end
    for _ in 1:iters   # 1.500 bước gradient
        S = W * Xb   # điểm số của từng lớp cho từng ảnh
        S .-= maximum(S; dims = 1)   # trừ giá trị lớn nhất để exp không tràn số
        P = exp.(S)   # softmax: điểm số → xác suất
        P ./= sum(P; dims = 1)   # mỗi cột cộng lại bằng 1
        G = (P - Y) * Xb' ./ n   # gradient của hàm mất mát cross-entropy
        G[:, 1:d] .+= λ .* W[:, 1:d]   # điều chuẩn L2 (không phạt hệ số chặn)
        W .-= lr .* G   # một bước gradient descent
    end
    return W   # trọng số đã học
end

predict(W, X) = [argmax(view(W * vcat(X, ones(1, size(X, 2))), :, j)) for j in 1:size(X, 2)]   # lớp có điểm số cao nhất

"""Histogram bag of visual words (đếm số mảnh mỗi từ, chuẩn hóa L1) của từng ảnh."""
function histograms(F, words, k)   # biểu diễn BoVW chuẩn: tần suất từng từ trong ảnh
    H = zeros(k, length(F.files))   # H[w, i] = số mảnh của ảnh i thuộc từ w
    for (j, w) in enumerate(words)   # từng mảnh j và từ w của nó
        H[w, F.owner[j]] += 1   # đếm
    end
    return H ./ max.(sum(H; dims = 1), 1)   # chuẩn hóa L1: mỗi cột cộng lại bằng 1
end

"""Đặc trưng nhị phân: ảnh có chứa tập visual word đặc trưng hay không."""
itemset_features(txs, patterns) = Float64[issubset(p.items, t) for p in patterns, t in txs]   # 1 nếu ảnh chứa mẫu, 0 nếu không

function evaluate(Xtr, ytr, Xte, yte, ncls)   # chuẩn hóa, huấn luyện, đo độ chính xác
    A, B = standardize(Xtr, Xte)   # chuẩn hóa đặc trưng
    W = train_softmax(A, ytr, ncls)   # huấn luyện trên tập huấn luyện
    pred = predict(W, B)   # dự đoán trên tập đánh giá
    return mean(pred .== yte), pred   # độ chính xác = tỉ lệ dự đoán đúng
end

function confusion(pred, y, ncls)   # ma trận nhầm lẫn
    M = zeros(Int, ncls, ncls)   # M[lớp thật, lớp dự đoán]
    for (p, t) in zip(pred, y)   # từng ảnh
        M[t, p] += 1   # đếm
    end
    return M   # ma trận
end

# ---------------------------------------------------------------------------

# [VẤN ĐÁP] main — quy trình đánh giá
# HỎI–ĐÁP   : H: Làm sao tránh chọn phương án "ăn may" trên tập kiểm tra? Đ: tách 25% ảnh huấn luyện làm validation để CHỌN
#             phương án; tập kiểm tra chỉ dùng một lần ở bước cuối (bảng B13).
function main()   # B11 → chọn phương án → B12, B13
    mkpath(OUT)   # thư mục kết quả
    F = deserialize(joinpath(CACHE, "features.jls"))   # descriptor, nhãn, chia huấn luyện/kiểm tra từ prepare.jl
    ncls = length(F.classes)   # 4 lớp
    labels = F.labels   # nhãn
    tr = findall(F.train)   # chỉ số ảnh huấn luyện
    te = findall(.!F.train)   # chỉ số ảnh kiểm tra (chỉ dùng ở bước cuối, bảng B13)
    # tách 25% ảnh huấn luyện làm tập validation (theo từng lớp) để CHỌN phương án; tập kiểm tra chỉ dùng ở cuối
    rng = MersenneTwister(SEED)
    sub, val = Int[], Int[]   # sub: học; val: kiểm định để chọn phương án
    for c in 1:ncls   # từng lớp
        ids = shuffle(rng, [i for i in tr if labels[i] == c])   # ảnh huấn luyện của lớp, xáo trộn
        nv = round(Int, 0.25 * length(ids))   # 25% làm validation
        append!(val, ids[1:nv])   # phần validation
        append!(sub, ids[nv+1:end])   # phần còn lại để học
    end
    sort!(sub); sort!(val)   # sub: ảnh để học; val: ảnh validation để chọn phương án

    # --- B11: các phương án biến đổi ---
    rows = []
    warm = to_db([Int32[1, 2], Int32[2, 3]])   # CSDL rất nhỏ để khởi động
    for v in ("v3", "v4", "v6")   # ba phiên bản được đo trong B11
        eclat(warm, 1, VARIANTS[v])                     # chạy khởi động
    end
    for k in KS   # từng kích thước codebook
        cb = deserialize(joinpath(CACHE, "codebook_k$(k).jls"))   # codebook k từ và từ của mọi mảnh
        stop = stopwords(F, cb.words, k)   # các từ quá phổ biến của codebook này
        H = histograms(F, cb.words, k)   # đặc trưng histogram
        acc_hist_val, _ = evaluate(H[:, sub], labels[sub], H[:, val], labels[val], ncls)   # độ chính xác validation của histogram
        for scheme in SCHEMES   # từng cách mã hóa
            txs = image_items(F, cb.words, k, scheme, stop)   # mọi ảnh → giao dịch theo cách mã hóa đang xét
            mkpath(joinpath(BASE, "transactions"))   # lưu giao dịch để E7 và SPMF dùng lại
            open(joinpath(BASE, "transactions", "k$(k)_$(scheme).txt"), "w") do f   # để E7 và SPMF dùng lại
                for t in txs[tr]   # chỉ ảnh huấn luyện
                    println(f, join(t, ' '))   # một giao dịch một dòng (định dạng SPMF)
                end
            end
            dbtr = to_db(txs[tr])   # CSDL giao dịch của ảnh huấn luyện
            N = n_transactions(dbtr)   # số ảnh huấn luyện
            m = n_items(dbtr)   # số item phân biệt
            L = sum(length, dbtr.transactions) / N   # độ dài giao dịch trung bình L̄
            σ = minsup_count(parse_minsup(MINSUP_GLOBAL), N)   # minsup 30% → số đếm
            st = EclatStats()   # bộ đếm
            nfi = Ref(0)   # số tập phổ biến
            eclat!((i, s) -> (nfi[] += 1), dbtr, σ, VARIANTS["v6"]; stats = st, maxlen = 4)   # KHAI THÁC BẰNG ECLAT CỦA NHÓM (v6), tập ≤ 4 từ
            times = Dict(v => minimum(@elapsed(eclat!((i, s) -> nothing, dbtr, σ, VARIANTS[v]; maxlen = 4)) for _ in 1:3)   # đo thời gian v3, v4, v6 (nhỏ nhất của 3 lần)
                         for v in ("v3", "v4", "v6"))   # (tiếp)
            pats = vcat([discriminative(txs, labels, sub, c)[1] for c in 1:ncls]...)   # mẫu đặc trưng tìm trên tập con huấn luyện
            acc_items_val = isempty(pats) ? 0.0 :   # không có mẫu → độ chính xác 0
                evaluate(itemset_features(txs[sub], pats), labels[sub], itemset_features(txs[val], pats), labels[val], ncls)[1]   # độ chính xác validation của đặc trưng itemset
            push!(rows, (k = k, scheme = scheme, m = m, L = L, density = L / m, nfi = nfi[], t3 = times["v3"],   # một hàng bảng B11
                         t4 = times["v4"], t6 = times["v6"], acc_items = acc_items_val, acc_hist = acc_hist_val))   # (tiếp)
            @printf("k=%3d %-13s m=%4d L̄=%6.1f density=%5.1f%% itemsets=%8d v3=%.4fs v4=%.4fs v6=%.4fs val(itemset)=%.3f val(hist)=%.3f\n",   # in tiến độ
                    k, scheme, m, L, 100L / m, nfi[], times["v3"], times["v4"], times["v6"], acc_items_val, acc_hist_val)   # (tiếp)
        end
    end
    # Chọn phương án có độ chính xác validation cao nhất khi chỉ dùng đặc trưng itemset;
    # hòa thì chọn k nhỏ hơn (codebook gọn hơn, dễ diễn giải hơn).
    best = first(sort(rows; by = r -> (-r.acc_items, r.k, findfirst(==(r.scheme), SCHEMES))))
    open(joinpath(OUT, "bovw_b11_transforms.csv"), "w") do f   # ghi B11 dạng CSV
        println(f, "k,scheme,m,avg_len,density,n_itemsets,t_v3,t_v4,t_v6,val_acc_itemset,val_acc_hist")   # tiêu đề cột
        for r in rows   # từng phương án
            println(f, join((r.k, r.scheme, r.m, r.L, r.density, r.nfi, r.t3, r.t4, r.t6, r.acc_items, r.acc_hist), ","))   # một dòng
        end
    end
    io = IOBuffer()   # bộ đệm chuỗi cho bảng Markdown
    println(io, "# Application 2: image-to-transaction transformation schemes (Table B11)\n")   # tiêu đề B11
    println(io, "Mined on $(length(tr)) training images, minsup = $MINSUP_GLOBAL, itemsets of at most 4 visual words. ",   # mô tả thiết lập
            "Times are the minimum of 3 warmed-up mining runs. Accuracy is measured on a validation split ",   # (tiếp)
            "($(length(val)) images held out from the training set); the test set is not used here.\n")   # (tiếp)
    println(io, "| k | Encoding | m | L̄ | Density | Itemsets | v3 (vector) | v4 (bitset) | v6 (hybrid) | Val. itemset | Val. histogram |")   # tiêu đề cột
    println(io, "|---|---|---|---|---|---|---|---|---|---|---|")   # đường kẻ
    for r in rows   # từng phương án
        mark = r === best ? " **(selected)**" : ""   # đánh dấu phương án được chọn
        @printf(io, "| %d | %s%s | %d | %.1f | %.1f%% | %d | %.2f ms | %.2f ms | %.2f ms | %.3f | %.3f |\n",   # một hàng
                r.k, SCHEME_LABEL[r.scheme], mark, r.m, r.L, 100r.density, r.nfi, 1000r.t3, 1000r.t4, 1000r.t6,   # (tiếp; giây → ms)
                r.acc_items, r.acc_hist)   # (tiếp)
    end
    println(io, "\n**Selected scheme:** k = $(best.k), ", SCHEME_LABEL[best.scheme],   # ghi phương án chọn
            ". Rule: highest validation accuracy with itemset features only; ties go to the smaller k.")   # và quy tắc chọn
    write(joinpath(OUT, "bovw_b11_transforms.md"), String(take!(io)))   # lưu B11

    # --- Phương án đã chọn: mẫu đặc trưng (B12) và bộ phân lớp (B13) trên tập kiểm tra ---
    k = best.k   # phương án đã chọn trên validation
    cb = deserialize(joinpath(CACHE, "codebook_k$(k).jls"))   # codebook k từ và từ của mọi mảnh
    stop = stopwords(F, cb.words, k)   # các từ quá phổ biến của codebook này
    txs = image_items(F, cb.words, k, best.scheme, stop)   # giao dịch theo phương án đã chọn
    per_class = [discriminative(txs, labels, tr, c) for c in 1:ncls]   # mẫu đặc trưng tìm trên TOÀN BỘ ảnh huấn luyện
    pats = vcat([p[1] for p in per_class]...)   # 20 mẫu mỗi lớp × 4 lớp = 80 đặc trưng
    io = IOBuffer()   # bộ đệm chuỗi cho bảng Markdown
    println(io, "# Application 2: discriminative visual-word itemsets per class (Table B12)\n")   # tiêu đề B12
    println(io, "Scheme: k = $k, ", SCHEME_LABEL[best.scheme], ". Each class is mined separately on its training images ",   # mô tả
            "(minsup = $MINSUP_CLASS of the class, itemsets of 2–$MAXLEN words), ranked by growth rate GR = s_class / s_other ",   # (tiếp)
            "(∞: never occurs in another class, a \"jumping emerging pattern\").",   # (tiếp)
            best.scheme == :count2 ? " Notation `w×2`: visual word w occurs at least twice in the image (item code $k + w)." : "",   # giải thích ký hiệu w×2
            "\n")   # (tiếp)
    for c in 1:ncls   # từng lớp
        top, nfi = per_class[c]   # mẫu và số tập phổ biến của lớp
        println(io, "## ", F.classes[c], " ($(nfi) frequent itemsets in the class)\n")   # một mục mỗi lớp
        println(io, "| # | Visual words | s (this class) | s (other classes) | GR |")
        println(io, "|---|---|---|---|---|")   # đường kẻ
        for (r, p) in enumerate(top[1:min(5, length(top))])   # 5 mẫu đầu
            @printf(io, "| %d | %s | %.2f | %.3f | %s |\n", r, join((item_label(x, k, best.scheme) for x in p.items), ", "), p.s_c, p.s_o,   # một hàng
                    isinf(p.gr) ? "∞" : @sprintf("%.1f", p.gr))   # GR
        end
        println(io)   # dòng trống
    end
    write(joinpath(OUT, "bovw_b12_patterns.md"), String(take!(io)))   # lưu B12

    H = histograms(F, cb.words, k)   # đặc trưng histogram
    acc_h, pred_h = evaluate(H[:, tr], labels[tr], H[:, te], labels[te], ncls)   # đặc trưng 1: histogram từ thị giác
    Itr, Ite = itemset_features(txs[tr], pats), itemset_features(txs[te], pats)   # đặc trưng 2: ảnh có chứa mẫu hay không
    acc_i, pred_i = evaluate(Itr, labels[tr], Ite, labels[te], ncls)   # phân lớp chỉ bằng đặc trưng itemset
    acc_b, pred_b = evaluate(vcat(H[:, tr], Itr), labels[tr], vcat(H[:, te], Ite), labels[te], ncls)   # kết hợp hai loại đặc trưng
    io = IOBuffer()   # bộ đệm chuỗi cho bảng Markdown
    println(io, "# Application 2: frequent visual patterns as classifier features (Table B13)\n")   # tiêu đề B13
    println(io, "Multinomial logistic regression (own implementation), $(length(tr)) training images, $(length(te)) test images, $(ncls) classes. ",   # mô tả
            "Discriminative patterns are mined on training images only.\n")   # (tiếp)
    println(io, "| Features | Dimensions | Test accuracy |")   # tiêu đề cột
    println(io, "|---|---|---|")   # đường kẻ
    @printf(io, "| Histogram bag of visual words (k = %d) | %d | %.3f |\n", k, k, acc_h)   # hàng histogram
    @printf(io, "| Discriminative itemsets (%d per class) | %d | %.3f |\n", TOP_PER_CLASS, length(pats), acc_i)   # hàng itemset
    @printf(io, "| Both combined | %d | %.3f |\n", k + length(pats), acc_b)   # hàng kết hợp
    println(io, "\nConfusion matrix of the itemset features (rows: true class, columns: predicted class; order ",   # ma trận nhầm lẫn
            join(F.classes, ", "), "):\n")   # (tiếp)
    M = confusion(pred_i, labels[te], ncls)   # tính trên ảnh kiểm tra
    println(io, "| | ", join(F.classes, " | "), " |")   # tiêu đề
    println(io, "|---|", repeat("---|", ncls))   # đường kẻ
    for c in 1:ncls   # từng lớp
        println(io, "| ", F.classes[c], " | ", join(M[c, :], " | "), " |")   # một hàng
    end
    write(joinpath(OUT, "bovw_b13_classification.md"), String(take!(io)))   # lưu B13

    serialize(joinpath(CACHE, "analysis.jls"), (k = k, scheme = best.scheme, txs = txs, per_class = per_class,   # lưu cho figures.jl
                                                 classes = F.classes))   # (tiếp)
    # Ghép ba bảng thành một file tóm tắt để notebook hiển thị (giống groceries_summary.md của B)
    parts = [read(joinpath(OUT, f), String) for f in ("bovw_b11_transforms.md", "bovw_b12_patterns.md", "bovw_b13_classification.md")]
    write(joinpath(OUT, "bovw_summary.md"), join(parts, "\n"))   # lưu tóm tắt cho notebook
    println(join(parts, "\n"))   # in
end

main()   # chạy
