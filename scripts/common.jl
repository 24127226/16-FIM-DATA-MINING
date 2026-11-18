# Tiện ích dùng chung cho các script: đường dẫn, gọi Java/SPMF, chạy tiến trình có giới hạn thời gian.
# Chỉ dùng thư viện chuẩn của Julia, nên chạy được trong môi trường gốc của repo.

const ROOT = normpath(joinpath(@__DIR__, ".."))

"""Lệnh Java: biến môi trường `JAVA`, mặc định `java` trong PATH. SPMF bản hiện tại cần Java ≥ 25."""
java_cmd() = get(ENV, "JAVA", "java")

"""Đường dẫn `spmf.jar`: biến môi trường `SPMF_JAR`, mặc định `tools/spmf.jar` (tải bằng `scripts/fetch_spmf.jl`)."""
spmf_jar() = get(ENV, "SPMF_JAR", joinpath(ROOT, "tools", "spmf.jar"))

"""Đường dẫn tuyệt đối tính từ gốc repo."""
rootpath(parts...) = joinpath(ROOT, parts...)

"""
    run_with_timeout(cmd; timeout) -> NamedTuple

Chạy `cmd`, gom stdout + stderr, dừng tiến trình nếu quá `timeout` giây.
Trả về `(status, output, wall_s, pid)` với `status ∈ (:ok, :error, :timeout)`.
"""
function run_with_timeout(cmd::Cmd; timeout::Real = 600)
    out = Pipe()
    t0 = time_ns()
    proc = run(pipeline(cmd; stdout = out, stderr = out); wait = false)
    pid = try
        getpid(proc)          # lấy ngay khi vừa khởi chạy; tiến trình rất ngắn có thể đã kết thúc
    catch
        -1
    end
    close(out.in)
    reader = @async read(out, String)
    timed_out = Ref(false)
    timer = Timer(timeout) do _
        if process_running(proc)
            timed_out[] = true
            kill(proc)
        end
    end
    wait(proc)
    wall = (time_ns() - t0) / 1e9
    close(timer)
    output = fetch(reader)
    status = timed_out[] ? :timeout : (success(proc) ? :ok : :error)
    return (status = status, output = output, wall_s = wall, pid = pid)
end

"""Thống kê SPMF in ra màn hình sau khi chạy."""
struct SPMFRun
    status::Symbol
    output::String
    wall_s::Float64      # thời gian tiến trình (gồm khởi động JVM)
    n_tx::Int            # "Transactions count from database"
    n_itemsets::Int      # "Frequent itemsets count"
    algo_ms::Float64     # "Total time ~ X ms" (thời gian SPMF tự đo)
    heap_mb::Float64     # "Maximum memory usage : X mb" (bộ nhớ heap JVM do SPMF tự đo)
end

function _grab(re::Regex, s::AbstractString, ::Type{T}, default) where {T}
    m = match(re, s)
    m === nothing ? default : parse(T, m.captures[1])
end

"""
    run_spmf(algo, input, output, minsup; xmx = "8g", timeout = 600) -> SPMFRun

Chạy một thuật toán SPMF. `minsup` truyền nguyên dạng chuỗi SPMF hiểu, ví dụ `"40%"`.
Để khớp tuyệt đối với code của nhóm, hai bên phải nhận **cùng một chuỗi minsup**
(xem `parse_minsup` và `results/spmf_behavior.md`).
"""
function run_spmf(algo::AbstractString, input::AbstractString, output::AbstractString,
                  minsup::AbstractString; xmx::AbstractString = "8g", timeout::Real = 600)
    cmd = `$(java_cmd()) -Xmx$(xmx) -jar $(spmf_jar()) run $algo $input $output $minsup`
    r = run_with_timeout(cmd; timeout = timeout)
    s = r.output
    status = r.status
    if status == :ok && occursin(r"ERROR|Exception|Error\.", s)
        status = :error
    end
    return SPMFRun(status, s, r.wall_s,
                   _grab(r"Transactions count from database : (\d+)", s, Int, -1),
                   _grab(r"Frequent itemsets count : (\d+)", s, Int, -1),
                   _grab(r"Total time ~ ([\d.]+) ms", s, Float64, NaN),
                   _grab(r"Maximum memory usage : ([\d.]+) mb", s, Float64, NaN))
end

"""Phiên bản Java chính (major), hoặc 0 nếu không chạy được."""
function java_major_version()
    r = try
        run_with_timeout(`$(java_cmd()) -version`; timeout = 30)
    catch
        return 0
    end
    m = match(r"version \"(\d+)", r.output)
    return m === nothing ? 0 : parse(Int, m.captures[1])
end
