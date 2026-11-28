# Tải spmf.jar (cài đặt tham chiếu) về tools/spmf.jar và kiểm tra phiên bản Java.
#
# Cách dùng (từ gốc repo):  julia --project=. scripts/fetch_spmf.jl
#
# Lưu ý: SPMF chỉ được chạy như một "hộp đen" để đối chiếu kết quả. Nhóm không đọc
# và không chép mã nguồn của SPMF (quy tắc liêm chính, KE_HOACH_DU_AN.md mục 13.7).

using Downloads, SHA
include(joinpath(@__DIR__, "common.jl"))

const SPMF_URL = "https://www.philippe-fournier-viger.com/spmf/spmf.jar"
# SHA-256 của hai bản spmf.jar nhóm đã dùng (SPMF, Eclat v2.65). Trang SPMF thay file jar theo thời gian, nên hai lần
# tải ở hai ngày khác nhau cho hai mã khác nhau. Cả hai bản đều cho kết quả khớp 100% với EclatFIM.
const SPMF_SHA_KNOWN = Dict(
    "bb371b99b3bfd58fbce6b92e0ea3ccda5f9d1fd173bfe8e40f177672117159ba" =>
        "bản tải ngày 27–28/11/2026 (máy B trong results/ENV.md, Colab)",   # bản hiện có trên trang SPMF
    "2cc2d89e39909230ea0455da4a1c79b389dc98ca04b0670befb63e679b5e2ea0" =>
        "bản tải ngày 17/11/2026 (máy A trong results/ENV_A.md)")           # bản dùng cho E7, E8, E10 và Ứng dụng 2
const JAVA_MIN = 25   # spmf.jar được biên dịch cho Java 25 (class file version 69)

function main()
    dest = spmf_jar()
    if !isfile(dest)
        mkpath(dirname(dest))
        println("↓ tải ", SPMF_URL)
        Downloads.download(SPMF_URL, dest)
    end
    got = open(io -> bytes2hex(sha256(io)), dest)
    if haskey(SPMF_SHA_KNOWN, got)   # trùng một trong hai bản nhóm đã dùng
        println("✓ spmf.jar trùng một bản nhóm đã dùng: ", SPMF_SHA_KNOWN[got], " — ", dest)
    else
        println("! spmf.jar khác các bản nhóm đã dùng (SHA-256 = ", got, ").")
        println("  Trang SPMF có thể đã cập nhật phiên bản mới. Kết quả vẫn phải khớp,")
        println("  nhưng hãy ghi SHA-256 mới vào results/ENV.md khi đo hiệu năng.")
    end
    v = java_major_version()
    if v == 0
        println("✗ không chạy được Java (lệnh: ", java_cmd(), "). Đặt biến môi trường JAVA hoặc cài Java ≥ $JAVA_MIN.")
    elseif v < JAVA_MIN
        println("✗ Java ", v, " quá cũ: bản spmf.jar này cần Java ≥ ", JAVA_MIN, ".")
    else
        println("✓ Java ", v)
    end
end

main()
