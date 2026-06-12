const header = document.querySelector(".site-header");

window.addEventListener("scroll", () => {
  if (window.scrollY > 12) {
    header.style.boxShadow = "0 10px 30px rgba(20, 35, 48, 0.08)";
  } else {
    header.style.boxShadow = "none";
  }
});
