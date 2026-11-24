# Cấu hình chung cho các script thực nghiệm (phần của B, KE_HOACH_DU_AN.md mục 8).

const SEED = 42

const BENCHMARK_DIR = joinpath(@__DIR__, "..", "data", "benchmark")
const SYNTHETIC_DIR = joinpath(@__DIR__, "..", "data", "synthetic")
const SUBSETS_DIR   = joinpath(@__DIR__, "..", "data", "subsets")
const RESULTS_DIR   = joinpath(@__DIR__, "..", "results")
const FIGURES_DIR   = joinpath(RESULTS_DIR, "figures")

const BENCHMARK_DATASETS = [
    (name = "chess",      path = joinpath(BENCHMARK_DIR, "chess.txt"),      kind = :dense),
    (name = "mushroom",   path = joinpath(BENCHMARK_DIR, "mushroom.txt"),   kind = :dense),
    (name = "retail",     path = joinpath(BENCHMARK_DIR, "retail.txt"),     kind = :sparse),
    (name = "T10I4D100K", path = joinpath(BENCHMARK_DIR, "T10I4D100K.txt"), kind = :sparse),
]

# Các mức tỉ lệ lấy mẫu lồng nhau cho E5 (Scalability)
const SUBSAMPLE_FRACS = [0.10, 0.25, 0.50, 0.75, 1.00]

# Tham số bộ sinh dữ liệu tổng hợp cho E6 (Độ dài giao dịch trung bình)
const SYNTHETIC_N        = 50_000
const SYNTHETIC_M        = 1_000
const SYNTHETIC_PATTERNS = 500
const SYNTHETIC_PAT_LEN  = 4.0
const SYNTHETIC_AVG_LENS = [5, 10, 15, 20, 25, 30]

# Lưới minsup khởi điểm (7 mức giảm dần theo thang log gần đều; sẽ chốt chính thức ở Tuần 4
# vào `results/minsup_grid.csv` sau khi đo thử thời gian trên máy đo chính thức).
const DEFAULT_MINSUP_GRID = Dict{String,Vector{String}}(
    "chess"      => ["95%", "90%", "85%", "80%", "75%", "70%", "65%"],
    "mushroom"   => ["70%", "55%", "45%", "35%", "28%", "22%", "18%"],
    "retail"     => ["10%", "5%", "2%", "1%", "0.5%", "0.2%", "0.1%"],
    "T10I4D100K" => ["5%", "3%", "2%", "1%", "0.5%", "0.3%", "0.2%"],
)

# Giới hạn thời gian (giây) cho mỗi lần chạy (mục 8.5)
const BENCH_TIMEOUT_S = 600
const SPMF_XMX        = "8g"

"""Đọc lưới minsup từ `results/minsup_grid.csv` nếu đã chốt, ngược lại dùng `DEFAULT_MINSUP_GRID`."""
function load_minsup_grid()
    grid_path = joinpath(RESULTS_DIR, "minsup_grid.csv")
    if !isfile(grid_path)
        return DEFAULT_MINSUP_GRID
    end
    grid = Dict{String,Vector{String}}()
    open(grid_path, "r") do io
        first_line = true
        for line in eachline(io)
            s = strip(line)
            isempty(s) && continue
            if first_line
                first_line = false
                continue
            end
            parts = split(s, ',')
            length(parts) >= 2 || continue
            ds = strip(parts[1])
            ms = strip(parts[2])
            push!(get!(grid, ds, String[]), ms)
        end
    end
    return isempty(grid) ? DEFAULT_MINSUP_GRID : grid
end
