# Kiểm thử các hàm lõi và kỷ luật hiệu năng (phần của A).
#
# - Hàm giao tidset cho kết quả đúng trên dữ liệu ngẫu nhiên (kể cả nhánh tìm kiếm nhảy);
# - hàm nóng ổn định kiểu (@inferred) và không cấp phát bộ nhớ (@allocated == 0);
# - bản dùng lại buffer (v2 trở đi) cấp phát ít hơn hẳn bản cơ bản (v0).

using EclatFIM: isect_merge!, isect_adaptive!, intersect_merge, GALLOP_RATIO

randset(rng, n, maxv) = sort!(unique!(Int32.(rand(rng, 1:maxv, n))))

@testset "Hàm giao tidset đúng trên dữ liệu ngẫu nhiên" begin
    rng = MersenneTwister(7)
    for trial in 1:2000
        maxv = rand(rng, 1:5000)
        a = randset(rng, rand(rng, 0:300), maxv)
        # một nửa số ca: b dài hơn a rất nhiều để đi vào nhánh tìm kiếm nhảy
        b = trial % 2 == 0 ? randset(rng, rand(rng, 0:300), maxv) :
                             randset(rng, rand(rng, 0:4000), maxv)
        ref = intersect(a, b)
        @test intersect_merge(a, b) == ref
        # đặt hai tidset lệch vị trí trong một buffer chung, như trong vùng nhớ dùng lại
        buf = vcat(Int32[-1, -1], a, Int32[-7], b)
        ao, bo = 3, 3 + length(a) + 1
        dst = fill(Int32(0), length(a) + length(b) + 5)
        c = isect_merge!(dst, 4, buf, ao, length(a), buf, bo, length(b))
        @test dst[4:3+c] == ref
        for ms in (1, max(1, length(ref)), length(ref) + 1)
            c2 = isect_adaptive!(dst, 2, buf, ao, length(a), buf, bo, length(b), ms)
            if length(ref) >= ms
                @test c2 == length(ref) && dst[2:1+c2] == ref     # đủ ngưỡng: kết quả giống hệt
            else
                @test c2 < ms                                    # dưới ngưỡng: được phép ngắt sớm
            end
        end
    end
end

@testset "Nhánh tìm kiếm nhảy thật sự được dùng" begin
    a = Int32[5, 500, 5000]
    b = Int32.(collect(1:6000))
    @test length(b) >= GALLOP_RATIO * length(a)
    dst = zeros(Int32, 3)
    @test isect_adaptive!(dst, 1, a, 1, 3, b, 1, 6000, 1) == 3
    @test dst == a
end

@testset "Hàm nóng ổn định kiểu và không cấp phát" begin
    a = Int32.(collect(1:2:2000))
    b = Int32.(collect(1:3:3000))
    dst = zeros(Int32, 2000)
    @inferred isect_merge!(dst, 1, a, 1, length(a), b, 1, length(b))
    @inferred isect_adaptive!(dst, 1, a, 1, length(a), b, 1, length(b), 10)
    isect_merge!(dst, 1, a, 1, length(a), b, 1, length(b))                 # chạy khởi động
    isect_adaptive!(dst, 1, a, 1, length(a), b, 1, length(b), 10)
    @test (@allocated isect_merge!(dst, 1, a, 1, length(a), b, 1, length(b))) == 0
    @test (@allocated isect_adaptive!(dst, 1, a, 1, length(a), b, 1, length(b), 10)) == 0
end

@testset "Dùng lại buffer giảm cấp phát so với bản cơ bản" begin
    rng = MersenneTwister(11)
    db = TransactionDB([Int32[x for x in 1:30 if rand(rng) < 0.5] for _ in 1:2000], collect(Int64, 1:30))
    σ = 300
    noop = (items, s) -> nothing
    eclat!(noop, db, σ, VARIANTS["v0"]); eclat!(noop, db, σ, VARIANTS["v2"])   # khởi động
    alloc_v0 = @allocated eclat!(noop, db, σ, VARIANTS["v0"])
    alloc_v2 = @allocated eclat!(noop, db, σ, VARIANTS["v2"])
    @info "Bộ nhớ cấp phát: v0 = $(round(alloc_v0 / 2^20; digits = 2)) MiB, v2 = $(round(alloc_v2 / 2^20; digits = 2)) MiB"
    @test alloc_v2 * 10 < alloc_v0
end
