# E7: biểu diễn tidset theo mật độ (phần của A). Kiểm chứng giả thuyết H2:
#   bộ nhớ: tidset dạng vector tốn 4σ byte, dạng bitset tốn N/8 byte → bằng nhau khi ρ = σ/N = 1/32;
#   thời gian: phép giao vector tốn O(σ_a + σ_b) (có ngắt sớm, tìm kiếm nhảy), bitset tốn O(N/64)
#   bất kể support, nên điểm cân bằng về thời gian có thể khác 1/32.
#
#   julia --project=. scripts/bench_density.jl
#
# Hai nguồn điểm đo (cùng một tiến trình, đã khởi động, lấy thời gian nhỏ nhất trong 3 lần):
#   1. dữ liệu tổng hợp có mật độ điều khiển được: m = 30 item, N = 50.000 giao dịch, mỗi item có mặt
#      độc lập với xác suất p; σ = ⌈0,8·p²·N⌉ để tập 2 item phổ biến còn tập 3 item thì không;
#   2. dữ liệu thật: 4 bộ benchmark (mức cao, giữa, thấp của lưới minsup), Groceries và các phương án của
#      Ứng dụng 2 (nếu đã chạy). Mật độ x = support trung bình của item phổ biến / N.
# Kết quả: results/e7_density.csv, results/e7_density.md

using EclatFIM, Random, Statistics, Printf   # Random: dữ liệu tổng hợp có seed; Statistics: mean
include(joinpath(@__DIR__, "config_a.jl"))   # cấu hình của A

const RES = results_dir()   # thư mục ghi kết quả
const VARS = ["v2", "v3", "v4", "v6"]   # v3 (danh sách) và v4 (dãy bit) là hai phiên bản cần so; v2, v6 để tham khảo

"""Thời gian nhỏ nhất trong `reps` lần (đã chạy khởi động) và byte tidset đỉnh."""
function measure(db, σ, v; reps = 3, limit = 60.0)   # đo trong CÙNG tiến trình đã khởi động
    cfg = VARIANTS[v]   # cấu hình phiên bản
    st = EclatStats()   # bộ đếm cho lần chạy khởi động
    eclat!((i, s) -> nothing, db, σ, cfg; stats = st)               # khởi động + bộ đếm
    best = Inf   # thời gian nhỏ nhất
    for _ in 1:reps   # lặp 3 lần
        t = @elapsed eclat!((i, s) -> nothing, db, σ, cfg)   # đo thời gian khai thác, sink không làm gì
        best = min(best, t)   # lấy nhỏ nhất: ít nhiễu nhất khi so tương đối nhiều điểm
        t > limit && break                                           # quá lâu: không lặp thêm
    end
    return best, st.bytes_peak, st.n_itemsets   # thời gian, tidset đỉnh, số tập
end

function root_density(db, σ)   # mật độ ρ = support trung bình của item phổ biến / N
    supp = zeros(Int, n_items(db))   # support từng item
    for t in db.transactions, x in t   # quét dữ liệu
        supp[x] += 1   # đếm
    end
    f = filter(>=(σ), supp)   # chỉ item phổ biến
    return isempty(f) ? NaN : mean(f) / n_transactions(db)   # NaN nếu không có item phổ biến
end

const HEADER = ["source", "dataset", "minsup", "density", "n_itemsets", "t_v2", "t_v3", "t_v4", "t_v6",   # cột của e7_density.csv
                "bytes_v3", "bytes_v4"]   # (tiếp)

function record!(path, source, ds, ms, db, σ)   # đo một điểm (một CSDL ở một ngưỡng) và ghi CSV
    res = Dict(v => measure(db, σ, v) for v in VARS)   # đo 4 phiên bản
    ρ = root_density(db, σ)   # mật độ của điểm này (trục x của hình F08)
    append_csv(path, HEADER, [source, ds, ms, ρ, res["v6"][3], (res[v][1] for v in VARS)...,   # ghi một dòng
                              res["v3"][2], res["v4"][2]])   # bộ nhớ tidset đỉnh của v3, v4
    @printf("  %-10s %-12s %-7s ρ = %.4f  v3/v4 = %6.2f  bộ nhớ v3/v4 = %6.3f\n", source, ds, ms, ρ,   # in tiến độ
            res["v3"][1] / res["v4"][1], res["v3"][2] / max(res["v4"][2], 1))   # tỉ số > 1: dãy bit có lợi hơn
end

# [VẤN ĐÁP] E7 — dãy bit hay danh sách tid, theo mật độ
# LÀM GÌ    : so v3 (danh sách) với v4 (dãy bit) trên dữ liệu tổng hợp có mật độ điều khiển được và trên dữ liệu thật.
# BẰNG CHỨNG: điểm cân bằng BỘ NHỚ ρ ≈ 0,058 (lý thuyết 1/32 ≈ 0,031); điểm cân bằng THỜI GIAN ρ ≈ 0,004.
#             Dãy bit nhanh hơn 48 lần ở ρ = 0,4; danh sách chỉ thắng khi hầu hết phép giao trượt ngưỡng (retail 0,1%).
# HỎI–ĐÁP   : H: Vì sao điểm cân bằng thời gian thấp hơn 1/32 nhiều? Đ: một phép AND 64 bit rẻ hơn nhiều một bước trộn có
#             rẽ nhánh; danh sách chỉ thắng khi dừng sớm được (đa số phép giao trượt ngưỡng).
#             H: Vì sao đo trong cùng tiến trình mà không dùng tiến trình mới như E8? Đ: E7 so TƯƠNG ĐỐI hai phiên bản trên
#             nhiều điểm; cả hai đã khởi động, lấy thời gian nhỏ nhất trong 3 lần nên đủ ổn định cho tỉ số.
function main()   # chạy ba nguồn dữ liệu rồi tóm tắt
    path = joinpath(RES, "e7_density.csv")   # file kết quả
    isfile(path) && rm(path)   # đo lại từ đầu
    warm = TransactionDB([Int32[1, 2], Int32[2, 3], Int32[1, 2, 3]], [1, 2, 3])   # CSDL rất nhỏ để khởi động (biên dịch JIT)
    for v in VARS   # khởi động mọi phiên bản
        eclat(warm, 1, VARIANTS[v])   # chạy thử một lần
    end
    println("== Dữ liệu tổng hợp (mật độ điều khiển được)")   # nguồn 1
    for p in (0.003, 0.006, 0.01, 0.02, 0.03125, 0.05, 0.1, 0.2, 0.4)   # xác suất có mặt của mỗi item = mật độ mong muốn
        rng = MersenneTwister(SEED)   # seed 42: tái lập được
        N, m = 50_000, 30   # 50.000 giao dịch, 30 item
        db = TransactionDB([Int32[x for x in 1:m if rand(rng) < p] for _ in 1:N], collect(Int64, 1:m))   # mỗi item có mặt độc lập với xác suất p
        σ = max(1, ceil(Int, 0.8 * p^2 * N))   # support kỳ vọng của một cặp là p²N → cặp phổ biến, bộ ba thì không
        record!(path, "synthetic", "uniform_p$(p)", "sigma=$σ", db, σ)   # ghi điểm tổng hợp
    end
    println("== Dữ liệu thật")   # nguồn 2
    grid = load_grid()   # lưới minsup của Chương 2
    for (ds, _, _) in DATASETS   # 4 bộ benchmark
        isfile(dataset_path(ds)) && haskey(grid, ds) || continue   # bỏ bộ chưa có dữ liệu
        db = read_spmf(dataset_path(ds))   # đọc bộ dữ liệu
        for ms in unique([grid[ds][1], median_minsup(grid[ds]), grid[ds][end]])   # mức cao, giữa, thấp
            record!(path, "benchmark", ds, ms, db, minsup_count(parse_minsup(ms), n_transactions(db)))   # ghi điểm benchmark
        end
    end
    gpath = rootpath("data", "apps", "groceries", "groceries.txt")   # Groceries (nếu đã chuyển sang định dạng SPMF)
    if isfile(gpath)   # không có thì bỏ qua
        db = read_spmf(gpath)   # đọc Groceries
        for ms in ("2%", "1%", "0.5%")   # ba mức minsup
            record!(path, "application1", "groceries", ms, db, minsup_count(parse_minsup(ms), n_transactions(db)))   # ghi điểm Ứng dụng 1
        end
    end
    txdir = rootpath("data", "apps", "caltech101", "transactions")   # giao dịch ảnh do apps/bovw/analyze.jl ghi ra
    for f in (isdir(txdir) ? sort(readdir(txdir; join = true)) : String[])   # 12 phương án biến đổi ảnh
        endswith(f, ".txt") || continue   # chỉ file giao dịch
        db = read_spmf(f)   # đọc phương án
        record!(path, "application2", replace(basename(f), ".txt" => ""), "30%", db,   # ghi điểm Ứng dụng 2
                minsup_count(parse_minsup("30%"), n_transactions(db)))   # minsup 30% như trong Ứng dụng 2
    end
    summarize(path)   # viết bảng tóm tắt e7_density.md
end

"""Ước lượng điểm cân bằng (tỉ số = 1) trên dữ liệu tổng hợp bằng nội suy tuyến tính trên thang log."""
function crossing(xs, ys)   # tìm x tại đó tỉ số y = 1 (điểm cân bằng)
    for i in 1:length(xs)-1   # xét từng đoạn giữa hai điểm liên tiếp
        if (ys[i] - 1) * (ys[i+1] - 1) <= 0   # tỉ số đi qua 1 trong đoạn này
            lx1, lx2 = log(xs[i]), log(xs[i+1])   # nội suy trên thang log (hình F08 dùng trục log)
            ly1, ly2 = log(ys[i]), log(ys[i+1])   # (tiếp)
            return exp(lx1 + (0 - ly1) * (lx2 - lx1) / (ly2 - ly1))   # log(y) = 0 ⇔ y = 1
        end
    end
    return NaN   # không đi qua 1
end

function summarize(path)   # bảng Markdown + điểm cân bằng thời gian và bộ nhớ
    lines = collect(eachline(path))   # đọc CSV
    header = split(lines[1], ",")   # tên cột
    rows = [Dict(zip(header, split(l, ","))) for l in lines[2:end]]   # mỗi dòng → Dict
    syn = [r for r in rows if r["source"] == "synthetic"]   # chỉ dữ liệu tổng hợp để ước lượng điểm cân bằng
    xs = [parse(Float64, r["density"]) for r in syn]   # mật độ
    tr = [parse(Float64, r["t_v3"]) / parse(Float64, r["t_v4"]) for r in syn]   # tỉ số thời gian danh sách / dãy bit
    mr = [parse(Float64, r["bytes_v3"]) / parse(Float64, r["bytes_v4"]) for r in syn]   # tỉ số bộ nhớ
    io = IOBuffer()   # bộ đệm chuỗi để ghép bảng
    println(io, "# E7: tidset representation versus density (hypothesis H2)\n")   # tiêu đề
    println(io, "Generated by `scripts/bench_density.jl`. A ratio > 1 means the bitset (v4) beats the vector (v3).\n")   # cách đọc bảng
    println(io, "| Source | Dataset | minsup | Density ρ | Time v3 / v4 | Tidset memory v3 / v4 | Hybrid v6 vs. best of v3, v4 |")   # tiêu đề cột
    println(io, "|---|---|---|---|---|---|---|")   # đường kẻ
    for r in rows   # mỗi điểm đo
        t3, t4, t6 = parse(Float64, r["t_v3"]), parse(Float64, r["t_v4"]), parse(Float64, r["t_v6"])   # thời gian ba phiên bản
        @printf(io, "| %s | %s | %s | %.4f | %.2f | %.3f | %.2f× |\n", r["source"], r["dataset"], r["minsup"],   # một hàng
                parse(Float64, r["density"]), t3 / t4, parse(Float64, r["bytes_v3"]) / max(parse(Float64, r["bytes_v4"]), 1),   # tỉ số thời gian, tỉ số bộ nhớ
                t6 / min(t3, t4))   # v6 so với phiên bản nhanh hơn trong v3, v4 (< 1: v6 nhanh hơn cả hai)
    end
    println(io, "\n**Estimated break-even density on synthetic data:** time ρ ≈ ",   # điểm cân bằng
            @sprintf("%.4f", crossing(xs, tr)), "; memory ρ ≈ ", @sprintf("%.4f", crossing(xs, mr)),   # thời gian; bộ nhớ
            " (theory: 1/32 = 0.03125).")   # so với lý thuyết
    write(joinpath(RES, "e7_density.md"), String(take!(io)))   # lưu bảng
    println(read(joinpath(RES, "e7_density.md"), String))   # in bảng
end

let t0 = time()   # đo tổng thời gian
    main()   # chạy
    log_run("scripts/bench_density.jl", ARGS, time() - t0)   # ghi results/LOG.md
end
