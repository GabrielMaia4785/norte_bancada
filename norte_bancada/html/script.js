// norte_bancada: o som do motor da máquina a trabalhar. O progresso está no ecrã do modelo (screen.html).
(() => {
    // O som do motor da máquina a trabalhar: em loop, com fade in ao começar, fade out ao parar e uma rampa curta
    // quando só a distância muda. O volume anda de 50 em 50 ms até ao alvo.
    const sound = new Audio('sounds/motor_bancada_loop.wav');
    sound.loop = true;
    sound.volume = 0;

    const STEP_MS = 50;
    const MOVE_MS = 300;   // distância a mudar com o som já a tocar
    let target = 0;
    let perStep = 0;       // quanto o volume anda por passo, nesta rampa
    let ramp = null;

    function stepVolume() {
        const now = sound.volume;
        const next = now < target ? Math.min(target, now + perStep) : Math.max(target, now - perStep);
        sound.volume = Math.min(1, Math.max(0, next));
        if (sound.volume === target) {
            clearInterval(ramp);
            ramp = null;
            if (target === 0) {
                sound.pause();
                sound.currentTime = 0;
            }
        }
    }

    function setSound(volume, fadeInMs, fadeOutMs) {
        const v = Math.min(1, Math.max(0, Number(volume) || 0));
        if (v === target) return;
        const starting = v > 0 && (sound.paused || sound.volume === 0);
        const stopping = v === 0;
        const ms = starting ? (Number(fadeInMs) || 1000) : stopping ? (Number(fadeOutMs) || 1000) : MOVE_MS;
        target = v;
        perStep = Math.max(0.002, Math.abs(v - sound.volume) * STEP_MS / ms);
        if (v > 0 && sound.paused) sound.play().catch(() => {});
        if (!ramp) ramp = setInterval(stepVolume, STEP_MS);
    }

    window.addEventListener('message', (e) => {
        const d = e.data || {};
        if (d.action === 'sound') setSound(d.volume, d.fadeIn, d.fadeOut);
    });
})();
