(function () {
    var lb = document.getElementById("lb");
    var lbImg = document.getElementById("lb-img");
    document.querySelectorAll(".shot img").forEach(function (img) {
        img.addEventListener("click", function () {
            lbImg.src = img.src;
            lbImg.alt = img.alt;
            lb.classList.add("open");
        });
    });
    lb.addEventListener("click", function (e) {
        if (
            e.target === lb ||
            e.target.classList.contains("lb-close")
        )
            lb.classList.remove("open");
    });
    document.addEventListener("keydown", function (e) {
        if (e.key === "Escape") lb.classList.remove("open");
    });
})();
