# Ghi thông tin môi trường đo (máy, Julia, Java, SPMF) vào results/ENV.md.
# Chạy trên máy đo chính thức trước mỗi đợt đo hiệu năng (KE_HOACH_DU_AN.md, mục 8.5).
#
# Cách dùng (từ gốc repo):  julia --project=. scripts/env_info.jl

using SHA, Dates
include(joinpath(@__DIR__, "common.jl"))

function main()
    io = IOBuffer()
    println(io, "# Môi trường đo\n")
    println(io, "Sinh bởi `scripts/env_info.jl` lúc ", Dates.format(now(), "yyyy-mm-dd HH:MM"), ".\n")
    cpu = Sys.cpu_info()
    println(io, "| Thành phần | Giá trị |")
    println(io, "|---|---|")
    println(io, "| Hệ điều hành | ", Sys.KERNEL, " (", Sys.MACHINE, ") |")
    println(io, "| CPU | ", isempty(cpu) ? "?" : strip(cpu[1].model), " |")
    println(io, "| Số luồng CPU | ", Sys.CPU_THREADS, " |")
    println(io, "| RAM | ", round(Sys.total_memory() / 2^30; digits = 1), " GiB |")
    println(io, "| Julia | ", VERSION, " |")
    println(io, "| Số luồng Julia | ", Threads.nthreads(), " |")
    jv = try
        r = run_with_timeout(`$(java_cmd()) -version`; timeout = 30)
        replace(strip(first(split(r.output, '\n'))), "|" => "/")
    catch
        "không chạy được"
    end
    println(io, "| Java | ", jv, " |")
    jar = spmf_jar()
    if isfile(jar)
        println(io, "| spmf.jar (SHA-256) | `", open(f -> bytes2hex(sha256(f)), jar), "` |")
        toy = rootpath("data", "toy", "pasquier99.txt")
        out = tempname()
        r = run_spmf("Eclat", toy, out, "40%")
        m = match(r"ECLAT (v[\d.]+)", r.output)
        println(io, "| Phiên bản Eclat của SPMF | ", m === nothing ? "?" : m.captures[1], " |")
        isfile(out) && rm(out)
    else
        println(io, "| spmf.jar | chưa có (chạy scripts/fetch_spmf.jl) |")
    end
    commit = try
        strip(read(pipeline(`git -C $(ROOT) rev-parse --short HEAD`; stderr = devnull), String))
    catch
        "(chưa có git)"
    end
    println(io, "| Commit | ", commit, " |")
    mkpath(rootpath("results"))
    path = rootpath("results", "ENV.md")
    write(path, String(take!(io)))
    println("Đã ghi ", path)
end

main()
