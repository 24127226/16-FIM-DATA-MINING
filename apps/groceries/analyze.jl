# Ứng dụng 1, bước 2: khai thác Groceries bằng Eclat của nhóm, sinh luật kết hợp và diễn giải.
#
#   julia --project=. apps/groceries/analyze.jl
#
# Đầu ra (results/apps/groceries/):
#   B08b_nguong.md          khảo sát ngưỡng (minsup × minconf) → số tập, số luật; lý do chọn ngưỡng
#   B09_top10_lift.md/.csv  top-10 luật theo lift (bảng chính của Ứng dụng 1)
#   B09b_top10_conf.md      top-10 theo confidence: vì sao không xếp theo confidence
#   B10_on_dinh.md          độ ổn định: luật tìm trên 80% dữ liệu, kiểm tra lại trên 20% còn lại
#   B08c_phuong_an.md       so sánh với phương án bỏ hóa đơn 1 món
#   rules.csv               mọi luật ở ngưỡng đã chọn (để vẽ hình F11)

using EclatFIM, Random, Printf
include(joinpath(@__DIR__, "..", "..", "scripts", "config.jl"))

const OUT = rootpath("results", "apps", "groceries")
const MINSUPS = ["0.5%", "1%", "2%"]
const MINCONFS = [0.2, 0.3, 0.5]

"""Tên mặt hàng theo mã nội bộ, đọc từ các dòng `@ITEM=mã=tên`."""
function item_names(path, db)
    byid = Dict{Int64,String}()
    for line in eachline(path)
        startswith(line, "@ITEM=") || continue
        _, id, name = split(line, "=", limit = 3)
        byid[parse(Int64, id)] = name
    end
    return [byid[id] for id in db.item_ids]
end

function mine(db, ms, mc)
    N = n_transactions(db)
    σ = minsup_count(parse_minsup(ms), N)
    t = @elapsed fis = eclat(db, σ)
    return (σ = σ, fis = fis, rules = rules(fis, N; minconf = mc), t = t)
end

pct(x) = @sprintf("%.2f%%", 100x)

"""Support (số giao dịch chứa tập `items`) trên một danh sách giao dịch đã sắp xếp."""
function count_support(txs::Vector{Vector{Int32}}, items::Vector{Int32})
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

function rules_table(io, rs, names, N)
    println(io, "| # | Luật | Số hóa đơn | Support | Confidence | Lift |")
    println(io, "|---|---|---|---|---|---|")
    for (k, r) in enumerate(rs)
        @printf(io, "| %d | %s | %d | %s | %.3f | %.3f |\n", k, format_rule(r, names), r.support_count,
                pct(r.support), r.confidence, r.lift)
    end
end

function main()
    path = rootpath("data", "apps", "groceries", "groceries.txt")
    isfile(path) || error("Chưa có $path: chạy apps/groceries/prepare.jl trước")
    mkpath(OUT)
    db = read_spmf(path)
    N = n_transactions(db)
    names = item_names(path, db)
    mine(db, MINSUPS[end], MINCONFS[end])           # chạy khởi động: thời gian trong bảng không chứa JIT

    # --- 1. Khảo sát ngưỡng ---
    io = IOBuffer()
    println(io, "# Ứng dụng 1: khảo sát ngưỡng\n")
    println(io, "N = $N hóa đơn. Mỗi ô: số tập phổ biến / số luật (thời gian khai thác).\n")
    println(io, "| minsup \\ minconf | ", join(MINCONFS, " | "), " |")
    println(io, "|---|", repeat("---|", length(MINCONFS)))
    grid = Dict{Tuple{String,Float64},Int}()
    for ms in MINSUPS
        cells = String[]
        for mc in MINCONFS
            r = mine(db, ms, mc)
            grid[(ms, mc)] = length(r.rules)
            push!(cells, "$(length(r.fis)) / $(length(r.rules)) ($(round(r.t * 1000; digits = 1)) ms)")
        end
        println(io, "| ", ms, " (σ = ", minsup_count(parse_minsup(ms), N), ") | ", join(cells, " | "), " |")
    end
    # Quy tắc chọn: trong các cặp cho 50–300 luật, lấy minsup nhỏ nhất (phủ nhiều mặt hàng nhất),
    # hòa thì lấy minconf lớn nhất (luật chắc chắn hơn).
    ok = [(ms, mc) for ms in MINSUPS for mc in MINCONFS if 50 <= grid[(ms, mc)] <= 300]
    isempty(ok) && error("Không có cặp ngưỡng nào cho 50–300 luật")
    ms_sel, mc_sel = first(sort(ok; by = p -> (parse_minsup(p[1]), -p[2])))
    println(io, "\n**Ngưỡng chọn:** minsup = ", ms_sel, ", minconf = ", mc_sel,
            ". Quy tắc: trong các cặp cho 50–300 luật (đủ để phân tích, không quá nhiều để đọc), lấy minsup nhỏ nhất ",
            "để phủ được nhiều mặt hàng nhất; hòa thì lấy minconf lớn nhất.")
    write(joinpath(OUT, "B08b_nguong.md"), String(take!(io)))

    # --- 2. Luật ở ngưỡng đã chọn: top-10 theo lift và theo confidence ---
    res = mine(db, ms_sel, mc_sel)
    rs = res.rules
    open(joinpath(OUT, "rules.csv"), "w") do f
        println(f, "antecedent,consequent,support_count,support,confidence,lift")
        for r in rs
            println(f, join(names[r.antecedent], " + "), ",", join(names[r.consequent], " + "), ",",
                    r.support_count, ",", r.support, ",", r.confidence, ",", r.lift)
        end
    end
    top = top_k(rs, 10; by = :lift)
    io = IOBuffer()
    println(io, "# Ứng dụng 1: top-10 luật theo lift\n")
    println(io, "minsup = $ms_sel (σ = $(res.σ)), minconf = $mc_sel; tổng $(length(res.fis)) tập phổ biến, $(length(rs)) luật.\n")
    rules_table(io, top, names, N)
    write(joinpath(OUT, "B09_top10_lift.md"), String(take!(io)))
    open(joinpath(OUT, "B09_top10_lift.csv"), "w") do f
        println(f, "rank,rule,support_count,support,confidence,lift")
        for (k, r) in enumerate(top)
            println(f, k, ",\"", format_rule(r, names), "\",", r.support_count, ",", r.support, ",", r.confidence, ",", r.lift)
        end
    end
    topc = top_k(rs, 10; by = :confidence)
    io = IOBuffer()
    println(io, "# Ứng dụng 1: top-10 luật theo confidence (để so với xếp theo lift)\n")
    rules_table(io, topc, names, N)
    milk = count(r -> any(==("whole milk"), names[r.consequent]), topc)
    println(io, "\n$milk/10 luật có vế phải chứa \"whole milk\" (mặt hàng có mặt trong ",
            pct(count_support(db.transactions, Int32[findfirst(==("whole milk"), names)]) / N),
            " hóa đơn). Confidence cao chủ yếu vì vế phải vốn đã rất phổ biến; lift chia cho support của vế phải nên loại được hiệu ứng này.")
    write(joinpath(OUT, "B09b_top10_conf.md"), String(take!(io)))

    # --- 3. Độ ổn định: tìm trên 80%, kiểm tra trên 20% ---
    perm = randperm(MersenneTwister(SEED), N)
    ntrain = round(Int, 0.8N)
    train = db.transactions[sort(perm[1:ntrain])]
    test = db.transactions[sort(perm[ntrain+1:end])]
    tr = mine(TransactionDB(train, db.item_ids), ms_sel, mc_sel)
    ttop = top_k(tr.rules, 10; by = :lift)
    nt = length(test)
    io = IOBuffer()
    println(io, "# Ứng dụng 1: độ ổn định của luật (80% huấn luyện / 20% kiểm tra, seed = $SEED)\n")
    println(io, "Luật tìm trên $(length(train)) hóa đơn huấn luyện; confidence và lift tính lại trên $nt hóa đơn kiểm tra.\n")
    println(io, "| # | Luật | Conf. (huấn luyện) | Conf. (kiểm tra) | Lift (huấn luyện) | Lift (kiểm tra) | Hóa đơn chứa luật (kiểm tra) |")
    println(io, "|---|---|---|---|---|---|---|")
    function test_metrics(r)
        Z = sort(vcat(r.antecedent, r.consequent))
        sz = count_support(test, Z)
        sx = count_support(test, r.antecedent)
        sy = count_support(test, r.consequent)
        conf = sx == 0 ? NaN : sz / sx
        lift = sy == 0 ? NaN : conf / (sy / nt)
        return conf, lift, sz
    end
    for (k, r) in enumerate(ttop)
        c, l, sz = test_metrics(r)
        @printf(io, "| %d | %s | %.3f | %.3f | %.3f | %.3f | %d |\n", k, format_rule(r, names), r.confidence, c, r.lift, l, sz)
    end
    allm = [test_metrics(r) for r in tr.rules]
    lifts = [m[2] for m in allm if !isnan(m[2])]
    keep = count(>(1), lifts)
    println(io, "\nTrên toàn bộ $(length(tr.rules)) luật tìm được ở tập huấn luyện: $keep luật (",
            pct(keep / length(tr.rules)), ") vẫn có lift > 1 trên tập kiểm tra.")
    top_overlap = length(intersect([(r.antecedent, r.consequent) for r in ttop], [(r.antecedent, r.consequent) for r in top]))
    println(io, "$top_overlap/10 luật trong top-10 (huấn luyện) trùng với top-10 trên toàn bộ dữ liệu.")
    write(joinpath(OUT, "B10_on_dinh.md"), String(take!(io)))

    # --- 4. So sánh phương án biến đổi: bỏ hóa đơn 1 món ---
    pmulti = rootpath("data", "apps", "groceries", "groceries_multi.txt")
    dbm = read_spmf(pmulti)
    rm_ = mine(dbm, ms_sel, mc_sel)
    mtop = top_k(rm_.rules, 10; by = :lift)
    io = IOBuffer()
    println(io, "# Ứng dụng 1: so sánh với phương án bỏ hóa đơn 1 món\n")
    println(io, "| Phương án | N | σ_min | Số tập | Số luật |")
    println(io, "|---|---|---|---|---|")
    println(io, "| Mỗi hóa đơn là một giao dịch | $N | $(res.σ) | $(length(res.fis)) | $(length(rs)) |")
    println(io, "| Bỏ hóa đơn 1 món | $(n_transactions(dbm)) | $(rm_.σ) | $(length(rm_.fis)) | $(length(rm_.rules)) |")
    ov = length(intersect([(r.antecedent, r.consequent) for r in mtop], [(r.antecedent, r.consequent) for r in top]))
    println(io, "\n$ov/10 luật top-10 theo lift trùng nhau giữa hai phương án. Top-10 của phương án bỏ hóa đơn 1 món:\n")
    rules_table(io, mtop, item_names(pmulti, dbm), n_transactions(dbm))
    write(joinpath(OUT, "B08c_phuong_an.md"), String(take!(io)))

    for f in ("B08b_nguong.md", "B09_top10_lift.md", "B09b_top10_conf.md", "B10_on_dinh.md", "B08c_phuong_an.md")
        println(read(joinpath(OUT, f), String))
    end
end

main()
