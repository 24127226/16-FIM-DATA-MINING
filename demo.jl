# Giao diện dòng lệnh (CLI) cho gói EclatFIM.
#
# Cú pháp:
#   julia --project=. demo.jl [tùy chọn] --minsup <ngưỡng> <file_input>
#
# Mã thoát chuẩn:
#   0  thực thi thành công
#   1  lỗi tham số dòng lệnh
#   2  lỗi đọc/định dạng dữ liệu hoặc ghi tệp đầu ra

using EclatFIM

# Chuỗi hướng dẫn sử dụng in ra khi người dùng gọi `-h`/`--help` hoặc truyền sai tham số
const USAGE = """
Cách dùng:
  julia --project=. demo.jl [tùy chọn] --minsup <ngưỡng> <file_input>

Tùy chọn:
  --minsup <giá trị>     Bắt buộc; tỉ lệ trong (0, 1] (vd: 0.01) hoặc phần trăm (vd: 1%)
  -o, --output <file>    File output chuẩn SPMF (mặc định: output.txt; dùng "-" để in ra stdout)
  --variant <v0..v6>     Phiên bản Eclat (mặc định: $(DEFAULT_VARIANT))
  --stats                In thêm bộ đếm nội bộ (không bật khi đo thời gian)
  -h, --help             Hiển thị hướng dẫn này

Ví dụ:
  julia --project=. demo.jl --minsup 0.4 data/toy/pasquier99.txt
  julia --project=. demo.jl --minsup 40% -o - data/toy/pasquier99.txt
"""

"""Mục đích cấu trúc: Gom toàn bộ tham số dòng lệnh đã được kiểm tra hợp lệ để truyền vào `run_cli`."""
struct CLIOptions
    input_path::String                                       # Đường dẫn tệp dữ liệu SPMF đầu vào
    minsup_str::String                                       # Chuỗi minsup gốc người dùng nhập (để in tóm tắt)
    minsup::Float64                                          # Giá trị minsup đã quy đổi về (0, 1]
    output_path::String                                      # Đường dẫn tệp kết quả (hoặc "-" nếu in ra stdout)
    variant::String                                          # Tên biến thể ("v0".."v6")
    cfg::EclatConfig                                         # Đối tượng cấu hình Eclat tương ứng với biến thể
    show_stats::Bool                                         # Cờ bật/tắt in bộ đếm nội bộ EclatStats
end

"""Mục đích cấu trúc: Ngoại lệ riêng cho lỗi cú pháp tham số dòng lệnh (trả về mã thoát 1)."""
struct CLIError <: Exception
    msg::String
end

"""
    parse_cli(args::Vector{String}) -> Union{Symbol, CLIOptions}

Mục đích hàm: Phân tích danh sách đối số dòng lệnh `ARGS` mà không cần thư viện ngoài.
Trả về `:help` nếu có cờ `-h`/`--help`, trả về `CLIOptions` nếu hợp lệ, hoặc ném `CLIError` nếu sai.
"""
function parse_cli(args::Vector{String})
    minsup_str = nothing                                     # Tham số bắt buộc, khởi tạo nothing để kiểm tra thiếu
    output_path = "output.txt"                               # Đường dẫn đầu ra mặc định
    variant = DEFAULT_VARIANT                                # Biến thể mặc định (v6 - hybrid)
    show_stats = false                                       # Mặc định tắt bộ đếm nội bộ để không ảnh hưởng tốc độ
    positionals = String[]                                   # Danh sách tham số vị trí (chứa đường dẫn tệp đầu vào)

    i = 1                                                    # Chỉ số duyệt qua mảng đối số `args`
    n = length(args)
    while i <= n
        arg = args[i]
        if arg == "-h" || arg == "--help"                    # Yêu cầu hiển thị trợ giúp -> thoát sớm trả `:help`
            return :help
        elseif arg == "--stats"                              # Bật chế độ thống kê bộ đếm nội bộ
            show_stats = true
            i += 1
        elseif arg == "--minsup"                             # Dạng tách 2 đối số: --minsup 0.01
            i + 1 <= n || throw(CLIError("Thiếu giá trị cho --minsup"))
            minsup_str = args[i + 1]
            i += 2
        elseif startswith(arg, "--minsup=")                  # Dạng gộp dấu '=': --minsup=0.01
            minsup_str = arg[length("--minsup=")+1:end]
            i += 1
        elseif arg == "-o" || arg == "--output"              # Dạng tách 2 đối số: -o out.txt
            i + 1 <= n || throw(CLIError("Thiếu đường dẫn cho $arg"))
            output_path = args[i + 1]
            i += 2
        elseif startswith(arg, "--output=")                  # Dạng gộp dấu '=': --output=out.txt
            output_path = arg[length("--output=")+1:end]
            i += 1
        elseif arg == "--variant"                            # Dạng tách 2 đối số: --variant v6
            i + 1 <= n || throw(CLIError("Thiếu tên phiên bản cho --variant"))
            variant = args[i + 1]
            i += 2
        elseif startswith(arg, "--variant=")                 # Dạng gộp dấu '=': --variant=v6
            variant = arg[length("--variant=")+1:end]
            i += 1
        elseif startswith(arg, "-") && arg != "-"            # Cờ lạ bắt đầu bằng '-' (nhưng không phải "-" của stdout)
            throw(CLIError("Tùy chọn không hợp lệ: $arg"))
        else                                                 # Tham số vị trí -> lưu làm đường dẫn tệp đầu vào
            push!(positionals, arg)
            i += 1
        end
    end

    # Kiểm tra các ràng buộc bắt buộc sau khi duyệt hết đối số
    minsup_str === nothing && throw(CLIError("Thiếu tham số bắt buộc --minsup"))
    isempty(positionals) && throw(CLIError("Thiếu đường dẫn <file_input>"))
    length(positionals) > 1 && throw(CLIError("Chỉ nhận một <file_input>, nhận được: $(join(positionals, ", "))"))

    minsup = try                                             # Kiểm tra và quy đổi chuỗi minsup sang Float64
        parse_minsup(minsup_str)
    catch err
        throw(CLIError(sprint(showerror, err)))
    end

    haskey(VARIANTS, variant) || throw(CLIError(             # Kiểm tra tên biến thể có nằm trong v0..v6 không
        "Phiên bản '$variant' không hợp lệ. Chọn trong: $(join(VARIANT_NAMES, ", "))"))
    cfg = VARIANTS[variant]                                  # Lấy cấu hình EclatConfig tương ứng

    try                                                      # Kiểm tra cấu hình biến thể hợp lệ trên bản cài đặt hiện tại
        EclatFIM.check_config(cfg)
    catch err
        throw(CLIError("Phiên bản '$variant' chưa được cài đặt ở bản code hiện tại: $(sprint(showerror, err))"))
    end

    return CLIOptions(positionals[1], minsup_str, minsup, output_path, variant, cfg, show_stats)
end

"""Mục đích hàm: Định dạng số giây làm tròn 4 chữ số thập phân để in báo cáo gọn đẹp."""
fmt_s(sec::Float64) = string(round(sec; digits = 4), " s")

"""
    run_cli(opts::CLIOptions) -> Int

Mục đích hàm: Thực thi trọn vẹn chương trình dòng lệnh theo 2 pha tách biệt:
- Pha 1: Đọc dữ liệu SPMF (`read_spmf`) và quy đổi `σ_min`.
- Pha 2: Khai thác bằng `eclat!` và xuất luồng trực tiếp qua `SPMFWriter` (ra tệp hoặc `stdout`),
  sau đó in bảng tóm tắt thời gian và bộ đếm nội bộ `EclatStats` (nếu bật `--stats`).
"""
function run_cli(opts::CLIOptions)
    # Pha 1: Đọc tệp giao dịch và đo thời gian đọc riêng biệt
    t_read_0 = time_ns()
    db = try
        read_spmf(opts.input_path)                           # Đọc tệp SPMF cấp byte
    catch err
        println(stderr, "Lỗi dữ liệu: ", sprint(showerror, err))
        return 2                                             # Mã thoát 2: lỗi dữ liệu / I/O
    end
    t_read_s = (time_ns() - t_read_0) / 1e9                  # Quy đổi nanosecond sang giây

    n_tx = n_transactions(db)                                # Tổng số giao dịch N
    sigma_min = minsup_count(opts.minsup, n_tx)              # Ngưỡng đếm tối thiểu σ_min = ceil(minsup * N)
    stats = opts.show_stats ? EclatStats() : nothing         # Chỉ cấp phát EclatStats khi người dùng bật --stats
    n_found = 0                                              # Đếm số tập phổ biến tìm được

    # Pha 2: Khai thác Eclat và xuất luồng kết quả qua SPMFWriter có bộ đệm 1 MiB
    t_mine_0 = time_ns()
    try
        if opts.output_path == "-"                           # Trường hợp xuất trực tiếp ra màn hình (stdout)
            w = SPMFWriter(stdout, db)
            if n_tx > 0
                eclat!((items, supp) -> write_itemset!(w, items, supp), # Hàm callback ghi từng tập ngay khi tìm thấy
                       db, sigma_min, opts.cfg; stats = stats)
            end
            close_writer!(w)                                 # Xả nốt dữ liệu còn trong bộ đệm ra stdout
            n_found = w.count
        else                                                 # Trường hợp xuất ra tệp trên đĩa
            dir = dirname(opts.output_path)
            !isempty(dir) && mkpath(dir)                     # Tự động tạo thư mục cha nếu chưa tồn tại
            open(opts.output_path, "w") do io
                w = SPMFWriter(io, db)
                if n_tx > 0
                    eclat!((items, supp) -> write_itemset!(w, items, supp),
                           db, sigma_min, opts.cfg; stats = stats)
                end
                close_writer!(w)                             # Xả nốt bộ đệm trước khi đóng tệp
                n_found = w.count
            end
        end
    catch err
        println(stderr, "Lỗi khi khai thác/ghi output: ", sprint(showerror, err))
        return 2                                             # Mã thoát 2: lỗi khi khai thác hoặc ghi tệp
    end
    t_mine_write_s = (time_ns() - t_mine_0) / 1e9            # Thời gian khai thác + ghi đĩa

    # Nếu kết quả SPMF đang in ra stdout ("-") thì đẩy bảng tóm tắt sang stderr để không làm bẩn output SPMF
    summary_io = opts.output_path == "-" ? stderr : stdout
    println(summary_io, "=== EclatFIM ($(opts.variant)) ===")
    println(summary_io, "  Input        : ", opts.input_path)
    println(summary_io, "  Giao dịch (N): ", n_tx, " (m = ", n_items(db), " item)")
    println(summary_io, "  Minsup       : ", opts.minsup_str, " (σ_min = ", sigma_min, ")")
    println(summary_io, "  Số tập phổ biến: ", n_found)
    println(summary_io, "  Thời gian đọc: ", fmt_s(t_read_s))
    println(summary_io, "  Khai thác+ghi: ", fmt_s(t_mine_write_s))
    println(summary_io, "  Tổng thời gian: ", fmt_s(t_read_s + t_mine_write_s))
    println(summary_io, "  Output       : ", opts.output_path == "-" ? "stdout" : opts.output_path)

    if stats !== nothing                                     # In thêm bộ đếm nội bộ nếu người dùng truyền --stats
        println(summary_io, "--- Bộ đếm nội bộ (EclatStats) ---")
        println(summary_io, "  Số phép giao : ", stats.n_intersections, " (không đạt ngưỡng: ", stats.n_failed, ")")
        println(summary_io, "  Số lớp con   : ", stats.n_classes)
        println(summary_io, "  Độ sâu tối đa: ", stats.max_depth)
        println(summary_io, "  Tidset đỉnh  : ", stats.bytes_peak, " bytes")
        println(summary_io, "  Thời gian mức 2: ", fmt_s(stats.time_level2_ns / 1e9))
    end

    return 0                                                 # Mã thoát 0: thành công
end

"""Mục đích hàm: Điểm vào chính của CLI — phân tích đối số, bắt lỗi tham số (mã 1) và gọi `run_cli`."""
function main(args::Vector{String})
    parsed = try
        parse_cli(args)                                      # Phân tích đối số dòng lệnh
    catch err
        if err isa CLIError                                  # Lỗi do người dùng nhập sai cờ/thiếu tham số
            println(stderr, "Lỗi tham số: ", err.msg)
            println(stderr, "\n", USAGE)
            return 1                                         # Mã thoát 1: lỗi tham số
        end
        rethrow()                                            # Ném tiếp nếu là lỗi không mong đợi khác
    end

    if parsed === :help                                      # Người dùng yêu cầu xem hướng dẫn
        print(stdout, USAGE)
        return 0
    end

    return run_cli(parsed)                                   # Chạy khai thác Eclat và trả về mã thoát tương ứng
end

# Chỉ chạy `main(ARGS)` khi tệp này được gọi trực tiếp từ dòng lệnh (không chạy khi bị `include` trong test)
if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end
