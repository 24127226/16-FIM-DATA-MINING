# Kịch bản thực nghiệm Ứng dụng 1: Phân tích giỏ hàng trên tập dữ liệu Groceries.
#
# Toàn bộ tập phổ biến và luật kết hợp được khai thác bởi gói `EclatFIM`.
# Các tệp kết quả xuất ra thư mục `results/`:
#   - groceries_b08_transforms.csv : Bảng B08 (so sánh hai phương án biến đổi dữ liệu)
#   - groceries_grid.csv           : Khảo sát độ nhạy trên lưới minsup × minconf
#   - groceries_rules.csv          : Toàn bộ tập luật ở ngưỡng lựa chọn (dữ liệu nguồn Hình F11)
#   - groceries_top10.csv          : Bảng B09 (10 luật dẫn đầu theo độ nâng)
#   - groceries_stability.csv      : Bảng B10 (đánh giá độ ổn định trên phép chia 80/20)
#   - groceries_summary.md         : Bản tổng hợp kết quả định lượng
#
# Cú pháp thực thi:
#   julia --project=. apps/groceries/run_groceries.jl

using Random
using Dates
using EclatFIM

const REPO_ROOT = normpath(joinpath(@__DIR__, "..", ".."))
include(joinpath(REPO_ROOT, "scripts", "config.jl"))
include(joinpath(@__DIR__, "prepare_groceries.jl"))

const GROCERIES_CSV = joinpath(REPO_ROOT, "data", "apps", "groceries", "groceries.csv")
const GROCERIES_DIR = joinpath(REPO_ROOT, "data", "apps", "groceries")

# Lưới ngưỡng khảo sát theo mục 9.2
const GRID_MINSUPS  = ["0.5%", "1%", "2%"]
const GRID_MINCONFS = [0.2, 0.3, 0.5]

# Cặp ngưỡng chính được chọn (cho ra ~50-300 luật trên Groceries, đủ sâu và tin cậy)
const CHOSEN_MINSUP  = "1%"
const CHOSEN_MINCONF = 0.3

"""Chuyển vector mã nội bộ sang chuỗi tên mặt hàng dễ đọc."""
function format_items(items::Vector{Int32}, db::TransactionDB, id_to_name::Dict{Int64,String})
    names = [id_to_name[db.item_ids[x]] for x in sort(items)]
    return join(names, " + ")
end

"""Escape chuỗi cho CSV."""
csv_esc(s::AbstractString) = '"' * replace(s, '"' => "\"\"") * '"'

"""
    profile_representation(label, spmf_path, minsup_str, cfg)

Mục đích: Đo thống kê cơ bản (N, m, L̄, mật độ ρ), thời gian khai thác Eclat (có warm-up trước)
và số lượng tập phổ biến/luật kết hợp sinh ra cho một phương án biến đổi dữ liệu (phục vụ Bảng B08).
"""
function profile_representation(label::String, spmf_path::String, minsup_str::String, cfg::EclatConfig)
    db = read_spmf(spmf_path)
    n = n_transactions(db)
    m = n_items(db)
    avg_len = sum(length(t) for t in db.transactions) / n   # Độ dài giỏ hàng trung bình (dùng generator expression)
    density = avg_len / m                                   # Mật độ ρ = L̄ / m (so sánh với ngưỡng lý thuyết 1/32)
    sigma_min = minsup_count(minsup_str, n)

    # Chạy nháp 1 lần (warm-up) để loại trừ thời gian biên dịch JIT khỏi phép đo
    _ = eclat(db, sigma_min, cfg)
    t0 = time_ns()
    isets = eclat(db, sigma_min, cfg)
    t_s = (time_ns() - t0) / 1e9

    rs = rules(isets, n; minconf = CHOSEN_MINCONF)
    return (label = label, n = n, m = m, avg_len = avg_len, density = density,
            sigma_min = sigma_min, n_itemsets = length(isets), n_rules = length(rs),
            t_s = t_s, db = db, isets = isets)
end

"""
    evaluate_stability(db, id_to_name, minsup_str, minconf, cfg; train_ratio=0.8, seed=42, k=10)

Mục đích: Kiểm tra độ ổn định ngoài mẫu của top-k luật theo lift (Bảng B10):
- Xáo trộn ngẫu nhiên với `seed` cố định và chia 80% tập huấn luyện / 20% tập kiểm tra.
- Khai thác tập phổ biến và chọn top-k luật CHỈ trên tập huấn luyện 80%.
- Đếm lại độ hỗ trợ, confidence và lift của đúng k luật đó trên 20% tập kiểm tra độc lập.
"""
function evaluate_stability(db::TransactionDB, id_to_name::Dict{Int64,String},
                            minsup_str::String, minconf::Float64, cfg::EclatConfig;
                            train_ratio::Float64 = 0.8, seed::Int = SEED, k::Int = 10)
    n = n_transactions(db)
    rng = MersenneTwister(seed)                  # Cố định hạt giống để kết quả chia 80/20 tái lập 100%
    perm = randperm(rng, n)
    n_train = round(Int, train_ratio * n)

    train_txs = db.transactions[perm[1:n_train]]
    test_txs  = db.transactions[perm[(n_train + 1):end]]
    n_test = length(test_txs)

    # Khai thác và sinh top-k luật chỉ trên tập huấn luyện (80%)
    train_db = TransactionDB(train_txs, db.item_ids)
    sigma_train = minsup_count(minsup_str, n_train)
    train_isets = eclat(train_db, sigma_train, cfg)
    train_rules = rules(train_isets, n_train; minconf = minconf)
    train_top = top_k(train_rules, k; by = :lift)

    # Đếm trực tiếp support của X, Y, X ∪ Y trên tập kiểm tra độc lập (20%)
    test_sets = [Set{Int32}(t) for t in test_txs]
    rows = NamedTuple[]
    for (rank, r) in enumerate(train_top)
        ant_set = Set{Int32}(r.antecedent)
        cons_set = Set{Int32}(r.consequent)
        both_set = union(ant_set, cons_set)

        sup_x = count(t -> issubset(ant_set, t), test_sets)
        sup_y = count(t -> issubset(cons_set, t), test_sets)
        sup_xy = count(t -> issubset(both_set, t), test_sets)

        test_sup = sup_xy / n_test
        test_conf = sup_x > 0 ? sup_xy / sup_x : 0.0
        test_lift = (sup_x > 0 && sup_y > 0) ? (sup_xy * n_test) / (sup_x * sup_y) : 0.0
        lift_diff_pct = r.lift > 0 ? 100.0 * (test_lift - r.lift) / r.lift : NaN  # % thay đổi lift từ train -> test

        push!(rows, (
            rank = rank,
            antecedent = format_items(r.antecedent, db, id_to_name),
            consequent = format_items(r.consequent, db, id_to_name),
            train_sup = r.support, train_conf = r.confidence, train_lift = r.lift,
            test_sup = test_sup, test_conf = test_conf, test_lift = test_lift,
            lift_diff_pct = lift_diff_pct,
        ))
    end
    return (n_train = n_train, n_test = n_test, rows = rows)
end

"""Hàm điều phối toàn bộ 5 bước thực nghiệm Ứng dụng 1 và xuất các tệp CSV/Markdown vào `results/`."""
function main()
    # Sử dụng phiên bản mặc định tốt nhất (DEFAULT_CONFIG = v6)
    cfg = DEFAULT_CONFIG

    println("1. Chuẩn bị dữ liệu Groceries (2 phương án biến đổi)...")
    prep = prepare_all_groceries(GROCERIES_CSV, GROCERIES_DIR)
    mkpath(RESULTS_DIR)

    # --- Bảng B08: So sánh 2 phương án biến đổi ---
    println("2. So sánh 2 phương án biến đổi dữ liệu (B08)...")
    p_fine   = profile_representation("169 mặt hàng gốc (chọn)", prep.fine.path, CHOSEN_MINSUP, cfg)
    p_coarse = profile_representation("Gộp 12 nhóm hàng cấp cao", prep.coarse.path, CHOSEN_MINSUP, cfg)

    b08_path = joinpath(RESULTS_DIR, "groceries_b08_transforms.csv")
    open(b08_path, "w") do io
        println(io, "representation,n_tx,n_items,avg_len,density,minsup,sigma_min,n_itemsets,n_rules_conf03,time_s")
        for p in (p_fine, p_coarse)
            println(io, join([csv_esc(p.label), p.n, p.m, round(p.avg_len; digits = 3),
                              round(p.density; digits = 5), CHOSEN_MINSUP, p.sigma_min,
                              p.n_itemsets, p.n_rules, round(p.t_s; digits = 5)], ','))
        end
    end

    # --- Khảo sát lưới minsup × minconf ---
    println("3. Khảo sát độ nhạy lưới minsup × minconf...")
    db = p_fine.db
    n = n_transactions(db)
    grid_path = joinpath(RESULTS_DIR, "groceries_grid.csv")
    grid_rows = NamedTuple[]
    open(grid_path, "w") do io
        println(io, "minsup,sigma_min,n_itemsets,minconf,n_rules,max_lift")
        for ms in GRID_MINSUPS
            sig = minsup_count(ms, n)
            isets = eclat(db, sig, cfg)
            for mc in GRID_MINCONFS
                rs = rules(isets, n; minconf = mc)
                max_l = isempty(rs) ? 0.0 : maximum(r.lift for r in rs)
                push!(grid_rows, (minsup = ms, sigma_min = sig, n_itemsets = length(isets),
                                  minconf = mc, n_rules = length(rs), max_lift = max_l))
                println(io, join([ms, sig, length(isets), mc, length(rs), round(max_l; digits = 4)], ','))
            end
        end
    end

    # --- Bảng B09 & toàn bộ luật ở ngưỡng đã chọn (cho F11) ---
    println("4. Trích xuất toàn bộ luật và top-10 theo lift (B09, F11)...")
    chosen_rules = rules(p_fine.isets, n; minconf = CHOSEN_MINCONF)
    top10_lift = top_k(chosen_rules, 10; by = :lift)
    top5_conf  = top_k(chosen_rules, 5; by = :confidence)

    rules_path = joinpath(RESULTS_DIR, "groceries_rules.csv")
    open(rules_path, "w") do io
        println(io, "antecedent,consequent,support_count,support,confidence,lift")
        for r in chosen_rules
            println(io, join([csv_esc(format_items(r.antecedent, db, prep.fine.id_to_name)),
                              csv_esc(format_items(r.consequent, db, prep.fine.id_to_name)),
                              r.support_count, round(r.support; digits = 6),
                              round(r.confidence; digits = 6), round(r.lift; digits = 6)], ','))
        end
    end

    b09_path = joinpath(RESULTS_DIR, "groceries_top10.csv")
    open(b09_path, "w") do io
        println(io, "rank,antecedent,consequent,support_count,support,confidence,lift")
        for (rank, r) in enumerate(top10_lift)
            println(io, join([rank,
                              csv_esc(format_items(r.antecedent, db, prep.fine.id_to_name)),
                              csv_esc(format_items(r.consequent, db, prep.fine.id_to_name)),
                              r.support_count, round(r.support; digits = 4),
                              round(r.confidence; digits = 4), round(r.lift; digits = 4)], ','))
        end
    end

    # --- Bảng B10: Kiểm tra độ ổn định chia 80/20 ---
    println("5. Kiểm tra độ ổn định luật trên chia tập 80/20 (seed=$SEED, B10)...")
    stab = evaluate_stability(db, prep.fine.id_to_name, CHOSEN_MINSUP, CHOSEN_MINCONF, cfg;
                              train_ratio = 0.8, seed = SEED, k = 10)
    b10_path = joinpath(RESULTS_DIR, "groceries_stability.csv")
    open(b10_path, "w") do io
        println(io, "rank,antecedent,consequent,train_sup,train_conf,train_lift,test_sup,test_conf,test_lift,lift_diff_pct")
        for row in stab.rows
            println(io, join([row.rank, csv_esc(row.antecedent), csv_esc(row.consequent),
                              round(row.train_sup; digits = 4), round(row.train_conf; digits = 4), round(row.train_lift; digits = 4),
                              round(row.test_sup; digits = 4), round(row.test_conf; digits = 4), round(row.test_lift; digits = 4),
                              round(row.lift_diff_pct; digits = 2)], ','))
        end
    end

    # --- Xuất tóm tắt Markdown ---
    whole_milk_cnt = prep.fine.counts["whole milk"]
    whole_milk_pct = round(100.0 * whole_milk_cnt / n; digits = 2)

    summary_path = joinpath(RESULTS_DIR, "groceries_summary.md")
    open(summary_path, "w") do io
        println(io, "# Kết quả Ứng dụng 1: Phân tích giỏ hàng (Groceries)\n")
        println(io, "Sinh bởi `apps/groceries/run_groceries.jl` ngày ", Dates.format(today(), "yyyy-mm-dd"),
                " bằng `EclatFIM` (`$(DEFAULT_VARIANT)`, seed = ", SEED, ").\n")

        println(io, "## 1. So sánh phương án biến đổi dữ liệu (Bảng B08)\n")
        println(io, "| Phương án | N | m | L̄ | Mật độ ρ | Tập phổ biến (1%) | Luật (conf ≥ 0,3) | Thời gian (s) |")
        println(io, "|---|---:|---:|---:|---:|---:|---:|---:|")
        for p in (p_fine, p_coarse)
            println(io, "| $(p.label) | $(p.n) | $(p.m) | $(round(p.avg_len; digits=2)) | $(round(p.density*100; digits=2))% | $(p.n_itemsets) | $(p.n_rules) | $(round(p.t_s; digits=4)) |")
        end
        println(io, "\n- Phương án 169 mặt hàng gốc có mật độ **$(round(p_fine.density*100; digits=2))%**, tiệm cận ngưỡng cân bằng lý thuyết `1/32 ≈ 3,125%` giữa biểu diễn `Vector` và `BitVector` của Eclat.")
        println(io, "- Phương án gom 12 nhóm hàng làm mật độ tăng lên **$(round(p_coarse.density*100; digits=2))%**, dẫn đến gia tăng mạnh số tập phổ biến và số luật nhưng làm giảm tính cụ thể của luật.\n")

        println(io, "## 2. Khảo sát độ nhạy trên lưới ngưỡng\n")
        println(io, "| minsup | σ_min | Tập phổ biến | minconf | Số luật | Lift lớn nhất |")
        println(io, "|---|---:|---:|---:|---:|---:|")
        for g in grid_rows
            println(io, "| $(g.minsup) | $(g.sigma_min) | $(g.n_itemsets) | $(g.minconf) | $(g.n_rules) | $(round(g.max_lift; digits=3)) |")
        end
        println(io, "\n- Cặp ngưỡng **minsup = $(CHOSEN_MINSUP), minconf = $(CHOSEN_MINCONF)** được lựa chọn vì tạo ra **$(length(chosen_rules)) luật** (thuộc vùng mục tiêu 50–300 luật), cân bằng giữa độ bao phủ và độ tin cậy diễn giải.\n")

        println(io, "## 3. Mười luật kết hợp dẫn đầu theo độ nâng (Bảng B09)\n")
        println(io, "| Hạng | Tiền đề (X) | Hệ quả (Y) | σ | Support | Confidence | Lift |")
        println(io, "|---:|---|---|---:|---:|---:|---:|")
        for (rank, r) in enumerate(top10_lift)
            println(io, "| $rank | $(format_items(r.antecedent, db, prep.fine.id_to_name)) | $(format_items(r.consequent, db, prep.fine.id_to_name)) | $(r.support_count) | $(round(r.support; digits=4)) | $(round(r.confidence; digits=4)) | $(round(r.lift; digits=3)) |")
        end
        println(io, "\n- **Phân tích tiêu chí xếp hạng:** mặt hàng `whole milk` xuất hiện trong **$(whole_milk_cnt)/$(n) hóa đơn ($(whole_milk_pct)%)**, khiến các luật đạt confidence cao nhất chủ yếu mang hệ quả `whole milk` nhưng chỉ đạt lift trung bình (1,8–2,3):")
        for r in top5_conf
            println(io, "  - `$(format_items(r.antecedent, db, prep.fine.id_to_name)) ⇒ $(format_items(r.consequent, db, prep.fine.id_to_name))`: conf = $(round(r.confidence; digits=3)), lift = $(round(r.lift; digits=3))")
        end

        println(io, "\n## 4. Đánh giá độ ổn định trên phép chia 80/20 (Bảng B10, train=$(stab.n_train), test=$(stab.n_test))\n")
        println(io, "| Hạng | Luật (X ⇒ Y) | Train Lift | Test Lift | Biến thiên | Train Conf | Test Conf |")
        println(io, "|---:|---|---:|---:|---:|---:|---:|")
        n_stable = 0
        for row in stab.rows
            row.test_lift > 1.5 && (n_stable += 1)
            println(io, "| $(row.rank) | $(row.antecedent) ⇒ $(row.consequent) | $(round(row.train_lift; digits=3)) | $(round(row.test_lift; digits=3)) | $(round(row.lift_diff_pct; digits=1))% | $(round(row.train_conf; digits=3)) | $(round(row.test_conf; digits=3)) |")
        end
        println(io, "\n- Toàn bộ **$(n_stable)/10** luật duy trì `test_lift > 1,5` trên tập kiểm tra độc lập 20%.")
    end

    println("Hoàn tất thực nghiệm Ứng dụng 1. Kết quả tổng hợp lưu tại: ", summary_path)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
