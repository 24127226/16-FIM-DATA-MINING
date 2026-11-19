# Kiểm thử trên dữ liệu benchmark thật (phần của B): so dấu vân tay với đáp án SPMF
# (test/expected/benchmark_fingerprints.txt, sinh bởi scripts/make_expected.jl).
# Bỏ qua (vẫn tính là pass) nếu chưa tải dữ liệu: julia --project=. scripts/fetch_data.jl benchmark

const BENCH_ROOT = normpath(joinpath(@__DIR__, ".."))

let lines = [l for l in eachline(joinpath(@__DIR__, "expected", "benchmark_fingerprints.txt")) if !startswith(l, "#")]
    for line in lines
        name, input, ms, count, hash = strip.(split(line, " | "))
        path = joinpath(BENCH_ROOT, input)
        @testset "$name" begin
            if !isfile(path)
                @info "Bỏ qua $name: chưa có $input"
                @test_skip isfile(path)
                continue
            end
            db = read_spmf(path)
            σ = minsup_count(parse_minsup(ms), n_transactions(db))
            for v in VARIANTS_HERE
                out = tempname()
                n = mine_to_file(db, σ, out, VARIANTS[v])
                fp = fingerprint(out)
                rm(out)
                @test n == parse(Int, count)
                @test fp.count == parse(Int, count)
                @test fp.hash == parse(UInt64, hash)
            end
        end
    end
end
