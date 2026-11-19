# Cấu hình dùng chung cho các thí nghiệm (KE_HOACH_DU_AN.md, mục 8).
# Mọi tham số ảnh hưởng đến số liệu trong báo cáo nằm ở đây, để tái lập được.

include(joinpath(@__DIR__, "common.jl"))

"""Seed cố định cho mọi phần ngẫu nhiên (lấy mẫu con, dữ liệu tổng hợp, k-means...)."""
const SEED = 42

"""Các bộ benchmark: tên → (đường dẫn, loại)."""
const DATASETS = [
    ("chess", "data/benchmark/chess.txt", "dày"),
    ("mushroom", "data/benchmark/mushroom.txt", "dày"),
    ("accidents", "data/benchmark/accidents.txt", "dày"),
    ("retail", "data/benchmark/retail.txt", "thưa"),
    ("T10I4D100K", "data/benchmark/T10I4D100K.txt", "thưa"),
]
dataset_path(name) = rootpath(only(d[2] for d in DATASETS if d[1] == name))
dataset_kind(name) = only(d[3] for d in DATASETS if d[1] == name)

"""
Lưới minsup (7 mức, giảm dần) cho từng bộ, đọc từ results/minsup_grid.csv
(chọn bằng chạy thử theo quy tắc ở mục 8.2 của kế hoạch). "Minsup trung bình" = mức thứ 4.
"""
function load_grid()
    path = rootpath("results", "minsup_grid.csv")
    grid = Dict{String,Vector{String}}()
    isfile(path) || return grid
    for line in Iterators.drop(eachline(path), 1)
        isempty(strip(line)) && continue
        name, levels = split(line, ",", limit = 2)
        grid[name] = String.(strip.(split(levels, ";")))
    end
    return grid
end
median_minsup(levels::Vector{String}) = levels[cld(length(levels), 2)]

"""Phiên bản mặc định của nhóm (DEFAULT_VARIANT, dùng ở CLI và E2, E4, E5, E6). Script gọi hàm này phải `using EclatFIM`."""
best_variant() = DEFAULT_VARIANT

"""Các phiên bản đã được cài đặt ở mốc hiện tại (check_config không báo lỗi)."""
function implemented_variants()
    [v for v in VARIANT_NAMES if (try
        EclatFIM.check_config(VARIANTS[v]); true
    catch
        false
    end)]
end

"""
Thư mục ghi kết quả thực nghiệm. Mặc định results/; notebook Colab ở chế độ nhanh đặt biến môi trường
FIM_RESULTS_DIR sang thư mục khác để không ghi chồng lên số liệu chính thức đã lưu trong repo.
"""
results_dir() = get(ENV, "FIM_RESULTS_DIR", rootpath("results"))

const REPEATS = 3               # số lần lặp mỗi phép đo (lấy trung vị)
const REPEATS_SHORT = 5         # số lần lặp khi một lần chạy < 1 giây
const TIMEOUT_S = 600           # giới hạn mỗi lần chạy (giây); quá thì ghi "timeout"
const JAVA_XMX = "8g"           # heap cố định cho SPMF ở mọi lần đo

"""Thông tin để mọi dòng CSV truy ngược được (commit, máy, ngày)."""
function provenance()
    commit = try
        strip(read(pipeline(`git -C $(ROOT) rev-parse --short HEAD`; stderr = devnull), String))
    catch
        "nogit"
    end
    machine = replace(gethostname(), "," => "_")
    return (commit = commit, machine = machine, date = string(round(Int, time())))
end

"""Thêm một dòng vào file CSV (tạo file và dòng tiêu đề nếu chưa có)."""
function append_csv(path::AbstractString, header::Vector{String}, row::Vector)
    mkpath(dirname(path))
    newfile = !isfile(path)
    open(path, "a") do io
        newfile && println(io, join(header, ","))
        println(io, join(replace.(string.(row), "," => ";"), ","))
    end
end

"""
Ghi một dòng vào results/LOG.md sau mỗi lần chạy script thực nghiệm (giao thức đo, KE_HOACH_DU_AN.md mục 8.5
bước 11): thời điểm, commit, máy, lệnh và thời gian chạy. Nhờ vậy biết mỗi CSV được sinh bởi lệnh nào.
"""
function log_run(script::AbstractString, args, seconds::Real)
    path = joinpath(results_dir(), "LOG.md")
    newfile = !isfile(path)
    p = provenance()
    mkpath(dirname(path))
    open(path, "a") do io
        if newfile
            println(io, "# Nhật ký các lần chạy thực nghiệm
")
            println(io, "Mỗi script thực nghiệm tự ghi thêm một dòng khi chạy xong (KE_HOACH_DU_AN.md mục 8.5, bước 11).")
            println(io, "Cấu hình máy: `results/ENV.md`.
")
            println(io, "| Thời điểm | Commit | Máy | Lệnh | Thời gian chạy |")
            println(io, "|---|---|---|---|---|")
        end
        cmd = strip("julia --project=. " * script * " " * join(args, " "))
        println(io, "| ", Libc.strftime("%Y-%m-%d %H:%M", time()), " | ", p.commit, " | ", p.machine, " | `", cmd,
                "` | ", round(seconds / 60; digits = 1), " phút |")
    end
end
