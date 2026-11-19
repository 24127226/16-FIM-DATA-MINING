# In thống kê của 5 bộ benchmark (đo lại trên file đã tải) cạnh bảng trong đề bài, để kiểm tra dữ liệu.
#
#   julia --project=. scripts/data_stats.jl
#
# N: số giao dịch; m: số item phân biệt; L̄: độ dài giao dịch trung bình; mật độ = L̄ / m.

using EclatFIM, Printf
include(joinpath(@__DIR__, "config.jl"))

# Bảng trong đề bài (N, m, L̄). Đề ghi số item của Retail là "16.47"; số đúng là 16.470.
const DE_BAI = Dict("chess" => (3196, 75, 37.0), "mushroom" => (8124, 119, 23.0), "accidents" => (340183, 468, 33.8),
                    "retail" => (88162, 16470, 10.3), "T10I4D100K" => (100000, 870, 10.1))

function main()
    @printf("%-11s %17s %15s %13s %8s  %s\n", "Bộ", "N (đo / đề)", "m (đo / đề)", "L̄ (đo / đề)", "Mật độ", "Khớp đề?")
    for (ds, _, kind) in DATASETS
        path = dataset_path(ds)
        if !isfile(path)
            println(rpad(ds, 11), " chưa tải: julia --project=. scripts/fetch_data.jl benchmark")
            continue
        end
        db = read_spmf(path)
        N, m = n_transactions(db), n_items(db)
        L = sum(length, db.transactions) / N
        dN, dm, dL = DE_BAI[ds]
        ok = N == dN && m == dm && abs(L - dL) < 0.05
        @printf("%-11s %8d / %-7d %7d / %-6d %6.2f / %-5.1f %7.2f%%  %s (%s)\n", ds, N, dN, m, dm, L, dL, 100L / m,
                ok ? "✓" : "✗", kind)
    end
end

main()
