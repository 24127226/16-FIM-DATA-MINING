# Tải dữ liệu benchmark và dữ liệu ứng dụng, kiểm tra SHA-256.
#
# Cách dùng (từ gốc repo):
#   julia --project=. scripts/fetch_data.jl              # mặc định: benchmark
#   julia --project=. scripts/fetch_data.jl benchmark groceries caltech
#   julia --project=. scripts/fetch_data.jl all
#
# Nếu đặt biến môi trường FIM_DATA_BASE (ví dụ link thư mục dataset trên Hugging Face của nhóm,
# dạng https://huggingface.co/datasets/<user>/<repo>/resolve/main), script thử nguồn đó trước.

using Downloads, SHA
include(joinpath(@__DIR__, "common.jl"))

const SPMF_DATA = "https://www.philippe-fournier-viger.com/spmf/publicdatasets"

const SOURCES = [
    (group = "benchmark", dest = "data/benchmark/chess.txt", url = "$SPMF_DATA/chess.txt",
     sha = "a12ea887df58a396709430af5bf0a9a32d1f6eba8e7c13dd41f28b98572c5db2", strip_trailing = false),
    (group = "benchmark", dest = "data/benchmark/mushroom.txt", url = "https://fimi.uantwerpen.be/data/mushroom.dat",
     sha = "06206c73983251a9488414c4379a030e836bbeb6fe9eff1b5624a0193a811640", strip_trailing = true),
    (group = "benchmark", dest = "data/benchmark/retail.txt", url = "$SPMF_DATA/retail.txt",
     sha = "732c26de19888cb570d3fbb97e47206a9b1c0ce064f85dc1403314ba38f04eaa", strip_trailing = false),
    (group = "benchmark", dest = "data/benchmark/accidents.txt", url = "$SPMF_DATA/accidents.txt",
     sha = "8c2275550966e3cb4b6066f2bb168489a9566c500af559fa3925f1b11d97f0cd", strip_trailing = false),
    (group = "benchmark", dest = "data/benchmark/T10I4D100K.txt", url = "$SPMF_DATA/T10I4D100K.txt",
     sha = "949983f61aa976d1b774474fadd31c5f15775b24728a5e7c8b79801822ab3f89", strip_trailing = false),
    (group = "groceries", dest = "data/apps/groceries/groceries.csv",
     url = "https://raw.githubusercontent.com/stedy/Machine-Learning-with-R-datasets/master/groceries.csv",
     sha = "ff1be892fd6b9b57d1a7bc50de067798963dda607619645988b21789bf23ae3b", strip_trailing = false),
    (group = "caltech", dest = "data/apps/caltech101/caltech-101.zip",
     url = "https://data.caltech.edu/records/mzrjq-6wc02/files/caltech-101.zip?download=1",
     sha = "331234750fc7f77520e50d9565e8b6907b03565e30320da1401130db08c61f91", strip_trailing = false),
]

file_sha256(path) = open(io -> bytes2hex(sha256(io)), path)

"""Bỏ dấu cách và CR ở cuối mỗi dòng (bản FIMI của Mushroom có dấu cách cuối dòng)."""
function strip_trailing_spaces(src::AbstractString, dst::AbstractString)
    open(dst, "w") do out
        for line in eachline(src)
            println(out, rstrip(line, (' ', '\r')))
        end
    end
end

"""
Link thư mục dataset của nhóm trên Hugging Face, dạng
"https://huggingface.co/datasets/<tài-khoản>/<tên-dataset>/resolve/main" (cách tạo: data/huggingface/README.md).
Script thử nguồn này trước, rồi mới đến nguồn gốc; mọi file đều được kiểm tra SHA-256 như nhau.
Để trống thì chỉ tải từ nguồn gốc. Biến môi trường FIM_DATA_BASE (nếu có) được ưu tiên hơn hằng số này.
"""
const HF_DATA_BASE = ""

function candidate_urls(s)
    urls = String[]
    base = get(ENV, "FIM_DATA_BASE", HF_DATA_BASE)
    isempty(base) || push!(urls, rstrip(base, '/') * "/" * basename(s.dest))
    push!(urls, s.url)
    return urls
end

function fetch_one(s)
    dest = rootpath(s.dest)
    if isfile(dest) && file_sha256(dest) == s.sha
        println("  ✓ đã có: ", s.dest)
        return true
    end
    mkpath(dirname(dest))
    for url in candidate_urls(s)
        tmp = dest * ".download"
        try
            println("  ↓ tải ", s.dest, " từ ", url)
            Downloads.download(url, tmp)
            if s.strip_trailing
                strip_trailing_spaces(tmp, dest)
                rm(tmp)
            else
                mv(tmp, dest; force = true)
            end
            got = file_sha256(dest)
            if got == s.sha
                println("  ✓ SHA-256 khớp")
                return true
            end
            println("  ✗ SHA-256 không khớp (", got, "), thử nguồn khác")
        catch err
            println("  ✗ lỗi khi tải: ", sprint(showerror, err))
        finally
            isfile(tmp) && rm(tmp)
        end
    end
    return false
end

function main(args)
    groups = isempty(args) ? ["benchmark"] : args
    "all" in groups && (groups = unique([s.group for s in SOURCES]))
    ok = true
    for g in groups
        list = [s for s in SOURCES if s.group == g]
        isempty(list) && error("Nhóm dữ liệu không tồn tại: $g (chọn trong: benchmark, groceries, caltech, all)")
        println("== ", g)
        for s in list
            ok &= fetch_one(s)
        end
    end
    ok || error("Có file chưa tải được hoặc sai SHA-256.")
    println("Xong.")
end

main(ARGS)
