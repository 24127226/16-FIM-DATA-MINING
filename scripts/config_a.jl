# Cấu hình dùng chung cho các script thực nghiệm của A: E7 (bench_density.jl), E8 (bench_ablation.jl),
# E10 (bench_memory_trace.jl) và hình F08, F10 (plots_a.jl).
#
# Vì sao có file riêng: config.jl của B (Cường) phục vụ run_chapter2.jl/bench.jl với tên hằng số khác.
# Hai file cùng định nghĩa SEED nên không thể include cả hai trong một script; các script của A chỉ
# include file này. Lưới minsup vẫn đọc từ CÙNG file results/minsup_grid.csv mà B đã chốt, để E7/E8/E10
# đo tại đúng các mức minsup của Chương 2.

include(joinpath(@__DIR__, "common.jl"))      # của B: ROOT, rootpath, run_with_timeout, run_spmf, ...

"""Seed cố định cho mọi phần ngẫu nhiên (dữ liệu tổng hợp của E7)."""
const SEED = 42                                # cùng giá trị với config.jl của B

"""Bốn bộ benchmark của Chương 2: tên → (đường dẫn tương đối, loại dữ liệu)."""
const DATASETS = [                             # cùng danh sách với BENCHMARK_DATASETS của B
    ("chess", "data/benchmark/chess.txt", "dense"),   # dày, 3.196 giao dịch, 75 item
    ("mushroom", "data/benchmark/mushroom.txt", "dense"),   # dày, 8.124 giao dịch
    ("retail", "data/benchmark/retail.txt", "sparse"),   # thưa, 88.162 giao dịch, 16.470 item
    ("T10I4D100K", "data/benchmark/T10I4D100K.txt", "sparse"),   # thưa, tổng hợp IBM, 100.000 giao dịch
]
dataset_path(name) = rootpath(only(d[2] for d in DATASETS if d[1] == name))   # tên bộ → đường dẫn tuyệt đối
dataset_kind(name) = only(d[3] for d in DATASETS if d[1] == name)             # tên bộ → "dense"/"sparse"

# [VẤN ĐÁP] config_a.jl
# HỎI–ĐÁP   : H: Vì sao A có file cấu hình riêng mà không dùng config.jl của B? Đ: hai file cùng định nghĩa hằng SEED nên
#             không include chung được; nhưng lưới minsup vẫn đọc từ CÙNG file results/minsup_grid.csv, nên E7, E8, E10
#             đo đúng các mức minsup của Chương 2.
"""
    load_grid() -> Dict{String,Vector{String}}

Đọc lưới minsup 7 mức (giảm dần) của từng bộ từ `results/minsup_grid.csv` (định dạng của B: mỗi dòng
`dataset,minsup`, các mức của một bộ nằm liên tiếp theo thứ tự giảm dần).
"""
function load_grid()   # đọc lưới minsup của Chương 2
    path = rootpath("results", "minsup_grid.csv")   # file lưới do B chốt
    grid = Dict{String,Vector{String}}()       # tên bộ → danh sách mức minsup theo thứ tự trong file
    isfile(path) || return grid                # chưa có lưới: trả về rỗng, script sẽ bỏ qua bộ đó
    for line in Iterators.drop(eachline(path), 1)          # bỏ dòng tiêu đề "dataset,minsup"
        s = strip(line)   # bỏ khoảng trắng hai đầu
        isempty(s) && continue                 # bỏ dòng trống
        ds, ms = strip.(split(s, ","; limit = 2))          # tách tên bộ và mức minsup
        push!(get!(grid, String(ds), String[]), String(ms))  # nối mức vào danh sách của bộ đó
    end
    return grid   # tên bộ → 7 mức minsup
end

"""Mức minsup ở giữa lưới (mức thứ 4 trong 7 mức), dùng cho E8, E10 như E4 của B."""
median_minsup(levels::Vector{String}) = levels[cld(length(levels), 2)]   # cld(7, 2) = 4: mức thứ 4

"""Thư mục ghi kết quả. Notebook có thể đặt biến môi trường FIM_RESULTS_DIR để không ghi đè số liệu chính thức."""
results_dir() = get(ENV, "FIM_RESULTS_DIR", rootpath("results"))   # mặc định results/

const REPEATS = 3               # số lần lặp mỗi phép đo thời gian (lấy trung vị), như giao thức của B
const REPEATS_SHORT = 5         # số lần lặp khi một lần chạy < 1 giây (đo ngắn dao động nhiều hơn)
const TIMEOUT_S = 600           # giới hạn mỗi lần chạy (giây)

"""Commit, tên máy, thời điểm: ghi vào mọi dòng CSV để truy ngược được số liệu."""
function provenance()   # nguồn gốc số liệu
    commit = try   # commit hiện tại của repo
        strip(read(pipeline(`git -C $(ROOT) rev-parse --short HEAD`; stderr = devnull), String))   # mã commit rút gọn
    catch
        "nogit"                                # chạy ngoài repo git (ví dụ bản giải nén)
    end
    machine = replace(gethostname(), "," => "_")   # bỏ dấu phẩy để không làm hỏng CSV
    return (commit = commit, machine = machine, date = string(round(Int, time())))   # thời điểm: giây kể từ 1970
end

"""Thêm một dòng vào file CSV; tạo file và dòng tiêu đề nếu chưa có."""
function append_csv(path::AbstractString, header::Vector{String}, row::Vector)   # ghi nối một dòng CSV
    mkpath(dirname(path))   # tạo thư mục nếu chưa có
    newfile = !isfile(path)   # file mới thì cần dòng tiêu đề
    open(path, "a") do io   # mở để ghi nối
        newfile && println(io, join(header, ","))                      # dòng tiêu đề, chỉ khi tạo file mới
        println(io, join(replace.(string.(row), "," => ";"), ","))      # thay dấu phẩy trong ô bằng chấm phẩy
    end
end

"""
Ghi một dòng vào `results/LOG.md` theo đúng định dạng 4 cột của B (Ngày | Commit | Lệnh | Ghi chú),
để mọi file CSV trong results/ truy ngược được lệnh đã sinh ra nó.
"""
function log_run(script::AbstractString, args, seconds::Real; project::AbstractString = ".")   # ghi nhật ký lần chạy
    path = joinpath(results_dir(), "LOG.md")   # nhật ký chung của nhóm
    p = provenance()   # commit, máy, thời điểm
    cmd = strip("julia --project=$(project) " * script * " " * join(args, " "))   # lệnh đã chạy
    open(path, "a") do io   # mở để ghi nối
        println(io, "| ", Libc.strftime("%Y-%m-%d %H:%M", time()), " | `", p.commit, "` | `", cmd, "` | ",   # một dòng bảng Markdown
                round(seconds / 60; digits = 1), " min, machine ", p.machine, " (results/ENV_A.md) |")   # thời gian chạy (phút), tên máy
    end
end
