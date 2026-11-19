# Tạo các tập con LỒNG NHAU 10% ⊂ 25% ⊂ 50% ⊂ 75% ⊂ 100% số giao dịch cho thí nghiệm E5.
#
#   julia --project=. scripts/subsample.jl [tên bộ dữ liệu, mặc định retail]
#
# Một hoán vị ngẫu nhiên (seed cố định) của các giao dịch; tập con p% là ⌈p·N⌉ giao dịch đầu của
# hoán vị đó (giữ thứ tự gốc trong file). Tập nhỏ nằm trọn trong tập lớn, nên khác biệt giữa các mức
# chỉ do kích thước, không do "rút thăm" khác nhau.
# Ghi data/subsets/<tên>_<p>.txt.

using Random
include(joinpath(@__DIR__, "config.jl"))

function main(args)
    name = isempty(args) ? "retail" : args[1]
    lines = [l for l in eachline(dataset_path(name)) if !isempty(strip(l)) && !(first(strip(l)) in ('#', '%', '@'))]
    N = length(lines)
    perm = randperm(MersenneTwister(SEED), N)
    dir = rootpath("data", "subsets")
    mkpath(dir)
    for pct in (10, 25, 50, 75, 100)
        k = ceil(Int, pct * N / 100)
        keep = sort(perm[1:k])
        path = joinpath(dir, "$(name)_$(pct).txt")
        open(path, "w") do io
            for j in keep
                println(io, lines[j])
            end
        end
        println(rpad(basename(path), 18), k, " giao dịch")
    end
end

main(ARGS)
