const trackEvents = ['pointermove', 'keydown', 'touchstart'];
const trackUrl = document.querySelector('#analytics')?.dataset.trackUrl;

let tracked = false;

function track(url) {
    if (tracked) return;
    tracked = true;
    navigator.sendBeacon(url);
    for (const e of trackEvents)
		window.removeEventListener(e, track);
}

for (const e of trackEvents)
	window.addEventListener(e, track(trackUrl));

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

if (window.baguetteBox) {
	baguetteBox.run('.baguettebox p');
}

document.querySelectorAll('.js-clipboard pre').forEach((pre) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = 'Copy';
    pre.appendChild(button);

    button.addEventListener('click', async () => {
        const clone = pre.cloneNode(true);
        clone.querySelector('button')?.remove();
        try {
            await navigator.clipboard.writeText(clone.innerText);
            button.textContent = 'Copied';
        } catch (e) {
            console.error('Clipboard copy failed:', e);
        }
    });

	pre.addEventListener('mouseenter', () => {
        button.textContent = 'Copy';
    });
});
