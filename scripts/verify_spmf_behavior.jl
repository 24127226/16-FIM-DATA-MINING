# Kiểm chứng hành vi của SPMF (quyết định D04, D05 trong KE_HOACH_DU_AN.md) bằng thí nghiệm hộp đen:
#   1. SPMF đổi minsup tỉ lệ sang số đếm thế nào (làm tròn, sai số số thực)?
#   2. SPMF đếm số giao dịch N thế nào (dòng rỗng, dòng chú thích)?
#   3. SPMF chấp nhận/từ chối định dạng input nào?
#
# Cách dùng (từ gốc repo):  julia --project=. scripts/verify_spmf_behavior.jl
# Kết quả ghi vào results/spmf_behavior.md.

include(joinpath(@__DIR__, "common.jl"))

# Quy tắc nhóm giả định (sẽ cài thành parse_minsup / minsup_count trong src/utils.jl).
our_minsup(s) = endswith(s, "%") ? parse(Float64, s[1:end-1]) / 100 : parse(Float64, s)
our_count(s, n) = ceil(Int, our_minsup(s) * n)

function exact_threshold(s::AbstractString, n::Integer)
    # giá trị toán học đúng: ceil(p * n) với p là số thập phân viết trong chuỗi
    t = endswith(s, "%") ? s[1:end-1] : s
    num = parse(BigInt, replace(t, "." => ""))
    den = BigInt(10)^(occursin('.', t) ? length(t) - findfirst('.', t) : 0)
    endswith(s, "%") && (den *= 100)
    return Int(cld(num * n, den))
end

function write_db(path, lines)
    open(path, "w") do io
        for l in lines
            write(io, l)
        end
    end
end

"""SPMF có coi item 1 (xuất hiện đúng k lần trong N giao dịch) là phổ biến ở mức minsup s không?"""
function item1_frequent(dir, n, k, s)
    inp = joinpath(dir, "fp_in.txt"); out = joinpath(dir, "fp_out.txt")
    write_db(inp, [i <= k ? "1 2\n" : "2\n" for i in 1:n])
    r = run_spmf("Eclat", inp, out, s)
    r.status == :ok || error("SPMF lỗi ở ca N=$n, minsup=$s:\n" * r.output)
    return any(startswith(l, "1 #SUP") for l in eachline(out))
end

function main()
    dir = mktempdir()
    report = IOBuffer()
    println(report, "# Hành vi của SPMF (kiểm chứng bằng thí nghiệm hộp đen)\n")
    println(report, "Sinh bởi `scripts/verify_spmf_behavior.jl`. Phiên bản SPMF: xem `results/ENV.md`.\n")

    # --- 1. Ngưỡng support ---
    println(report, "## 1. Đổi minsup sang số đếm\n")
    println(report, "Mỗi ca dùng một CSDL N giao dịch, trong đó item 1 xuất hiện đúng k lần. Ngưỡng thật của SPMF")
    println(report, "là số k nhỏ nhất để item 1 được coi là phổ biến.\n")
    println(report, "| N | minsup | Giá trị toán học đúng | `ceil((p/100)·N)` bằng Float64 | Ngưỡng SPMF quan sát được | Khớp quy tắc của nhóm? |")
    println(report, "|---|---|---|---|---|---|")
    cases = [(5, "40%"), (5, "30%"), (10, "70%"), (25, "28%"), (50, "14%"), (40, "17.5%"),
             (20, "35%"), (100, "7%"), (10, "0.7"), (3196, "50%")]
    all_ok = true
    for (n, s) in cases
        ours = our_count(s, n)
        below = ours > 1 ? item1_frequent(dir, n, ours - 1, s) : false
        at = item1_frequent(dir, n, ours, s)
        observed = (!below && at) ? string(ours) : "khác (k=$(ours-1): $below, k=$ours: $at)"
        ok = !below && at
        all_ok &= ok
        println(report, "| $n | `$s` | $(exact_threshold(s, n)) | $ours | $observed | $(ok ? "✅" : "❌") |")
    end
    println(report)
    println(report, all_ok ?
        "**Kết luận:** SPMF dùng đúng công thức `σ_min = ceil(minsup × N)` tính bằng số thực Float64, với `\"p%\"` được đổi thành `p / 100`, còn chuỗi không có `%` được hiểu là tỉ lệ. Kết quả **có thể lệch** khỏi giá trị toán học đúng (ví dụ 28% của 25 cho ngưỡng 8, không phải 7). Muốn khớp 100% thì code của nhóm phải tính **y hệt**, và hai bên phải nhận **cùng một chuỗi minsup**.\n" :
        "**Cảnh báo:** có ca không khớp quy tắc giả định, phải xem lại `minsup_count`.\n")

    # --- 2 & 3. Định dạng input ---
    println(report, "## 2. Đếm số giao dịch và định dạng input\n")
    println(report, "| Ca | Nội dung thử | SPMF chạy được? | N SPMF đếm | Số tập (minsup 40%) |")
    println(report, "|---|---|---|---|---|")
    base = ["1 3 4\n", "2 3 5\n", "1 2 3 5\n", "2 5\n", "1 2 3 5\n"]
    probes = [
        ("Chuẩn (Pasquier99)", "5 dòng, cách nhau một dấu cách", base),
        ("Dòng rỗng và chú thích", "chèn dòng rỗng, `#…`, `%…`, `@…`", ["1 3 4\n", "\n", "2 3 5\n", "#chu thich 9\n", "%chu thich 9\n", "@meta\n", "1 2 3 5\n", "2 5\n", "1 2 3 5\n"]),
        ("Item 0", "thay item 1 bằng 0", ["0 3 4\n", "2 3 5\n", "0 2 3 5\n", "2 5\n", "0 2 3 5\n"]),
        ("Chưa sắp xếp", "`3 1 4`, `5 2`", ["3 1 4\n", "2 3 5\n", "1 2 3 5\n", "5 2\n", "1 2 3 5\n"]),
        ("Item trùng", "`2 3 5 5`", ["1 3 4\n", "2 3 5 5\n", "1 2 3 5\n", "2 5\n", "1 2 3 5\n"]),
        ("Dấu tab", "`2 3 5<TAB>`", ["1 3 4\n", "2 3 5\t\n", "1 2 3 5\n", "2 5\n", "1 2 3 5\n"]),
        ("Hai dấu cách liền nhau", "`2  3 5`", ["1 3 4\n", "2  3 5\n", "1 2 3 5\n", "2 5\n", "1 2 3 5\n"]),
        ("Dấu cách đầu dòng", "` 1 3 4`", [" 1 3 4\n", "2 3 5\n", "1 2 3 5\n", "2 5\n", "1 2 3 5\n"]),
        ("Dấu cách cuối dòng", "`1 3 4 `", ["1 3 4 \n", "2 3 5\n", "1 2 3 5\n", "2 5\n", "1 2 3 5 \n"]),
        ("Xuống dòng kiểu Windows", "CRLF", replace.(base, "\n" => "\r\n")),
    ]
    for (name, desc, lines) in probes
        inp = joinpath(dir, "probe.txt"); out = joinpath(dir, "probe_out.txt")
        isfile(out) && rm(out)
        write_db(inp, lines)
        r = run_spmf("Eclat", inp, out, "40%")
        okrun = r.status == :ok
        println(report, "| $name | $desc | $(okrun ? "✅" : "❌ lỗi") | $(okrun ? r.n_tx : "—") | $(okrun ? r.n_itemsets : "—") |")
    end
    println(report)
    println(report, """**Kết luận cho bộ đọc của nhóm (`read_spmf`):**

- Bỏ qua dòng rỗng và dòng bắt đầu bằng `#`, `%`, `@`; **N là số dòng còn lại**, đúng như SPMF đếm.
- Item 0 hợp lệ (dù tài liệu SPMF ghi "positive integer").
- Thứ tự item trong dòng không ảnh hưởng kết quả của Eclat; bộ đọc của nhóm vẫn sắp xếp lại.
- SPMF **báo lỗi** khi có item trùng, dấu tab, hai dấu cách liền nhau hoặc dấu cách đầu dòng. Bộ đọc của nhóm dễ tính hơn (chấp nhận mọi khoảng trắng, tự bỏ item trùng), nhưng **file dữ liệu dùng để so với SPMF phải sạch**: các script chuyển đổi dữ liệu luôn ghi đúng một dấu cách giữa các item.
""")

    # --- 3. Mã item rất lớn ---
    println(report, "## 3. Mã item rất lớn và rời rạc\n")
    println(report, "CSDL 5 giao dịch, minsup 40%, mã item lớn nhất 1.000.000 (đáp án đúng: 8 tập phổ biến; ca kiểm thử ",
            "\"Mã item rất lớn và rời rạc\" trong `test/test_correctness.jl`).\n")
    println(report, "| Thuật toán SPMF | Chạy được? | Số tập | Dòng lỗi đầu tiên | Dòng đầu của stack trace |")
    println(report, "|---|---|---|---|---|")
    big = ["7 20 35\n", "20 35\n", "7 20 1000000\n", "35 1000000\n", "20 35 1000000\n"]
    for algo in ("Eclat", "Eclat_bitset")
        inp = joinpath(dir, "probe_big.txt"); out = joinpath(dir, "probe_big_out.txt")
        isfile(out) && rm(out)
        write_db(inp, big)
        r = run_spmf(algo, inp, out, "40%"; timeout = 120)
        okrun = r.status == :ok
        lines = split(r.output, '\n')
        errs = filter(l -> occursin(r"Error|Exception", l), lines)
        frames = filter(l -> startswith(strip(l), "at "), lines)        # dòng đầu của stack trace SPMF in ra
        err = okrun ? "" : (isempty(errs) ? "(không có)" : first(errs))
        frame = okrun || isempty(frames) ? "" : first(frames)
        println(report, "| `$algo` | $(okrun ? "✅" : "❌ $(r.status)") | $(okrun ? r.n_itemsets : "—") | `",
                replace(strip(err), "|" => "/"), "` | `", replace(strip(frame), "|" => "/"), "` |")
    end
    println(report, "\nDòng lỗi chỉ ghi lại thông báo SPMF in ra màn hình (kiểm chứng hộp đen); nhóm không đọc mã nguồn SPMF. ",
            "Bộ đọc của nhóm đổi mã gốc về 1..m nên không bị ảnh hưởng bởi độ lớn của mã item.")
    mkpath(rootpath("results"))
    path = rootpath("results", "spmf_behavior.md")
    write(path, String(take!(report)))
    println("Đã ghi ", path, all_ok ? "  (mọi ca ngưỡng đều khớp quy tắc của nhóm)" : "  (CÓ CA KHÔNG KHỚP)")
end

main()
