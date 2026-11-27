# Kiểm thử các hàm lõi và kỷ luật hiệu năng (phần của A).
#
# - Hàm giao tidset cho kết quả đúng trên dữ liệu ngẫu nhiên (kể cả nhánh tìm kiếm nhảy);
# - hàm nóng ổn định kiểu (@inferred) và không cấp phát bộ nhớ (@allocated == 0);
# - bản dùng lại buffer (v2 trở đi) cấp phát ít hơn hẳn bản cơ bản (v0).
#
# Vì sao cần file này: các test khác (oracle, SPMF) chỉ kiểm tra KẾT QUẢ đúng. Một thay đổi làm
# hàm giao vô tình cấp phát bộ nhớ hoặc mất ổn định kiểu vẫn cho kết quả đúng, nhưng làm chậm
# chương trình nhiều lần. File này bắt các lỗi hiệu năng đó, và là bằng chứng cho các khẳng định
# "không cấp phát" của v2, v3 trong báo cáo.
#
# File được include từ runtests.jl, nên đã có sẵn Test, Random (MersenneTwister) và EclatFIM.

# Lấy thêm các hàm nội bộ (không export) cần kiểm thử.
using EclatFIM: isect_merge!, isect_adaptive!, intersect_merge, GALLOP_RATIO

# Tạo một tidset ngẫu nhiên hợp lệ: n giá trị trong 1..maxv, bỏ trùng, sắp tăng dần, kiểu Int32.
randset(rng, n, maxv) = sort!(unique!(Int32.(rand(rng, 1:maxv, n))))

@testset "Hàm giao tidset đúng trên dữ liệu ngẫu nhiên" begin
    rng = MersenneTwister(7)                 # hạt giống cố định: lần chạy nào cũng sinh cùng dữ liệu
    for trial in 1:2000
        maxv = rand(rng, 1:5000)             # khoảng giá trị tid: nhỏ thì nhiều phần tử chung, lớn thì ít
        a = randset(rng, rand(rng, 0:300), maxv)
        # một nửa số ca: b dài hơn a rất nhiều để đi vào nhánh tìm kiếm nhảy
        b = trial % 2 == 0 ? randset(rng, rand(rng, 0:300), maxv) :
                             randset(rng, rand(rng, 0:4000), maxv)
        ref = intersect(a, b)                # đáp án chuẩn: hàm giao có sẵn của Julia
        @test intersect_merge(a, b) == ref
        # đặt hai tidset lệch vị trí trong một buffer chung, như trong vùng nhớ dùng lại
        # (các giá trị -1, -7 là "rác" xung quanh: nếu hàm đọc tràn ra ngoài đoạn thì kết quả sẽ sai)
        buf = vcat(Int32[-1, -1], a, Int32[-7], b)
        ao, bo = 3, 3 + length(a) + 1        # vị trí bắt đầu của a và b trong buf
        dst = fill(Int32(0), length(a) + length(b) + 5)
        c = isect_merge!(dst, 4, buf, ao, length(a), buf, bo, length(b))   # ghi từ ô 4 để thử dpos ≠ 1
        @test dst[4:3+c] == ref
        # Thử ba mức ngưỡng: thấp (luôn đủ), đúng bằng |ref| (vừa đủ), |ref| + 1 (trượt).
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
    @test length(b) >= GALLOP_RATIO * length(a)     # bảo đảm b đủ dài để isect_adaptive! chọn nhánh nhảy
    dst = zeros(Int32, 3)
    @test isect_adaptive!(dst, 1, a, 1, 3, b, 1, 6000, 1) == 3   # cả 3 phần tử của a đều có trong b
    @test dst == a
end

# Ổn định kiểu: Julia suy ra được kiểu trả về chỉ từ kiểu tham số. Nếu không, mỗi phép toán phải
# kiểm tra kiểu lúc chạy và chậm đi nhiều lần. @inferred báo lỗi nếu kiểu trả về không suy ra được.
# Không cấp phát: @allocated đo số byte xin thêm khi gọi hàm; vòng lặp nóng phải bằng 0.
@testset "Hàm nóng ổn định kiểu và không cấp phát" begin
    a = Int32.(collect(1:2:2000))            # các số lẻ
    b = Int32.(collect(1:3:3000))            # 1, 4, 7, ...: có phần tử chung với a
    dst = zeros(Int32, 2000)
    @inferred isect_merge!(dst, 1, a, 1, length(a), b, 1, length(b))
    @inferred isect_adaptive!(dst, 1, a, 1, length(a), b, 1, length(b), 10)
    # Lần gọi đầu tiên Julia biên dịch hàm (tốn bộ nhớ cho việc biên dịch), nên phải gọi trước một lần
    # rồi mới đo; nếu không, @allocated sẽ tính cả bộ nhớ biên dịch.
    isect_merge!(dst, 1, a, 1, length(a), b, 1, length(b))                 # chạy khởi động
    isect_adaptive!(dst, 1, a, 1, length(a), b, 1, length(b), 10)
    @test (@allocated isect_merge!(dst, 1, a, 1, length(a), b, 1, length(b))) == 0
    @test (@allocated isect_adaptive!(dst, 1, a, 1, length(a), b, 1, length(b), 10)) == 0
end

@testset "Dùng lại buffer giảm cấp phát so với bản cơ bản" begin
    rng = MersenneTwister(11)
    # CSDL ngẫu nhiên: 2000 giao dịch, 30 item, mỗi item có mặt với xác suất 0.5 (dữ liệu dày).
    db = TransactionDB([Int32[x for x in 1:30 if rand(rng) < 0.5] for _ in 1:2000], collect(Int64, 1:30))
    σ = 300                                  # minsup dạng số đếm (15% số giao dịch)
    noop = (items, s) -> nothing             # sink không làm gì: chỉ đo phần của thuật toán
    eclat!(noop, db, σ, VARIANTS["v0"]); eclat!(noop, db, σ, VARIANTS["v2"])   # khởi động
    alloc_v0 = @allocated eclat!(noop, db, σ, VARIANTS["v0"])
    alloc_v2 = @allocated eclat!(noop, db, σ, VARIANTS["v2"])
    @info "Bộ nhớ cấp phát: v0 = $(round(alloc_v0 / 2^20; digits = 2)) MiB, v2 = $(round(alloc_v2 / 2^20; digits = 2)) MiB"
    @test alloc_v2 * 10 < alloc_v0           # v2 phải cấp phát ít hơn v0 ít nhất 10 lần
end
