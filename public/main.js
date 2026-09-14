const nav = document.querySelector('nav');
const key = 'nav-scroll-pos';

document.addEventListener('DOMContentLoaded', (e) => {
    const saved = localStorage.getItem(key);
    if (saved) {
        const { top = 0 } = JSON.parse(saved);
        nav.scrollTop = top;
    }
});

nav.addEventListener('click', (e) => {
    localStorage.setItem(key, JSON.stringify({
        top: nav.scrollTop,
    }));
});

window.addEventListener('pagehide', (e) => {
    localStorage.setItem(key, JSON.stringify({
        top: nav.scrollTop,
    }));
});

if (window.ScrollReveal) {
	ScrollReveal().reveal('.scrollreveal section', {
		duration: 1000,
		distance: '4em'
	});
}
